import Foundation
import Testing
@testable import CodexQuota

@Test func parsesOfficialAppServerWeeklyWindow() throws {
    let json = """
    {"id":2,"result":{"rateLimits":{
      "primary":{"usedPercent":56.7321,"windowDurationMins":10080,"resetsAt":1785635488},
      "secondary":null
    }}}
    """
    let snapshot = try QuotaParser.appServerSnapshot(
        from: Data(json.utf8),
        observedAt: Date(timeIntervalSince1970: 123)
    )
    #expect(snapshot.remainingPercent == 43.2679)
    #expect(snapshot.remainingPercentText == "43.27")
    #expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1785635488))
    #expect(snapshot.source == .appServer)
}

@Test func choosesWeeklyWindowFromLegacyLog() throws {
    let json = """
    {"timestamp":"2026-07-14T15:24:44.199Z","type":"event_msg","payload":{
      "type":"token_count",
      "rate_limits":{
        "primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1784620000},
        "secondary":{"used_percent":26.0,"window_minutes":10080,"resets_at":1784627847}
      }
    }}
    """
    let snapshot = try #require(QuotaParser.logSnapshot(from: Data(json.utf8)))
    #expect(snapshot.remainingPercent == 74)
    #expect(snapshot.remainingPercentText == "74")
    #expect(snapshot.source == .sessionLog)
}

@Test func displaysAtMostTwoFractionDigits() {
    let base = QuotaSnapshot(
        remainingPercent: 43.2,
        resetsAt: .distantFuture,
        observedAt: .now,
        source: .appServer
    )
    #expect(base.remainingPercentText == "43.2")

    let precise = QuotaSnapshot(
        remainingPercent: 43.2679,
        resetsAt: .distantFuture,
        observedAt: .now,
        source: .appServer
    )
    #expect(precise.remainingPercentText == "43.27")
}

@Test func choosesSevenDayWindowInsteadOfLongerWindow() throws {
    let json = """
    {"id":3,"result":{"rateLimits":{
      "primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1785635488},
      "secondary":{"usedPercent":80,"windowDurationMins":43200,"resetsAt":1787635488}
    }}}
    """
    let snapshot = try QuotaParser.appServerSnapshot(from: Data(json.utf8))
    #expect(snapshot.remainingPercent == 93)
}

@Test func parsesAccountAndTimestampWithoutFractionalSeconds() throws {
    let accountJSON = """
    {"id":2,"result":{"account":{"type":"chatgpt","email":"user@example.com","planType":"plus"},"requiresOpenaiAuth":true}}
    """
    let account = try #require(QuotaParser.accountInfo(from: Data(accountJSON.utf8)))
    #expect(account.email == "user@example.com")
    #expect(account.planType == "plus")
    #expect(account.accountType == "chatgpt")

    let logJSON = """
    {"timestamp":"2026-07-14T15:24:44Z","payload":{"rate_limits":{
      "secondary":{"used_percent":26,"window_minutes":10080,"resets_at":1784627847}
    }}}
    """
    let snapshot = try #require(QuotaParser.logSnapshot(from: Data(logJSON.utf8)))
    #expect(snapshot.observedAt == ISO8601DateFormatter().date(from: "2026-07-14T15:24:44Z"))
}

@Test func rejectsNonWeeklyOnlyResponse() {
    let json = """
    {"id":2,"result":{"rateLimits":{
      "primary":{"usedPercent":7,"windowDurationMins":300,"resetsAt":1785635488}
    }}}
    """
    #expect(throws: QuotaError.self) {
        try QuotaParser.appServerSnapshot(from: Data(json.utf8))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_QUOTA_LIVE_TEST"] == "1"))
func readsLiveQuotaThroughSupportedAppServer() async throws {
    let snapshot = try await QuotaProvider().fetch()
    #expect(snapshot.source == .appServer)
    #expect((0...100).contains(snapshot.remainingPercent))
    #expect(snapshot.resetsAt > Date())
}
