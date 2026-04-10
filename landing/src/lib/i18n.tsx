import { createContext, useContext, useState, useEffect, type ReactNode } from "react"

export type Lang = "zh" | "en"

const translations = {
  // Navbar
  "nav.demo": { zh: "演示", en: "Demo" },
  "nav.features": { zh: "功能", en: "Features" },
  "nav.howItWorks": { zh: "快速上手", en: "Get Started" },
  "nav.github": { zh: "GitHub", en: "GitHub" },
  "nav.download": { zh: "下载", en: "Download" },

  // SideNav
  "sidenav.codelight": { zh: "Code Light", en: "Code Light" },
  "sidenav.opensource": { zh: "开源", en: "Open Source" },

  // Hero
  "hero.title1": { zh: "MacBook 灵动岛", en: "Dynamic Island" },
  "hero.title2": { zh: "变身 ", en: "for your " },
  "hero.title3": { zh: "AI 指挥台", en: "Claude Code" },
  "hero.subtitle1": { zh: "让你的刘海不再浪费。", en: "Stay in flow while your agents keep working." },
  "hero.subtitle2": { zh: "实时监控 Claude Code 会话、一键审批、秒回终端。", en: "Monitor, approve, and jump back — right from the notch." },
  "hero.subtitle3": { zh: "Mac 灵动岛 + iPhone App — Apple 全生态。", en: "Mac Dynamic Island + iPhone App — full Apple ecosystem." },
  "hero.download": { zh: "Mac 免费下载", en: "Download for Mac" },
  "hero.star": { zh: "GitHub Star", en: "Star on GitHub" },

  // NotchDemo
  "demo.sectionTag": { zh: "交互演示", en: "INTERACTIVE DEMO" },
  "demo.sectionTitle": { zh: "试试看", en: "See it in action" },
  "demo.monitor": { zh: "实时监控", en: "Monitor" },
  "demo.approve": { zh: "审批权限", en: "Approve" },
  "demo.ask": { zh: "互动问答", en: "Ask" },
  "demo.jump": { zh: "跳转终端", en: "Jump" },
  "demo.monitorDesc": { zh: "所有 Claude Code 会话状态一览，工具调用、运行时长实时更新。", en: "See all Claude Code sessions at a glance — tool calls, duration, status updated in real time." },
  "demo.approveDesc": { zh: "Claude 需要权限？代码改了啥一目了然，直接在刘海里审批。", en: "Claude needs permission? See the code diff and approve or deny right from the notch." },
  "demo.askDesc": { zh: "Claude 有问题要问你？直接在刘海查看并跳到终端回复。", en: "Claude has a question? View it in the notch and jump to terminal to respond." },
  "demo.jumpDesc": { zh: "一键跳到对应的终端标签页，支持十几种终端应用。", en: "Jump to the exact terminal tab with one click. Supports 10+ terminal apps." },

  // Features
  "features.tag": { zh: "功能特性", en: "FEATURES" },
  "features.title": { zh: "全部塞进刘海里", en: "Everything in the notch" },
  "features.monitor.title": { zh: "灵动岛实时监控", en: "Real-time Monitoring" },
  "features.monitor.desc": { zh: "折叠态左右翼显示状态圆点、Buddy 图标、项目名。青色=进行中，绿色=完成，红色=出错。", en: "Collapsed notch wings show status dots, buddy icon, and project name. Cyan=working, green=done, red=error." },
  "features.approval.title": { zh: "刘海内审批", en: "Notch Approval" },
  "features.approval.desc": { zh: "Claude 要权限？代码改了啥一目了然，diff 高亮预览，一键批准或拒绝，不用切窗口。", en: "Claude needs permission? See the diff with green/red highlighting. Approve or deny without switching windows." },
  "features.smart.title": { zh: "智能摘要 + 用量统计", en: "Smart Summary + Usage Stats" },
  "features.smart.desc": { zh: "不用展开就能看到 Claude 在聊什么。实时显示 API 用量，帮你盯着额度别超了。", en: "See what Claude is discussing without expanding. Real-time API usage tracking to avoid exceeding limits." },
  "features.jump.title": { zh: "一键跳转终端", en: "Terminal Jump" },
  "features.jump.desc": { zh: "自动识别 Ghostty、iTerm2、Warp、Terminal 等十几种终端，精确跳到对应标签页。", en: "Auto-detects Ghostty, iTerm2, Warp, Terminal and 10+ more. Jumps to the exact tab." },
  "features.buddy.title": { zh: "Buddy 宠物 + 像素猫", en: "Buddy Pet + Pixel Cat" },
  "features.buddy.desc": { zh: "你的 Claude Buddy 住在刘海里，18 种物种 ASCII 动画。还有手绘像素猫 6 种表情状态。", en: "Your Claude Buddy lives in the notch. 18 species with ASCII animation. Plus a hand-drawn pixel cat with 6 expression states." },
  "features.sound.title": { zh: "8-bit 音效 + 无人值守告警", en: "8-bit Sounds + Unattended Alerts" },
  "features.sound.desc": { zh: "每个事件专属芯片音提醒。超过 30 秒未处理变橙色，60 秒变红色，离开工位也放心。", en: "Chiptune alerts for every event. 30s unattended turns orange, 60s turns red — safe to step away." },
  "features.zero.title": { zh: "零配置即用", en: "Zero Config" },
  "features.zero.desc": { zh: "启动一次，自动安装 hooks。不用改配置文件，不用装额外依赖。", en: "One launch, done. Auto-installs hooks. No config files to edit, no extra dependencies." },
  "features.i18n.title": { zh: "中英双语", en: "Bilingual" },
  "features.i18n.desc": { zh: "跟随系统语言自动切换，也可以在设置里手动选择。", en: "Follows system language automatically. Manual override available in settings." },

  // HowItWorks
  "how.tag": { zh: "快速上手", en: "GET STARTED" },
  "how.title": { zh: "两步开始", en: "Two steps to flow" },
  "how.install.cmd": { zh: "brew install MioMioOS/tap/mioisland", en: "brew install MioMioOS/tap/mioisland" },
  "how.install.title": { zh: "安装", en: "Install" },
  "how.install.or": { zh: "或", en: "or" },
  "how.install.dmg": { zh: "下载 DMG 安装包", en: "Download DMG" },
  "how.install.copied": { zh: "已复制!", en: "Copied!" },
  "how.flow.auto": { zh: "启动后自动配置 Claude Code hooks，无需手动编辑配置文件。", en: "Auto-configures Claude Code hooks on launch. No config files to edit." },
  "how.flow.result": { zh: "监控、审批、跳回终端——全在刘海里完成，不打断心流。", en: "Monitor, approve, jump back — all from the notch. Stay in flow." },

  // OpenSource
  "os.title": { zh: "开源免费", en: "Open Source & Free" },
  "os.desc": { zh: "CodeIsland 基于 CC BY-NC 4.0 协议开源。个人免费使用，代码透明可审查。和社区一起构建，为社区服务。", en: "CodeIsland is open source under CC BY-NC 4.0. Free for personal use. Built with the community, for the community." },
  "os.contributors": { zh: "贡献者", en: "Contributors" },
  "os.fork": { zh: "Fork & 参与贡献", en: "Fork & Contribute" },
  "os.docs": { zh: "查看文档", en: "Read the Docs" },

  // NotchDemo internal
  "demo.activeSessions": { zh: "2 个活跃会话", en: "2 active sessions" },
  "demo.permissionRequest": { zh: "权限请求", en: "Permission Request" },
  "demo.allow": { zh: "允许", en: "Allow" },
  "demo.deny": { zh: "拒绝", en: "Deny" },
  "demo.claudeAsking": { zh: "Claude 在问你", en: "Claude is asking" },
  "demo.claudeQuestion": { zh: "要不要同时更新 refresh token 逻辑来匹配新的认证方式？", en: "Should I also update the refresh token logic to match the new auth pattern?" },
  "demo.yes": { zh: "好的", en: "Yes" },
  "demo.no": { zh: "不用", en: "No" },
  "demo.jumpToTerminal": { zh: "跳转到终端", en: "Jumping to terminal" },
  "demo.active": { zh: "活跃", en: "active" },
  "demo.monitorTitle": { zh: "实时监控所有会话", en: "Monitor all sessions" },
  "demo.monitorSub": { zh: "一眼看到所有 Agent 的状态——工具调用、运行时长实时更新。", en: "See every running agent at a glance — status, tool calls, duration." },
  "demo.approveTitle": { zh: "不切窗口直接审批", en: "Approve without switching" },
  "demo.approveSub": { zh: "代码 diff 预览，允许或拒绝——全在刘海里完成。", en: "Review code diffs and allow or deny — right from the notch." },
  "demo.askTitle": { zh: "在刘海里回答问题", en: "Answer from the notch" },
  "demo.askSub": { zh: "Agent 需要你的输入？选一个选项继续推进。", en: "When an agent needs input, pick an option and keep moving." },
  "demo.jumpTitle": { zh: "跳转到对应终端", en: "Jump to the right terminal" },
  "demo.jumpSub": { zh: "一键跳到对应的终端标签页和分屏。", en: "One click to the exact tab and split pane in cmux or iTerm2." },

  // Community
  "community.join": { zh: "加入社区", en: "Join Community" },
  "community.title": { zh: "加入 CodeIsland 用户群", en: "Join CodeIsland Community" },
  "community.subtitle": { zh: "扫码加入微信群，第一时间获取更新、提 bug、交流使用技巧", en: "Scan to join our WeChat group — get updates, report bugs, share tips" },
  "community.tabGroup": { zh: "微信群", en: "Group Chat" },
  "community.tabPersonal": { zh: "开发者微信", en: "Developer WeChat" },
  "community.groupNote": { zh: "使用微信扫一扫加入群聊", en: "Use WeChat to scan and join the group" },
  "community.groupExpiry": { zh: "群二维码每 7 天自动更新", en: "Group QR code refreshes every 7 days" },
  "community.personalNote": { zh: "如群二维码失效，扫码添加开发者", en: "If group QR is expired, add the developer" },
  "community.wechatId": { zh: "微信号：", en: "WeChat ID: " },
  "community.close": { zh: "关闭", en: "Close" },

  // Code Light
  "codelight.tag": { zh: "iPhone 伴侣", en: "IPHONE COMPANION" },
  "codelight.title": { zh: "Code Light", en: "Code Light" },
  "codelight.subtitle": { zh: "Claude 在思考，你在吃午饭。你会知道。", en: "Claude is thinking. You're at lunch. You'll know." },
  "codelight.desc": { zh: "Mac 刘海里那只像素猫，现在也住进了你 iPhone 的灵动岛。当前会话状态、最近的用户提问、Claude 的回复预览 —— 直接显示在锁屏上。", en: "The pixel cat from your Mac's notch now lives in your iPhone's Dynamic Island. Session status, latest question, Claude's reply — right on your lock screen." },
  "codelight.macs": { zh: "一台 iPhone N 台 Mac", en: "One iPhone, N Macs" },
  "codelight.sessions": { zh: "会话管理", en: "Session Tabs" },
  "codelight.commands": { zh: "/斜杠命令", en: "/Slash Commands" },
  "codelight.chat": { zh: "实时聊天", en: "Live Chat" },
  "codelight.settings": { zh: "自托管 · 私密", en: "Self-hosted" },
  "codelight.f1.title": { zh: "灵动岛实时状态", en: "Live Dynamic Island" },
  "codelight.f1.desc": { zh: "iPhone 灵动岛实时显示 Claude 工作状态", en: "Real Dynamic Island showing Claude's live status" },
  "codelight.f2.title": { zh: "远程审批", en: "Remote Approval" },
  "codelight.f2.desc": { zh: "手机上直接 approve / deny 权限请求", en: "Approve or deny permission requests from your phone" },
  "codelight.f3.title": { zh: "斜杠命令", en: "Slash Commands" },
  "codelight.f3.desc": { zh: "/model /cost /usage 远程执行带回显", en: "/model /cost /usage — remote execution with round-trip" },
  "codelight.f4.title": { zh: "远程启动", en: "Remote Launch" },
  "codelight.f4.desc": { zh: "一键 spawn cmux workspace 新会话", en: "Spawn a new cmux workspace with one tap" },
  "codelight.f5.title": { zh: "图片附件", en: "Image Attach" },
  "codelight.f5.desc": { zh: "拍照直接发给 Claude 分析", en: "Take a photo and send it to Claude" },
  "codelight.f6.title": { zh: "永久配对码", en: "Permanent Pairing" },
  "codelight.f6.desc": { zh: "6 位配对码重启不变，多设备同时配对", en: "6-char code survives restarts, multi-device pairing" },
  "codelight.f7.title": { zh: "端到端加密", en: "E2E Encrypted" },
  "codelight.f7.desc": { zh: "可自托管、零知识中继，数据只属于你", en: "Self-hostable, zero-knowledge relay — your data stays yours" },
  "codelight.status": { zh: "App Store 已上架（中国大陆地区暂不可用）", en: "Available on the App Store (not available in mainland China)" },
  "codelight.star": { zh: "GitHub Star · 获取最新消息", en: "GitHub Star · Stay Updated" },
  "codelight.appstore": { zh: "App Store 下载", en: "Download on App Store" },
  "codelight.regionNote": { zh: "因政策原因，中国大陆 App Store 暂无法上架。可切换至其他地区账号下载。", en: "Due to regional restrictions, Code Light is not available on the mainland China App Store. Switch to another region to download." },

  // Footer
  "footer.madeWith": { zh: "Made with", en: "Made with" },
} as const

type TranslationKey = keyof typeof translations

interface I18nContextType {
  lang: Lang
  setLang: (lang: Lang) => void
  t: (key: TranslationKey) => string
}

const I18nContext = createContext<I18nContextType>({
  lang: "zh",
  setLang: () => {},
  t: (key) => key,
})

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLang] = useState<Lang>(() => {
    const saved = localStorage.getItem("codeisland-lang")
    if (saved === "en" || saved === "zh") return saved
    return navigator.language.startsWith("zh") ? "zh" : "en"
  })

  useEffect(() => {
    localStorage.setItem("codeisland-lang", lang)
  }, [lang])

  const t = (key: TranslationKey) => translations[key]?.[lang] ?? key

  return (
    <I18nContext.Provider value={{ lang, setLang, t }}>
      {children}
    </I18nContext.Provider>
  )
}

export function useI18n() {
  return useContext(I18nContext)
}
