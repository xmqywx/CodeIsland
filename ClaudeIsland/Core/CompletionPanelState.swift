//
//  CompletionPanelState.swift
//  ClaudeIsland
//
//  Pure priority-queue + preemption logic for the Completion Panel.
//  Deterministic and side-effect-free; the @MainActor CompletionPanelController
//  wrapper owns all I/O (Task for timer, SessionStore sink, UserDefaults
//  observation, NotificationCenter). See spec §5.2 / §5.3.
//
//  ⚠️ Mirrored verbatim in scripts/test-completion-panel-state.swift for
//  the standalone test runner — keep both bodies in sync when editing.
//

import Foundation

enum PanelVariant: Equatable {
    case claudeStop(summary: String)
    case subagentDone(subagents: [SubagentLine])
    case pendingTool(request: ToolApprovalRequest)

    var priority: Int {
        switch self {
        case .pendingTool: return 30
        case .claudeStop:  return 20
        case .subagentDone: return 10
        }
    }

    var isSticky: Bool {
        if case .subagentDone = self { return true }
        return false
    }

    /// nil for sticky variants (no auto-dismiss); 15 s for A and C.
    var autoDismissSeconds: TimeInterval? {
        isSticky ? nil : 15
    }
}

struct SubagentLine: Equatable {
    let agentType: String
    let description: String
    let lastToolHint: String
}

struct ToolApprovalRequest: Equatable {
    let toolName: String
    let argumentsSummary: String
    let riskLevel: RiskLevel

    static let lowRiskTools: Set<String> = ["Bash", "Read", "Grep", "Glob", "LS"]
    static let highRiskTools: Set<String> = ["Edit", "Write", "MultiEdit", "Delete", "NotebookEdit"]
}

enum RiskLevel: Equatable { case low, high }

struct CompletionEntry: Equatable, Identifiable {
    let id: UUID
    let stableId: String
    let projectName: String
    let variant: PanelVariant
    let enqueuedAt: Date

    init(id: UUID = UUID(), stableId: String, projectName: String, variant: PanelVariant, enqueuedAt: Date = Date()) {
        self.id = id; self.stableId = stableId; self.projectName = projectName
        self.variant = variant; self.enqueuedAt = enqueuedAt
    }
}

struct CompletionPanelState: Equatable {
    struct ErrorState: Equatable {
        let stableId: String
        let message: String
    }

    private(set) var front: CompletionEntry?
    private(set) var pending: [CompletionEntry] = []
    private(set) var sendError: ErrorState? = nil
    private(set) var timerToken: UInt64 = 0
    var isPanelVisible: Bool = false

    var pendingCount: Int { pending.count }
    var totalQueued: Int { (front == nil ? 0 : 1) + pending.count }

    mutating func enqueue(_ entry: CompletionEntry) {
        // Step 1: same-session update — replace variant, preserve id & timer
        if let f = front, f.stableId == entry.stableId {
            front = CompletionEntry(
                id: f.id, stableId: f.stableId, projectName: entry.projectName,
                variant: entry.variant, enqueuedAt: f.enqueuedAt
            )
            return
        }
        // Step 2: preempt higher-priority over lower front
        if let f = front, entry.variant.priority > f.variant.priority {
            pending.insert(f, at: insertionIndex(for: f))
            front = entry
            bumpTimer()
            return
        }
        // Step 3: empty front
        if front == nil {
            front = entry
            bumpTimer()
            return
        }
        // Step 4: lower/equal priority — insert into pending
        // Dedup: same stableId in pending → replace in place
        if let idx = pending.firstIndex(where: { $0.stableId == entry.stableId }) {
            pending[idx] = entry
            return
        }
        pending.insert(entry, at: insertionIndex(for: entry))
    }

    /// Highest-priority first, FIFO within same priority.
    private func insertionIndex(for entry: CompletionEntry) -> Int {
        for (i, e) in pending.enumerated() {
            if entry.variant.priority > e.variant.priority { return i }
        }
        return pending.count
    }

    mutating func dismissFront(stableId: String) {
        guard let f = front, f.stableId == stableId else { return }
        if pending.isEmpty {
            front = nil
        } else {
            front = pending.removeFirst()
            bumpTimer()
        }
        sendError = nil
    }

    mutating func recordSendFailure(stableId: String, message: String) {
        guard let f = front, f.stableId == stableId else { return }
        sendError = ErrorState(stableId: stableId, message: message)
    }

    mutating func syncWithCurrentWaiting(_ active: Set<String>) {
        pending.removeAll { !active.contains($0.stableId) }
        if let f = front, !active.contains(f.stableId) {
            if pending.isEmpty { front = nil } else { front = pending.removeFirst(); bumpTimer() }
            sendError = nil
        }
    }

    mutating func flush(enabled: Bool) {
        if !enabled {
            front = nil
            pending.removeAll()
            sendError = nil
        }
    }

    private mutating func bumpTimer() { timerToken &+= 1 }
}
