//
//  ClaudeStopVariantView.swift
//  ClaudeIsland
//
//  Variant A — Claude Stop. 3-line summary + phrase buttons + "Go to
//  terminal". 15s auto-dismiss + autoCollapseOnMouseLeave. Spec §5.6.
//

import SwiftUI

struct ClaudeStopVariantView: View {
    let entry: CompletionEntry
    let summary: String
    @ObservedObject private var controller = CompletionPanelController.shared
    @State private var isCodex: Bool = false

    private var phrases: [QuickReplyPhrase] { QuickReplyPhrases.current }

    // Gradient palette shared by title + summary + CTA glow
    private let accentGradient = LinearGradient(
        colors: [
            Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255),
            Color(red: 0x7A/255, green: 0xE6/255, blue: 0xFF/255),
            Color(red: 0xB4/255, green: 0xA0/255, blue: 0xFF/255)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let titleGradient = LinearGradient(
        colors: [.white, Color.white.opacity(0.75)],
        startPoint: .leading, endPoint: .trailing
    )
    private let summaryGradient = LinearGradient(
        colors: [Color.white.opacity(0.95), Color.white.opacity(0.7)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            summaryView
            if let err = controller.state.sendError, err.stableId == entry.stableId {
                errorRow(err.message)
            }
            if !isCodex { phraseRow }
            terminalButtonRow
        }
        .task(id: entry.stableId) {
            isCodex = (await SessionStore.shared.session(withStableId: entry.stableId)?.codexTranscriptPath != nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .onAppear { controller.setPanelVisible(true) }
        .onDisappear { controller.setPanelVisible(false) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accentGradient)
                .frame(width: 6, height: 6)
                .shadow(color: Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(0.6), radius: 4)
            Text(entry.projectName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleGradient)
            Spacer()
            if controller.state.pendingCount > 0 {
                pendingBadge
            }
            CloseButton(action: { controller.dismissFront(stableId: entry.stableId) })
        }
    }

    private var pendingBadge: some View {
        Text("+\(controller.state.pendingCount)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Summary (3-line reserved height + gradient text)

    private var summaryView: some View {
        Text(summary.isEmpty ? "…" : summary)
            .font(.system(size: 12.5, weight: .regular, design: .default))
            .foregroundStyle(summaryGradient)
            .lineLimit(3)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
    }

    // MARK: - Error row

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange],
                                   startPoint: .top, endPoint: .bottom)
                )
            Text(message).font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
            Spacer()
            Button(action: jumpToTerminal) {
                Text(L10n.qrGoToTerminal)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(colors: [
                        Color.yellow.opacity(0.18),
                        Color.orange.opacity(0.10)
                    ], startPoint: .leading, endPoint: .trailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.yellow.opacity(0.35), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Phrase row

    private var phraseRow: some View {
        HStack(spacing: 7) {
            ForEach(phrases) { phrase in
                PhraseButton(text: phrase.text) { send(phrase.text) }
            }
            Spacer()
        }
    }

    // MARK: - CTA row

    private var terminalButtonRow: some View {
        HStack {
            Spacer()
            PrimaryCTAButton(label: L10n.qrGoToTerminal, action: jumpToTerminal)
        }
    }

    // MARK: - Panel background

    private var panelBackground: some View {
        PixelCardBackground(cornerRadius: 14)
    }

    // MARK: - Actions

    private func send(_ text: String) {
        let stableId = entry.stableId
        Task {
            guard let session = await SessionStore.shared.session(withStableId: stableId) else {
                DebugLogger.log("CP/send", "no session for stableId=\(stableId.prefix(8))")
                await MainActor.run {
                    controller.recordSendFailure(stableId: stableId, message: L10n.qrSendFailed)
                }
                return
            }
            DebugLogger.log("CP/send", "attempt session=\(stableId.prefix(8)) termApp=\(session.terminalApp ?? "nil") pid=\(session.pid) cwd=\(session.cwd) text=\(text)")
            let ok = await TerminalWriter.shared.sendTextDirect(
                text + "\n",
                claudeUuid: session.sessionId,
                cwd: session.cwd,
                livePid: session.pid,
                cmuxWorkspaceId: nil,
                cmuxSurfaceId: nil,
                terminalApp: session.terminalApp
            )
            DebugLogger.log("CP/send", "result session=\(stableId.prefix(8)) ok=\(ok)")
            await MainActor.run {
                if ok { controller.dismissFront(stableId: stableId) }
                else  { controller.recordSendFailure(stableId: stableId, message: L10n.qrSendFailed) }
            }
        }
    }

    private func jumpToTerminal() {
        let stableId = entry.stableId
        Task {
            guard let session = await SessionStore.shared.session(withStableId: stableId) else { return }
            _ = await TerminalJumper.shared.jump(to: session)
            await MainActor.run { controller.dismissFront(stableId: stableId) }
        }
    }
}

// MARK: - Reusable button components

/// Soft gradient pill with hover scale, glow, and press-state animation.
private struct PhraseButton: View {
    let text: String
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isHovering
                            ? [.white, Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)]
                            : [Color.white.opacity(0.92), Color.white.opacity(0.82)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: isHovering
                                    ? [Color.white.opacity(0.22), Color.white.opacity(0.10)]
                                    : [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: isHovering
                                            ? [Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(0.5),
                                               Color(red: 0x7A/255, green: 0xE6/255, blue: 0xFF/255).opacity(0.3)]
                                            : [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isHovering ? 1.0 : 0.5
                                )
                        )
                )
                .shadow(
                    color: isHovering
                        ? Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(0.35)
                        : Color.clear,
                    radius: isHovering ? 10 : 0,
                    y: 0
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.94 : (isHovering ? 1.04 : 1.0))
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
        .pressEvents(onPress: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = true }
        }, onRelease: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
        })
    }
}

/// The bright "Go to terminal" CTA — lime base with animated glow.
private struct PrimaryCTAButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Base gradient fill
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0xE8/255, green: 0xFF/255, blue: 0x3E/255),
                                Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255),
                                Color(red: 0xA4/255, green: 0xE6/255, blue: 0x2E/255)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                // Shimmer overlay while hovering
                if isHovering {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: UnitPoint(x: shimmerPhase - 0.3, y: 0),
                                endPoint: UnitPoint(x: shimmerPhase + 0.3, y: 1)
                            )
                        )
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                }
                Text(label)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 7)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .shadow(
            color: Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(isHovering ? 0.55 : 0.25),
            radius: isHovering ? 14 : 6,
            y: isHovering ? 4 : 2
        )
        .scaleEffect(isPressed ? 0.96 : (isHovering ? 1.05 : 1.0))
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                isHovering = hovering
            }
            if hovering {
                // Start shimmer loop
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.3
                }
            } else {
                shimmerPhase = 0
            }
        }
        .pressEvents(onPress: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = true }
        }, onRelease: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
        })
    }
}

/// Close × with hover brightening.
private struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(isHovering ? 0.95 : 0.55))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovering ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(L10n.qrClose)
    }
}

// MARK: - Press-event helper

/// SwiftUI `Button` doesn't expose "mouse down / mouse up" separately,
/// so we piggyback `DragGesture(minimumDistance: 0)` to detect press state
/// for the scale-down animation on tap.
private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}
