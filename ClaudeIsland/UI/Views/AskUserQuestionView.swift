//
//  AskUserQuestionView.swift
//  ClaudeIsland
//
//  Interactive UI for answering AskUserQuestion prompts from Claude Code.
//  Sends the selected option index to the terminal via AppleScript / cmux.
//

import SwiftUI

struct AskUserQuestionView: View {
    let session: SessionState
    let context: QuestionContext
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @State private var customText: String = ""
    @State private var hoveredIndex: Int? = nil
    @State private var isSending: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(session.projectName)
                    .notchFont(11, weight: .semibold)
                    .notchSecondaryForeground()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Questions + options
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(context.questions.enumerated()), id: \.offset) { _, question in
                        questionBlock(question: question)
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 4)

            // Custom text input
            customInputBar
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            // Jump to terminal — bottom, full width
            jumpToTerminalButton
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Question Block

    @ViewBuilder
    private func questionBlock(question: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.question)
                .notchFont(12, weight: .semibold)
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 2)

            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                optionRow(index: index + 1, option: option, optionCount: question.options.count)
            }
        }
    }

    private func optionRow(index: Int, option: QuestionOption, optionCount: Int) -> some View {
        Button {
            guard !isSending else { return }
            isSending = true
            DebugLogger.log("AskUser", "Option \(index) tapped: \(option.label)")
            Task { await approveAndSendOption(index: index) }
        } label: {
            HStack(spacing: 8) {
                Text("\(index)")
                    .notchFont(10, weight: .bold)
                    .foregroundColor(TerminalColors.amber)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TerminalColors.amber.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .notchFont(11, weight: .medium)
                        .foregroundColor(.white.opacity(0.85))

                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .notchFont(9, weight: .regular)
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .notchFont(8)
                    .foregroundColor(.white.opacity(hoveredIndex == index ? 0.5 : 0.15))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredIndex == index ? TerminalColors.amber.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                hoveredIndex == index ? TerminalColors.amber.opacity(0.2) : Color.white.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredIndex = isHovered ? index : nil
        }
    }

    // MARK: - Custom Input

    private var customInputBar: some View {
        HStack(spacing: 6) {
            TextField("Type your answer...", text: $customText)
                .textFieldStyle(.plain)
                .notchFont(11)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .onSubmit { submitCustomText() }

            Button {
                submitCustomText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(
                        customText.isEmpty || isSending
                            ? Color.white.opacity(0.15)
                            : TerminalColors.amber
                    )
            }
            .buttonStyle(.plain)
            .disabled(customText.isEmpty || isSending)
        }
    }

    // MARK: - Jump to Terminal

    private var jumpToTerminalButton: some View {
        Button {
            Task { await TerminalJumper.shared.jump(to: session) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .notchFont(10)
                Text("Jump to Terminal")
                    .notchFont(10, weight: .medium)
            }
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Terminal Sending

    /// Release the hook with "ask" (so Claude Code shows its normal UI),
    /// wait for the UI to render, then send the option number to the terminal.
    private func approveAndSendOption(index: Int) async {
        // Step 1: Release the hook — respond with "ask" so Claude Code
        // shows its normal terminal UI instead of skipping it
        releaseHook()

        // Step 2: Wait for Claude Code to render the question UI in the terminal
        try? await Task.sleep(nanoseconds: 800_000_000) // 800ms

        // Step 3: Send the option number to the terminal
        await sendToTerminal("\(index)")
    }

    private func submitCustomText() {
        guard !customText.isEmpty, !isSending else { return }
        isSending = true
        let text = customText
        let optionCount = context.questions.first?.options.count ?? 0
        DebugLogger.log("AskUser", "Custom text: \(text)")
        Task {
            releaseHook()
            try? await Task.sleep(nanoseconds: 800_000_000)
            // Send "Other" option (last + 1), then the text
            await sendToTerminal("\(optionCount + 1)")
            try? await Task.sleep(nanoseconds: 500_000_000)
            await sendToTerminal(text)
        }
    }

    /// Respond to the PermissionRequest hook with "ask" — this makes the
    /// Python script exit without output, so Claude Code falls back to
    /// showing its normal interactive UI in the terminal.
    /// Using "allow" would skip the interactive UI entirely.
    private func releaseHook() {
        guard let permission = session.activePermission else { return }
        HookSocketServer.shared.respondToPermission(
            toolUseId: permission.toolUseId,
            decision: "ask"
        )
        DebugLogger.log("AskUser", "Released hook with 'ask' for \(permission.toolUseId.prefix(12))")
    }

    /// Send text to the terminal via cmux input text or AppleScript.
    private func sendToTerminal(_ text: String) async {
        let termApp = session.terminalApp?.lowercased() ?? ""

        // cmux: use native AppleScript input text
        if termApp.contains("cmux") || CmuxTreeParser.isAvailable {
            let sent = CmuxTreeParser.sendText("\(text)\r", toCwd: session.cwd)
            DebugLogger.log("AskUser", "Sent '\(text)' to cmux: \(sent)")
            if sent { return }
        }

        // iTerm2: write text
        if termApp.contains("iterm") {
            let script = """
            tell application "iTerm2"
                tell current session of current tab of current window
                    write text "\(text)"
                end tell
            end tell
            """
            if runAppleScript(script) {
                DebugLogger.log("AskUser", "Sent '\(text)' via iTerm2")
                return
            }
        }

        // Terminal.app
        if termApp.contains("terminal") && !termApp.contains("wez") {
            let script = """
            tell application "Terminal"
                do script "\(text)" in selected tab of front window
            end tell
            """
            if runAppleScript(script) {
                DebugLogger.log("AskUser", "Sent '\(text)' via Terminal.app")
                return
            }
        }

        // Fallback: jump to terminal
        DebugLogger.log("AskUser", "No supported terminal, jumping")
        await TerminalJumper.shared.jump(to: session)
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
