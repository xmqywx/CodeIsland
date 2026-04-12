//
//  ClaudeInstancesView.swift
//  ClaudeIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import AppKit
import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    /// Tracks which project groups are collapsed, keyed by group id (cwd path)
    @State private var collapsedGroups: Set<String> = []
    /// Whether to show grouped by project or flat list (default: flat)
    @AppStorage("showGroupedSessions") private var showGrouped: Bool = false
    @ObservedObject private var buddyReader = BuddyReader.shared
    @State private var showBuddyCard: Bool = false
    @AppStorage("usePixelCat") private var usePixelCat: Bool = false
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Top bar: session count + settings
                    HStack {
                        Text("\(sessionMonitor.instances.count) \(L10n.sessions)")
                            .notchFont(11)
                            .notchSecondaryForeground()
                        Spacer()

                        // Plugin header buttons
                        PluginHeaderButtons(viewModel: viewModel)

                        HeaderIconButton(icon: "gearshape", hoverColor: Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)) {
                            SystemSettingsWindow.shared.show()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                    if showBuddyCard, let buddy = buddyReader.buddy {
                        buddyCardView(buddy)
                    } else if showGrouped {
                        groupedList
                    } else {
                        flatList
                    }
                }
                .padding(.bottom, 50)

                // Bottom right: buddy + usage stats
                // Hidden when buddy card open or when expanded with many sessions
                // Also honor the user's showBuddy / showUsageBar preferences.
                if !showBuddyCard && !(sortedInstances.count > 4 && viewModel.isInstancesExpanded)
                    && (notchStore.customization.showBuddy || notchStore.customization.showUsageBar) {
                    VStack(alignment: .trailing, spacing: 4) {
                        // Only show buddy when ≤ 5 sessions AND the user has
                        // the showBuddy preference enabled.
                        if notchStore.customization.showBuddy,
                           sortedInstances.count <= 5,
                           let buddy = buddyReader.buddy {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showBuddyCard.toggle()
                                }
                            } label: {
                                BuddyASCIIView(buddy: buddy)
                                    .frame(width: 80, height: 50)
                                    .scaleEffect(0.7)
                            }
                            .buttonStyle(.plain)
                        }

                        if notchStore.customization.showUsageBar {
                            UsageStatsBar(monitor: rateLimitMonitor, totalMinutes: totalSessionMinutes)
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 12)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // Bottom left: Codex usage stats
                if codexGate.isEnabled && !showBuddyCard && !(sortedInstances.count > 4 && viewModel.isInstancesExpanded)
                    && notchStore.customization.showUsageBar {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        CodexUsageStatsBar(monitor: codexUsageMonitor)
                    }
                    .padding(.leading, 4)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onReceive(sessionMonitor.$instances) { instances in
                viewModel.sessionCount = instances.count
                viewModel.activeSessionCount = instances.filter {
                    $0.phase != .idle && $0.phase != .ended
                }.count
            }
        }
    }

    // MARK: - Buddy Card

    @ViewBuilder
    private func buddyCardView(_ buddy: BuddyInfo) -> some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Text(buddy.rarity.stars)
                    .notchFont(11)
                    .foregroundColor(buddy.rarity.color)
                Text(buddy.rarity.displayName.uppercased())
                    .notchFont(11, weight: .bold, design: .monospaced)
                    .foregroundColor(buddy.rarity.color)
                Spacer()
                Text(buddy.species.rawValue.uppercased())
                    .notchFont(11, weight: .medium, design: .monospaced)
                    .notchSecondaryForeground()
                if buddy.isShiny {
                    Text("✨")
                        .notchFont(11)
                }
            }
            .padding(.horizontal, 10)

            // Left-right layout: ASCII art | stats
            HStack(alignment: .top, spacing: 8) {
                // Left: ASCII sprite (name shown by BuddyASCIIView)
                BuddyASCIIView(buddy: buddy)
                    .frame(width: 100, height: 65)

                // Right: stats + personality
                VStack(alignment: .leading, spacing: 4) {
                    if buddy.stats.debugging > 0 {
                        asciiStatBar("DBG", value: buddy.stats.debugging, color: .cyan)
                        asciiStatBar("PAT", value: buddy.stats.patience, color: .green)
                        asciiStatBar("CHS", value: buddy.stats.chaos, color: .red)
                        asciiStatBar("WIS", value: buddy.stats.wisdom, color: .purple)
                        asciiStatBar("SNK", value: buddy.stats.snark, color: .orange)
                    }

                    Text(buddy.personality)
                        .notchFont(8)
                        .notchSecondaryForeground()
                        .lineLimit(3)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 8)

            // Back
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showBuddyCard = false
                }
            } label: {
                Text(L10n.back)
                    .notchFont(11, weight: .medium)
                    .notchSecondaryForeground()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    /// ASCII-style stat bar: `DBG [████████░░] 64`
    private func asciiStatBar(_ label: String, value: Int, color: Color) -> some View {
        let filled = value / 10
        let empty = 10 - filled
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)

        return HStack(spacing: 3) {
            Text(label)
                .notchFont(11, weight: .medium, design: .monospaced)
                .notchSecondaryForeground()
                .frame(width: 30, alignment: .trailing)
            Text("[\(bar)]")
                .notchFont(11, weight: .regular, design: .monospaced)
                .foregroundColor(color.opacity(0.7))
            Text("\(value)")
                .notchFont(11, weight: .regular, design: .monospaced)
                .foregroundColor(color.opacity(0.5))
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - Empty State

    @State private var emptyPulse = false
    @State private var emptyFloat = false

    private var emptyState: some View {
        VStack(spacing: 0) {
            // Top bar with settings
            HStack {
                Spacer()

                // Plugin header buttons
                PluginHeaderButtons(viewModel: viewModel)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.toggleMenu()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .notchFont(10)
                        .notchSecondaryForeground()
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Spacer()

            // Animated pixel cat
            VStack(spacing: 12) {
                if usePixelCat {
                    PixelCharacterView(state: .idle)
                        .scaleEffect(0.8)
                        .frame(width: 52, height: 44)
                        .offset(y: emptyFloat ? -3 : 3)
                } else if let buddy = buddyReader.buddy {
                    BuddyASCIIView(buddy: buddy)
                        .frame(width: 80, height: 55)
                        .scaleEffect(0.8)
                        .offset(y: emptyFloat ? -3 : 3)
                } else {
                    PixelCharacterView(state: .idle)
                        .scaleEffect(0.8)
                        .frame(width: 52, height: 44)
                        .offset(y: emptyFloat ? -3 : 3)
                }

                Text(L10n.noSessions)
                    .notchFont(13, weight: .medium)
                    .opacity(emptyPulse ? 0.5 : 0.3)

                Text(L10n.runClaude)
                    .notchFont(10)
                    .opacity(0.2)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)

                // Usage stats if available (honors showUsageBar)
                if notchStore.customization.showUsageBar {
                    UsageStatsBar(monitor: rateLimitMonitor, totalMinutes: 0)
                        .padding(.top, 4)
                    if codexGate.isEnabled {
                        CodexUsageStatsBar(monitor: codexUsageMonitor)
                            .padding(.top, 4)
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                emptyPulse = true
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                emptyFloat = true
            }
        }
    }

    // MARK: - Stats

    /// Total minutes across all sessions
    private var totalSessionMinutes: Int {
        sessionMonitor.instances.reduce(0) { total, session in
            total + Int(Date().timeIntervalSince(session.createdAt) / 60)
        }
    }

    /// Format total time as "Xh Ym" or "Ym"
    private func formatTotalTime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }

    @StateObject private var rateLimitMonitor = RateLimitMonitor.shared
    @StateObject private var codexUsageMonitor = CodexUsageMonitor.shared
    @ObservedObject private var codexGate = CodexFeatureGate.shared

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        SessionFilter.filterForDisplay(sessionMonitor.instances)
        .sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .waitingForQuestion, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    /// Sessions grouped by project (cwd), with per-group sorting preserved
    private var projectGroups: [ProjectGroup] {
        ProjectGroup.group(sessions: sortedInstances)
    }

    private var flatList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedInstances.enumerated()), id: \.element.id) { index, session in
                    InstanceRow(
                        session: session,
                        onFocus: { focusSession(session) },
                        onChat: { openChat(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onReject: { rejectSession(session) }
                    )
                    .id(session.stableId)

                    // Subagent rows under this session
                    if session.subagentState.hasActiveSubagent {
                        SubagentListView(session: session)
                    }

                    // Gradient divider between rows
                    if index < sortedInstances.count - 1 {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    }
                }

                // Footer: expand/collapse when >4 sessions, or just count
                if sortedInstances.count > 4 && !viewModel.isInstancesExpanded {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.isInstancesExpanded = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .notchFont(8)
                            Text(L10n.showAllSessions(sortedInstances.count))
                                .notchFont(10)
                        }
                        .notchSecondaryForeground()
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.04))
                        )
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                } else if sortedInstances.count > 4 && viewModel.isInstancesExpanded {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.isInstancesExpanded = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .notchFont(8)
                            Text("收起")
                                .notchFont(10)
                        }
                        .notchSecondaryForeground()
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                } else if sortedInstances.count > 0 {
                    Text(L10n.showAllSessions(sortedInstances.count))
                        .notchFont(10)
                        .opacity(0.2)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var groupedList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(projectGroups) { group in
                    ProjectGroupHeader(
                        group: group,
                        isCollapsed: collapsedGroups.contains(group.id)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if collapsedGroups.contains(group.id) {
                                collapsedGroups.remove(group.id)
                            } else {
                                collapsedGroups.insert(group.id)
                            }
                        }
                    }

                    if !collapsedGroups.contains(group.id) {
                        ForEach(group.sessions) { session in
                            InstanceRow(
                                session: session,
                                onFocus: { focusSession(session) },
                                onChat: { openChat(session) },
                                onArchive: { archiveSession(session) },
                                onApprove: { approveSession(session) },
                                onReject: { rejectSession(session) }
                            )
                            .id(session.stableId)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        Task {
            await TerminalJumper.shared.jump(to: session)
            await MainActor.run { viewModel.notchClose() }
        }
    }

    private func openChat(_ session: SessionState) {
        // If session has AskUserQuestion pending, show the question UI instead of chat
        if session.pendingToolName == "AskUserQuestion",
           session.phase.isWaitingForApproval {
            viewModel.showQuestion(for: session)
        } else {
            viewModel.showChat(for: session)
        }
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false

    // MARK: - Colors

    /// Blue pill colors for "Claude" tag
    private static let claudeTagBg = Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.2) // #2563EB @ 0.2
    private static let claudeTagFg = Color(red: 0.376, green: 0.647, blue: 0.98) // #60A5FA
    private static let cyanColor = Color(red: 0.4, green: 0.91, blue: 0.98)

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    /// Duration since session started, formatted as "<Xm" or "Xh"
    private var durationText: String {
        let elapsed = Date().timeIntervalSince(session.createdAt)
        let minutes = Int(elapsed / 60)
        if minutes < 1 {
            return "<1m"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        return "\(hours)h"
    }

    /// Terminal tag color based on app type
    private var terminalTagColor: Color {
        let tag = terminalTag.lowercased()
        if tag.contains("cmux") { return Color(red: 0.56, green: 0.79, blue: 0.98) }      // blue
        if tag.contains("ghostty") { return Color(red: 0.7, green: 0.6, blue: 1.0) }       // purple
        if tag.contains("zellij") { return Color(red: 0.3, green: 0.85, blue: 0.75) }     // teal
        if tag.contains("iterm") { return Color(red: 0.29, green: 0.87, blue: 0.5) }       // green
        if tag.contains("warp") { return Color(red: 0.96, green: 0.62, blue: 0.04) }       // amber
        if tag.contains("cursor") { return Color(red: 0.4, green: 0.91, blue: 0.98) }      // cyan
        if tag.contains("codex") { return Color(red: 1.0, green: 0.55, blue: 0.0) }        // orange
        if tag.contains("code") { return Color(red: 0.29, green: 0.67, blue: 0.96) }       // vs blue
        if tag.contains("kitty") { return Color(red: 0.94, green: 0.5, blue: 0.5) }        // salmon
        if tag.contains("claude") { return Self.claudeTagFg }                               // claude blue
        return Color.white.opacity(0.4)
    }

    /// Terminal app name — auto-detected from process tree; falls back to "claude" for plain CLI sessions
    private var terminalTag: String {
        session.terminalApp ?? (session.isInTmux ? "tmux" : "claude")
    }

    /// Accent color based on phase (used for status dot)
    private var accentColor: Color {
        switch session.phase {
        case .processing, .compacting: return Self.cyanColor
        case .waitingForApproval, .waitingForQuestion: return Color(red: 0.96, green: 0.62, blue: 0.04) // amber
        case .waitingForInput: return Color(red: 0.29, green: 0.87, blue: 0.5)  // green
        case .idle, .ended: return Color.white.opacity(0.2)
        }
    }

    /// Title text: "projectName · displayTitle" or just projectName if same
    private var titleText: String {
        let display = session.displayTitle
        if display == session.projectName {
            return session.projectName
        }
        return "\(session.projectName) \u{00B7} \(display)"
    }

    @ObservedObject private var buddyReader = BuddyReader.shared
    @AppStorage("usePixelCat") private var usePixelCat: Bool = false
    @State private var phaseFlash = false
    @State private var previousPhase: SessionPhase?

    /// Whether the pending tool is AskUserQuestion with options
    private var askUserOptions: [QuestionOption]? {
        guard let toolName = session.pendingToolName, toolName == "AskUserQuestion",
              let input = session.activePermission?.toolInput,
              let questionsValue = input["questions"]?.value as? [[String: Any]] else { return nil }
        var options: [QuestionOption] = []
        for q in questionsValue {
            if let opts = q["options"] as? [[String: Any]] {
                for opt in opts {
                    let label = opt["label"] as? String ?? ""
                    let desc = opt["description"] as? String
                    options.append(QuestionOption(label: label, description: desc))
                }
            }
        }
        return options.isEmpty ? nil : options
    }

    /// Animation state derived from session phase
    private var animationState: AnimationState {
        switch session.phase {
        case .processing, .compacting: return .working
        case .waitingForApproval, .waitingForQuestion: return .needsYou
        case .waitingForInput: return .done
        case .idle, .ended: return .idle
        }
    }

    /// Whether this session is active (not idle/ended)
    private var isActive: Bool {
        switch session.phase {
        case .processing, .compacting, .waitingForApproval, .waitingForQuestion, .waitingForInput:
            return true
        case .idle, .ended:
            return false
        }
    }

    /// Whether this session has ended
    private var isEnded: Bool { session.phase == .ended }

    private var iconScale: CGFloat { isActive ? 0.45 : 0.35 }
    private var iconSize: CGFloat { isActive ? 28 : 22 }
    private var titleFontSize: CGFloat { isActive ? 13 : 11 }
    private var subtitleFontSize: CGFloat { isActive ? 10 : 9 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: isActive ? 8 : 6) {
                // Buddy icon or pixel cat
                ZStack {
                    if usePixelCat {
                        PixelCharacterView(state: animationState)
                            .scaleEffect(iconScale)
                    } else if let buddy = buddyReader.buddy {
                        EmojiPixelView(emoji: buddy.species.emoji, style: .rock)
                            .scaleEffect(iconScale)
                    } else {
                        PixelCharacterView(state: animationState)
                            .scaleEffect(iconScale)
                    }
                    // Status dot overlay
                    Circle()
                        .fill(accentColor)
                        .frame(width: isActive ? 6 : 5, height: isActive ? 6 : 5)
                        .shadow(color: accentColor.opacity(0.6), radius: isActive ? 3 : 2)
                        .offset(x: iconSize / 2 - 3, y: iconSize / 2 - 3)
                }
                .frame(width: iconSize, height: iconSize)
                .padding(.top, 2)

                // Content
                VStack(alignment: .leading, spacing: isActive ? 4 : 3) {
                    // Title row
                    HStack(spacing: 4) {
                        Text(titleText)
                            .notchFont(titleFontSize, weight: isActive ? .semibold : .medium)
                            .opacity(isActive ? 0.95 : 0.85)
                            .lineLimit(isActive ? 2 : 1)

                        Spacer(minLength: 0)

                        // Subagent badge (if active)
                        if session.subagentState.hasActiveSubagent {
                            Text("⚡\(session.subagentState.activeTasks.count)")
                                .notchFont(8, weight: .medium)
                                .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.12))
                                )
                        }

                        // Terminal tag — colored by terminal type
                        Text(terminalTag)
                            .notchFont(8, weight: .semibold)
                            .foregroundColor(terminalTagColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(terminalTagColor.opacity(0.12))
                            )

                        // Ended tag
                        if isEnded {
                            Text(L10n.ended)
                                .notchFont(8, weight: .semibold)
                                .notchSecondaryForeground()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }

                        // Duration — colored when active, otherwise inherits palette fg
                        Text(durationText)
                            .notchFont(10, weight: isActive ? .medium : .regular)
                            .foregroundColor(isActive ? accentColor.opacity(0.7) : nil)
                            .opacity(isActive ? 1.0 : 0.3)

                        // Terminal jump button — hidden for ended sessions
                        if !isEnded {
                            Image(systemName: "terminal")
                                .notchFont(10)
                                .foregroundColor(Color(red: 0.29, green: 0.87, blue: 0.5).opacity(0.7))
                                .frame(width: 20, height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(red: 0.29, green: 0.87, blue: 0.5).opacity(0.1))
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onFocus() }
                        }

                        // Delete button (always visible so users can dismiss stuck sessions)
                        Image(systemName: "xmark")
                            .notchFont(8, weight: .medium)
                            .notchSecondaryForeground()
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .onTapGesture { onArchive() }
                    }

                    // Subtitle
                    subtitleView

                    // Active session: show last tool action
                    if isActive, let toolName = session.lastToolName,
                       let lastMsg = session.lastMessage {
                        HStack(spacing: 3) {
                            Image(systemName: "wrench.and.screwdriver")
                                .notchFont(8)
                                .opacity(0.2)
                            Text("\(toolName): \(lastMsg)")
                                .notchFont(9)
                                .notchSecondaryForeground()
                                .lineLimit(1)
                        }
                    }

                    // AskUserQuestion: show options inline
                    if isWaitingForApproval, let options = askUserOptions {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.claudeNeedsInput)
                                .notchFont(9)
                                .foregroundColor(TerminalColors.amber.opacity(0.7))

                            HStack(spacing: 6) {
                                ForEach(Array(options.prefix(3).enumerated()), id: \.offset) { index, option in
                                    Text(option.label)
                                        .notchFont(9, weight: .medium)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(TerminalColors.amber.opacity(0.15))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .strokeBorder(TerminalColors.amber.opacity(0.2), lineWidth: 0.5)
                                                )
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            DebugLogger.log("AskUser", "Option \(index + 1) tapped: \(option.label)")
                                            Task {
                                                await sendOptionToTerminal(index: index + 1, session: session)
                                            }
                                        }
                                }

                                Image(systemName: "terminal")
                                    .notchFont(9)
                                    .foregroundColor(TerminalColors.amber.opacity(0.5))
                                    .frame(width: 20, height: 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(TerminalColors.amber.opacity(0.08))
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onFocus() }
                            }
                        }
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    // Regular approval buttons
                    else if isWaitingForApproval {
                        InlineApprovalButtons(
                            onChat: onChat,
                            onApprove: onApprove,
                            onReject: onReject
                        )
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, isActive ? 10 : 7)
            .contentShape(Rectangle())
            .onTapGesture { onChat() }
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: isActive ? 8 : 6)
                        .fill(isActive
                            ? accentColor.opacity(isHovered ? 0.1 : 0.05)
                            : (isHovered ? Color.white.opacity(0.06) : Color.clear))

                    // Phase transition flash
                    if phaseFlash {
                        RoundedRectangle(cornerRadius: isActive ? 8 : 6)
                            .fill(accentColor.opacity(0.15))
                            .transition(.opacity)
                    }
                }
            )
            .onChange(of: session.phase) { oldPhase, newPhase in
                // Flash on phase transition
                if oldPhase != newPhase {
                    withAnimation(.easeIn(duration: 0.15)) {
                        phaseFlash = true
                    }
                    withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                        phaseFlash = false
                    }
                    // Play sound for important transitions
                    if newPhase == .waitingForInput && (oldPhase == .processing || oldPhase == .compacting) {
                        SoundManager.shared.play(.sessionComplete)
                    }
                }
            }
        }
        .onHover { isHovered = $0 }
        .opacity(isEnded ? 0.4 : 1.0)
    }

    // MARK: - AskUserQuestion Response

    /// Send an option selection to the session's terminal
    private func sendOptionToTerminal(index: Int, session: SessionState) async {
        let termApp = session.terminalApp?.lowercased() ?? ""

        // Try AppleScript for iTerm2 / Terminal.app / Ghostty
        if termApp.contains("iterm") {
            let script = """
            tell application "iTerm2"
                tell current session of current tab of current window
                    write text "\(index)"
                end tell
            end tell
            """
            if runAppleScript(script) {
                DebugLogger.log("AskUser", "Sent via iTerm2")
                return
            }
        }

        if termApp.contains("terminal") && !termApp.contains("wez") {
            let script = """
            tell application "Terminal"
                do script "\(index)" in selected tab of front window
            end tell
            """
            if runAppleScript(script) {
                DebugLogger.log("AskUser", "Sent via Terminal.app")
                return
            }
        }

        // cmux — native AppleScript: send text directly to the terminal
        guard CmuxTreeParser.isAvailable else {
            DebugLogger.log("AskUser", "No supported terminal, jumping")
            await TerminalJumper.shared.jump(to: session)
            return
        }

        DebugLogger.log("AskUser", "Sending '\(index)' to cmux terminal cwd=\(session.cwd)")
        let sent = CmuxTreeParser.sendText("\(index)\r", toCwd: session.cwd)
        DebugLogger.log("AskUser", "Sent: \(sent)")
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleView: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            // Approval state: show tool info as subtitle
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(L10n.you)
                        .notchFont(9)
                        .notchSecondaryForeground()
                    Text(MCPToolFormatter.formatToolName(toolName))
                        .notchFont(9)
                        .opacity(0.55)
                        .lineLimit(1)
                }
                HStack(spacing: 2) {
                    Text("AI ")
                        .notchFont(9, weight: .medium)
                        .foregroundColor(Self.cyanColor.opacity(0.7))
                    if isInteractiveTool {
                        Text(L10n.needsInput)
                            .notchFont(9)
                            .foregroundColor(Self.cyanColor.opacity(0.5))
                            .lineLimit(1)
                    } else if let input = session.pendingToolInput {
                        Text(input)
                            .notchFont(9)
                            .foregroundColor(Self.cyanColor.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
        } else if let summary = session.smartSummary {
            // Smart summary with role prefixes
            VStack(alignment: .leading, spacing: 1) {
                let parts = summary.components(separatedBy: "\n")
                if parts.count >= 2 {
                    // Line 1: user question
                    HStack(spacing: 0) {
                        Text(L10n.you)
                            .notchFont(9)
                            .notchSecondaryForeground()
                        Text(parts[0])
                            .notchFont(9)
                            .opacity(0.55)
                            .lineLimit(1)
                    }
                    // Line 2: AI reply
                    HStack(spacing: 0) {
                        Text("AI ")
                            .notchFont(9, weight: .medium)
                            .foregroundColor(Self.cyanColor.opacity(0.7))
                        Text(parts[1])
                            .notchFont(9)
                            .foregroundColor(Self.cyanColor.opacity(0.45))
                            .lineLimit(1)
                    }
                } else {
                    // Single line summary — show as AI line
                    HStack(spacing: 0) {
                        Text("AI ")
                            .notchFont(9, weight: .medium)
                            .foregroundColor(Self.cyanColor.opacity(0.7))
                        Text(summary)
                            .notchFont(9)
                            .foregroundColor(Self.cyanColor.opacity(0.45))
                            .lineLimit(1)
                    }
                }
            }
        } else if let role = session.lastMessageRole {
            // Fallback: show last message with role prefix
            VStack(alignment: .leading, spacing: 1) {
                switch role {
                case "user":
                    HStack(spacing: 0) {
                        Text(L10n.you)
                            .notchFont(9)
                            .notchSecondaryForeground()
                        if let msg = session.lastMessage {
                            Text(msg)
                                .notchFont(9)
                                .opacity(0.55)
                                .lineLimit(1)
                        }
                    }
                case "tool":
                    HStack(spacing: 0) {
                        Text("AI ")
                            .notchFont(9, weight: .medium)
                            .foregroundColor(Self.cyanColor.opacity(0.7))
                        if let toolName = session.lastToolName {
                            Text(MCPToolFormatter.formatToolName(toolName))
                                .notchFont(9)
                                .foregroundColor(Self.cyanColor.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                default:
                    HStack(spacing: 0) {
                        Text("AI ")
                            .notchFont(9, weight: .medium)
                            .foregroundColor(Self.cyanColor.opacity(0.7))
                        if let msg = session.lastMessage {
                            Text(msg)
                                .notchFont(9)
                                .foregroundColor(Self.cyanColor.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                }
            }
        } else if let lastMsg = session.lastMessage {
            HStack(spacing: 0) {
                Text("AI ")
                    .notchFont(9, weight: .medium)
                    .foregroundColor(Self.cyanColor.opacity(0.7))
                Text(lastMsg)
                    .notchFont(9)
                    .foregroundColor(Self.cyanColor.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Project Group Header

struct ProjectGroupHeader: View {
    let group: ProjectGroup
    let isCollapsed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .notchFont(11, weight: .semibold)
                    .notchSecondaryForeground()
                    .frame(width: 12)

                Text(group.name)
                    .notchFont(13, weight: .semibold)
                    .opacity(0.8)

                if group.activeCount > 0 {
                    Text("\(group.activeCount) \(L10n.active)")
                        .notchFont(11, weight: .medium)
                        .notchSecondaryForeground()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                } else if group.isArchivable {
                    Text(L10n.archived)
                        .notchFont(11, weight: .medium)
                        .notchSecondaryForeground()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                        )
                }

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text(L10n.deny)
                    .notchFont(11, weight: .medium)
                    .notchSecondaryForeground()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text(L10n.allow)
                    .notchFont(11, weight: .medium)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .notchFont(12, weight: .medium)
                .opacity(isHovered ? 0.8 : 0.4)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .notchFont(12, weight: .medium)
                Text(L10n.goToTerminal)
                    .notchFont(13, weight: .medium)
            }
            .opacity(isEnabled ? 0.9 : 0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .notchFont(12, weight: .medium)
                Text(L10n.terminal)
                    .notchFont(13, weight: .medium)
            }
            .foregroundColor(isEnabled ? .black : nil)
            .opacity(isEnabled ? 1.0 : 0.4)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subagent List View

struct SubagentListView: View {
    let session: SessionState
    @State private var isExpanded = true

    private static let agentColor = Color(red: 0.6, green: 0.8, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Self.agentColor.opacity(0.15))
                    .frame(width: 1, height: 14)
                    .padding(.leading, 18)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .notchFont(7, weight: .medium)
                    .foregroundColor(Self.agentColor.opacity(0.4))

                Text("Subagents (\(session.subagentState.activeTasks.count))")
                    .notchFont(9, weight: .medium)
                    .foregroundColor(Self.agentColor.opacity(0.5))

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .padding(.vertical, 3)

            if isExpanded {
                ForEach(Array(session.subagentState.activeTasks.values), id: \.taskToolId) { task in
                    HStack(spacing: 5) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Self.agentColor.opacity(0.15))
                                .frame(width: 1)
                            Rectangle()
                                .fill(Self.agentColor.opacity(0.15))
                                .frame(width: 8, height: 1)
                        }
                        .frame(width: 12, height: 16)
                        .padding(.leading, 18)

                        Circle()
                            .fill(Self.agentColor.opacity(0.6))
                            .frame(width: 4, height: 4)

                        Text(task.description ?? "Agent")
                            .notchFont(9)
                            .opacity(0.45)
                            .lineLimit(1)

                        Spacer()

                        if !task.subagentTools.isEmpty {
                            Text("\(task.subagentTools.count) tools")
                                .notchFont(8)
                                .opacity(0.2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Usage Stats Bar

struct UsageStatsBar: View {
    @ObservedObject var monitor: RateLimitMonitor
    let totalMinutes: Int

    @AppStorage("usageWarningThreshold") private var usageWarningThreshold: Int = 90
    @State private var appear = false
    @State private var pulsePhase = false

    private var fiveHourPct: CGFloat {
        CGFloat(monitor.rateLimitInfo?.fiveHourPercent ?? 0) / 100.0
    }

    private var sevenDayPct: CGFloat {
        CGFloat(monitor.rateLimitInfo?.sevenDayPercent ?? 0) / 100.0
    }

    private func barColor(_ pct: Int) -> Color {
        let threshold = usageWarningThreshold
        if threshold > 0 && pct >= threshold { return Color(red: 0.94, green: 0.27, blue: 0.27) }
        if threshold > 0 && pct >= max(threshold - 20, 50) { return Color(red: 1.0, green: 0.6, blue: 0.2) }
        return Color(red: 0.29, green: 0.87, blue: 0.5)
    }

    private func formatTime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 6) {
            if let info = monitor.rateLimitInfo {
                // 5h gauge
                usageGauge(
                    pct: info.fiveHourPercent ?? 0,
                    label: "5h",
                    resetAt: info.fiveHourResetAt
                )

                // 7d gauge (if > 0)
                if let sevenDay = info.sevenDayPercent, sevenDay > 0 {
                    usageGauge(
                        pct: sevenDay,
                        label: "7d",
                        resetAt: info.sevenDayResetAt
                    )
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1, height: 14)

                // Session time
                if totalMinutes > 0 {
                    Text(formatTime(totalMinutes))
                        .notchFont(8, weight: .regular, design: .monospaced)
                        .notchSecondaryForeground()
                }

                // Refresh
                Image(systemName: "arrow.clockwise")
                    .notchFont(7)
                    .opacity(monitor.isLoading ? 0.5 : 0.2)
                    .rotationEffect(.degrees(monitor.isLoading ? 360 : 0))
                    .animation(monitor.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: monitor.isLoading)
                    .contentShape(Rectangle().size(width: 16, height: 16))
                    .onTapGesture {
                        Task { await monitor.refresh() }
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 5)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                appear = true
            }
        }
    }

    private func shouldBlink(_ pct: Int) -> Bool {
        usageWarningThreshold > 0 && pct >= usageWarningThreshold
    }

    @ViewBuilder
    private func usageGauge(pct: Int, label: String, resetAt: Date?) -> some View {
        let color = barColor(pct)
        VStack(alignment: .leading, spacing: 2) {
            // Label + percentage
            HStack(spacing: 3) {
                Text(label)
                    .notchFont(7, weight: .bold)
                    .notchSecondaryForeground()
                Text("\(pct)%")
                    .notchFont(9, weight: .semibold, design: .monospaced)
                    .foregroundColor(color)
                    .opacity(shouldBlink(pct) ? (pulsePhase ? 1.0 : 0.3) : 1.0)
                if let resetAt = resetAt {
                    let remaining = resetAt.timeIntervalSinceNow
                    if remaining > 0 {
                        Text(formatResetShort(remaining))
                            .notchFont(7)
                            .opacity(0.2)
                    }
                }
            }

            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.06))
                    .frame(width: 50, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(2, 50 * CGFloat(pct) / 100), height: 3)
                    .shadow(color: color.opacity(0.4), radius: 2)
            }
        }
        .help(usageTooltip(pct: pct, label: label, resetAt: resetAt))
    }

    private func formatResetShort(_ seconds: TimeInterval) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 {
            let h = Int(seconds / 3600)
            let m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(Int(seconds / 86400))d"
    }

    private func usageTooltip(pct: Int, label: String, resetAt: Date?) -> String {
        let window = label == "7d" ? "7天" : "5小时"
        guard let resetAt = resetAt else { return "\(window)窗口: \(pct)%" }
        let remaining = resetAt.timeIntervalSinceNow
        if remaining <= 0 { return "\(window)窗口: \(pct)% (已重置)" }
        let timeStr: String
        if remaining < 3600 {
            timeStr = "\(Int(remaining / 60))分钟"
        } else if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
            timeStr = m > 0 ? "\(h)小时\(m)分钟" : "\(h)小时"
        } else {
            timeStr = "\(Int(remaining / 86400))天"
        }
        return "\(window)窗口: \(pct)% (\(timeStr)后重置)"
    }
}

// MARK: - Codex Usage Stats Bar

struct CodexUsageStatsBar: View {
    @ObservedObject var monitor: CodexUsageMonitor

    @AppStorage("usageWarningThreshold") private var usageWarningThreshold: Int = 90
    @State private var appear = false
    @State private var pulsePhase = false

    private func barColor(_ pct: Int) -> Color {
        let threshold = usageWarningThreshold
        if threshold > 0 && pct >= threshold { return Color(red: 0.94, green: 0.27, blue: 0.27) }
        if threshold > 0 && pct >= max(threshold - 20, 50) { return Color(red: 1.0, green: 0.6, blue: 0.2) }
        return Color(red: 0.29, green: 0.87, blue: 0.5)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let snapshot = monitor.snapshot, !snapshot.isEmpty {
                Text("Codex")
                    .notchFont(7, weight: .bold)
                    .notchSecondaryForeground()
                    .opacity(0.5)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1, height: 14)

                ForEach(snapshot.windows) { window in
                    usageGauge(
                        pct: window.roundedUsedPercentage,
                        label: window.label,
                        resetAt: window.resetsAt
                    )
                }

                Image(systemName: "arrow.clockwise")
                    .notchFont(7)
                    .opacity(monitor.isLoading ? 0.5 : 0.2)
                    .rotationEffect(.degrees(monitor.isLoading ? 360 : 0))
                    .animation(
                        monitor.isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: monitor.isLoading
                    )
                    .contentShape(Rectangle().size(width: 16, height: 16))
                    .onTapGesture { Task { await monitor.refresh() } }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 5)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                appear = true
            }
        }
    }

    private func shouldBlink(_ pct: Int) -> Bool {
        usageWarningThreshold > 0 && pct >= usageWarningThreshold
    }

    @ViewBuilder
    private func usageGauge(pct: Int, label: String, resetAt: Date?) -> some View {
        let color = barColor(pct)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(label)
                    .notchFont(7, weight: .bold)
                    .notchSecondaryForeground()
                Text("\(pct)%")
                    .notchFont(9, weight: .semibold, design: .monospaced)
                    .foregroundColor(color)
                    .opacity(shouldBlink(pct) ? (pulsePhase ? 1.0 : 0.3) : 1.0)
                if let resetAt, resetAt.timeIntervalSinceNow > 0 {
                    Text(formatResetShort(resetAt.timeIntervalSinceNow))
                        .notchFont(7)
                        .opacity(0.2)
                }
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.06))
                    .frame(width: 50, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(2, 50 * CGFloat(pct) / 100), height: 3)
                    .shadow(color: color.opacity(0.4), radius: 2)
            }
        }
        .help(usageTooltip(pct: pct, label: label, resetAt: resetAt))
    }

    private func formatResetShort(_ seconds: TimeInterval) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 {
            let h = Int(seconds / 3600)
            let m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(Int(seconds / 86400))d"
    }

    private func usageTooltip(pct: Int, label: String, resetAt: Date?) -> String {
        guard let resetAt else { return "Codex \(label): \(pct)%" }
        let remaining = resetAt.timeIntervalSinceNow
        if remaining <= 0 { return "Codex \(label): \(pct)% (reset)" }
        return "Codex \(label): \(pct)% (resets in \(formatResetShort(remaining)))"
    }
}
