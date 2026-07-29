import Foundation

struct QuotaProvider: Sendable {
    /// `preferredExecutable` 非空时只读取用户明确选择的安装，绝不静默切换到另一个账号。
    func fetch(preferredExecutable: String? = nil) async throws -> QuotaSnapshot {
        if let preferredExecutable {
            guard FileManager.default.isExecutableFile(atPath: preferredExecutable) else {
                throw QuotaError.noCodexBinary
            }
            return try await runAppServer(installation: Self.installation(for: preferredExecutable))
        }

        var serverError: Error?
        do {
            return try await fetchFromAppServer()
        } catch {
            serverError = error
        }

        if let local = try? fetchFromSessionLogs() {
            return local
        }
        throw serverError ?? QuotaError.noLocalSnapshot
    }

    /// 设置页按需读取所有安装的账号信息；不影响 30 秒刷新策略。
    func inspectInstallations() async -> [CodexInstallation] {
        let candidates = Self.availableInstallations()
        return await withTaskGroup(of: CodexInstallation.self) { group in
            for installation in candidates {
                group.addTask {
                    guard let snapshot = try? await runAppServer(installation: installation),
                          let inspected = snapshot.installation
                    else {
                        var unavailable = installation
                        unavailable.inspectionFailed = true
                        return unavailable
                    }
                    return inspected
                }
            }
            var inspected: [CodexInstallation] = []
            for await installation in group {
                inspected.append(installation)
            }
            return candidates.compactMap { candidate in
                inspected.first { $0.id == candidate.id }
            }
        }
    }

    private func fetchFromAppServer() async throws -> QuotaSnapshot {
        let candidates = Self.availableInstallations()
        guard !candidates.isEmpty else {
            throw QuotaError.noCodexBinary
        }

        // 自动模式保留优先级，并保留首选安装的错误，避免后面的损坏 CLI
        // 覆盖 ChatGPT 返回的鉴权等更有价值的信息。
        var firstError: Error?
        for installation in candidates {
            do {
                return try await runAppServer(installation: installation)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        throw firstError ?? QuotaError.noCodexBinary
    }

    static func availableInstallations() -> [CodexInstallation] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ]
        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted,
                  FileManager.default.isExecutableFile(atPath: path)
            else { return nil }
            return installation(for: path)
        }
    }

    private static func installation(for path: String) -> CodexInstallation {
        let displayName: String
        if path.contains("ChatGPT.app/Contents/Resources") {
            displayName = path.hasPrefix("/Applications/") ? "ChatGPT 桌面版" : "用户目录的 ChatGPT"
        } else if path.hasPrefix("/opt/homebrew/") {
            displayName = "Codex CLI（Homebrew）"
        } else if path.hasPrefix("/usr/local/") {
            displayName = "Codex CLI（/usr/local）"
        } else {
            displayName = "Codex CLI（~/.local）"
        }
        return CodexInstallation(
            path: path,
            displayName: displayName,
            accountEmail: nil,
            planType: nil
        )
    }

    private func runAppServer(installation: CodexInstallation) async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let operation = AppServerOperation(installation: installation, continuation: continuation)
            operation.start()
        }
    }

    private func fetchFromSessionLogs() throws -> QuotaSnapshot {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw QuotaError.noLocalSnapshot
        }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff
            else { continue }
            files.append((url, modified))
        }
        files.sort { $0.1 > $1.1 }

        var newest: QuotaSnapshot?
        // 只看最近修改的少量文件，且每个只读尾部少量字节，
        // 避免在大会话目录（可能数 GB）上产生磁盘 IO 风暴。
        for (url, _) in files.prefix(40) {
            guard let data = tail(of: url, maximumBytes: 256_000) else { continue }
            for line in data.split(separator: 0x0A).reversed() {
                guard line.contains(Data(#""rate_limits""#.utf8)),
                      let snapshot = QuotaParser.logSnapshot(from: Data(line))
                else { continue }
                if newest == nil || snapshot.observedAt > newest!.observedAt {
                    newest = snapshot
                }
                break
            }
        }
        guard let newest else {
            throw QuotaError.noLocalSnapshot
        }
        return newest
    }

    private func tail(of url: URL, maximumBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(maximumBytes) ? size - UInt64(maximumBytes) : 0
        try? handle.seek(toOffset: offset)
        return try? handle.readToEnd()
    }
}

private final class AppServerOperation: @unchecked Sendable {
    private let installation: CodexInstallation
    private let continuation: CheckedContinuation<QuotaSnapshot, Error>
    private let lock = NSLock()
    private var finished = false
    private var buffer = Data()
    private var process: Process?
    private var accountResponseReceived = false
    private var accountInfo: CodexAccountInfo?
    private var rateLimitResponse: Data?
    // The pipe callbacks intentionally capture weakly. Retain the operation
    // itself until a response, process exit, or timeout completes it.
    private var keepAlive: AppServerOperation?

    init(installation: CodexInstallation, continuation: CheckedContinuation<QuotaSnapshot, Error>) {
        self.installation = installation
        self.continuation = continuation
    }

    func start() {
        keepAlive = self
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        self.process = process

        process.executableURL = URL(fileURLWithPath: installation.path)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        // 必须持续排空 stderr，否则异常版本大量输出时可能填满管道并卡住子进程。
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] process in
            self?.finishIfNeeded(.failure(
                QuotaError.appServer("进程退出（\(process.terminationStatus)）")
            ))
        }

        do {
            try process.run()
            let requests = [
                #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_quota_menubar","title":"Codex 额度","version":"1.0.0"}}}"#,
                #"{"method":"initialized"}"#,
                #"{"method":"account/read","id":2,"params":{"refreshToken":false}}"#,
                #"{"method":"account/rateLimits/read","id":3,"params":{}}"#
            ].joined(separator: "\n") + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))
        } catch {
            finishIfNeeded(.failure(QuotaError.appServer(error.localizedDescription)))
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finishIfNeeded(.failure(QuotaError.appServer("请求超时")))
        }
    }

    /// 强制终止子进程，并在短暂宽限后确保它已退出（terminate 未生效则 SIGKILL 兑底）。
    private func forceTerminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        let chunks = buffer.split(separator: 0x0A, omittingEmptySubsequences: true)
        let endsWithNewline = buffer.last == 0x0A
        let completeCount = endsWithNewline ? chunks.count : max(0, chunks.count - 1)
        var complete: [Data] = []
        for index in 0..<completeCount {
            complete.append(Data(chunks[index]))
        }
        if endsWithNewline {
            buffer.removeAll(keepingCapacity: true)
        } else if let last = chunks.last {
            buffer = Data(last)
        }
        lock.unlock()

        for line in complete {
            guard
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let id = (object["id"] as? NSNumber)?.intValue
            else { continue }

            switch id {
            case 2:
                recordAccountResponse(QuotaParser.accountInfo(from: line))
            case 3:
                recordRateLimitResponse(line)
            default:
                continue
            }
        }
    }

    private func recordAccountResponse(_ info: CodexAccountInfo?) {
        lock.lock()
        accountResponseReceived = true
        accountInfo = info
        let ready = rateLimitResponse
        lock.unlock()
        if let ready { finishResponse(rateLimitData: ready) }
    }

    private func recordRateLimitResponse(_ data: Data) {
        lock.lock()
        rateLimitResponse = data
        let accountReady = accountResponseReceived
        lock.unlock()
        if accountReady { finishResponse(rateLimitData: data) }
    }

    private func finishResponse(rateLimitData: Data) {
        var identifiedInstallation = installation
        lock.lock()
        let info = accountInfo
        lock.unlock()
        identifiedInstallation.accountEmail = info?.email
        identifiedInstallation.planType = info?.planType
        identifiedInstallation.accountType = info?.accountType

        do {
            let snapshot = try QuotaParser.appServerSnapshot(
                from: rateLimitData,
                installation: identifiedInstallation
            )
            finishIfNeeded(.success(snapshot))
        } catch {
            finishIfNeeded(.failure(error))
        }
    }

    private func finishIfNeeded(_ result: Result<QuotaSnapshot, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            forceTerminate(process)
        }
        continuation.resume(with: result)
        keepAlive = nil
    }
}
