//
//  NotchView.swift
//  ClaudeIsland
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var sessionMonitor = ClaudeSessionMonitor()
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @State private var previousPendingIds: Set<String> = []
    @State private var previousWaitingForInputIds: Set<String> = []
    @State private var previousWaitingForQuestionIds: Set<String> = []
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = true
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false
    @State private var autoCollapseTimer: DispatchWorkItem? = nil
    /// Track previous phases to detect transitions from working states to waitingForInput
    @State private var previousPhases: [String: SessionPhase] = [:]

    @AppStorage("smartSuppression") private var smartSuppression: Bool = true
    @AppStorage("autoCollapseOnMouseLeave") private var autoCollapseOnMouseLeave: Bool = true
    @AppStorage("compactCollapsed") private var compactCollapsed: Bool = false
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @ObservedObject private var controller = CompletionPanelController.shared
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        let now = Date()
        let displayDuration: TimeInterval = 30  // Show checkmark for 30 seconds

        return sessionMonitor.instances.contains { session in
            guard session.phase == .waitingForInput else { return false }
            // Only show if within the 30-second display window
            if let enteredAt = waitingForInputTimestamps[session.stableId] {
                return now.timeIntervalSince(enteredAt) < displayDuration
            }
            return false
        }
    }

    /// Whether any Claude session is waiting for a question answer
    private var hasWaitingForQuestion: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForQuestion }
    }

    /// Whether there are any active (non-ended) sessions
    private var hasActiveSessions: Bool {
        sessionMonitor.instances.contains { $0.phase != .ended }
    }

    /// The most urgent animation state across all active sessions.
    /// Priority: needsYou > error > working > thinking > done > idle
    private var mostUrgentAnimationState: AnimationState {
        var best: AnimationState = .idle
        for session in sessionMonitor.instances {
            let state = session.phase.animationState
            if animationPriority(state) > animationPriority(best) {
                best = state
            }
        }
        return best
    }

    /// Priority ordering for animation states (higher = more urgent)
    private func animationPriority(_ state: AnimationState) -> Int {
        switch state {
        case .idle: return 0
        case .done: return 1
        case .thinking: return 2
        case .working: return 3
        case .error: return 4
        case .needsYou: return 5
        }
    }

    /// The highest-priority session: urgent states first, then most recently active
    private var highestPrioritySession: SessionState? {
        sessionMonitor.instances
            .filter { $0.phase != .ended }
            .max { a, b in
                let pa = animationPriority(a.phase.animationState)
                let pb = animationPriority(b.phase.animationState)
                if pa != pb { return pa < pb }
                return a.lastActivity < b.lastActivity
            }
    }

    /// Split text into project name and status for separate styling
    private var activityTextParts: (project: String, status: String)? {
        guard let session = highestPrioritySession else { return nil }

        let project = session.projectName
        switch session.phase {
        case .processing:
            let status = session.lastToolName ?? L10n.working
            return (project, status)
        case .waitingForApproval:
            let status = session.pendingToolName.map { L10n.approveWhat($0) } ?? L10n.needsApproval
            return (project, status)
        case .waitingForQuestion:
            return (project, "Needs answer")
        case .waitingForInput:
            // Show smart summary when available, otherwise fall back to "done"
            let status = session.smartSummary ?? L10n.done
            return (project, status)
        case .compacting:
            return (project, L10n.compacting)
        case .idle:
            return (project, L10n.idle)
        case .ended:
            return nil
        }
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        // Always honor the user's notchHeight — even on hardware-
        // notched MacBooks. The software Mio Island can be taller or
        // shorter than the physical camera cutout; previously this
        // branch pinned to viewModel.deviceNotchRect.height, which
        // was captured at launch and never updated, so the live edit
        // height buttons appeared to do nothing on MacBook.
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        let height = NotchHardwareDetector.clampedHeight(geo.notchHeight)
        return CGSize(
            width: viewModel.deviceNotchRect.width,
            height: height
        )
    }

    /// Extra width for expanding activities (like Dynamic Island).
    ///
    /// Reads from the per-screen `ScreenGeometry.maxWidth` so the live edit
    /// "resize" arrow buttons visibly grow / shrink the notch as the
    /// user drives the slider. The user's `maxWidth` is the total
    /// closed-with-content width — subtracting the hardware notch
    /// width yields the wing expansion.
    ///
    /// Compact mode caps at 100pt regardless of the user's max so the
    /// dot+icon+count layout never overflows the visible notch ring.
    /// Full mode honors the user's max directly. Idle state (no
    /// active sessions) is always 0 — the notch shrinks tight around
    /// the hardware shape.
    private var expansionWidth: CGFloat {
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        let userMax = geo.maxWidth
        let userExpansion = max(0, userMax - closedNotchSize.width)
        if compactCollapsed {
            return min(100, userExpansion)
        }
        return userExpansion
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    /// Width of the closed content (notch + any expansion)
    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    /// While in Live Edit, the closed notch is pinned to the exact
    /// configured width/height so the ◀▶/▲▼ arrows produce visible,
    /// WYSIWYG feedback even when there is no active session content
    /// to fill the expansion wings. Outside edit mode, the notch keeps
    /// its content-hugging behavior — no always-on black bar. (Issue #30)
    private var forceClosedPreviewSize: Bool {
        notchStore.isEditing && viewModel.status != .opened
    }

    /// User-customized horizontal offset of the notch, clamped at
    /// render time so an off-screen stored value on a smaller
    /// secondary display never bleeds past the edge. Spec 5.5.
    private var clampedHorizontalOffset: CGFloat {
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        return NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
            screenWidth: viewModel.screenRect.width
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .notchPalette()
                    .frame(
                        minWidth: forceClosedPreviewSize ? closedContentWidth : nil,
                        maxWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
                        minHeight: forceClosedPreviewSize ? closedNotchSize.height : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(NotchPalette.for(notchStore.customization.theme).bg)
                    .animation(.easeInOut(duration: 0.3), value: notchStore.customization.theme)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(NotchPalette.for(notchStore.customization.theme).bg)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                            .animation(.easeInOut(duration: 0.3), value: notchStore.customization.theme)
                    }
                    .shadow(color: notchShadowColor, radius: notchShadowRadius)
                    .frame(
                        minWidth: forceClosedPreviewSize ? closedContentWidth : nil,
                        maxWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
                        minHeight: forceClosedPreviewSize ? closedNotchSize.height : nil,
                        maxHeight: viewModel.status == .opened
                            ? notchSize.height
                            : (forceClosedPreviewSize ? closedNotchSize.height : nil),
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: activityCoordinator.expandingActivity)
                    .animation(.smooth, value: hasActiveSessions)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }

                        // Auto-collapse on mouse leave (Task 2)
                        if hovering {
                            // Mouse re-entered: cancel pending auto-collapse
                            autoCollapseTimer?.cancel()
                            autoCollapseTimer = nil
                        } else if autoCollapseOnMouseLeave && viewModel.status == .opened {
                            // Mouse left: start 1.5s countdown unless waiting for approval or question
                            let hasApprovalPending = sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
                            let hasQuestionPending = sessionMonitor.instances.contains { $0.phase.isWaitingForQuestion }
                            if !hasApprovalPending && !hasQuestionPending {
                                let workItem = DispatchWorkItem { [self] in
                                    if !isHovering && viewModel.status == .opened {
                                        viewModel.notchClose()
                                    }
                                }
                                autoCollapseTimer = workItem
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
                            }
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            // Sticky Completion Panel: clicking the notch bar dismisses it.
                            if case .completion(let entry) = viewModel.contentType,
                               entry.variant.isSticky {
                                controller.dismissFront(stableId: entry.stableId)
                                return
                            }
                            if viewModel.status != .opened {
                                viewModel.notchOpen(reason: .click)
                            }
                        }
                    )
                    .offset(x: clampedHorizontalOffset)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionMonitor.startMonitoring()
            // Always show notch (standby state shows even with no sessions)
            isVisible = true
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: sessionMonitor.pendingInstances) { _, sessions in
            handlePendingSessionsChange(sessions)
        }
        .onChange(of: sessionMonitor.instances) { _, instances in
            handleProcessingChange()
            handleWaitingForInputChange(instances)
            handleWaitingForQuestionChange(instances)
        }
        .onChange(of: expansionWidth) { _, newWidth in
            viewModel.currentExpansionWidth = newWidth
        }
        .task {
            // Sync the initial expansion width into the view model on
            // first appearance so the hit-test region matches the
            // visible notch from the very first frame.
            viewModel.currentExpansionWidth = expansionWidth
        }
        .onChange(of: controller.state.front) { _, front in
            DebugLogger.log("CP/onChange", "front=\(front?.stableId.prefix(8) ?? "nil") variantId=\(front?.id.uuidString.prefix(8) ?? "nil") contentType=\(viewModel.contentType.id)")
            if let front {
                if case .completion(let current) = viewModel.contentType,
                   current.stableId == front.stableId,
                   current.id == front.id {
                    return
                }
                viewModel.contentType = .completion(front)
                viewModel.notchOpen(reason: .notification)
            } else if case .completion = viewModel.contentType {
                // Spec §1: instances list / chat = manual user action only.
                // After Completion Panel auto-dismisses, close the notch
                // entirely — do NOT auto-show instances list (that's the
                // exact regression the user flagged at smoke time).
                viewModel.notchClose()
            }
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        activityCoordinator.expandingActivity.show && activityCoordinator.expandingActivity.type == .claude
    }

    /// Whether to show the expanded closed state (any active sessions)
    private var showClosedActivity: Bool {
        isProcessing || hasPendingPermission || hasWaitingForQuestion || hasWaitingForInput || hasActiveSessions
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - hidden when opened, full when closed
            headerRow
                .frame(height: viewModel.status == .opened ? 4 : max(24, closedNotchSize.height))

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24, alignment: .top) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            if viewModel.status == .opened {
                // Opened state: invisible spacer only — no icon
                Color.clear
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: viewModel.status == .opened)
                    .frame(width: 1, height: 1)
            } else if hasActiveSessions {
                // Closed with sessions: Dynamic Island style content
                CollapsedNotchContent(
                    sessions: sessionMonitor.instances,
                    mostUrgentState: mostUrgentAnimationState,
                    activityTextParts: activityTextParts,
                    notchHeight: closedNotchSize.height,
                    isBouncing: isBouncing,
                    activityNamespace: activityNamespace,
                    waitingForInputTimestamps: waitingForInputTimestamps,
                    compactMode: compactCollapsed,
                    hasPhysicalNotch: viewModel.hasPhysicalNotch,
                    notchWidth: closedNotchSize.width
                )
                .clipped()
            } else {
                standbyContent
            }
        }
        .frame(height: closedNotchSize.height)
        .clipped()
    }

    // MARK: - Shadow helpers

    private var notchShadowColor: Color {
        (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear
    }

    private var notchShadowRadius: CGFloat { 6 }

    // MARK: - Standby Content

    /// Mirrors the left wing of CollapsedNotchContent (compact style):
    /// idle dot + buddy icon, left-aligned, full active-state width.
    private var standbyContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.idleColor.opacity(theme.isRetroArcade ? 0.75 : 0.3))
                    .frame(width: 6, height: 6)
                if notchStore.customization.showBuddy {
                    PixelCharacterView(state: .idle)
                        .scaleEffect(0.28)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.leading, 6)
            Spacer()
        }
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 12) {
            Spacer()

            // Menu toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.toggleMenu()
                }
            } label: {
                Image(systemName: viewModel.contentType == .menu ? "xmark" : "line.3.horizontal")
                    .notchFont(11, weight: .medium)
                    .notchSecondaryForeground()
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .instances:
                ClaudeInstancesView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .menu:
                NotchMenuView(viewModel: viewModel)
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .question(let session):
                QuestionContentWrapper(
                    session: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .plugin(let pluginId):
                PluginContentView(pluginId: pluginId, viewModel: viewModel)
            case .completion(let entry):
                CompletionPanelView(entry: entry)
            }

            // Plugin footer slot (e.g. mini player bar) — only if plugins provide one
            if NativePluginManager.shared.loadedPlugins.contains(where: { $0.viewForSlot("footer") != nil }) {
                PluginSlotView(slot: "footer")
            }
        }
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
        // Removed .id() - was causing view recreation and performance issues
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if hasActiveSessions {
            // Show notch whenever there are active sessions
            if isAnyProcessing || hasPendingPermission || hasWaitingForQuestion {
                activityCoordinator.showActivity(type: .claude)
            } else {
                activityCoordinator.hideActivity()
            }
            isVisible = true
        } else {
            // No sessions: hide activity but keep notch visible in standby
            activityCoordinator.hideActivity()
            isVisible = true
        }
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear waiting-for-input timestamps only when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover {
                waitingForInputTimestamps.removeAll()
            }
            // If a session is waiting for a question, auto-show the question UI
            // (handles the case where user closed notch accidentally and reopened)
            if case .instances = viewModel.contentType,
               let questionSession = sessionMonitor.instances.first(where: { $0.phase.isWaitingForQuestion }) {
                viewModel.showQuestion(for: questionSession)
            }
        case .closed:
            // Always remain visible — standby content shows even with no sessions
            break
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.stableId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        if !newPendingIds.isEmpty && viewModel.status == .closed {
            let termFront = TerminalVisibilityDetector.isTerminalFrontmost()
            if smartSuppression && termFront {
                DebugLogger.log("Suppress", "[pending] Suppressed — terminal frontmost")
            } else {
                // Only AskUserQuestion goes to the legacy question UI.
                // Non-AskUserQuestion pending tools are handled by
                // CompletionPanelController via its SessionStore sink.
                if let askSession = sessions.first(where: {
                    newPendingIds.contains($0.stableId) && $0.pendingToolName == "AskUserQuestion"
                }) {
                    viewModel.notchOpen(reason: .notification)
                    viewModel.showQuestion(for: askSession)
                }
            }
        }

        previousPendingIds = currentIds
    }

    private func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.stableId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Track timestamps for newly waiting sessions
        let now = Date()
        for session in waitingForInputSessions where newWaitingIds.contains(session.stableId) {
            waitingForInputTimestamps[session.stableId] = now
        }

        // Clean up timestamps for sessions no longer waiting
        let staleIds = Set(waitingForInputTimestamps.keys).subtracting(currentIds)
        for staleId in staleIds {
            waitingForInputTimestamps.removeValue(forKey: staleId)
        }

        // Bounce the notch when a session newly enters waitingForInput state
        if !newWaitingIds.isEmpty {
            // Get the sessions that just entered waitingForInput
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.stableId) }

            // Q1: Codex sessions stay silent (no bounce / no sound / no auto-popup)
            // unless the user explicitly opts in. Reason: Codex turns are short and
            // claude-mem–like short-lived child sessions end up triggering constant
            // feedback for things the user didn't initiate.
            //
            // Q4 safety net: sessions with no user-visible content at all
            // (no tool calls, no messages, no summary) are also suppressed.
            // Catches claude-mem plugin-spawned Claude children that fire
            // SessionStart + Stop within a second, and any future event
            // source that delivers malformed / empty hook payloads.
            let codexNotifyOnComplete = UserDefaults.standard.object(forKey: "codexNotifyOnComplete") as? Bool ?? false
            let notifiableSessions = newlyWaitingSessions.filter { session in
                guard !session.hasNoContentYet else { return false }
                return session.codexTranscriptPath == nil || codexNotifyOnComplete
            }

            if !notifiableSessions.isEmpty {
                // Play notification sound if the session is not actively focused
                if let soundName = AppSettings.notificationSound.soundName {
                    // Check if we should play sound (async check for tmux pane focus)
                    Task {
                        let shouldPlaySound = await shouldPlayNotificationSound(for: notifiableSessions)
                        if shouldPlaySound {
                            await MainActor.run {
                                NSSound(named: soundName)?.play()
                            }
                        }
                    }
                }

                // Trigger bounce animation to get user's attention
                DispatchQueue.main.async {
                    isBouncing = true
                    // Bounce back after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isBouncing = false
                    }
                }
            }

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        // Update previous phases for all current instances
        for instance in instances {
            previousPhases[instance.stableId] = instance.phase
        }
        // Clean up phases for sessions that no longer exist
        let currentStableIds = Set(instances.map { $0.stableId })
        for key in previousPhases.keys where !currentStableIds.contains(key) {
            previousPhases.removeValue(forKey: key)
        }

        previousWaitingForInputIds = currentIds
    }

    private func handleWaitingForQuestionChange(_ instances: [SessionState]) {
        let questionSessions = instances.filter { $0.phase.isWaitingForQuestion }
        let currentIds = Set(questionSessions.map { $0.stableId })
        let newQuestionIds = currentIds.subtracting(previousWaitingForQuestionIds)

        if !newQuestionIds.isEmpty {
            // Only open question UI if not already showing one — prevents UI swap
            // that can cause accidental clicks when content changes under the cursor.
            if case .question = viewModel.contentType {
                DebugLogger.log("AskUser", "[question] newIds=\(newQuestionIds.count) — already showing question, skipping")
            } else if let session = questionSessions.first(where: { newQuestionIds.contains($0.stableId) }) {
                DebugLogger.log("AskUser", "[question] newIds=\(newQuestionIds.count) — opening question UI")
                viewModel.notchOpen(reason: .notification)
                viewModel.showQuestion(for: session)

                // Bounce the notch to attract attention
                DispatchQueue.main.async {
                    isBouncing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isBouncing = false
                    }
                }
            }
        }

        // If no sessions are waiting for question and we're currently showing question content, go back to instances
        if currentIds.isEmpty, case .question = viewModel.contentType {
            viewModel.contentType = .instances
        }

        previousWaitingForQuestionIds = currentIds
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    private func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions {
            guard let pid = session.pid else {
                // No PID means we can't check focus, assume not focused
                return true
            }

            let isFocused = await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
            if !isFocused {
                return true
            }
        }

        return false
    }
}

// MARK: - Animated Ellipsis

/// Cycles dots: `.` -> `..` -> `...` -> `.` -> ...
/// Used for "working" / "processing" status in the collapsed notch.
struct AnimatedEllipsis: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: dotCount + 1))
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 3
            }
    }
}

// MARK: - Collapsed Notch Content (Dynamic Island Style)

/// Shows session dots + pixel character + rotating carousel text in the collapsed notch.
struct CollapsedNotchContent: View {
    let sessions: [SessionState]
    let mostUrgentState: AnimationState
    let activityTextParts: (project: String, status: String)?
    let notchHeight: CGFloat
    let isBouncing: Bool
    var activityNamespace: Namespace.ID
    /// Timestamps when sessions entered waitingForInput, keyed by stableId
    var waitingForInputTimestamps: [String: Date]
    /// Compact mode: only show dot + icon + count, no text
    var compactMode: Bool = false
    /// Whether the device has a physical notch (camera housing)
    var hasPhysicalNotch: Bool = true
    /// Width of the physical notch (used for camera avoidance spacing)
    var notchWidth: CGFloat = 200

    // MARK: - Content Carousel

    /// Current carousel slide index
    @State private var carouselIndex: Int = 0
    /// Timer that advances the carousel every 3 seconds
    private let carouselTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    /// The total number of carousel slides
    private let carouselSlideCount = 4

    /// The most active session (highest priority, most recently active)
    private var mostActiveSession: SessionState? {
        sessions
            .filter { $0.phase != .ended }
            .max { a, b in a.lastActivity < b.lastActivity }
    }

    /// Whether the current status text represents a "working" state that should use animated dots
    private var isWorkingStatus: Bool {
        mostUrgentState == .working || mostUrgentState == .thinking
    }

    /// The status text label without trailing dots (for animated ellipsis pairing)
    private var statusLabelWithoutDots: String? {
        guard let parts = activityTextParts else { return nil }
        var s = parts.status
        // Strip trailing dots / ellipsis so AnimatedEllipsis can replace them
        while s.hasSuffix("...") || s.hasSuffix("\u{2026}") {
            if s.hasSuffix("...") {
                s = String(s.dropLast(3))
            } else {
                s = String(s.dropLast(1))
            }
        }
        while s.hasSuffix(".") {
            s = String(s.dropLast(1))
        }
        return s
    }

    /// Duration string for the most active session (e.g. "27m")
    private var durationString: String? {
        guard let session = mostActiveSession else { return nil }
        return SessionPhaseHelpers.timeAgo(session.createdAt)
    }

    /// Color for a session dot based on its phase
    private func dotColor(for phase: SessionPhase) -> Color {
        switch phase {
        case .processing, .compacting:
            return theme.workingColor
        case .waitingForApproval, .waitingForQuestion:
            return theme.needsYouColor
        case .waitingForInput:
            return theme.doneColor
        case .idle, .ended:
            return theme.mutedText.opacity(theme.isRetroArcade ? 0.55 : 0.25)
        }
    }

    /// Group sessions by project (cwd), preserving order.
    /// Skips ended and user-hidden cwds.
    private var sessionsByProject: [[SessionState]] {
        var groups: [[SessionState]] = []
        var seen: [String: Int] = [:]  // cwd -> group index

        for session in sessions where session.phase != .ended {
            if HiddenProjectsStore.shared.isHidden(cwd: session.cwd) { continue }
            if let idx = seen[session.cwd] {
                groups[idx].append(session)
            } else {
                seen[session.cwd] = groups.count
                groups.append([session])
            }
        }
        return groups
    }

    /// Total number of active (non-ended) sessions
    private var activeSessionCount: Int {
        sessions.filter { $0.phase != .ended }.count
    }

    @State private var pulsePhase: Bool = false
    @ObservedObject private var buddyReader = BuddyReader.shared
    @AppStorage("usePixelCat") private var usePixelCat: Bool = false
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @ObservedObject private var hiddenStore: HiddenProjectsStore = .shared
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    // MARK: - Unattended Task Alert

    /// How long the oldest waitingForInput session has been unattended (seconds)
    @State private var unattendedSeconds: TimeInterval = 0
    /// Timer that checks every 5 seconds for unattended sessions
    @State private var unattendedTimer: Timer? = nil

    /// Compute the longest unattended duration from waitingForInput timestamps
    private var longestUnattendedDuration: TimeInterval {
        let now = Date()
        var maxDuration: TimeInterval = 0
        for session in sessions where session.phase == .waitingForInput {
            if let enteredAt = waitingForInputTimestamps[session.stableId] {
                let duration = now.timeIntervalSince(enteredAt)
                maxDuration = max(maxDuration, duration)
            }
        }
        return maxDuration
    }

    /// Whether any session has been unattended for >30 seconds
    private var isUnattended: Bool {
        unattendedSeconds > 30
    }

    /// Whether any session has been unattended for >60 seconds (stronger alert)
    private var isUrgentlyUnattended: Bool {
        unattendedSeconds > 60
    }

    /// Override status dot color when unattended
    private var effectiveStatusDotColor: Color {
        if isUrgentlyUnattended {
            return theme.errorColor
        } else if isUnattended {
            return theme.needsYouColor
        }
        return statusDotColor
    }

    /// Status dot color for the left wing.
    /// Semantic states (working / needsYou / error / done / thinking) stay
    /// universal — they carry meaning the user reads across themes. Idle
    /// defers to the current theme's accent so each theme announces itself
    /// at rest (森林 moss-green, 霓虹东京 hot pink, 落日 coral, etc.),
    /// and the old `Color.white.opacity(0.3)` hardcode is gone — it was
    /// invisible on light-bg themes (sunset / sakura / retroArcade).
    private var statusDotColor: Color {
        switch mostUrgentState {
        case .working: return theme.workingColor
        case .needsYou: return theme.needsYouColor
        case .error: return theme.errorColor
        case .done: return theme.doneColor
        case .thinking: return theme.thinkingColor
        case .idle: return theme.idleColor
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left wing (visible left of camera) ──
            HStack(spacing: 4) {
                // Status dot — small, subtle
                Circle()
                    .fill(effectiveStatusDotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: effectiveStatusDotColor.opacity(0.5), radius: 3)
                    .opacity(pulsePhase ? 1.0 : 0.5)

                // Buddy icon — honors the showBuddy preference and the
                // user's buddy-style pick (pixelCat / emoji). Emoji mode
                // falls through to pixel cat when Claude Code has no
                // companion data in ~/.claude.json.
                if notchStore.customization.showBuddy {
                    switch notchStore.customization.buddyStyle {
                    case .pixelCat:
                        PixelCharacterView(state: mostUrgentState)
                            .scaleEffect(0.28)
                            .frame(width: 16, height: 16)
                            .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)
                    case .emoji:
                        if let buddy = buddyReader.buddy {
                            EmojiPixelView(emoji: buddy.species.emoji, style: .wave)
                                .scaleEffect(0.30)
                                .frame(width: 16, height: 16)
                                .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)
                        } else {
                            PixelCharacterView(state: mostUrgentState)
                                .scaleEffect(0.28)
                                .frame(width: 16, height: 16)
                                .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)
                        }
                    }
                }

                // Carousel status text — hidden in compact mode
                if !compactMode {
                    carouselContent
                        .frame(height: 16)
                        .clipped()
                }
            }
            .padding(.leading, 6)

            // Camera avoidance: on notched devices, ensure content stays outside camera area
            if hasPhysicalNotch {
                Spacer(minLength: notchWidth * 0.35)
            } else {
                Spacer()
            }

            // ── Right wing (visible right of camera) ──
            HStack(spacing: 4) {
                // Project name — hidden in compact mode
                if !compactMode, let parts = activityTextParts {
                    Text(parts.project)
                        .notchFont(13, weight: .medium, design: .monospaced)
                        .notchSecondaryForeground()
                        .lineLimit(1)
                }

                if activeSessionCount > 0 {
                    Text("\u{00D7}\(activeSessionCount)")
                        .notchFont(13, weight: .medium, design: .monospaced)
                        .foregroundColor(badgeColor)
                }
            }
            .padding(.trailing, 6)
        }
        .onReceive(carouselTimer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                carouselIndex = (carouselIndex + 1) % carouselSlideCount
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
            // Start unattended check timer (every 5 seconds)
            unattendedTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                DispatchQueue.main.async {
                    unattendedSeconds = longestUnattendedDuration
                }
            }
        }
        .onDisappear {
            unattendedTimer?.invalidate()
            unattendedTimer = nil
        }
    }

    // MARK: - Carousel Content

    @ViewBuilder
    private var carouselContent: some View {
        let slide = carouselIndex % carouselSlideCount
        Group {
            switch slide {
            case 0:
                // Slide 0: Status text (current behavior) with animated ellipsis for working states
                carouselStatusText
            case 1:
                // Slide 1: Task title / first user message of most active session
                carouselTaskTitle
            case 2:
                // Slide 2: Last tool name + action (e.g. "Edit: middleware.ts")
                carouselToolAction
            case 3:
                // Slide 3: Project name + duration (e.g. "CodeIsland \u{00B7} 27m")
                carouselProjectDuration
            default:
                carouselStatusText
            }
        }
        .transition(.push(from: .bottom))
        .animation(.easeInOut(duration: 0.3), value: carouselIndex)
        .id(slide)  // Force view identity change for transition
    }

    @ViewBuilder
    private var carouselStatusText: some View {
        if isWorkingStatus, let label = statusLabelWithoutDots {
            HStack(spacing: 0) {
                Text(label)
                    .notchFont(13, weight: .medium, design: .monospaced)
                    .foregroundStyle(statusGradient)
                    .lineLimit(1)

                AnimatedEllipsis()
                    .notchFont(13, weight: .medium, design: .monospaced)
                    .foregroundStyle(statusGradient)

            }
        } else if let parts = activityTextParts {
            Text(parts.status)
                .notchFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(statusGradient)
                .lineLimit(1)

        }
    }

    @ViewBuilder
    private var carouselTaskTitle: some View {
        if let session = mostActiveSession,
           let title = session.firstUserMessage ?? session.conversationInfo.summary {
            let truncated = title.count > 24 ? String(title.prefix(24)) + "\u{2026}" : title
            Text(truncated)
                .notchFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(statusGradient)
                .lineLimit(1)

        } else {
            // Fall back to status text if no task title available
            carouselStatusText
        }
    }

    /// Formatted tool action string for carousel slide 2
    private var toolActionLabel: String? {
        guard let session = mostActiveSession,
              let toolName = session.lastToolName else { return nil }
        if let msg = session.lastMessage {
            let components = msg.components(separatedBy: CharacterSet(charactersIn: "/\\"))
            let filename = components.last ?? msg
            let short = filename.count > 18 ? String(filename.prefix(18)) + "\u{2026}" : filename
            return "\(toolName): \(short)"
        }
        return toolName
    }

    @ViewBuilder
    private var carouselToolAction: some View {
        if let label = toolActionLabel {
            Text(label)
                .notchFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(statusGradient)
                .lineLimit(1)

        } else {
            // Fall back to status text if no tool info
            carouselStatusText
        }
    }

    @ViewBuilder
    private var carouselProjectDuration: some View {
        if let session = mostActiveSession {
            let duration = durationString ?? ""
            let display = duration.isEmpty
                ? session.projectName
                : "\(session.projectName) \u{00B7} \(duration)"
            Text(display)
                .notchFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(statusGradient)
                .lineLimit(1)

        } else if let parts = activityTextParts {
            Text(parts.project)
                .notchFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(statusGradient)
                .lineLimit(1)

        }
    }

    /// Status text gradient based on state
    private var statusGradient: LinearGradient {
        if theme.isRetroArcade {
            return LinearGradient(colors: [theme.primaryText, theme.primaryText], startPoint: .leading, endPoint: .trailing)
        }
        switch mostUrgentState {
        case .working:
            return LinearGradient(colors: [theme.workingColor, theme.doneColor], startPoint: .leading, endPoint: .trailing)
        case .needsYou:
            return LinearGradient(colors: [theme.needsYouColor, theme.needsYouColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .error:
            return LinearGradient(colors: [theme.errorColor, theme.errorColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .thinking:
            return LinearGradient(colors: [theme.thinkingColor, theme.workingColor], startPoint: .leading, endPoint: .trailing)
        case .done:
            return LinearGradient(colors: [theme.doneColor, theme.doneColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .idle:
            return LinearGradient(colors: [theme.secondaryText, theme.secondaryText], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Badge color for the "×N" session count. Idle defers to theme accent
    /// so the "×1" pill also reflects the active theme at rest, instead of
    /// a hardcoded 30%-white that vanishes on light-bg themes.
    private var badgeColor: Color {
        if theme.isRetroArcade { return theme.primaryText }
        switch mostUrgentState {
        case .needsYou: return theme.needsYouColor
        case .error: return theme.errorColor
        case .working: return theme.workingColor
        case .thinking: return theme.thinkingColor
        case .done: return theme.doneColor
        case .idle: return theme.idleColor
        }
    }

    /// Flatten sessions into dot entries with group separators, capped at max dots
    private var dotEntries: [(session: SessionState, isLastInGroup: Bool)] {
        let groups = sessionsByProject
        let totalActive = activeSessionCount
        let maxDots = totalActive > 8 ? 7 : min(totalActive, 8)

        var entries: [(session: SessionState, isLastInGroup: Bool)] = []
        for (groupIndex, group) in groups.enumerated() {
            for (sessionIndex, session) in group.enumerated() {
                guard entries.count < maxDots else { break }
                let isLast = sessionIndex == group.count - 1 && groupIndex < groups.count - 1
                entries.append((session: session, isLastInGroup: isLast))
            }
            guard entries.count < maxDots else { break }
        }
        return entries
    }

    @ViewBuilder
    private var sessionDots: some View {
        let totalActive = activeSessionCount
        let showOverflow = totalActive > 8
        let entries = dotEntries

        HStack(spacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                Circle()
                    .fill(dotColor(for: entry.session.phase))
                    .frame(width: 4, height: 4)
                    .padding(.trailing, entry.isLastInGroup ? 2 : 0)
            }

            if showOverflow {
                Text("+\(totalActive - 7)")
                    .notchFont(11, weight: .medium, design: .monospaced)
                    .notchSecondaryForeground()
                    .padding(.leading, 1)
            }
        }
    }
}

// MARK: - Scrolling Text View

/// Horizontally scrolling text for the collapsed notch.
/// If text fits, it stays static. If it overflows, it scrolls continuously.
struct ScrollingTextView: View {
    let text: String

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var needsScrolling: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width

            Text(text)
                .notchFont(13, weight: .regular, design: .monospaced)
                .notchSecondaryForeground()
                .lineLimit(1)

                .background(
                    GeometryReader { textGeo in
                        Color.clear
                            .onAppear {
                                textWidth = textGeo.size.width
                                containerWidth = availableWidth
                                startScrollingIfNeeded()
                            }
                            .onChange(of: text) { _, _ in
                                textWidth = textGeo.size.width
                                containerWidth = availableWidth
                                offset = 0
                                startScrollingIfNeeded()
                            }
                    }
                )
                .offset(x: needsScrolling ? offset : 0)
        }
        .frame(height: 14)
        .clipped()
    }

    private func startScrollingIfNeeded() {
        guard needsScrolling else {
            offset = 0
            return
        }

        // Scroll from right edge to left, then reset
        let scrollDistance = textWidth + 40  // extra gap before restart
        let duration = Double(scrollDistance) / 30.0  // ~30pt/sec

        // Reset to start position (text starts just off-screen right)
        offset = containerWidth

        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -textWidth
        }
    }
}

// MARK: - Question Content Wrapper

/// Wrapper view that resolves QuestionContext from either .waitingForQuestion
/// or .waitingForApproval with AskUserQuestion tool, then shows AskUserQuestionView.
/// Extracted to a separate struct to avoid SwiftUI type-checker complexity in NotchView.
private struct QuestionContentWrapper: View {
    let session: SessionState
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        let liveSession = sessionMonitor.instances.first(where: { $0.sessionId == session.sessionId }) ?? session
        if let ctx = Self.questionContext(for: liveSession) {
            AskUserQuestionView(
                session: liveSession,
                context: ctx,
                sessionMonitor: sessionMonitor
            )
        } else {
            ClaudeInstancesView(
                sessionMonitor: sessionMonitor,
                viewModel: viewModel
            )
            .onAppear {
                viewModel.contentType = .instances
            }
        }
    }

    static func questionContext(for session: SessionState) -> QuestionContext? {
        if let ctx = session.phase.questionContext {
            return ctx
        }
        if let permission = session.activePermission,
           session.pendingToolName == "AskUserQuestion",
           let input = permission.toolInput,
           let questionsRaw = input["questions"]?.value as? [[String: Any]] {
            let questions = questionsRaw.compactMap { q -> QuestionItem? in
                guard let question = q["question"] as? String else { return nil }
                let header = q["header"] as? String
                let multiSelect = q["multiSelect"] as? Bool ?? false
                let optionsRaw = q["options"] as? [[String: Any]] ?? []
                let options = optionsRaw.compactMap { o -> QuestionOption? in
                    guard let label = o["label"] as? String else { return nil }
                    return QuestionOption(label: label, description: o["description"] as? String)
                }
                return QuestionItem(question: question, header: header, options: options, multiSelect: multiSelect)
            }
            guard !questions.isEmpty else { return nil }
            return QuestionContext(
                toolUseId: permission.toolUseId,
                questions: questions,
                receivedAt: permission.receivedAt
            )
        }
        return nil
    }
}
