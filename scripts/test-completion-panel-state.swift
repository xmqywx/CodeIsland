#!/usr/bin/env swift
import Foundation

// === Copy of CompletionPanelState + nested types (kept in sync with
//     ClaudeIsland/Core/CompletionPanelState.swift) ===

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

// === test harness ===
var passed = 0, failed = 0
func check(_ cond: @autoclosure () -> Bool, _ desc: String, line: UInt = #line) {
    if cond() { passed += 1; print("  ✓ \(desc)") }
    else { failed += 1; print("  ✗ \(desc) (line \(line))") }
}

func claudeEntry(_ id: String, summary: String = "s") -> CompletionEntry {
    .init(stableId: id, projectName: "Proj", variant: .claudeStop(summary: summary))
}
func subagentEntry(_ id: String) -> CompletionEntry {
    .init(stableId: id, projectName: "Proj", variant: .subagentDone(subagents: []))
}
func pendingEntry(_ id: String, tool: String = "Bash") -> CompletionEntry {
    .init(stableId: id, projectName: "Proj", variant: .pendingTool(request: ToolApprovalRequest(toolName: tool, argumentsSummary: "x", riskLevel: .low)))
}

print("=== T1: empty state ===")
var s = CompletionPanelState()
check(s.front == nil, "front is nil")
check(s.pendingCount == 0, "pending empty")
check(s.totalQueued == 0, "total 0")

print("=== T2: single enqueue → front, timer bumped ===")
let tok0 = s.timerToken
s.enqueue(claudeEntry("A"))
check(s.front?.stableId == "A", "front=A")
check(s.timerToken == tok0 &+ 1, "timer bumped")

print("=== T3: second enqueue different session lower/equal priority → pending, no timer bump ===")
let tok1 = s.timerToken
s.enqueue(claudeEntry("B"))
check(s.front?.stableId == "A", "front still A")
check(s.pendingCount == 1, "B in pending")
check(s.timerToken == tok1, "timer NOT bumped")

print("=== T4: same-session variant update → replace front, preserve id, NO timer bump ===")
let aId = s.front?.id
let tok2 = s.timerToken
s.enqueue(CompletionEntry(stableId: "A", projectName: "Proj", variant: .claudeStop(summary: "updated")))
check(s.front?.stableId == "A", "still A")
if case .claudeStop(let sum) = s.front!.variant { check(sum == "updated", "summary updated") }
else { check(false, "variant still claudeStop") }
check(s.front?.id == aId, "id preserved (no transition)")
check(s.timerToken == tok2, "timer NOT bumped")

print("=== T5: preempt — higher-priority arrives, old front goes to pending ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
let tok3 = s.timerToken
s.enqueue(pendingEntry("B"))
check(s.front?.stableId == "B", "B preempted")
check(s.pendingCount == 1, "A pushed to pending")
check(s.pending.first?.stableId == "A", "A is first in pending")
check(s.timerToken == tok3 &+ 1, "timer bumped on preempt")

print("=== T6: preempt — lower-priority arrives, goes to pending, no preempt ===")
s = CompletionPanelState()
s.enqueue(pendingEntry("A"))
let tok4 = s.timerToken
s.enqueue(subagentEntry("B"))
check(s.front?.stableId == "A", "A still front")
check(s.pendingCount == 1, "B in pending")
check(s.timerToken == tok4, "no timer bump")

print("=== T7: same-priority different session → append, no preempt ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.enqueue(claudeEntry("B"))
s.enqueue(claudeEntry("C"))
check(s.front?.stableId == "A", "A still front")
check(s.pendingCount == 2, "B+C in pending")
check(s.pending[0].stableId == "B" && s.pending[1].stableId == "C", "FIFO within same priority")

print("=== T8: priority ordering in pending ===")
s = CompletionPanelState()
s.enqueue(pendingEntry("X"))
s.enqueue(subagentEntry("S"))
s.enqueue(claudeEntry("C"))
check(s.pending[0].stableId == "C" && s.pending[1].stableId == "S", "pending sorted high-to-low")

print("=== T9: dismissFront promotes highest-priority pending + bumps timer ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.enqueue(subagentEntry("S"))
s.enqueue(pendingEntry("P"))
let tok5 = s.timerToken
s.dismissFront(stableId: "P")
check(s.front?.stableId == "A", "A promoted (priority 20 > 10)")
check(s.pendingCount == 1 && s.pending.first?.stableId == "S", "S remains in pending")
check(s.timerToken == tok5 &+ 1, "timer bumped on promotion")

print("=== T10: dismissFront last → front nil, no bump ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
let tok6 = s.timerToken
s.dismissFront(stableId: "A")
check(s.front == nil, "front nil")
check(s.timerToken == tok6, "no bump on empty promotion")

print("=== T11: dismissFront wrong id is no-op ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
let tok7 = s.timerToken
s.dismissFront(stableId: "Z")
check(s.front?.stableId == "A", "unchanged")
check(s.timerToken == tok7, "no bump")

print("=== T12: recordSendFailure sets error, no timer bump ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
let tok8 = s.timerToken
s.recordSendFailure(stableId: "A", message: "fail")
check(s.sendError?.stableId == "A", "error set")
check(s.timerToken == tok8, "no bump on failure")

print("=== T13: recordSendFailure on wrong id = no-op ===")
s.recordSendFailure(stableId: "Z", message: "fail2")
check(s.sendError?.message == "fail", "error unchanged")

print("=== T14: dismissFront clears sendError ===")
s.dismissFront(stableId: "A")
check(s.sendError == nil, "error cleared")

print("=== T15: flush(enabled=false) clears everything ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.enqueue(claudeEntry("B"))
s.recordSendFailure(stableId: "A", message: "x")
s.flush(enabled: false)
check(s.front == nil && s.pendingCount == 0 && s.sendError == nil, "all cleared")

print("=== T16: flush(enabled=true) on populated state is no-op ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.flush(enabled: true)
check(s.front?.stableId == "A", "front preserved")

print("=== T17: syncWithCurrentWaiting drops dead front + pending, promotes next ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.enqueue(claudeEntry("B"))
s.enqueue(claudeEntry("C"))
s.syncWithCurrentWaiting(Set(["B"]))
check(s.front?.stableId == "B", "B promoted (A dead)")
check(s.pendingCount == 0, "C also dead")

print("=== T18: syncWithCurrentWaiting(empty) clears all ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.enqueue(claudeEntry("B"))
s.syncWithCurrentWaiting(Set())
check(s.front == nil && s.pendingCount == 0, "all cleared")

print("=== T19: dedup in pending — same stableId replaces in place ===")
s = CompletionPanelState()
s.enqueue(claudeEntry("A"))
s.enqueue(claudeEntry("B", summary: "old"))
s.enqueue(claudeEntry("B", summary: "new"))
check(s.pendingCount == 1, "not duplicated")
if case .claudeStop(let sum) = s.pending.first!.variant { check(sum == "new", "summary updated") }

print("=== T20: PanelVariant priority ordering ===")
check(PanelVariant.pendingTool(request: .init(toolName:"x", argumentsSummary:"", riskLevel:.low)).priority == 30, "pendingTool=30")
check(PanelVariant.claudeStop(summary: "").priority == 20, "claudeStop=20")
check(PanelVariant.subagentDone(subagents: []).priority == 10, "subagentDone=10")

print("=== T21: PanelVariant.isSticky ===")
check(PanelVariant.subagentDone(subagents: []).isSticky, "subagentDone sticky")
check(!PanelVariant.claudeStop(summary: "").isSticky, "claudeStop NOT sticky")
check(!PanelVariant.pendingTool(request: .init(toolName:"x", argumentsSummary:"", riskLevel:.low)).isSticky, "pendingTool NOT sticky")

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
