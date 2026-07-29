import AppKit
import SwiftUI

@main
@MainActor
struct CodexQuotaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .onAppear {
                    model.panelDidAppear()
                }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                Text(model.menuBarText)
                    .monospacedDigit()
                if model.hasDataWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                }
            }
            .onAppear {
                model.startAutomaticRefresh()
            }
            .accessibilityLabel("Codex 额度 \(model.menuBarText)")
        }
        .menuBarExtraStyle(.window)
    }
}
