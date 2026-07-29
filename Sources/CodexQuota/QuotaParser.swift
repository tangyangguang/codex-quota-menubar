import Foundation

enum QuotaParser {
    static func appServerSnapshot(
        from data: Data,
        observedAt: Date = Date(),
        installation: CodexInstallation? = nil
    ) throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw QuotaError.appServer(message)
        }

        guard
            let result = root["result"] as? [String: Any],
            let limits = result["rateLimits"] as? [String: Any]
        else {
            throw QuotaError.noWeeklyWindow
        }

        let windows = ["primary", "secondary"].compactMap {
            parseWindow(limits[$0] as? [String: Any], camelCase: true)
        }
        guard let weekly = weeklyWindow(in: windows) else {
            throw QuotaError.noWeeklyWindow
        }
        return snapshot(
            from: weekly,
            observedAt: observedAt,
            source: .appServer,
            installation: installation
        )
    }

    static func accountInfo(from data: Data) -> CodexAccountInfo? {
        guard
            let root = try? jsonObject(data),
            root["error"] == nil,
            let result = root["result"] as? [String: Any],
            let account = result["account"] as? [String: Any]
        else {
            return nil
        }
        return CodexAccountInfo(
            email: account["email"] as? String,
            planType: account["planType"] as? String,
            accountType: account["type"] as? String
        )
    }

    static func logSnapshot(from data: Data) -> QuotaSnapshot? {
        guard
            let root = try? jsonObject(data),
            let payload = root["payload"] as? [String: Any],
            let limits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let windows = ["primary", "secondary"].compactMap {
            parseWindow(limits[$0] as? [String: Any], camelCase: false)
        }
        guard let weekly = weeklyWindow(in: windows) else {
            return nil
        }

        let observedAt: Date
        if let timestamp = root["timestamp"] as? String,
           let date = parseISO8601(timestamp) {
            observedAt = date
        } else {
            observedAt = weekly.resetsAt.addingTimeInterval(-weekly.windowMinutes * 60)
        }
        return snapshot(from: weekly, observedAt: observedAt, source: .sessionLog)
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.appServer("响应格式无效")
        }
        return object
    }

    private static func parseWindow(_ value: [String: Any]?, camelCase: Bool) -> RateWindow? {
        guard let value else { return nil }
        let usedKey = camelCase ? "usedPercent" : "used_percent"
        let durationKey = camelCase ? "windowDurationMins" : "window_minutes"
        let resetKey = camelCase ? "resetsAt" : "resets_at"
        guard
            let used = number(value[usedKey]),
            let duration = number(value[durationKey]),
            let reset = number(value[resetKey]),
            used.isFinite, duration > 0, reset > 0
        else {
            return nil
        }
        return RateWindow(
            usedPercent: used,
            windowMinutes: duration,
            resetsAt: Date(timeIntervalSince1970: reset)
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    // Codex 历史日志里两种合法格式都出现过：有小数秒和无小数秒。
    nonisolated(unsafe) private static let iso8601Formatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return [fractional, wholeSeconds]
    }()

    private static func parseISO8601(_ value: String) -> Date? {
        iso8601Formatters.lazy.compactMap { $0.date(from: value) }.first
    }

    private static func weeklyWindow(in windows: [RateWindow]) -> RateWindow? {
        // 周窗口目前是 10,080 分钟。只接受 6～8 天，并选最接近 7 天的，
        // 避免未来新增月窗口时把“最长窗口”误认成本周额度。
        let weeklyMinutes = 7.0 * 24 * 60
        return windows
            .filter { (6.0 * 24 * 60...8.0 * 24 * 60).contains($0.windowMinutes) }
            .min {
                abs($0.windowMinutes - weeklyMinutes) < abs($1.windowMinutes - weeklyMinutes)
            }
    }

    private static func snapshot(
        from window: RateWindow,
        observedAt: Date,
        source: QuotaSnapshot.Source,
        installation: CodexInstallation? = nil
    ) -> QuotaSnapshot {
        let remaining = 100.0 - window.usedPercent
        return QuotaSnapshot(
            remainingPercent: min(100.0, max(0.0, remaining)),
            resetsAt: window.resetsAt,
            observedAt: observedAt,
            source: source,
            installation: installation
        )
    }
}
