import Foundation

struct CodexInstallation: Identifiable, Equatable, Sendable {
    let path: String
    let displayName: String
    var accountEmail: String?
    var planType: String?
    var accountType: String? = nil
    var inspectionFailed = false

    var id: String { path }

    var accountLabel: String {
        if let accountEmail, !accountEmail.isEmpty {
            if let planType, !planType.isEmpty {
                return "\(accountEmail) · \(Self.displayName(forPlan: planType))"
            }
            return accountEmail
        }
        if accountType == "apiKey" { return "API Key" }
        if accountType == "amazonBedrock" { return "Amazon Bedrock" }
        return inspectionFailed ? "不可用或未登录" : "账号信息待读取"
    }

    private static func displayName(forPlan plan: String) -> String {
        switch plan {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "team": return "Team"
        case "business", "self_serve_business_usage_based": return "Business"
        case "enterprise", "enterprise_cbp_usage_based": return "Enterprise"
        case "edu": return "Edu"
        default: return plan
        }
    }
}

struct CodexAccountInfo: Equatable, Sendable {
    let email: String?
    let planType: String?
    let accountType: String?
}

struct QuotaSnapshot: Equatable, Sendable {
    let remainingPercent: Double
    let resetsAt: Date
    let observedAt: Date
    let source: Source
    var installation: CodexInstallation? = nil

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
