//
//  NotchWindowController.swift
//  ClaudeIsland
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let screen: NSScreen
    let screenID: String
    private var cancellables = Set<AnyCancellable>()

    /// Subscription to NotchCustomizationStore.$customization. Held
    /// as a dedicated cancellable (not lumped into `cancellables`)
    /// so it can be torn down independently if the controller is
    /// ever re-attached to a different store instance.
    private var customizationCancellable: AnyCancellable?
    private var editingCancellable: AnyCancellable?

    /// Active live-edit overlay panel, non-nil only while
    /// store.isEditing == true.
    private var liveEditPanel: NotchLiveEditPanel?

    init(screen: NSScreen) {
        self.screen = screen
        self.screenID = screen.persistentID

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        // Create view model
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch,
            screenID: screen.persistentID
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak notchWindow, weak viewModel] status in
                switch status {
                case .opened:
                    // Accept mouse events when opened so buttons work
                    notchWindow?.ignoresMouseEvents = false
                    notchWindow?.acceptsMouseMovedEvents = true
                    // Elevate above menu bar icons so clicks land on the notch
                    notchWindow?.level = .popUpMenu
                    // Only steal focus on user-initiated opens (click)
                    // Hover/notification opens should not interrupt typing in other apps
                    if viewModel?.shouldActivateOnOpen == true {
                        NSApp.activate(ignoringOtherApps: false)
                        notchWindow?.makeKeyAndOrderFront(nil)
                    } else {
                        notchWindow?.orderFrontRegardless()
                    }
                case .closed, .popping:
                    // Ignore mouse events when closed so clicks pass through
                    notchWindow?.ignoresMouseEvents = true
                    // Lower back to normal level so transparent areas
                    // don't block clicks on menu bar icons
                    notchWindow?.level = .mainMenu + 3
                }
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true

        // Perform boot animation after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.viewModel.performBootAnimation()
        }

        // Start watchdog to auto-recover if main thread hangs with window elevated
        startWatchdog()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Main-thread watchdog

    /// Background timer that pings the main thread every 2 s.
    /// If the main thread doesn't respond within 3 s the window is
    /// forced into pass-through mode so a frozen app can't block input.
    private var watchdogTimer: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.codeisland.watchdog", qos: .utility)

    func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 5, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.pingMainThread()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func pingMainThread() {
        let responded = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { responded.signal() }
        let result = responded.wait(timeout: .now() + 3)
        if result == .timedOut {
            // Main thread is hung — force window into safe state.
            // These calls are thread-safe on NSWindow.
            if let w = window {
                w.ignoresMouseEvents = true
                w.level = .mainMenu + 3
            }
        }
    }

    func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    // MARK: - NotchCustomizationStore integration

    /// Subscribe to the given store and reapply geometry every
    /// time the user's customization changes. Safe to call
    /// multiple times — the previous subscription is released
    /// before the new one is attached.
    ///
    /// Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
    /// section 5.5.
    @MainActor
    func attachStore(_ store: NotchCustomizationStore) {
        customizationCancellable = store.$customization
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyGeometryFromStore()
            }

        // Mirror live edit lifecycle into panel creation / teardown.
        editingCancellable = store.$isEditing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] editing in
                guard let self else { return }
                if editing {
                    self.enterLiveEditMode()
                } else {
                    self.exitLiveEditMode()
                }
            }
    }

    @MainActor
    func enterLiveEditMode() {
        guard liveEditPanel == nil else { return }

        // Force the notch back into the closed state so the live edit
        // overlay's dashed border + arrow buttons line up with the
        // visible closed-state notch instead of an opened chat panel.
        viewModel.notchClose()

        let activeScreen = window?.screen ?? self.screen
        let panel = NotchLiveEditPanel(screen: activeScreen)

        // Pass the panel's screen explicitly into the overlay so its
        // hardware-notch detection doesn't accidentally read NSScreen.main
        // (which can return a non-notched secondary display once the
        // live edit panel becomes key on a multi-monitor setup).
        let overlay = NotchLiveEditOverlay(
            screenID: screenID,
            screenProvider: { activeScreen },
            onExit: { [weak self] in
                self?.exitLiveEditMode()
            }
        )
        let hosting = NSHostingView(rootView: overlay)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)

        panel.orderFrontRegardless()
        panel.makeKey()
        self.liveEditPanel = panel
    }

    @MainActor
    func exitLiveEditMode() {
        guard let panel = liveEditPanel else { return }
        panel.orderOut(nil)
        panel.close()
        self.liveEditPanel = nil
    }

    /// Recompute the panel frame from the current store state +
    /// active screen metrics and animate into the new frame.
    /// Stateless — does NOT write anything back to the store, so
    /// render-time clamping on a smaller screen is transparent
    /// and reversible when the larger screen returns.
    @MainActor
    func applyGeometryFromStore() {
        let store = NotchCustomizationStore.shared
        let geo = store.customization.geometry(for: screenID)
        let window = self.window

        guard let window else { return }
        let activeScreen = window.screen ?? self.screen
        let screenFrame = activeScreen.frame

        let runtimeWidth = NotchHardwareDetector.clampedWidth(
            measuredContentWidth: geo.maxWidth,
            maxWidth: geo.maxWidth
        )
        let clampedOffset = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: runtimeWidth,
            screenWidth: screenFrame.width
        )
        let baseX = (screenFrame.width - runtimeWidth) / 2
        let finalX = screenFrame.origin.x + baseX + clampedOffset

        _ = (finalX, runtimeWidth)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(window.frame, display: true)
        }
    }
}
