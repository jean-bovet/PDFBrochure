import SwiftUI
import Sparkle

@main
struct PDFBrochureApp: App {
    @StateObject private var model = PDFBrochureModel()

    // Owned by the App so the updater outlives any single window. Starting
    // the updater immediately is what enables the background "check on launch"
    // schedule controlled by SUEnableAutomaticChecks in Info.plist.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("PDFBrochure") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowResizability(.contentSize)
        .commands {
            // Slot the menu item into the App menu, just under "About PDFBrochure".
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
