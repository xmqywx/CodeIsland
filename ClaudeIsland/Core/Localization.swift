//
//  Localization.swift
//  ClaudeIsland
//
//  Simple i18n helper: auto-detects system locale and provides
//  English/Chinese translations for all user-visible strings.
//

import Foundation

enum L10n {
    /// Language options: "auto" (system), "en", "zh"
    static var appLanguage: String {
        get { UserDefaults.standard.string(forKey: "appLanguage") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "appLanguage") }
    }

    static var isChinese: Bool {
        switch appLanguage {
        case "zh": return true
        case "en": return false
        default: // "auto"
            let lang = Locale.current.language.languageCode?.identifier ?? "en"
            return lang == "zh"
        }
    }

    static var currentLanguageLabel: String {
        switch appLanguage {
        case "zh": return "中文"
        case "en": return "English"
        default: return isChinese ? "自动" : "Auto"
        }
    }

    static func tr(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }

    // Settings
    static var language: String { tr("Language", "语言") }

    // MARK: - Session list

    static var sessions: String { tr("sessions", "个会话") }
    static var noSessions: String { tr("No sessions", "暂无会话") }
    static var runClaude: String { tr("Run claude in terminal", "在终端中运行 claude") }
    static var needsInput: String { tr("Needs your input", "需要你的输入") }
    static var you: String { tr("You:", "你：") }
    static var working: String { tr("Working...", "工作中...") }
    static var needsApproval: String { tr("Needs approval", "需要审批") }
    static var doneJump: String { tr("Done \u{2014} click to jump", "完成 \u{2014} 点击跳转") }
    static var compacting: String { tr("Compacting...", "压缩中...") }
    static var idle: String { tr("Idle", "空闲") }
    static var archived: String { tr("archived", "已归档") }
    static var active: String { tr("active", "活跃") }

    static func showAllSessions(_ count: Int) -> String { tr("Show all \(count) sessions", "显示全部 \(count) 个会话") }

    // MARK: - Menu

    static var back: String { tr("Back", "返回") }
    static var groupByProject: String { tr("Group by Project", "按项目分组") }
    static var pixelCatMode: String { tr("Pixel Cat Mode", "像素猫模式") }
    static var launchAtLogin: String { tr("Launch at Login", "开机启动") }
    static var hooks: String { tr("Hooks", "钩子") }
    static var accessibility: String { tr("Accessibility", "辅助功能") }
    static var version: String { tr("Version", "版本") }
    static var quit: String { tr("Quit", "退出") }
    static var on: String { tr("On", "开") }
    static var off: String { tr("Off", "关") }
    static var enable: String { tr("Enable", "启用") }
    static var enabled: String { tr("On", "已开启") }

    // MARK: - Notch collapsed status

    static var approve: String { tr("approve", "审批") }
    static var done: String { tr("done", "完成") }

    // MARK: - Approval

    static var allow: String { tr("Allow", "允许") }
    static var deny: String { tr("Deny", "拒绝") }
    static var permissionRequest: String { tr("Permission Request", "权限请求") }
    static var goToTerminal: String { tr("Go to Terminal", "前往终端") }
    static var terminal: String { tr("Terminal", "终端") }

    // MARK: - Session state

    static var ended: String { tr("Ended", "已结束") }
    static var clearEnded: String { tr("Clear Ended", "清除已结束") }

    // MARK: - Sound settings

    static var soundSettings: String { tr("Sound Settings", "声音设置") }
    static var globalMute: String { tr("Global Mute", "全部静音") }
    static var eventSounds: String { tr("Event Sounds", "事件声音") }
    static var notificationSound: String { tr("Notification Sound", "通知声音") }
    static var screen: String { tr("Screen", "屏幕") }
    static var automatic: String { tr("Automatic", "自动") }
    static var auto_: String { tr("Auto", "自动") }
    static var builtIn: String { tr("Built-in", "内置") }
    static var main_: String { tr("Main", "主屏幕") }
    static var builtInOrMain: String { tr("Built-in or Main", "内置或主屏幕") }

    // MARK: - Sound events

    static var sessionStart: String { tr("Session Start", "会话开始") }
    static var processingBegins: String { tr("Processing Begins", "开始处理") }
    static var approvalGranted: String { tr("Approval Granted", "已批准") }
    static var approvalDenied: String { tr("Approval Denied", "已拒绝") }
    static var sessionComplete: String { tr("Session Complete", "会话完成") }
    static var error: String { tr("Error", "错误") }
    static var contextCompacting: String { tr("Context Compacting", "上下文压缩") }
    static var rateLimitWarning: String { tr("Usage Warning (90%)", "用量警告 (90%)") }

    // MARK: - Chat view

    static var loadingMessages: String { tr("Loading messages...", "加载消息中...") }
    static var noMessages: String { tr("No messages", "暂无消息") }
    static var processing: String { tr("Processing", "处理中") }
    static var claudeNeedsInput: String { tr("Claude Code needs your input", "Claude Code 需要你的输入") }
    static var interrupted: String { tr("Interrupted", "已中断") }
    static func newMessages(_ count: Int) -> String { tr("\(count) new messages", "\(count) 条新消息") }
    static func runningAgent(_ desc: String?) -> String {
        let d = desc ?? tr("Running agent...", "运行代理中...")
        return d
    }
    static var runningAgentDefault: String { tr("Running agent...", "运行代理中...") }
    static func waiting(_ desc: String) -> String { tr("Waiting: \(desc)", "等待中: \(desc)") }
    static func hiddenToolCalls(_ count: Int) -> String { tr("\(count) more tool calls", "还有 \(count) 个工具调用") }
    static func subagentTools(_ count: Int) -> String { tr("Subagent used \(count) tools:", "子代理使用了 \(count) 个工具：") }

    // MARK: - Tool result views

    static var userModified: String { tr("(user modified)", "(用户已修改)") }
    static var created: String { tr("Created", "已创建") }
    static var written: String { tr("Written", "已写入") }
    static func backgroundTask(_ id: String) -> String { tr("Background task: \(id)", "后台任务: \(id)") }
    static var stderrLabel: String { tr("Stderr:", "错误输出：") }
    static var noContent: String { tr("(no content)", "(无内容)") }
    static var noMatches: String { tr("No matches", "未找到匹配") }
    static func filesMatched(_ count: Int) -> String { tr("\(count) files matched", "\(count) 个文件有匹配") }
    static var noFiles: String { tr("No files found", "未找到文件") }
    static var moreTruncated: String { tr("... more (truncated)", "... 更多（已截断）") }
    static func tools(_ count: Int) -> String { tr("\(count) tools", "\(count) 个工具") }
    static var noResults: String { tr("No results found", "未找到结果") }
    static func moreResults(_ count: Int) -> String { tr("... \(count) more results", "... 还有 \(count) 个结果") }
    static func status(_ s: String) -> String { tr("Status: \(s)", "状态: \(s)") }
    static func exitCode(_ code: Int) -> String { tr("Exit code: \(code)", "退出码: \(code)") }
    static func shellKilled(_ id: String) -> String { tr("Shell \(id) killed", "Shell \(id) 已终止") }
    static var completed: String { tr("Completed", "已完成") }
    static func moreLines(_ count: Int) -> String { tr("... (\(count) more lines)", "... (\(count) 更多行)") }
    static func moreFiles(_ count: Int) -> String { tr("... \(count) more files", "... 还有 \(count) 个文件") }
    static func moreHunks(_ count: Int) -> String { tr("... \(count) more hunks", "... 还有 \(count) 个代码块") }

    // MARK: - Sound event display names (for SoundManager)

    static func soundEventName(_ event: String) -> String {
        switch event {
        case "session_start": return sessionStart
        case "processing_begins": return processingBegins
        case "needs_approval": return needsApproval
        case "approval_granted": return approvalGranted
        case "approval_denied": return approvalDenied
        case "session_complete": return sessionComplete
        case "error": return error
        case "compacting": return contextCompacting
        case "rate_limit_warning": return rateLimitWarning
        default: return event
        }
    }

    // MARK: - Sound settings preview tooltip

    static func previewSound(_ name: String) -> String { tr("Preview \(name) sound", "预览 \(name) 声音") }

    // MARK: - Notch view status text

    static func approveWhat(_ tool: String) -> String { tr("\(L10n.approve) \(tool)?", "\(L10n.approve) \(tool)?") }

    // MARK: - Smart interactions

    static var smartSuppression: String { tr("Smart Suppression", "智能抑制") }
    static var autoCollapseOnMouseLeave: String { tr("Auto-Collapse on Leave", "离开时自动收起") }
    static var compactCollapsed: String { tr("Compact Notch", "紧凑刘海") }
}
