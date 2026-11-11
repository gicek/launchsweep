import SwiftUI

@main
struct LaunchSweepApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    private static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        Window("LaunchSweep", id: "main") {
            // As the host of the unit tests, the app shows nothing and leaves the real database alone.
            if !Self.isHostingTests {
                ContentView()
            }
        }
        // The content draws its own background up to the top edge; only the window buttons remain.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 640)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
