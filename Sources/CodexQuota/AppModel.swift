import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: QuotaSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private let provider = QuotaProvider()
    @ObservationIgnored private var automaticRefreshTimer: Timer?

    var menuBarText: String {
        guard let snapshot else { return "--%" }
        return "\(snapshot.remainingPercentText)%"
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let value = try await provider.fetch()
                snapshot = value
                errorMessage = value.isStale ? "本地记录已陈旧，打开 Codex 后再刷新" : nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    func startAutomaticRefresh() {
        guard automaticRefreshTimer == nil else { return }

        refresh()

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticRefreshTimer = timer
    }
}
