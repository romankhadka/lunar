import Foundation
import ServiceManagement

/// Observable launch-at-login state, so the menu toggle redraws after a change.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = LaunchAtLogin.readStatus()

    func toggle() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.ui.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        isEnabled = Self.readStatus()
    }

    nonisolated private static func readStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
