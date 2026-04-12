import AppKit
import SwiftUI
import UserNotifications

@MainActor class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowManager: WindowManager?
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
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        HookInstaller.installIfNeeded()
        CodexFeatureGate.shared.onLaunch()
        logHookHealth()

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

        // Load native plugins from ~/.config/codeisland/plugins/
        NativePluginManager.shared.loadAll()

        // Initialize CodeLight sync (connects to server if configured)
        _ = SyncManager.shared

        // Stats are now handled by the external stats plugin.
        // AnalyticsCollector.shared.start() is called by the plugin's activate().
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    private func logHookHealth() {
        let reports = [HookHealthCheck.checkClaude(), HookHealthCheck.checkCodex()]
        for report in reports where !report.isHealthy {
            for issue in report.errors {
                NSLog("[CodeIsland] Hook health (\(report.agent)): \(issue)")
            }
        }
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
