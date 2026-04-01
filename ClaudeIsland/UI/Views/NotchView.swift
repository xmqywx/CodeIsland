//
//  NotchView.swift
//  ClaudeIsland
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
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
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false

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
            let status = session.lastToolName ?? "working..."
            return (project, status)
        case .waitingForApproval:
            let status = session.pendingToolName.map { "approve \($0)?" } ?? "needs approval"
            return (project, status)
        case .waitingForInput:
            return (project, "done")
        case .compacting:
            return (project, "compacting...")
        case .idle:
            return (project, "idle")
        case .ended:
            return nil
        }
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.deviceNotchRect.width,
            height: viewModel.deviceNotchRect.height
        )
    }

    /// Extra width for expanding activities (like Dynamic Island)
    private var expansionWidth: CGFloat {
        if hasActiveSessions {
            return 80
        }
        return 0
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

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
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
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if viewModel.status != .opened {
                                viewModel.notchOpen(reason: .click)
                            }
                        }
                    )
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionMonitor.startMonitoring()
            // On non-notched devices, keep visible so users have a target to interact with
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
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
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        activityCoordinator.expandingActivity.show && activityCoordinator.expandingActivity.type == .claude
    }

    /// Whether to show the expanded closed state (any active sessions)
    private var showClosedActivity: Bool {
        isProcessing || hasPendingPermission || hasWaitingForInput || hasActiveSessions
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
                    .frame(width: notchSize.width - 24) // Fixed width to prevent reflow
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
                    activityNamespace: activityNamespace
                )
                .clipped()
            } else {
                // Closed without sessions: empty space
                Rectangle()
                    .fill(.clear)
                    .frame(width: closedNotchSize.width - 20)
            }
        }
        .frame(height: closedNotchSize.height)
        .clipped()
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
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
            }
        }
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
        // Removed .id() - was causing view recreation and performance issues
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if hasActiveSessions {
            // Show notch whenever there are active sessions
            if isAnyProcessing || hasPendingPermission {
                activityCoordinator.showActivity(type: .claude)
            } else {
                activityCoordinator.hideActivity()
            }
            isVisible = true
        } else {
            // Hide activity when no sessions
            activityCoordinator.hideActivity()

            // Delay hiding the notch until animation completes
            // Don't hide on non-notched devices - users need a visible target
            if viewModel.status == .closed && viewModel.hasPhysicalNotch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !hasActiveSessions && viewModel.status == .closed {
                        isVisible = false
                    }
                }
            }
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
        case .closed:
            // Don't hide on non-notched devices - users need a visible target
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !hasActiveSessions && !activityCoordinator.expandingActivity.show {
                    isVisible = false
                }
            }
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.stableId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        if !newPendingIds.isEmpty &&
           viewModel.status == .closed &&
           !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace() {
            viewModel.notchOpen(reason: .notification)
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

            // Play notification sound if the session is not actively focused
            if let soundName = AppSettings.notificationSound.soundName {
                // Check if we should play sound (async check for tmux pane focus)
                Task {
                    let shouldPlaySound = await shouldPlayNotificationSound(for: newlyWaitingSessions)
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

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        previousWaitingForInputIds = currentIds
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

// MARK: - Collapsed Notch Content (Dynamic Island Style)

/// Shows session dots + pixel character + scrolling text in the collapsed notch.
struct CollapsedNotchContent: View {
    let sessions: [SessionState]
    let mostUrgentState: AnimationState
    let activityTextParts: (project: String, status: String)?
    let notchHeight: CGFloat
    let isBouncing: Bool
    var activityNamespace: Namespace.ID

    /// Color for a session dot based on its phase
    private func dotColor(for phase: SessionPhase) -> Color {
        switch phase {
        case .processing, .compacting:
            return TerminalColors.green
        case .waitingForApproval:
            return TerminalColors.amber
        case .waitingForInput:
            return TerminalColors.blue
        case .idle, .ended:
            return Color.white.opacity(0.25)
        }
    }

    /// Group sessions by project (cwd), preserving order
    private var sessionsByProject: [[SessionState]] {
        var groups: [[SessionState]] = []
        var seen: [String: Int] = [:]  // cwd -> group index

        for session in sessions where session.phase != .ended {
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

    var body: some View {
        HStack(spacing: 6) {
            // Left: buddy emoji or pixel character
            if let buddy = buddyReader.buddy {
                Text(buddy.species.emoji)
                    .font(.system(size: 12))
                    .offset(y: pulsePhase ? -1 : 1)
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)
            } else {
                PixelCharacterView(state: mostUrgentState)
                    .scaleEffect(0.28)
                    .frame(width: 14, height: 14)
                    .offset(y: pulsePhase ? -1 : 1)
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)
            }

            // Center: buddy name or project name + status
            if let parts = activityTextParts {
                HStack(spacing: 3) {
                    if let buddy = buddyReader.buddy {
                        Text(buddy.name)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text(parts.project)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(parts.status)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusGradient)
                        .opacity(pulsePhase ? 1.0 : 0.6)
                }
                .lineLimit(1)
                .fixedSize()
            }

            // Right: session count
            if activeSessionCount > 0 {
                Text("×\(activeSessionCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(badgeColor)
            }
        }
        .padding(.horizontal, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        }
    }

    /// Status text gradient based on state
    private var statusGradient: LinearGradient {
        switch mostUrgentState {
        case .working:
            return LinearGradient(colors: [Color(red:0.3,green:0.9,blue:0.95), Color(red:0.2,green:0.95,blue:0.5)], startPoint: .leading, endPoint: .trailing)
        case .needsYou:
            return LinearGradient(colors: [Color(red:1.0,green:0.75,blue:0.3), Color(red:1.0,green:0.55,blue:0.2)], startPoint: .leading, endPoint: .trailing)
        case .error:
            return LinearGradient(colors: [Color(red:1.0,green:0.4,blue:0.4), Color(red:0.9,green:0.2,blue:0.2)], startPoint: .leading, endPoint: .trailing)
        case .thinking:
            return LinearGradient(colors: [Color(red:0.7,green:0.6,blue:1.0), Color(red:0.5,green:0.8,blue:1.0)], startPoint: .leading, endPoint: .trailing)
        case .done:
            return LinearGradient(colors: [Color(red:0.3,green:0.87,blue:0.5), Color(red:0.2,green:0.8,blue:0.7)], startPoint: .leading, endPoint: .trailing)
        case .idle:
            return LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Badge color based on most urgent state
    private var badgeColor: Color {
        switch mostUrgentState {
        case .needsYou: return TerminalColors.amber
        case .error: return Color(red: 0.94, green: 0.27, blue: 0.27)
        case .working: return TerminalColors.green
        case .thinking: return Color(red: 0.65, green: 0.55, blue: 0.98)
        case .done: return TerminalColors.blue
        case .idle: return Color.white.opacity(0.3)
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
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
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
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
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
