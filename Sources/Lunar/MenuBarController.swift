import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var coordinator: AppCoordinator
    let openPhasesFolder: () -> Void
    let openLog: () -> Void
    let toggleLaunchAtLogin: () -> Void
    let isLaunchAtLoginEnabled: Bool

    var body: some View {
        if let p = coordinator.currentPhase {
            Text("Today: \(p.phaseName.displayName) · \(Int((p.illumination*100).rounded()))%")
        } else {
            Text("Lunar is starting…")
        }
        if let n = coordinator.nextPhase {
            let df: DateFormatter = {
                let f = DateFormatter(); f.dateFormat = "MMM d"; return f
            }()
            Text("Next: \(n.name.displayName) · \(df.string(from: n.date))")
        }
        if let err = coordinator.lastError {
            Text("Error: \(err)").foregroundColor(.red)
        }
        Divider()
        Button("Refresh This Desktop") { try? coordinator.updateWallpaper(force: true) }
        Button("Open Phases Folder…", action: openPhasesFolder)
        Button("Open Log", action: openLog)
        Divider()
        Toggle("Launch at Login",
               isOn: Binding(get: { isLaunchAtLoginEnabled },
                              set: { _ in toggleLaunchAtLogin() }))
        Divider()
        Button("Quit Lunar") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
