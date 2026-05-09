import SwiftUI
import Sparkle

/// Renders the "Check for Updates…" menu item and reflects Sparkle's
/// `canCheckForUpdates` so the item disables itself while a check is already
/// in flight.
struct CheckForUpdatesView: View {
    @ObservedObject private var checker: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checker = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checker.canCheckForUpdates)
    }
}

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

// No #Preview here: SPUUpdater can't be constructed standalone; the only
// sensible preview is the live one inside the running app's menu bar.
