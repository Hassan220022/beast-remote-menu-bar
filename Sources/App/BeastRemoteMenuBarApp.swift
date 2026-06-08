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
        // One-shot sync at launch so the menu bar icon reflects reality without
        // keeping the full polling loop alive in the background. The periodic
        // loop only runs while the popover is open (see BeastMenuView).
        Task { @MainActor in
            await model.refresh()
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
