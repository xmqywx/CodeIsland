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

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                // Top bar: session count left, gear right
                HStack {
                    Text("\(sessionMonitor.instances.count) sessions")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.toggleMenu()
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)

                if showGrouped {
                    groupedList
                } else {
                    flatList
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Run claude in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
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
        case .waitingForApproval, .processing, .compacting: return 0
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
                    .contentShape(Rectangle())
                    .onTapGesture { openChat(session) }
                    .id(session.stableId)

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
                            .contentShape(Rectangle())
                            .onTapGesture { openChat(session) }
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
            let cwd = session.cwd
            let cmuxScript = """
            tell application "cmux"
                set allTerms to terminals
                repeat with t in allTerms
                    if working directory of t contains "\(cwd)" then
                        focus t
                        return
                    end if
                end repeat
                activate
            end tell
            """
            do {
                _ = try await ProcessExecutor.shared.run("/usr/bin/osascript", arguments: ["-e", cmuxScript])
            } catch {}
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
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
    @State private var isYabaiAvailable = false

    private static let rowBackground = Color(red: 0.11, green: 0.11, blue: 0.18)  // #1C1C2E
    private static let rowBorder = Color.white.opacity(0.08)
    private static let purple = Color(red: 0.7, green: 0.4, blue: 0.9)

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    /// Duration since session started, formatted as "Xm" or "Xh"
    private var durationText: String {
        let elapsed = Date().timeIntervalSince(session.createdAt)
        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "\(max(1, minutes))m"
        }
        let hours = minutes / 60
        return "\(hours)h"
    }

    /// Short terminal name derived from tty path
    private var terminalTag: String {
        if session.isInTmux {
            return "cmux"
        }
        if let tty = session.tty {
            let name = URL(fileURLWithPath: tty).lastPathComponent
            return name
        }
        return "term"
    }

    /// Accent color based on phase
    private var accentColor: Color {
        switch session.phase {
        case .processing, .compacting: return Color(red: 0.4, green: 0.91, blue: 0.98) // cyan
        case .waitingForApproval: return Color(red: 0.96, green: 0.62, blue: 0.04) // amber
        case .waitingForInput: return Color(red: 0.29, green: 0.87, blue: 0.5)  // green
        case .idle, .ended: return Color.white.opacity(0.2)
        }
    }

    /// Lighter tint for title text
    private var titleColor: Color {
        switch session.phase {
        case .processing, .compacting: return Color(red: 0.88, green: 0.97, blue: 1.0) // light cyan
        case .waitingForApproval: return Color(red: 1.0, green: 0.95, blue: 0.78) // light amber
        case .waitingForInput: return Color(red: 0.82, green: 0.98, blue: 0.88)  // light green
        case .idle, .ended: return Color.white.opacity(0.4)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Active: cat animation, Idle: glow dot
                if session.phase == .processing || session.phase == .compacting || session.phase.isWaitingForApproval {
                    PixelCharacterView(state: session.phase.animationState)
                        .scaleEffect(0.28)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)
                } else {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: accentColor.opacity(0.6), radius: 4)
                        .shadow(color: accentColor.opacity(0.3), radius: 8)
                        .padding(.top, 5)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    // Title row
                    HStack {
                        Text(session.displayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(titleColor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(durationText)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    // Subtitle
                    subtitleView
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isHovered ? Color.white.opacity(0.04) : Color.clear)
            .cornerRadius(8)
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleView: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            HStack(spacing: 4) {
                Text(MCPToolFormatter.formatToolName(toolName))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.9))
                if isInteractiveTool {
                    Text("Needs your input")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                } else if let input = session.pendingToolInput {
                    Text(input)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else if let role = session.lastMessageRole {
            switch role {
            case "tool":
                HStack(spacing: 4) {
                    if let toolName = session.lastToolName {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    if let input = session.lastMessage {
                        Text(input)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            case "user":
                HStack(spacing: 4) {
                    Text("You:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    if let msg = session.lastMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            default:
                if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        } else if let lastMsg = session.lastMessage {
            Text(lastMsg)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    // MARK: - Status Line

    @ViewBuilder
    private var statusLine: some View {
        switch session.phase {
        case .processing:
            Text("Working...")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.cyan)
        case .waitingForApproval:
            if isInteractiveTool {
                // Interactive tools: show approval buttons inline on the status line
                HStack(spacing: 6) {
                    Text("Needs approval")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.amber)
                    Spacer()
                    InlineApprovalButtons(
                        onChat: onChat,
                        onApprove: onApprove,
                        onReject: onReject
                    )
                }
            } else {
                HStack(spacing: 6) {
                    Text("Needs approval")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.amber)
                    Spacer()
                    InlineApprovalButtons(
                        onChat: onChat,
                        onApprove: onApprove,
                        onReject: onReject
                    )
                }
            }
        case .waitingForInput:
            Button {
                onFocus()
            } label: {
                Text("Done \u{2014} click to jump")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.green)
            }
            .buttonStyle(.plain)
        case .compacting:
            Text("Compacting...")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Self.purple)
        case .idle, .ended:
            Text("Idle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 12)

                Text(group.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                if group.activeCount > 0 {
                    Text("\(group.activeCount) active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                } else if group.isArchivable {
                    Text("archived")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
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
                Text("Deny")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
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
                Text("Allow")
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
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
                    .font(.system(size: 8, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
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
                    .font(.system(size: 11, weight: .medium))
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
