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
    private let provider = QuotaProvider()
    @ObservationIgnored private var automaticRefreshTimer: Timer?
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var isAsleep = false

    private static let refreshIntervalDefaultsKey = "refreshIntervalSeconds"

    /// 面板关闭（后台）时的保底刷新间隔：至少 5 分钟。
    /// 额度数据以小时计变化，后台无需频繁拉起 255MB 的 codex 进程。
    private static let backgroundMinimumInterval: TimeInterval = 300

    /// 当前自动刷新间隔。修改后会持久化并重建定时器。
    var refreshInterval: RefreshInterval {
        didSet {
            guard oldValue != refreshInterval else { return }
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Self.refreshIntervalDefaultsKey)
            restartAutomaticRefresh()
        }
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalDefaultsKey)
        refreshInterval = RefreshInterval(rawValue: stored) ?? .default
    }

    /// 根据面板是否可见选择实际调度间隔：
    /// 可见时用用户设定的高频间隔，后台时取与保底间隔的较大值。
    private var activeInterval: TimeInterval {
        if isPanelVisible {
            return refreshInterval.seconds
        }
        return max(refreshInterval.seconds, Self.backgroundMinimumInterval)
    }

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

        registerSleepWakeObservers()
        refresh()
        scheduleAutomaticRefresh()
    }

    /// 面板打开：立即刷新拿最新数据，并切到高频间隔。
    func panelDidAppear() {
        isPanelVisible = true
        guard !isAsleep else { return }
        refresh()
        restartAutomaticRefresh()
    }

    /// 面板关闭：切回后台保底间隔，减少无人查看时的拉起次数。
    func panelDidDisappear() {
        isPanelVisible = false
        guard !isAsleep else { return }
        restartAutomaticRefresh()
    }

    /// 按当前情境重建定时器（刷新间隔或面板可见性变化后调用）。
    func restartAutomaticRefresh() {
        automaticRefreshTimer?.invalidate()
        automaticRefreshTimer = nil
        scheduleAutomaticRefresh()
    }

    private func scheduleAutomaticRefresh() {
        guard !isAsleep else { return }
        let timer = Timer(timeInterval: activeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticRefreshTimer = timer
    }

    // MARK: - 休眠 / 唤醒

    /// 监听系统休眠与唤醒：休眠时停掉定时器，唤醒后立即刷新并恢复。
    private func registerSleepWakeObservers() {
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
        automaticRefreshTimer?.invalidate()
        automaticRefreshTimer = nil
    }

    private func resumeAutomaticRefresh() {
        isAsleep = false
        guard automaticRefreshTimer == nil else { return }
        refresh()
        scheduleAutomaticRefresh()
    }
}
