import AppKit
import Foundation
import SwiftUI

@main
struct BeastRemoteMenuBarApp: App {
    private let panelWidth: CGFloat = 360
    private let panelHeight: CGFloat = 640
    @StateObject private var model: BeastRemoteModel

    init() {
        let model = BeastRemoteModel()
        _model = StateObject(wrappedValue: model)
        // Start the always-on polling loop so state is never fully stale on
        // reopen. The loop runs at idle cadence (15s) when the popover is
        // closed and switches to fast cadence (2s) while it's open.
        Task { @MainActor in
            model.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            BeastMenuView(model: model)
                .frame(
                    minWidth: panelWidth,
                    idealWidth: panelWidth,
                    maxWidth: panelWidth,
                    minHeight: panelHeight,
                    idealHeight: panelHeight,
                    maxHeight: panelHeight
                )
        } label: {
            Label("Beast", systemImage: model.connected ? "music.note" : "exclamationmark.triangle")
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: panelWidth, height: panelHeight)
        .windowResizability(.contentSize)
        .commands {
            // Standard Cmd+Q quit affordance. MenuBarExtra apps don't get the
            // default app menu, so wire the shortcut explicitly.
            CommandGroup(replacing: .appTermination) {
                Button("Quit Beast Remote") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
