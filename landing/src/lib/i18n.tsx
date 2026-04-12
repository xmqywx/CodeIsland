import { createContext, useContext, useState, useEffect, type ReactNode } from "react"

export type Lang = "zh" | "en"

const translations = {
  // Navbar
  "nav.demo": { zh: "演示", en: "Demo" },
  "nav.features": { zh: "功能", en: "Features" },
  "nav.codelight": { zh: "Code Light", en: "Code Light" },
  "nav.howItWorks": { zh: "快速上手", en: "Get Started" },
  "nav.pricing": { zh: "定价", en: "Pricing" },
  "nav.faq": { zh: "FAQ", en: "FAQ" },
  "nav.github": { zh: "GitHub", en: "GitHub" },
  "nav.download": { zh: "下载", en: "Download" },

  // SideNav
  "sidenav.codelight": { zh: "Code Light", en: "Code Light" },
  "sidenav.opensource": { zh: "开源", en: "Open Source" },
  "sidenav.pricing": { zh: "定价", en: "Pricing" },
  "sidenav.plugins": { zh: "插件", en: "Plugins" },
  "sidenav.faq": { zh: "FAQ", en: "FAQ" },

  // Hero
  "hero.title1": { zh: "MioIsland", en: "MioIsland" },
  "hero.title2": { zh: "MacBook 灵动岛", en: "Dynamic Island" },
  "hero.title3": { zh: "AI 编程指挥台", en: "for AI Coding" },
  "hero.subtitle1": { zh: "把刘海变成 AI 编程的控制中心。", en: "Turn your MacBook notch into an AI coding control center." },
  "hero.subtitle2": { zh: "实时监控 Claude Code 会话、一键审批、秒回终端。", en: "Monitor Claude Code sessions, approve in one click, jump back instantly." },
  "hero.subtitle3": { zh: "Mac 灵动岛 + iPhone 伴侣 App — Apple 全生态联动。", en: "Mac Dynamic Island + iPhone companion — full Apple ecosystem." },
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

  // Features (MioIsland)
  "features.tag": { zh: "MAC 端功能", en: "MAC FEATURES" },
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

  // Code Light (iPhone Companion)
  "codelight.tag": { zh: "iPhone 伴侣", en: "IPHONE COMPANION" },
  "codelight.title": { zh: "Code Light", en: "Code Light" },
  "codelight.subtitle": { zh: "用 iPhone 遥控你的 Claude Code", en: "Control Claude Code from your iPhone" },
  "codelight.desc": { zh: "Mac 刘海里那只像素猫，现在也住进了你 iPhone 的灵动岛。会话状态实时同步、远程审批、斜杠命令 —— 离开工位也能掌控全局。", en: "The pixel cat from your Mac's notch now lives in your iPhone's Dynamic Island. Real-time session sync, remote approval, slash commands — stay in control even away from your desk." },
  "codelight.beta": { zh: "内测免费体验", en: "Free Beta Access" },
  "codelight.betaDesc": { zh: "Code Light 目前处于公测阶段，所有功能完全免费。正式版将转为付费，欢迎提前体验并反馈意见，你的建议会直接影响产品方向。", en: "Code Light is currently in public beta — all features are completely free. It will become a paid app after beta. Try it now and share your feedback — your input directly shapes the product." },
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
  "codelight.f5.title": { zh: "图片 + 截屏", en: "Images + Screenshot" },
  "codelight.f5.desc": { zh: "拍照发给 Claude 分析，或远程请求 Mac 截屏", en: "Send photos to Claude, or remotely request Mac screenshots" },
  "codelight.f6.title": { zh: "永久配对码", en: "Permanent Pairing" },
  "codelight.f6.desc": { zh: "6 位配对码重启不变，多设备同时配对", en: "6-char code survives restarts, multi-device pairing" },
  "codelight.f7.title": { zh: "端到端加密", en: "E2E Encrypted" },
  "codelight.f7.desc": { zh: "可自托管、零知识中继，数据只属于你", en: "Self-hostable, zero-knowledge relay — your data stays yours" },
  "codelight.status": { zh: "公测中 · App Store 已上架（中国大陆暂不可用）", en: "Beta · Available on the App Store (not in mainland China)" },
  "codelight.star": { zh: "GitHub Star · 获取最新消息", en: "GitHub Star · Stay Updated" },
  "codelight.appstore": { zh: "App Store 下载", en: "Download on App Store" },
  "codelight.feedbackCta": { zh: "内测期间欢迎提 Issue 或加群反馈，一起让 CodeLight 更好用", en: "During beta, open Issues or join our community to help make CodeLight better" },
  "codelight.regionNote": { zh: "因政策原因，中国大陆 App Store 暂无法上架。可切换至其他地区账号下载。", en: "Due to regional restrictions, Code Light is not available on the mainland China App Store. Switch to another region to download." },
  "codelight.showcase.lockscreen": { zh: "锁屏灵动岛实时显示", en: "Lock Screen Dynamic Island" },
  "codelight.showcase.chat": { zh: "实时查看 Claude 工作进展", en: "Watch Claude work in real time" },
  "codelight.showcase.workflow": { zh: "远程操控 Claude 编写代码", en: "Remotely control Claude coding" },
  "codelight.showcase.appstore": { zh: "App Store 上架 · 扫码配对", en: "On the App Store · Scan to pair" },

  // How It Works (3-step)
  "how.tag": { zh: "快速上手", en: "GET STARTED" },
  "how.title": { zh: "三步配对，即刻联动", en: "Three steps to get connected" },
  "how.step1.title": { zh: "安装 MioIsland (Mac)", en: "Install MioIsland (Mac)" },
  "how.step1.desc": { zh: "用 Homebrew 一行命令安装，或下载 DMG 手动安装。启动后自动配置 Claude Code hooks，无需手动编辑任何配置文件。", en: "Install with one Homebrew command, or download the DMG. Auto-configures Claude Code hooks on launch — no config files to edit." },
  "how.step2.title": { zh: "下载 Code Light (iPhone)", en: "Download Code Light (iPhone)" },
  "how.step2.desc": { zh: "在 App Store 搜索 Code Light 下载安装。目前公测期间完全免费，所有功能开放。", en: "Search for Code Light on the App Store. Currently in beta — completely free with all features unlocked." },
  "how.step3.title": { zh: "配对连接", en: "Pair & Connect" },
  "how.step3.desc": { zh: "在 Mac 端生成 6 位配对码，iPhone 输入即可连接。也支持扫描二维码快速配对。", en: "Generate a 6-digit pairing code on your Mac, enter it on iPhone to connect. QR code scanning also supported." },
  "how.install.cmd": { zh: "brew install MioMioOS/tap/mioisland", en: "brew install MioMioOS/tap/mioisland" },
  "how.install.or": { zh: "或", en: "or" },
  "how.install.dmg": { zh: "下载 DMG 安装包", en: "Download DMG" },
  "how.install.copied": { zh: "已复制!", en: "Copied!" },
  "how.result": { zh: "配对完成后，iPhone 灵动岛会实时同步 Mac 上的 Claude Code 状态。监控、审批、跳转终端 —— 全在手腕间完成。", en: "Once paired, your iPhone's Dynamic Island syncs with Claude Code on your Mac in real time. Monitor, approve, jump to terminal — all from your pocket." },

  // Pricing
  "pricing.tag": { zh: "定价方案", en: "PRICING" },
  "pricing.title": { zh: "开源 Mac + 免费公测 iPhone", en: "Open source Mac + Free beta iPhone" },
  "pricing.mioisland.name": { zh: "MioIsland", en: "MioIsland" },
  "pricing.mioisland.price": { zh: "永久免费", en: "Free forever" },
  "pricing.mioisland.desc": { zh: "Mac 灵动岛 AI 控制台，开源透明", en: "Mac Dynamic Island AI dashboard, open source" },
  "pricing.mioisland.f1": { zh: "灵动岛实时监控所有会话", en: "Dynamic Island real-time session monitoring" },
  "pricing.mioisland.f2": { zh: "刘海内一键审批权限请求", en: "One-click approval from the notch" },
  "pricing.mioisland.f3": { zh: "支持 10+ 终端一键跳转", en: "Jump to 10+ terminals with one click" },
  "pricing.mioisland.f4": { zh: "Buddy 宠物 + 像素猫 + 8-bit 音效", en: "Buddy pet + pixel cat + 8-bit sounds" },
  "pricing.mioisland.f5": { zh: "CC BY-NC 4.0 开源协议", en: "CC BY-NC 4.0 open source license" },
  "pricing.codelight.name": { zh: "Code Light", en: "Code Light" },
  "pricing.codelight.price": { zh: "公测免费", en: "Free in beta" },
  "pricing.codelight.desc": { zh: "iPhone 远程控制 Claude Code", en: "iPhone remote control for Claude Code" },
  "pricing.codelight.f1": { zh: "iPhone 灵动岛实时状态同步", en: "iPhone Dynamic Island real-time sync" },
  "pricing.codelight.f2": { zh: "远程审批 / 斜杠命令 / 实时聊天", en: "Remote approval / slash commands / live chat" },
  "pricing.codelight.f3": { zh: "一台 iPhone 连接多台 Mac", en: "One iPhone connects to multiple Macs" },
  "pricing.codelight.f4": { zh: "端到端加密，可自托管中继", en: "E2E encrypted, self-hostable relay" },
  "pricing.codelight.f5": { zh: "拍照直接发给 Claude 分析", en: "Photo attach — send images to Claude" },
  "pricing.codelight.beta": { zh: "公测中", en: "BETA" },
  "pricing.codelight.cta": { zh: "App Store 免费下载", en: "Free on App Store" },
  "pricing.codelight.future": { zh: "正式版定价待定", en: "Pricing TBD after beta" },
  "pricing.mioisland.cta": { zh: "免费下载", en: "Download Free" },
  "pricing.feedback": { zh: "公测期间欢迎尽情体验，你的反馈会直接影响正式版的功能和定价。", en: "Enjoy full access during beta. Your feedback directly shapes the final product and pricing." },

  // Plugins
  "plugins.tag": { zh: "插件生态", en: "PLUGIN ECOSYSTEM" },
  "plugins.title": { zh: "用插件打造你的专属刘海", en: "Customize your notch with plugins" },
  "plugins.desc": { zh: "主题、宠物、音效、工具——通过插件市场无限扩展你的灵动岛体验。开发者也可以创建并发布自己的插件。", en: "Themes, buddies, sounds, utilities — extend your Dynamic Island experience with the plugin marketplace. Developers can create and publish their own plugins too." },
  "plugins.theme.title": { zh: "主题插件", en: "Themes" },
  "plugins.theme.desc": { zh: "渐变背景、发光边框、自定义配色——让刘海成为你的个性标签", en: "Gradient backgrounds, glowing borders, custom palettes — make the notch uniquely yours" },
  "plugins.buddy.title": { zh: "伙伴精灵", en: "Buddy Spirits" },
  "plugins.buddy.desc": { zh: "可爱的像素宠物住在你的刘海里，陪你写代码", en: "Cute pixel pets live in your notch, keeping you company while you code" },
  "plugins.sound.title": { zh: "音效包", en: "Sound Packs" },
  "plugins.sound.desc": { zh: "8-bit 芯片音、自然白噪声、机械键盘音——每个事件专属音效", en: "8-bit chiptunes, nature ambience, mechanical keys — unique sounds for every event" },
  "plugins.utility.title": { zh: "实用工具", en: "Utilities" },
  "plugins.utility.desc": { zh: "番茄钟、天气、快捷指令——开发者社区持续扩展中", en: "Pomodoro timer, weather, shortcuts — the developer community keeps building" },
  "plugins.browse": { zh: "浏览插件商店", en: "Browse Plugin Store" },
  "plugins.developer": { zh: "成为开发者", en: "Become a Developer" },

  // FAQ
  "faq.tag": { zh: "常见问题", en: "FAQ" },
  "faq.title": { zh: "你可能想知道", en: "Frequently asked questions" },
  "faq.q1": { zh: "MioIsland 是什么？", en: "What is MioIsland?" },
  "faq.a1": { zh: "MioIsland 是一款 macOS 应用，把 MacBook 的刘海（notch）变成 AI 编程的灵动岛控制台。你可以在刘海里实时监控 Claude Code 会话、审批权限请求、一键跳回终端，完全不用切窗口。", en: "MioIsland is a macOS app that turns your MacBook's notch into a Dynamic Island dashboard for AI coding. Monitor Claude Code sessions, approve permissions, and jump to terminal — all without switching windows." },
  "faq.q2": { zh: "Code Light 是什么？", en: "What is Code Light?" },
  "faq.a2": { zh: "Code Light 是 MioIsland 的 iPhone 伴侣应用。它让你在手机上远程监控和控制 Mac 上的 Claude Code，包括实时状态同步、远程审批、斜杠命令等，离开工位也能掌控编程进度。", en: "Code Light is the iPhone companion app for MioIsland. It lets you remotely monitor and control Claude Code on your Mac — real-time status sync, remote approval, slash commands, and more. Stay in control even away from your desk." },
  "faq.q3": { zh: "收费吗？", en: "Is it free?" },
  "faq.a3": { zh: "MioIsland (Mac) 永久免费开源（CC BY-NC 4.0）。Code Light (iPhone) 目前公测期间完全免费，正式版将转为付费应用，定价待定。此外，插件商店中的部分高级插件可能为付费内容，开发者可以通过发布插件获得收入。", en: "MioIsland (Mac) is free and open source forever (CC BY-NC 4.0). Code Light (iPhone) is completely free during the beta period. It will become a paid app after beta — pricing TBD. Additionally, some premium plugins in the plugin store may be paid, and developers can earn revenue by publishing plugins." },
  "faq.q4": { zh: "支持哪些终端？", en: "Which terminals are supported?" },
  "faq.a4": { zh: "支持 Ghostty、iTerm2、Warp、Terminal、Kitty、Alacritty、WezTerm、Hyper、Tabby、Rio、cmux 等十几种主流终端，可精确跳转到对应标签页和分屏。", en: "Supports Ghostty, iTerm2, Warp, Terminal, Kitty, Alacritty, WezTerm, Hyper, Tabby, Rio, cmux and 10+ more. Jumps to the exact tab and split pane." },
  "faq.q5": { zh: "不用 Claude Code 能用吗？", en: "Does it work without Claude Code?" },
  "faq.a5": { zh: "MioIsland 专为 Claude Code 设计，也支持 OpenAI Codex。暂不支持其他 AI 编程工具。后续会根据社区需求考虑更多集成。", en: "MioIsland is designed specifically for Claude Code, and also supports OpenAI Codex. Other AI coding tools are not supported yet. More integrations may come based on community demand." },
  "faq.q6": { zh: "我的代码数据安全吗？", en: "Is my code data safe?" },
  "faq.a6": { zh: "绝对安全。Mac 和 iPhone 之间通过零知识中继通信，服务器不存储任何数据，端到端加密。你还可以自托管中继服务器，数据完全由你掌控。", en: "Absolutely. Communication between Mac and iPhone uses a zero-knowledge relay — no data is stored on the server, fully end-to-end encrypted. You can also self-host the relay server for complete control." },
  "faq.q7": { zh: "什么是插件？怎么安装？", en: "What are plugins? How to install?" },
  "faq.a7": { zh: "插件是第三方开发者或官方制作的扩展包，包括主题、伙伴精灵、音效和工具。在 MioIsland 设置中打开插件商店即可一键安装。开发者也可以通过 miomio.chat 发布自己的插件。", en: "Plugins are extension packs made by third-party developers or officially, including themes, buddy spirits, sound effects, and utilities. Open the plugin store in MioIsland settings to install with one click. Developers can also publish their own plugins via miomio.chat." },

  // OpenSource
  "os.title": { zh: "开源免费", en: "Open Source & Free" },
  "os.desc": { zh: "MioIsland 基于 CC BY-NC 4.0 协议开源。个人免费使用，代码透明可审查。和社区一起构建，为社区服务。", en: "MioIsland is open source under CC BY-NC 4.0. Free for personal use, fully transparent and auditable. Built with the community, for the community." },
  "os.contributors": { zh: "贡献者", en: "Contributors" },
  "os.fork": { zh: "Fork & 参与贡献", en: "Fork & Contribute" },
  "os.docs": { zh: "查看文档", en: "Read the Docs" },

  // Community
  "community.join": { zh: "加入社区", en: "Join Community" },
  "community.title": { zh: "加入 MioIsland 用户群", en: "Join MioIsland Community" },
  "community.subtitle": { zh: "扫码加入微信群，第一时间获取更新、提 bug、交流使用技巧", en: "Scan to join our WeChat group — get updates, report bugs, share tips" },
  "community.tabGroup": { zh: "微信群", en: "Group Chat" },
  "community.tabPersonal": { zh: "开发者微信", en: "Developer WeChat" },
  "community.groupNote": { zh: "使用微信扫一扫加入群聊", en: "Use WeChat to scan and join the group" },
  "community.groupExpiry": { zh: "群二维码每 7 天自动更新", en: "Group QR code refreshes every 7 days" },
  "community.personalNote": { zh: "如群二维码失效，扫码添加开发者", en: "If group QR is expired, add the developer" },
  "community.wechatId": { zh: "微信号：", en: "WeChat ID: " },
  "community.close": { zh: "关闭", en: "Close" },

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
    const saved = localStorage.getItem("mioisland-lang")
    if (saved === "en" || saved === "zh") return saved
    return navigator.language.startsWith("zh") ? "zh" : "en"
  })

  useEffect(() => {
    localStorage.setItem("mioisland-lang", lang)
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
