import AppKit
import Foundation
import Observation

/// 自动刷新间隔的可选项（秒）。默认 30 秒。
enum RefreshInterval: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case threeMinutes = 180
    case fiveMinutes = 300

    static let `default`: RefreshInterval = .thirtySeconds

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .thirtySeconds: return "30 秒"
        case .oneMinute: return "1 分钟"
        case .twoMinutes: return "2 分钟"
        case .threeMinutes: return "3 分钟"
        case .fiveMinutes: return "5 分钟"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: QuotaSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var installations: [CodexInstallation]
    private(set) var isInspectingInstallations = false
    private let provider = QuotaProvider()
    @ObservationIgnored private var automaticRefreshTimer: DispatchSourceTimer?
    @ObservationIgnored private var automaticRefreshActivity: NSObjectProtocol?
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var refreshRequestedWhileBusy = false
    @ObservationIgnored private var didRegisterSleepWakeObservers = false

    private static let refreshIntervalDefaultsKey = "refreshIntervalSeconds"
    private static let selectedInstallationDefaultsKey = "selectedCodexExecutable"

    /// 当前自动刷新间隔。修改后会持久化并重建定时器。
    var refreshInterval: RefreshInterval {
        didSet {
            guard oldValue != refreshInterval else { return }
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Self.refreshIntervalDefaultsKey)
            restartAutomaticRefresh()
        }
    }

    /// 空字符串表示自动选择；指定后只读取该安装，避免静默显示另一个账号。
    var selectedInstallationID: String {
        didSet {
            guard oldValue != selectedInstallationID else { return }
            if selectedInstallationID.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.selectedInstallationDefaultsKey)
            } else {
                UserDefaults.standard.set(
                    selectedInstallationID,
                    forKey: Self.selectedInstallationDefaultsKey
                )
            }
            refresh()
        }
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalDefaultsKey)
        refreshInterval = RefreshInterval(rawValue: stored) ?? .default
        installations = QuotaProvider.availableInstallations()
        selectedInstallationID = UserDefaults.standard.string(
            forKey: Self.selectedInstallationDefaultsKey
        ) ?? ""
    }

    var menuBarText: String {
        guard let snapshot else { return "--%" }
        return "\(snapshot.remainingPercentText)%"
    }

    var hasDataWarning: Bool {
        guard let snapshot else { return false }
        return errorMessage != nil || snapshot.isStale
    }

    func refresh() {
        guard !isRefreshing else {
            // 用户刚切换账号或主动打开面板时，不应因为上一轮尚未结束而丢掉刷新。
            refreshRequestedWhileBusy = true
            return
        }
        isRefreshing = true
        Task {
            do {
                let preferred = selectedInstallationID.isEmpty ? nil : selectedInstallationID
                let value = try await provider.fetch(preferredExecutable: preferred)
                snapshot = value
                mergeInstallation(from: value)
                errorMessage = value.isStale ? "本地记录已陈旧，打开 Codex 后再刷新" : nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
            if refreshRequestedWhileBusy {
                refreshRequestedWhileBusy = false
                refresh()
            }
        }
    }

    func startAutomaticRefresh() {
        registerSleepWakeObservers()
        guard !isAsleep, automaticRefreshTimer == nil else { return }

        refresh()
        scheduleAutomaticRefresh()
    }

    /// 面板打开：立即刷新拿最新数据，提升打开瞬间的新鲜度。
    func panelDidAppear() {
        guard !isAsleep else { return }
        refresh()
    }

    /// 仅在用户打开设置时探测各安装对应的账号，不增加平时 30 秒刷新的成本。
    func settingsDidAppear() {
        guard !isInspectingInstallations else { return }
        isInspectingInstallations = true
        Task {
            installations = await provider.inspectInstallations()
            isInspectingInstallations = false
        }
    }

    private func mergeInstallation(from snapshot: QuotaSnapshot) {
        guard let installation = snapshot.installation else { return }
        if let index = installations.firstIndex(where: { $0.id == installation.id }) {
            installations[index] = installation
        } else {
            installations.append(installation)
        }
    }

    /// 按当前间隔重建定时器（用户切换刷新间隔后调用）。
    func restartAutomaticRefresh() {
        automaticRefreshTimer?.cancel()
        automaticRefreshTimer = nil
        scheduleAutomaticRefresh()
    }

    private func scheduleAutomaticRefresh() {
        guard !isAsleep, automaticRefreshTimer == nil else { return }
        beginAutomaticRefreshActivity()

        // MenuBarExtra 面板关闭后，普通 RunLoop Timer 可能被 App Nap 大幅延后。
        // DispatchSourceTimer 配合显式 activity，保证用户设定的 30 秒后台刷新语义。
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .seconds(refreshInterval.rawValue),
            repeating: .seconds(refreshInterval.rawValue),
            leeway: .seconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        automaticRefreshTimer = timer
        timer.resume()
    }

    private func beginAutomaticRefreshActivity() {
        guard automaticRefreshActivity == nil else { return }
        automaticRefreshActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "按用户设置在后台刷新 Codex 额度"
        )
    }

    private func endAutomaticRefreshActivity() {
        guard let activity = automaticRefreshActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        automaticRefreshActivity = nil
    }

    // MARK: - 休眠 / 唤醒

    /// 监听系统休眠与唤醒：休眠时停掉定时器，唤醒后立即刷新并恢复。
    private func registerSleepWakeObservers() {
        guard !didRegisterSleepWakeObservers else { return }
        didRegisterSleepWakeObservers = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pauseAutomaticRefresh() }
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeAutomaticRefresh() }
        }
    }

    private func pauseAutomaticRefresh() {
        isAsleep = true
        automaticRefreshTimer?.cancel()
        automaticRefreshTimer = nil
        endAutomaticRefreshActivity()
    }

    private func resumeAutomaticRefresh() {
        isAsleep = false
        guard automaticRefreshTimer == nil else { return }
        refresh()
        scheduleAutomaticRefresh()
    }
}
