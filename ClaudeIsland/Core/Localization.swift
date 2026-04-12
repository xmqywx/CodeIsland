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

    // MARK: - Settings window
    static var systemSettings: String { tr("System Settings", "系统设置") }
    static var openSettings: String { tr("Settings", "设置") }
    static var tabGeneral: String { tr("General", "通用") }
    static var tabAppearance: String { tr("Appearance", "外观") }
    static var tabNotifications: String { tr("Notifications", "通知") }
    static var tabBehavior: String { tr("Behavior", "行为") }
    static var tabAdvanced: String { tr("Advanced", "高级") }
    static var tabAbout: String { tr("About", "关于") }
    static var tabPresets: String { tr("Launch Presets", "启动预设") }
    static var tabCodeLight: String { tr("CodeLight", "CodeLight") }
    static var pairedIPhones: String { tr("Paired iPhones", "已配对 iPhone") }
    static var pairNewPhone: String { tr("Pair New iPhone", "配对新 iPhone") }
    static var launchPresetsSection: String { tr("Launch Presets", "启动预设") }
    static var addPreset: String { tr("New Preset", "新建预设") }
    static var noPresets: String { tr("No presets yet — tap + to add one", "还没有预设，点击 + 添加") }
    static var presetsHint: String { tr("Paired iPhones can launch these as new cmux sessions", "配对的 iPhone 可以用这些预设启动新的 cmux 会话") }
    static var behavior: String { tr("Behavior", "行为") }
    static var system: String { tr("System", "系统") }
    static var appearanceSection: String { tr("Appearance", "外观") }
    static var usageWarningThreshold: String { tr("Usage Warning", "用量警告") }
    static var clearEndedSessions: String { tr("Clear Ended Sessions", "清除已结束会话") }
    static var feedback: String { tr("Feedback", "反馈") }
    static var starOnGitHub: String { tr("Star on GitHub", "GitHub 点星") }
    static var wechatLabel: String { tr("WeChat", "微信") }
    static var maintainedTagline: String { tr("Actively maintained · Your star keeps us going!", "持续更新中 · Star 是我们最大的动力！") }

    // MARK: - Daily report
    static var yesterdayLabel: String { tr("Yesterday", "昨天") }
    static var turnsLabel: String { tr("Turns", "轮次") }
    static var focusLabel: String { tr("Focus", "专注时长") }
    static var linesLabel: String { tr("Lines", "代码行") }
    static var sessionsLabel: String { tr("Sessions", "会话") }
    static var projectsLabel: String { tr("Projects", "项目") }
    static var peakBurstLabel: String { tr("Peak", "最长专注") }
    static var filesLabel: String { tr("Files", "文件") }
    static var peakHourLabel: String { tr("Peak hour", "活跃时段") }
    static var topToolsHeader: String { tr("Top tools", "常用工具") }
    static var topSkillsHeader: String { tr("Top skills", "常用 Skills") }
    static var topMCPHeader: String { tr("MCP plugins", "MCP 调用") }
    static var primaryProjectHeader: String { tr("Primary project", "主要项目") }

    // Day / Week view switcher
    static var dayViewTab: String { tr("Day", "日") }
    static var weekViewTab: String { tr("Week", "周") }

    // Week view extras
    static var weekHighlightsHeader: String { tr("Week highlights", "本周高光") }
    static var streakLabel: String { tr("Streak", "连续天数") }
    static func streakDays(_ days: Int) -> String {
        tr(days == 1 ? "\(days) day" : "\(days) days", "\(days) 天")
    }
    static var vsLastWeekHeader: String { tr("vs. last week", "对比上周") }
    static func peakDayHighlight(_ weekdayName: String, turns: Int) -> String {
        tr("Peak day: \(weekdayName) · \(turns) turns",
           "峰值日: \(weekdayName) · \(turns) 轮")
    }
    static func peakBurstHighlight(_ weekdayName: String, minutes: String) -> String {
        tr("Longest focus: \(minutes) on \(weekdayName)",
           "最长专注: \(minutes)（\(weekdayName)）")
    }
    static func primaryProjectHighlight(_ project: String) -> String {
        tr("Main project: \(project)", "主要项目: \(project)")
    }
    static var noActivityThisWeek: String { tr("No activity this week yet.", "本周还没有活动") }
    static var sparklineLabel: String { tr("Daily focus", "每日专注") }
    /// Prefix for the sparkline normalization ceiling, e.g. "max 4h13m".
    static var sparklineMaxPrefix: String { tr("max", "最高") }

    // Hero card expand / collapse
    static var expandLabel: String { tr("Show more", "查看更多") }
    static var collapseLabel: String { tr("Show less", "收起") }

    // First-launch loading state
    static var analyzingTitle: String { tr("Crunching your numbers…", "正在统计你的数据…") }
    static var analyzingSubtitle: String {
        tr("Scanning the last 14 days of Claude activity. First launch takes a moment.",
           "扫描过去 14 天的 Claude 活动，首次启动稍等一下。")
    }

    static func dailyTaglineWeek(_ focus: String) -> String {
        tr("You worked with Claude for \(focus) this week — here's the recap.",
           "本周你和 Claude 协作了 \(focus) — 一周回顾")
    }
    /// Tagline under the header, filled with the focus duration.
    static func dailyTagline(_ focus: String) -> String {
        tr("You worked with Claude for \(focus) — here's the recap.",
           "你和 Claude 协作了 \(focus) — 昨日回顾")
    }
    static func focusHelperDesc(_ sessions: Int) -> String {
        tr("Active time across \(sessions) sessions (idle gaps excluded)",
           "跨 \(sessions) 个会话的活跃时长（不含空闲）")
    }

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

    // MARK: - Notch customization
    //
    // Deviation from spec: the spec (Section 4.5) lists these keys
    // for `Localizable.xcstrings`, but this project currently uses
    // the hand-rolled `L10n` helper (en + zh-Hans as Swift string
    // pairs). Strings added here follow the established pattern
    // and match the voice of surrounding entries. A future migration
    // to `.xcstrings` can pick them up mechanically from this file.

    static var notchSectionHeader: String { tr("Notch", "灵动岛") }
    static var notchTheme: String { tr("Theme", "主题") }
    static var notchThemeClassic: String { tr("Classic", "经典") }
    static var notchThemePaper: String { tr("Paper", "纸张") }
    static var notchThemeNeonLime: String { tr("Neon Lime", "霓虹青柠") }
    static var notchThemeCyber: String { tr("Cyber", "赛博") }
    static var notchThemeMint: String { tr("Mint", "薄荷") }
    static var notchThemeSunset: String { tr("Sunset", "日落") }
    static var notchThemeRosegold: String { tr("Rosé Gold", "玫瑰金") }
    static var notchThemeOcean: String { tr("Ocean", "深海") }
    static var notchThemeAurora: String { tr("Aurora", "极光") }
    static var notchThemeMocha: String { tr("Mocha", "摩卡") }
    static var notchThemeLavender: String { tr("Lavender", "薰衣草") }
    static var notchThemeCherry: String { tr("Cherry", "樱桃") }
    static var notchHoverSpeed: String { tr("Hover Speed", "展开速度") }
    static var notchHoverInstant: String { tr("Fast", "即时") }
    static var notchHoverNormal: String { tr("1s", "1秒") }
    static var notchHoverSlow: String { tr("2s", "2秒") }
    static var notchFontSize: String { tr("Font Size", "字号") }
    static var notchFontSmall: String { tr("S", "小") }
    static var notchFontDefault: String { tr("M", "中") }
    static var notchFontLarge: String { tr("L", "大") }
    static var notchFontXLarge: String { tr("XL", "特大") }
    static var notchFontSmallFull: String { tr("Small", "小") }
    static var notchFontDefaultFull: String { tr("Default", "默认") }
    static var notchFontLargeFull: String { tr("Large", "大") }
    static var notchFontXLargeFull: String { tr("Extra Large", "特大") }
    static var notchShowBuddy: String { tr("Show Buddy", "显示宠物") }
    static var notchShowUsageBar: String { tr("Show Usage Bar", "显示用量条") }
    static var notchHardwareMode: String { tr("Hardware Notch", "硬件刘海") }
    static var notchHardwareAuto: String { tr("Auto", "自动") }
    static var notchHardwareForceVirtual: String { tr("Force Virtual", "强制虚拟") }
    static var notchCustomizeButton: String { tr("Customize Size & Position…", "自定义尺寸与位置…") }
    static var notchEditSave: String { tr("Save", "保存") }
    static var notchEditCancel: String { tr("Cancel", "取消") }
    static var notchEditNotchPreset: String { tr("Notch Preset", "贴合刘海") }
    static var notchEditDragMode: String { tr("Drag Mode", "拖动模式") }
    static var notchEditReset: String { tr("Reset", "复位") }
    static var notchEditPresetDisabledTooltip: String { tr("Your device doesn't have a hardware notch", "你的设备没有硬件刘海") }
    static func notchThemeName(_ id: NotchThemeID) -> String {
        switch id {
        case .classic:  return notchThemeClassic
        case .paper:    return notchThemePaper
        case .neonLime: return notchThemeNeonLime
        case .cyber:    return notchThemeCyber
        case .mint:     return notchThemeMint
        case .sunset:   return notchThemeSunset
        case .rosegold: return notchThemeRosegold
        case .ocean:    return notchThemeOcean
        case .aurora:   return notchThemeAurora
        case .mocha:    return notchThemeMocha
        case .lavender: return notchThemeLavender
        case .cherry:   return notchThemeCherry
        }
    }
}
