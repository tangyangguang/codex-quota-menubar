import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var isShowingSettings = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 E HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        Group {
            if isShowingSettings {
                settingsView
            } else {
                mainView
            }
        }
        .padding(16)
        .frame(width: 286)
    }

    // MARK: - 主页面

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Codex 本周额度")
                    .font(.headline)
                Spacer()
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let snapshot = model.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(snapshot.remainingPercentText)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("% 剩余")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow {
                        Text("每周重置")
                            .foregroundStyle(.secondary)
                        Text(Self.dateFormatter.string(from: snapshot.resetsAt))
                    }
                    GridRow {
                        Text("最后更新")
                            .foregroundStyle(.secondary)
                        Text(Self.timeFormatter.string(from: snapshot.observedAt))
                    }
                    if let installation = snapshot.installation {
                        GridRow {
                            Text("当前账号")
                                .foregroundStyle(.secondary)
                            Text(installation.accountEmail ?? installation.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .font(.system(size: 12))
            } else {
                Text(model.isRefreshing ? "正在读取额度…" : "暂无额度数据")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(height: 66)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                if let source = model.snapshot?.source.rawValue {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    model.settingsDidAppear()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isShowingSettings = true
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("设置")

                Spacer()
                    .frame(width: 28)

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 设置页面

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isShowingSettings = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer()

                Text("设置")
                    .font(.headline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("显示哪个 Codex 账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isInspectingInstallations {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                Picker("", selection: $model.selectedInstallationID) {
                    Text("自动选择（优先 ChatGPT）")
                        .tag("")
                    ForEach(model.installations) { installation in
                        Text("\(installation.displayName) · \(installation.accountLabel)")
                            .tag(installation.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("选定后只读取该安装，不会静默切换到其他账号。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("自动刷新间隔")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(RefreshInterval.allCases) { interval in
                    Button {
                        model.refreshInterval = interval
                    } label: {
                        HStack {
                            Text(interval.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.refreshInterval == interval {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.refreshInterval == interval
                                      ? Color.primary.opacity(0.06)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.callout)
                }
            }
        }
    }
}
