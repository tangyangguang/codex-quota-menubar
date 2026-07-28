import Foundation

enum QuotaParser {
    static func appServerSnapshot(from data: Data, observedAt: Date = Date()) throws -> QuotaSnapshot {
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
        return snapshot(from: weekly, observedAt: observedAt, source: .appServer)
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

    // ISO8601DateFormatter 的 date(from:) 是线程安全的（Apple 文档保证），
    // 缓存一个实例避免每次解析都新建。
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseISO8601(_ value: String) -> Date? {
        iso8601Formatter.date(from: value)
    }

    private static func weeklyWindow(in windows: [RateWindow]) -> RateWindow? {
        // Codex currently reports a weekly window as 10,080 minutes. Accept six
        // days or longer so small server-side duration rounding remains compatible.
        windows
            .filter { $0.windowMinutes >= 6 * 24 * 60 }
            .max { $0.windowMinutes < $1.windowMinutes }
    }

    private static func snapshot(
        from window: RateWindow,
        observedAt: Date,
        source: QuotaSnapshot.Source
    ) -> QuotaSnapshot {
        let remaining = 100.0 - window.usedPercent
        return QuotaSnapshot(
            remainingPercent: min(100.0, max(0.0, remaining)),
            resetsAt: window.resetsAt,
            observedAt: observedAt,
            source: source
        )
    }
}
