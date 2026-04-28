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

private func normalizedPanelText(_ raw: String?) -> String {
    SummaryExtraction.extract(raw)
}

private func latestUserPrompt(in session: SessionState) -> String {
    for item in session.chatItems.reversed() {
        if case .user(let text) = item.type {
            let clean = normalizedPanelText(text)
            if !clean.isEmpty { return clean }
        }
    }
    if let latest = session.conversationInfo.latestUserMessage {
        let clean = normalizedPanelText(latest)
        if !clean.isEmpty { return clean }
    }
    return ""
}

private func latestAssistantResponse(in session: SessionState) -> String {
    if let lastUserIndex = session.chatItems.lastIndex(where: {
        if case .user = $0.type { return true }
        return false
    }) {
        let afterLastUser = session.chatItems.index(after: lastUserIndex)
        if afterLastUser < session.chatItems.endIndex {
            for item in session.chatItems[afterLastUser...].reversed() {
                if case .assistant(let text) = item.type {
                    let clean = normalizedPanelText(text)
                    if !clean.isEmpty { return clean }
                }
            }
        }
        return ""
    }

    for item in session.chatItems.reversed() {
        if case .assistant(let text) = item.type {
            let clean = normalizedPanelText(text)
            if !clean.isEmpty { return clean }
        }
    }

    if session.conversationInfo.lastMessageRole == "assistant" {
        let clean = normalizedPanelText(session.conversationInfo.lastMessage)
        if !clean.isEmpty { return clean }
    }
    return ""
}

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
    /// Per-session `lastStopAt` snapshot. Main signal for claudeStop
    /// detection: if `session.lastStopAt` advanced since last tick, a real
    /// Stop hook just landed. Unlike phase-diff (which misses
    /// SubagentStop→Stop sequences where the session is already in
    /// waitingForInput) or activity-triggered (which over-fires on
    /// idle→waiting transitions), this is the single authoritative
    /// "Claude just finished" signal.
    private var previousLastStopAtByStableId: [String: Date] = [:]

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
        state.syncWithCurrentWaiting(waitingIds) { [weak self] entry in
            guard let self else { return false }
            return self.popTimePredicateHolds(for: entry)
        }

        let activeIds = Set(sessions.map(\.stableId))
        previousActiveTaskIds = previousActiveTaskIds.filter { activeIds.contains($0.key) }
        previousTaskContextByToolId = previousTaskContextByToolId.filter { activeIds.contains($0.key) }
        previousPhaseByStableId = previousPhaseByStableId.filter { activeIds.contains($0.key) }
        previousLastStopAtByStableId = previousLastStopAtByStableId.filter { activeIds.contains($0.key) }

        if !didCaptureBaseline {
            previousWaitingIds = waitingIds
            for session in sessions {
                previousPhaseByStableId[session.stableId] = session.phase
                previousActiveTaskIds[session.stableId] = Set(session.subagentState.activeTasks.keys)
                previousTaskContextByToolId[session.stableId] = session.subagentState.activeTasks
                if let stop = session.lastStopAt {
                    previousLastStopAtByStableId[session.stableId] = stop
                }
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

            // Primary signal: the Stop hook itself. `session.lastStopAt` is
            // set in SessionStore only on Stop events, so any advance = real
            // Claude completion. Robust across SubagentStop→Stop sequences
            // where phase-diff would miss because prev was already
            // waitingForInput, and across idle→waiting where
            // activity-triggered used to over-fire.
            let prevStop = previousLastStopAtByStableId[session.stableId]
            let stopEventFired: Bool = {
                guard let currStop = session.lastStopAt else { return false }
                if let prev = prevStop, currStop <= prev { return false }
                // Recency: cap at 30 s so a hook that arrived while app was
                // backgrounded doesn't pop a stale panel. 30 s > 100 ms
                // publisher debounce + any realistic hook pipeline latency.
                return Date().timeIntervalSince(currStop) < 30.0
            }()

            let alreadyQueued = state.front?.stableId == session.stableId
                || state.pending.contains(where: { $0.stableId == session.stableId })

            let transitionedToWaiting = stopEventFired
                && session.phase == .waitingForInput
                && !alreadyQueued

            if stopEventFired && session.phase != .waitingForInput {
                DebugLogger.log("CP/suppress", "stopEvent but phase=\(String(describing: session.phase)) session=\(session.stableId.prefix(8))")
            }
            if transitionedToWaiting {
                DebugLogger.log("CP/transition", "stop-event session=\(session.stableId.prefix(8)) prevPhase=\(String(describing: prevPhase)) stopAt=\(session.lastStopAt?.description ?? "nil")")
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
                state.enqueue(makeClaudeStopEntry(for: session))
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

        refreshQueuedClaudeStopContent(using: sessions)

        refreshSnapshots(sessions)
        restartTimer()
    }

    private func refreshSnapshots(_ sessions: [SessionState]) {
        var newPhase: [String: SessionPhase] = [:]
        var newSubs: [String: Set<String>] = [:]
        var newTaskCtx: [String: [String: TaskContext]] = [:]
        var newStop: [String: Date] = [:]
        for session in sessions {
            newPhase[session.stableId] = session.phase
            newSubs[session.stableId] = Set(session.subagentState.activeTasks.keys)
            newTaskCtx[session.stableId] = session.subagentState.activeTasks
            if let stop = session.lastStopAt {
                newStop[session.stableId] = stop
            }
        }
        previousPhaseByStableId = newPhase
        previousActiveTaskIds = newSubs
        previousTaskContextByToolId = newTaskCtx
        previousLastStopAtByStableId = newStop
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

    private func makeClaudeStopEntry(for session: SessionState) -> CompletionEntry {
        CompletionEntry(
            stableId: session.stableId,
            projectName: session.projectName,
            variant: .claudeStop(content: buildClaudeStopContent(for: session))
        )
    }

    private func buildClaudeStopContent(for session: SessionState) -> ClaudeStopContent {
        let prompt = latestUserPrompt(in: session)
        let response = latestAssistantResponse(in: session)
        DebugLogger.log(
            "CP/content",
            "session=\(session.stableId.prefix(8)) agent=\(session.agentTag) terminal=\(session.terminalTag) "
                + "promptLen=\(prompt.count) responseLen=\(response.count) "
                + "prompt=\(String(prompt.prefix(80))) response=\(String(response.prefix(120)))"
        )
        return ClaudeStopContent(
            prompt: prompt,
            response: response,
            agentTag: session.agentTag,
            terminalTag: session.terminalTag
        )
    }

    private func hasQueuedClaudeStop(for stableId: String) -> Bool {
        if let front = state.front,
           front.stableId == stableId,
           case .claudeStop = front.variant {
            return true
        }
        return state.pending.contains {
            guard $0.stableId == stableId else { return false }
            if case .claudeStop = $0.variant { return true }
            return false
        }
    }

    private func refreshQueuedClaudeStopContent(using sessions: [SessionState]) {
        for session in sessions where session.phase == .waitingForInput {
            guard hasQueuedClaudeStop(for: session.stableId) else { continue }
            state.enqueue(makeClaudeStopEntry(for: session))
            scheduleTranscriptRefresh(for: session)
        }
    }

    private func scheduleTranscriptRefresh(for session: SessionState) {
        if session.codexTranscriptPath == nil {
            let stableId = session.stableId
            let sessionId = session.sessionId
            let cwd = session.cwd
            Task { [weak self] in
                for attempt in 0..<5 {
                    let messages = await ConversationParser.shared.parseFullConversation(sessionId: sessionId, cwd: cwd)
                    if let lastAssistantText = messages.last(where: { $0.role == .assistant })?.textContent {
                        let clean = normalizedPanelText(lastAssistantText)
                        if !clean.isEmpty {
                            await MainActor.run { [weak self] in
                                guard let self, self.hasQueuedClaudeStop(for: stableId),
                                      let refreshedSession = self.lastKnownSessions[stableId] else { return }
                                let content = ClaudeStopContent(
                                    prompt: latestUserPrompt(in: refreshedSession),
                                    response: clean,
                                    agentTag: refreshedSession.agentTag,
                                    terminalTag: refreshedSession.terminalTag
                                )
                                self.state.enqueue(CompletionEntry(
                                    stableId: stableId,
                                    projectName: refreshedSession.projectName,
                                    variant: .claudeStop(content: content)
                                ))
                            }
                            return
                        }
                    }
                    if attempt < 4 {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
            }
            return
        }

        let stableId = session.stableId
        let path = session.codexTranscriptPath!
        Task { [weak self] in
            for attempt in 0..<5 {
                let full = await CodexChatHistoryParser.shared.lastAssistantMessage(transcriptPath: path) ?? ""
                let clean = normalizedPanelText(full)
                if !clean.isEmpty {
                    await MainActor.run { [weak self] in
                        guard let self, self.hasQueuedClaudeStop(for: stableId),
                              let refreshedSession = self.lastKnownSessions[stableId] else { return }
                        let content = ClaudeStopContent(
                            prompt: latestUserPrompt(in: refreshedSession),
                            response: clean,
                            agentTag: refreshedSession.agentTag,
                            terminalTag: refreshedSession.terminalTag
                        )
                        self.state.enqueue(CompletionEntry(
                            stableId: stableId,
                            projectName: refreshedSession.projectName,
                            variant: .claudeStop(content: content)
                        ))
                    }
                    return
                }
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
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
