//
//  WindowManager.swift
//  ClaudeIsland
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.codeisland", category: "Window")

class WindowManager {
    private(set) var windowController: NotchWindowController?

    /// Set up or recreate the notch window
    @MainActor func setupNotchWindow() -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        windowController = NotchWindowController(screen: screen)
        windowController?.showWindow(nil)

        // Hook the notch window up to the customization store so
        // theme / font / visibility / geometry changes reapply
        // in real time. The controller owns the subscription and
        // releases it on deinit.
        MainActor.assumeIsolated {
            windowController?.attachStore(NotchCustomizationStore.shared)
        }

        return windowController
    }
}
