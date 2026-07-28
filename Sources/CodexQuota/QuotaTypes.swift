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
            return "未检测到 Codex。请先安装并登录 ChatGPT 桌面版（或 Codex CLI）后重试。"
        case .appServer(let message):
            return "读取额度失败：\(message)。请确认 ChatGPT / Codex 已登录。"
        case .noWeeklyWindow:
            return "服务未返回周额度数据，请稍后再试。"
        case .noLocalSnapshot:
            return "暂无额度数据。请先安装并登录 ChatGPT 桌面版（或 Codex CLI）。"
        }
    }
}

struct RateWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowMinutes: Double
    let resetsAt: Date
}
