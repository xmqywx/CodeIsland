//
//  AskUserQuestionView.swift
//  ClaudeIsland
//
//  Interactive UI for answering AskUserQuestion prompts from Claude Code
//

import SwiftUI

struct AskUserQuestionView: View {
    let session: SessionState
    let context: QuestionContext
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor

    @State private var selections: [Int: Set<String>] = [:]
    @State private var otherTexts: [Int: String] = [:]
    @State private var showOther: [Int: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            questionsList
            submitBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(session.projectName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button(action: jumpToTerminal) {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                    Text("Terminal")
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Questions List

    private var questionsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(context.questions.enumerated()), id: \.offset) { index, question in
                    questionBlock(index: index, question: question)
                }
            }
        }
    }

    @ViewBuilder
    private func questionBlock(index: Int, question: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            ChipFlowLayout(spacing: 6) {
                ForEach(question.options, id: \.label) { option in
                    chipButton(
                        label: option.label,
                        isSelected: selections[index]?.contains(option.label) == true,
                        action: { toggleOption(index: index, label: option.label, multiSelect: question.multiSelect) }
                    )
                }
                chipButton(
                    label: "Other",
                    isSelected: showOther[index] == true,
                    action: {
                        showOther[index] = !(showOther[index] ?? false)
                        if showOther[index] == true {
                            selections[index] = []
                        }
                    }
                )
            }

            if let selected = selections[index]?.first,
               let desc = question.options.first(where: { $0.label == selected })?.description {
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.leading, 2)
            }

            if showOther[index] == true {
                TextField("Type your answer...", text: Binding(
                    get: { otherTexts[index] ?? "" },
                    set: { otherTexts[index] = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? TerminalColors.amber.opacity(0.3) : Color.white.opacity(0.08))
                .foregroundColor(isSelected ? TerminalColors.amber : .white.opacity(0.7))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? TerminalColors.amber.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit Bar

    private var submitBar: some View {
        HStack {
            Spacer()
            Button(action: submit) {
                Text("Submit")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(canSubmit ? TerminalColors.amber : Color.white.opacity(0.1))
                    .foregroundColor(canSubmit ? .black : .white.opacity(0.3))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        for (index, _) in context.questions.enumerated() {
            let hasSelection = !(selections[index] ?? []).isEmpty
            let hasOther = !(otherTexts[index] ?? "").isEmpty && showOther[index] == true
            if !hasSelection && !hasOther { return false }
        }
        return true
    }

    private func toggleOption(index: Int, label: String, multiSelect: Bool) {
        showOther[index] = false
        otherTexts[index] = nil

        if multiSelect {
            var current = selections[index] ?? []
            if current.contains(label) {
                current.remove(label)
            } else {
                current.insert(label)
            }
            selections[index] = current
        } else {
            selections[index] = [label]
        }
    }

    private func submit() {
        var answers: [String: String] = [:]
        for (index, question) in context.questions.enumerated() {
            if showOther[index] == true, let text = otherTexts[index], !text.isEmpty {
                answers[question.question] = text
            } else if let selected = selections[index] {
                answers[question.question] = selected.joined(separator: ", ")
            }
        }
        sessionMonitor.answerQuestion(sessionId: session.sessionId, answers: answers)
    }

    private func jumpToTerminal() {
        sessionMonitor.skipQuestion(sessionId: session.sessionId)
        Task {
            await TerminalJumper.shared.jump(to: session)
        }
    }
}
