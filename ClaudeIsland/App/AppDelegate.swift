import AppKit
import SwiftUI
import UserNotifications
import os.log

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowManager: WindowManager?
    private static let logger = Logger(subsystem: "com.codeisland", category: "AppDelegate")
    private var screenObserver: ScreenObserver?

    static var shared: AppDelegate?

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        super.init()
        AppDelegate.shared = self
        UserDefaults.standard.register(defaults: ["usageWarningThreshold": 90])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application did finish launching")
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        HookInstaller.installIfNeeded()

        // Request notification permission — .accessory policy blocks the system dialog,
        // so temporarily switch to .regular when permission is not yet determined.
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .notDetermined {
                    NSApplication.shared.setActivationPolicy(.regular)
                    center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                        DispatchQueue.main.async {
                            NSApplication.shared.setActivationPolicy(.accessory)
                        }
                    }
                } else {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
            }
        }

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        // Initialize CodeLight sync (connects to server if configured)
        _ = SyncManager.shared

        // Compute "yesterday" activity report and schedule midnight refresh.
        // Runs off the main thread inside the collector; launch is instant.
        Task { @MainActor in
            AnalyticsCollector.shared.start()
        }

        // Start session monitoring (includes TCP relay for remote hooks)
        sessionMonitor.startMonitoring()
    }

    private let sessionMonitor = ClaudeSessionMonitor()

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionMonitor.stopMonitoring()
        screenObserver = nil
    }

    // Allow notifications to show even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.codeisland.app"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
