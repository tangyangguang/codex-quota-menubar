import Foundation

struct QuotaSnapshot: Equatable, Sendable {
    let remainingPercent: Double
    let resetsAt: Date
    let observedAt: Date
    let source: Source

    enum Source: String, Sendable {
        case appServer = "Codex 服务"
        case sessionLog = "本地会话"
    }

    var isStale: Bool {
        Date().timeIntervalSince(observedAt) > 15 * 60
    }

    var remainingPercentText: String {
        var text = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            remainingPercent
        )
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }
}

enum QuotaError: LocalizedError, Sendable {
    case noCodexBinary
    case appServer(String)
    case noWeeklyWindow
    case noLocalSnapshot

    var errorDescription: String? {
        switch self {
        case .noCodexBinary:
            return "未找到可用的 Codex 程序"
        case .appServer(let message):
            return "Codex 服务读取失败：\(message)"
        case .noWeeklyWindow:
            return "服务未返回周额度窗口"
        case .noLocalSnapshot:
            return "没有可用的本地额度记录"
        }
    }
}

struct RateWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowMinutes: Double
    let resetsAt: Date
}
