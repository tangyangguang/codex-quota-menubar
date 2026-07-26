import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var model: AppModel

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
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 286)
    }
}
