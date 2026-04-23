//
//  CompletionPanelController.swift
//  ClaudeIsland
//
//  @MainActor wrapper around the pure CompletionPanelState. Owns all
//  side effects: the 15 s auto-dismiss Task, Combine subscription to
//  SessionStore.sessionsPublisher, KVO observer for the
//  "quickReplyEnabled" UserDefault. Spec §5.4.
//

import Combine
import Foundation

@MainActor
final class CompletionPanelController: NSObject, ObservableObject {
    static let shared = CompletionPanelController()

    @Published private(set) var state = CompletionPanelState()

    // MARK: - Dependencies / observers

    private var autoDismissTask: Task<Void, Never>?
    private var sessionsCancellable: AnyCancellable?
    private var observingEnabledKey = false
    private static let enabledKey = "quickReplyEnabled"

    // MARK: - Detection caches

    private var previousWaitingIds: Set<String> = []
    private var didCaptureBaseline = false
    private var previousPhaseByStableId: [String: SessionPhase] = [:]
    private var previousActiveTaskIds: [String: Set<String>] = [:]
    private var previousTaskContextByToolId: [String: [String: TaskContext]] = [:]
    private var lastKnownSessions: [String: SessionState] = [:]
    /// Per-session `lastActivity` snapshot from prev tick. Used as a
    /// monotonic marker — if a session is in .waitingForInput AND its
    /// lastActivity advanced since last snapshot, treat it as a fresh
    /// Stop event even if the phase-diff test missed it (SessionStore
    /// publisher can coalesce rapid processing→waiting→processing frames).
    private var previousLastActivityByStableId: [String: Date] = [:]

    // MARK: - Init

    private override init() {
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: Self.enabledKey, options: [.new, .old], context: nil)
        observingEnabledKey = true

        sessionsCancellable = SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                Task { @MainActor [weak self] in self?.onSessionsUpdate(sessions) }
            }
    }

    deinit {
        if observingEnabledKey {
            UserDefaults.standard.removeObserver(self, forKeyPath: Self.enabledKey)
        }
    }

    // MARK: - KVO

    override nonisolated func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.enabledKey else { return }
        let oldV = (change?[.oldKey] as? Bool) ?? true
        let newV = (change?[.newKey] as? Bool) ?? true
        guard oldV != newV else { return }
        Task { @MainActor [weak self] in self?.applyEnabledChange() }
    }

    // MARK: - Public actions (called from views)

    func dismissFront(stableId: String) {
        state.dismissFront(stableId: stableId)
        while let next = state.front, !popTimePredicateHolds(for: next) {
            state.dismissFront(stableId: next.stableId)
        }
        restartTimer()
    }

    func recordSendFailure(stableId: String, message: String) {
        state.recordSendFailure(stableId: stableId, message: message)
        autoDismissTask?.cancel(); autoDismissTask = nil
    }

    func setPanelVisible(_ visible: Bool) {
        state.isPanelVisible = visible
        if visible { restartTimer() } else { autoDismissTask?.cancel(); autoDismissTask = nil }
    }

    /// Mouse-over on the panel pauses the 15s auto-dismiss timer. When the
    /// mouse leaves, the timer restarts fresh. Keeps the panel open as long
    /// as the user is actively interacting with it.
    private(set) var isPanelHovered: Bool = false
    func setPanelHovered(_ hovered: Bool) {
        isPanelHovered = hovered
        if hovered {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        } else {
            restartTimer()
        }
    }

    // MARK: - Internals

    private func applyEnabledChange() {
        let enabled = (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
        state.flush(enabled: enabled)
        restartTimer()
    }

    private func onSessionsUpdate(_ sessions: [SessionState]) {
        // Drop user-hidden cwds before any state derivation — completion panel,
        // unattended alert, and "needs you" badges all skip blacklisted projects.
        let sessions = sessions.filter { !HiddenProjectsStore.shared.isHidden(cwd: $0.cwd) }

        lastKnownSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.stableId, $0) })

        let waitingNow = sessions.filter { $0.phase == .waitingForInput }
        let waitingIds = Set(waitingNow.map(\.stableId))
        state.syncWithCurrentWaiting(waitingIds)

        let activeIds = Set(sessions.map(\.stableId))
        previousActiveTaskIds = previousActiveTaskIds.filter { activeIds.contains($0.key) }
        previousTaskContextByToolId = previousTaskContextByToolId.filter { activeIds.contains($0.key) }
        previousPhaseByStableId = previousPhaseByStableId.filter { activeIds.contains($0.key) }
        previousLastActivityByStableId = previousLastActivityByStableId.filter { activeIds.contains($0.key) }

        if !didCaptureBaseline {
            previousWaitingIds = waitingIds
            for session in sessions {
                previousPhaseByStableId[session.stableId] = session.phase
                previousActiveTaskIds[session.stableId] = Set(session.subagentState.activeTasks.keys)
                previousTaskContextByToolId[session.stableId] = session.subagentState.activeTasks
                previousLastActivityByStableId[session.stableId] = session.lastActivity
            }
            didCaptureBaseline = true
            return
        }

        let enabled = (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
        guard enabled else {
            refreshSnapshots(sessions)
            return
        }

        for session in sessions {
            let prevPhase = previousPhaseByStableId[session.stableId]
            let prevSubs = previousActiveTaskIds[session.stableId] ?? []
            let nowSubs = Set(session.subagentState.activeTasks.keys)
            let finishedSubs = prevSubs.subtracting(nowSubs)

            // Phase-diff detection (strict).
            let phaseTransitionedToWaiting = (prevPhase == .processing || prevPhase == .compacting)
                && session.phase == .waitingForInput

            // Activity-marker detection (loose). Catches cases where SessionStore
            // publisher coalesced processing → waitingForInput → processing frames:
            // session is currently waiting AND its lastActivity advanced since
            // last snapshot AND we don't already have an entry for this session
            // (avoid duplicate enqueues when phase-diff already fired).
            let prevActivity = previousLastActivityByStableId[session.stableId]
            let activityAdvanced = prevActivity.map { $0 < session.lastActivity } ?? false
            let isWaiting = session.phase == .waitingForInput
            let alreadyQueued = state.front?.stableId == session.stableId
                || state.pending.contains(where: { $0.stableId == session.stableId })
            let activityTriggered = isWaiting && activityAdvanced && !alreadyQueued

            let transitionedToWaiting = phaseTransitionedToWaiting || activityTriggered
            if activityTriggered && !phaseTransitionedToWaiting {
                DebugLogger.log("CP/transition", "activity-triggered session=\(session.stableId.prefix(8)) prevPhase=\(String(describing: prevPhase)) currentPhase=waitingForInput")
            }

            let transitionedToApproval: Bool = {
                guard let prev = prevPhase else { return false }
                if case .waitingForApproval = prev { return false }
                if case .waitingForApproval = session.phase { return true }
                return false
            }()

            if transitionedToWaiting, !finishedSubs.isEmpty {
                let lines = finishedSubs.compactMap { toolId -> SubagentLine? in
                    guard let ctx = (previousTaskContextByToolId[session.stableId] ?? [:])[toolId] else { return nil }
                    return Self.subagentLine(from: ctx)
                }
                guard !lines.isEmpty else { continue }
                state.enqueue(CompletionEntry(
                    stableId: session.stableId,
                    projectName: session.projectName,
                    variant: .subagentDone(subagents: lines)
                ))
            } else if transitionedToWaiting {
                if session.hasNoContentYet {
                    DebugLogger.log("CP/suppress", "claudeStop suppressed hasNoContentYet session=\(session.stableId.prefix(8))")
                    continue
                }
                // NOTE: Dropped the `isSessionTerminalFrontmost` suppression
                // (v2 spec Q10 had it). In real usage the user works terminal +
                // Claude side by side — the terminal is frontmost most of the
                // time, which suppressed almost every panel. Users want the
                // panel to surface EVEN when the terminal is front so they
                // can respond without pulling focus off their terminal.
                let rawSummary = resolveSummary(for: session)
                let clean = SummaryExtraction.extract(rawSummary)
                state.enqueue(CompletionEntry(
                    stableId: session.stableId,
                    projectName: session.projectName,
                    variant: .claudeStop(summary: clean)
                ))
            }

            if transitionedToApproval {
                if session.pendingToolName == "AskUserQuestion" { continue }
                guard let perm = session.activePermission else { continue }
                let toolName = perm.toolName
                let risk: RiskLevel =
                    ToolApprovalRequest.lowRiskTools.contains(toolName) ? .low :
                    ToolApprovalRequest.highRiskTools.contains(toolName) ? .high : .high
                // formattedInput is optional — fallback to empty string if nil
                let args = String((perm.formattedInput ?? "").prefix(200))
                state.enqueue(CompletionEntry(
                    stableId: session.stableId,
                    projectName: session.projectName,
                    variant: .pendingTool(request: ToolApprovalRequest(
                        toolName: toolName, argumentsSummary: args, riskLevel: risk
                    ))
                ))
            }
        }

        refreshSnapshots(sessions)
        restartTimer()
    }

    private func refreshSnapshots(_ sessions: [SessionState]) {
        var newPhase: [String: SessionPhase] = [:]
        var newSubs: [String: Set<String>] = [:]
        var newTaskCtx: [String: [String: TaskContext]] = [:]
        var newActivity: [String: Date] = [:]
        for session in sessions {
            newPhase[session.stableId] = session.phase
            newSubs[session.stableId] = Set(session.subagentState.activeTasks.keys)
            newTaskCtx[session.stableId] = session.subagentState.activeTasks
            newActivity[session.stableId] = session.lastActivity
        }
        previousPhaseByStableId = newPhase
        previousActiveTaskIds = newSubs
        previousTaskContextByToolId = newTaskCtx
        previousLastActivityByStableId = newActivity
        previousWaitingIds = Set(sessions.filter { $0.phase == .waitingForInput }.map(\.stableId))
    }

    private static func subagentLine(from ctx: TaskContext) -> SubagentLine {
        let agentType = ctx.agentId ?? "agent"
        let description = String((ctx.description ?? "").prefix(60))
        let lastToolHint: String = {
            guard let last = ctx.subagentTools.last else { return "" }
            // input is [String: String] — join up to 2 key-value pairs for a compact hint
            let inputStr = last.input.prefix(2).map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            let combined = "[\(last.name)] \(inputStr)"
            return String(combined.prefix(80))
        }()
        return SubagentLine(agentType: agentType, description: description, lastToolHint: lastToolHint)
    }

    private func resolveSummary(for session: SessionState) -> String {
        if session.codexTranscriptPath == nil {
            // Claude session. conversationInfo.lastMessage may be tool INPUT
            // when the last transcript entry is a tool call (ConversationParser
            // line ~178) — that's why the panel showed a raw bash command.
            // Seed with the (possibly wrong) fallback now so the panel pops
            // immediately, then refresh asynchronously with the real last
            // assistant text from the transcript via enqueue dedup.
            let fallback = session.conversationInfo.lastMessage ?? ""
            let stableId = session.stableId
            let projectName = session.projectName
            let sessionId = session.sessionId
            let cwd = session.cwd
            Task { [weak self] in
                let messages = await ConversationParser.shared.parseFullConversation(
                    sessionId: sessionId, cwd: cwd
                )
                guard let lastAssistantText = messages.last(where: { $0.role == .assistant })?.textContent,
                      !lastAssistantText.isEmpty else { return }
                let clean = SummaryExtraction.extract(lastAssistantText)
                guard !clean.isEmpty else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.state.front?.stableId == stableId
                        || self.state.pending.contains(where: { $0.stableId == stableId }) {
                        self.state.enqueue(CompletionEntry(
                            stableId: stableId, projectName: projectName,
                            variant: .claudeStop(summary: clean)
                        ))
                    }
                }
            }
            return fallback
        }
        // Codex session — attempt async transcript parse, return fast fallback immediately
        let fallback = session.conversationInfo.lastMessage ?? ""
        let stableId = session.stableId
        let projectName = session.projectName
        let path = session.codexTranscriptPath!
        Task { [weak self] in
            let full = await CodexChatHistoryParser.shared.lastAssistantMessage(transcriptPath: path) ?? ""
            let clean = SummaryExtraction.extract(full)
            guard !clean.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.state.front?.stableId == stableId
                    || self.state.pending.contains(where: { $0.stableId == stableId }) {
                    self.state.enqueue(CompletionEntry(
                        stableId: stableId, projectName: projectName,
                        variant: .claudeStop(summary: clean)
                    ))
                }
            }
        }
        return fallback
    }

    private func popTimePredicateHolds(for entry: CompletionEntry) -> Bool {
        guard let s = lastKnownSessions[entry.stableId] else { return false }
        switch entry.variant {
        case .claudeStop:     return s.phase == .waitingForInput
        case .subagentDone:   return true
        case .pendingTool:    if case .waitingForApproval = s.phase { return true }; return false
        }
    }

    private func restartTimer() {
        autoDismissTask?.cancel()
        guard let front = state.front else { return }
        guard state.isPanelVisible, state.sendError == nil else { return }
        // Mouse currently over panel — skip scheduling; setPanelHovered(false)
        // will call restartTimer again when the mouse leaves.
        guard !isPanelHovered else { return }
        guard let seconds = front.variant.autoDismissSeconds else { return }

        let token = state.timerToken
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, self.state.timerToken == token else { return }
            if let f = self.state.front { self.dismissFront(stableId: f.stableId) }
        }
    }
}
