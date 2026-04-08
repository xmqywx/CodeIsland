<div align="center">

<img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" height="128" alt="CodeIsland" />

# CodeIsland

**你的 AI 代理住在刘海里。**

这是一个纯粹出于个人兴趣开发的项目，**完全免费开源**，没有任何商业目的。欢迎大家试用、提 Bug、推荐给身边的同事使用，也欢迎贡献代码。一起把它做得更好！

**如果觉得好用，请点个 Star 支持一下！这是我们持续更新的最大动力。**

[![GitHub stars](https://img.shields.io/github/stars/xmqywx/CodeIsland?style=social)](https://github.com/xmqywx/CodeIsland/stargazers)

[![Website](https://img.shields.io/badge/website-xmqywx.github.io%2FCodeIsland-7c3aed?style=flat-square)](https://xmqywx.github.io/CodeIsland/)
[![Release](https://img.shields.io/github/v/release/xmqywx/CodeIsland?style=flat-square&color=4ADE80)](https://github.com/xmqywx/CodeIsland/releases)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?style=flat-square&logo=apple)](https://github.com/xmqywx/CodeIsland/releases)
[![License](https://img.shields.io/badge/license-CC%20BY--NC%204.0-green?style=flat-square)](LICENSE.md)

[English](README.md) | 中文

</div>

---

> ## ⚠️ 安装说明（v1.9.0-rc1 及后续版本）
>
> 最新版本**已使用 Developer ID 签名**，但**暂未完成 Apple 公证**。我们正在积极联系 Apple 处理后台的配置问题（公证错误 7000）。应用代码与之前已公证的版本完全一致，仅缺少 Apple 公证票。
>
> **系统要求：** macOS **15.0** 或更高（通用二进制，同时支持 Apple Silicon 和 Intel 芯片）。
>
> **首次打开 —— 任选一种方式：**
>
> **方式 A —— 右键打开（推荐）：**
> 1. 下载 `CodeIsland-vX.Y.Z.zip` 并解压
> 2. 把 `Code Island.app` 拖到 `/应用程序`（Applications）
> 3. **右键** 应用 → **打开** → 在弹窗中再次点 **打开**
> 4. 之后双击即可正常启动，不会再有提示
>
> **方式 B —— 终端命令（一行搞定）：**
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Code Island.app" && open "/Applications/Code Island.app"
> ```
>
> Apple 处理完后，后续版本将恢复正常双击安装体验。感谢理解。
>
> ---
>
> ## ⚠️ Installation Notice (v1.9.0-rc1 and later)
>
> The latest builds are **code-signed** with our Developer ID but **not yet notarized** by Apple. We are actively working with Apple to resolve a server-side issue (notarization error 7000) on their end. The app binary is identical to previous notarized releases — only the Apple notary ticket is missing.
>
> **System requirement:** macOS **15.0** or later (universal binary, supports both Apple Silicon and Intel).
>
> **First launch — choose one:**
>
> **Option A — Right-click to open (recommended):**
> 1. Download `CodeIsland-vX.Y.Z.zip` and unzip
> 2. Move `Code Island.app` to `/Applications`
> 3. **Right-click** the app → **Open** → click **Open** in the dialog
> 4. Subsequent launches will work normally with a double-click
>
> **Option B — Command line (one-liner):**
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Code Island.app" && open "/Applications/Code Island.app"
> ```
>
> Once Apple resolves the notarization issue, future releases will install with a normal double-click. Thank you for your patience.

---

<div align="center">

## 📱 即将推出：**[Code Light](https://github.com/xmqywx/CodeLight)** —— 你的 iPhone 伴侣 🐱✨

> ### *Claude 在思考，你在吃午饭。**你会知道。***

<img src="marketing/codelight/lockscreen-live-activity.jpeg" width="640" alt="Code Light 锁屏 Live Activity —— 像素猫图标、当前 Claude 阶段、最近用户消息和回复预览、计时器"/>

*Mac 刘海里那只像素猫，现在也住进了你 iPhone 的**灵动岛**。当前会话阶段、最近的用户提问、Claude 的回复预览 —— 直接显示在你的锁屏上。*

</div>

<table>
<tr>
<td width="20%"><img src="marketing/codelight/macs-list.png" alt="一台 iPhone 配对多台 Mac"/></td>
<td width="20%"><img src="marketing/codelight/sessions.png" alt="活跃 / 最近 / 归档 三 tab 会话视图"/></td>
<td width="20%"><img src="marketing/codelight/commands.png" alt="内置斜杠命令选择器"/></td>
<td width="20%"><img src="marketing/codelight/chat.png" alt="实时聊天 + 富文本 Markdown 渲染"/></td>
<td width="20%"><img src="marketing/codelight/settings.png" alt="自托管、多服务器、完全私密"/></td>
</tr>
<tr>
<td align="center"><b>🖥️ 一台 iPhone N 台 Mac</b><br><sub>一键切换</sub></td>
<td align="center"><b>📋 活跃·最近·归档</b><br><sub>三 tab 会话管理</sub></td>
<td align="center"><b>⚡ 任意 /斜杠命令</b><br><sub>/model · /cost · /usage…</sub></td>
<td align="center"><b>💬 实时聊天 + Markdown</b><br><sub>代码块·表格·列表</sub></td>
<td align="center"><b>⚙️ 自托管 · 完全私密</b><br><sub>零知识中继</sub></td>
</tr>
</table>

<div align="center">

### CodeIsland 下个版本会带来什么

CodeIsland 下一个版本会发布 **Code Light Sync 模块** —— 把刘海应用变成 Mac、云端、iPhone 之间的双向桥梁：

| 功能 | 对你的意义 |
|---|---|
| 🏝️ **真正的灵动岛** | ActivityKit Live Activity 实时反映"Claude 此刻在干什么"——阶段、工具名、计时 |
| 🎯 **精准终端定位** | 手机消息精确落到**你选中的那个** Claude 终端。CodeIsland 通过 `ps -Ax` 找到 `claude --session-id` 进程 → 读 `CMUX_WORKSPACE_ID` / `CMUX_SURFACE_ID` 环境变量 → `cmux send --workspace --surface`。零猜测 |
| ⚡ **斜杠命令带回显** | 在手机输入 `/model`、`/cost`、`/usage`、`/clear`。CodeIsland 给 cmux 窗格拍快照、注入命令、diff 输出，作为合成消息回传。手机上看到的就跟普通 Claude 回复一样 |
| 🚀 **远程新建会话** | 在手机上点 **+**，选一个启动预设（`claude --dangerously-skip-permissions --chrome`），选项目路径 —— CodeIsland 立刻在 Mac 上 spawn 一个新的 cmux workspace 跑那条命令 |
| 📷 **图片附件** | iPhone 相机拍照，CodeIsland 下载 blob → `NSPasteboard` + AppleScript Cmd+V 粘进 cmux 窗格 |
| 🔐 **永久 6 位配对码** | 每台 Mac 一个永久 shortCode（懒分配、永不轮转）。CodeIsland 重启—码不变；再配一台 iPhone—同一个码 |
| 🖥️ **一台 Mac 多部 iPhone · 一部 iPhone 多台 Mac** | server 端的 DeviceLink 图。一台 Mac 可以同时配对 N 部 iPhone；一部 iPhone 可以配对 M 台分布在不同后端服务器的 Mac |
| 🔄 **60 秒 echo 去重环** | 手机注入的文字不会因为 CodeIsland 的 JSONL 监听器再次检测到而被回传成重复消息 |
| 🌐 **可自托管、零知识** | 在任何 VPS 跑你自己的 CodeLight Server。中继只存加密 blob |

</div>

> **状态**：Code Light 已进入 TestFlight，App Store 提交中。
> CodeIsland 的 Sync 模块会作为下一个公开版本的一部分发布。⭐ **[给 CodeIsland 加 Star](https://github.com/xmqywx/CodeIsland)** + ⭐ **[给 Code Light 加 Star](https://github.com/xmqywx/CodeLight)** 以获得发布通知。

---

## 🐱 CodeIsland 现在长这样

<div align="center">

<img src="marketing/island/notch-collapsed.png" width="900" alt="CodeIsland 在 MacBook 刘海中 —— 像素猫 + 'hi' 状态 + 'carey ×3' 活跃会话角标"/>

*收起的刘海 —— 像素猫陪伴、当前状态文字、活跃会话数角标。一直在那儿，又不挡道。*

</div>

<table>
<tr>
<td width="33%"><img src="marketing/island/session-list.png" alt="展开的会话列表 —— 两个活跃 Claude Code 会话，cmux 标签、运行时长、实时用量进度条"/></td>
<td width="33%"><img src="marketing/island/buddy-card.png" alt="Claude Code 宠物卡片 —— 传说级章鱼物种，5 项属性条 (DBG/PAT/CHS/WIS/SNK)、ASCII 艺术 sprite、性格描述"/></td>
<td width="33%"><img src="marketing/island/settings-menu.png" alt="CodeIsland 设置菜单 —— Screen / Notification Sound / Language 选择器，Pixel Cat / Smart Suppression / Auto-Collapse / Hooks 开关，Pair iPhone Online 状态，Launch Presets 入口"/></td>
</tr>
<tr>
<td align="center"><b>📋 实时会话列表</b><br><sub>cmux 跳转 · 用量条</sub></td>
<td align="center"><b>🐙 Claude Code 宠物</b><br><sub>18 物种 · 5 项属性 · ASCII 艺术</sub></td>
<td align="center"><b>⚙️ 紧凑设置菜单</b><br><sub>同步 · 预设 · 辅助功能</sub></td>
</tr>
</table>

---

> **关键词**：Claude Code 灵动岛、MacBook 刘海监控、Claude Code 可视化、Claude Code Mac 客户端、Claude Code 监控工具、MacBook 刘海工具、AI 编程助手、Claude Code 桌面应用、Mac Dynamic Island、Claude Code 状态栏、AI coding agent monitor、macOS notch app

一款原生 macOS 应用，将你的 MacBook 刘海变成 AI 编码代理的实时控制面板。监控会话、审批权限、跳转终端、和你的 Claude Code 宠物互动 — 无需离开当前工作流。

## 功能特性

### 灵动岛刘海

收起状态一眼掌握全局：

- **动画宠物** — 你的 Claude Code `/buddy` 宠物渲染为 16x16 像素画，带波浪/消散/重组动画
- **状态指示点** — 颜色表示状态：
  - 🟦 青色 = 工作中
  - 🟧 琥珀色 = 等待审批
  - 🟩 绿色 = 完成 / 等待输入
  - 🟣 紫色 = 思考中
  - 🔴 红色 = 出错，或会话超过 60 秒无人处理
  - 🟠 橙色 = 会话超过 30 秒无人处理
- **项目名 + 状态** — 轮播显示任务标题、工具动态、项目名
- **会话数量** — `×3` 角标显示活跃会话数
- **像素猫模式** — 可切换显示手绘像素猫或宠物 emoji 动画

### 会话列表

展开刘海查看所有 Claude Code 会话：

- **活跃会话凸显** — 更大图标、加粗标题、状态色背景、工具动态行
- **自动识别终端** — 彩色标签显示终端类型（cmux 蓝、Ghostty 紫、iTerm 绿、Warp 琥珀等）
- **任务标题** — 显示最新用户消息或 Claude 摘要
- **运行时长** — 活跃会话用状态色显示
- **终端跳转** — 绿色按钮一键跳到对应终端
- **删除会话** — 空闲/结束的会话可一键删除
- **Subagent 追踪** — ⚡ 标签 + 可折叠的子 Agent 详情列表
- **动态面板高度** — ≤4 个会话自适应，>4 个可展开/收起

### Claude 用量监控

实时显示 Claude 使用量：

- **5h/7d 百分比** — 直接调用 Anthropic OAuth API 获取
- **进度条 + 重置时间** — 绿色 <70%，橙色 70-90%，红色 >90%
- **自动刷新** — 每 5 分钟刷新，支持手动刷新
- **零配置** — 从 macOS 钥匙串读取 OAuth Token

### 智能弹出抑制

当 Claude 会话完成时，智能判断是否弹出：

- **cmux** — 精确到 workspace 级别，正在看的 tab 不弹出
- **iTerm2** — 检测当前 session 名称
- **Ghostty** — 检测前台窗口标题
- **Terminal.app** — 检测 tab 标题
- **不抢焦点** — hover/通知弹出不会打断你在其他应用的打字

### AskUserQuestion 快捷回复

Claude 提问时，选项按钮直接显示在会话行：

- **cmux** — 点击直接发送答案（`cmux send`）
- **iTerm2** — AppleScript `write text`
- **Terminal.app** — AppleScript `do script`
- 其他终端跳转手动选择

### Claude Code 宠物集成

与 Claude Code 的 `/buddy` 伙伴系统完整集成：

- **精确属性** — 物种、稀有度、眼型、帽子、闪光状态和全部 5 项属性
- **动态盐值检测** — 支持修改过的安装（兼容 any-buddy）
- **ASCII 精灵动画** — 全部 18 种宠物物种
- **宠物卡片** — ASCII 精灵 + 属性条 + 性格描述
- **稀有度星级** — ★ 普通 到 ★★★★★ 传说

### 权限审批

直接在刘海中审批 Claude Code 的权限请求：

- **代码差异预览** — 绿色/红色行高亮
- **拒绝/允许按钮** — 带键盘快捷键提示
- **基于 Hook 协议** — 通过 Unix socket 响应

### 像素猫伙伴

手绘像素猫，6 种动画状态：

| 状态 | 表情 |
|------|------|
| 空闲 | 黑色眼睛，每 90 帧温柔眨眼 |
| 工作中 | 眼球左/中/右移动（阅读代码） |
| 需要你 | 眼睛 + 右耳抖动 |
| 思考中 | 闭眼，鼻子呼吸 |
| 出错 | 红色 X 眼 |
| 完成 | 绿色爱心眼 + 绿色调叠加 |

### 8-bit 音效系统

每个事件的芯片音乐提醒，每个声音可单独开关。

### Code Light Sync (iPhone 伴侣)

CodeIsland 的**同步模块**是 [Code Light](https://github.com/xmqywx/CodeLight) iPhone 伴侣应用得以工作的桥梁。从刘海菜单打开 `Pair iPhone` 即可开始。

<details>
<summary><b>技术细节（点击展开）</b></summary>

#### 配对方式

每台 Mac 在 server 端有一个**永久 6 位 `shortCode`**（首次连接时懒分配，永不轮转）。配对窗口同时显示：
- 二维码（用 iPhone 相机扫描）
- 6 位大字号字符码（不想扫码就直接输入）

两条路径走的是同一个 `POST /v1/pairing/code/redeem` 接口。同一个码可以配对任意多部 iPhone —— 永不过期、CodeIsland 重启也不变、升级后依然有效。

#### 手机 → 终端 路由

手机发来的消息必须**精准**落到用户选中的那个 Claude 终端。CodeIsland 的 `TerminalWriter` 不做任何猜测：

1. `ps -Ax` 找到匹配 session 标签的 `claude --session-id <UUID>` 进程
2. `ps -E -p <pid>` 读取 `CMUX_WORKSPACE_ID` 和 `CMUX_SURFACE_ID` 环境变量
3. `cmux send --workspace <ws> --surface <surf> -- <text>`

如果 Claude 进程被 `claude --resume` 重启过，PID 已经轮转，会以 `cwd` 为范围 fallback —— 在同一目录下挑 PID 最高的 cmux 中托管 Claude 进程。如果都没匹配到，消息会被干净地丢掉，绝不会误发到旁边的窗口。

非 cmux 终端（iTerm2、Ghostty、Terminal.app）走 AppleScript fallback。

#### 斜杠命令带回显

`/model`、`/cost`、`/usage`、`/clear`、`/compact` 这类命令**不会**写入 Claude 的 JSONL —— 输出根本不会被文件监听器看到。CodeIsland 特殊处理：

1. 用 `cmux capture-pane` 给当前 pane 拍快照
2. 用 `cmux send` 注入斜杠命令
3. 每 200ms 轮询 pane 直到输出稳定
4. diff 前后快照，把新增的行作为合成的 `terminal_output` 消息发回 server

手机端在聊天里看到回复，就像 `/cost` 是普通的 Claude 回答一样。

#### 远程新建会话

手机可以让 CodeIsland 直接 spawn 一个新的 cmux workspace，跑指定命令。CodeIsland 在本地定义**启动预设** —— 名称 + 命令 + 图标 —— 并上传到 server（使用 Mac 生成的 UUID 作为主键，让 round-trip 不需要做 ID 转换）。

手机调 `POST /v1/sessions/launch {macDeviceId, presetId, projectPath}` 时，server 给这台 Mac 的 deviceId 推一个 `session-launch` socket 事件。CodeIsland 的 `LaunchService` 在本地查到预设后跑：

```bash
cmux new-workspace --cwd <projectPath> --command "<preset.command>"
```

首次启动会自动 seed 两个默认预设：
- `Claude (skip perms)` → `claude --dangerously-skip-permissions`
- `Claude + Chrome` → `claude --dangerously-skip-permissions --chrome`

可以从刘海菜单的 **Launch Presets** 项里增删改自己的预设。

#### 图片附件

手机发来的图片是不透明的 blob ID（手机通过 `POST /v1/blobs` 上传）。CodeIsland 下载每个 blob → 聚焦目标 cmux pane → 把图片以 NSImage / `public.jpeg` / `.tiff` 三种格式同时写入 `NSPasteboard` → `System Events keystroke "v" using {command down}`（CGEvent fallback）。Claude 看到 `[Image #N]` 和后续文本作为同一条消息。

这需要**辅助功能权限** —— 而权限是按 app 签名路径记录的，所以 CodeIsland 会自安装一份到 `/Applications/Code Island.app`，让权限在 Debug rebuild 后依然有效。

#### 项目路径同步

CodeIsland 每 5 分钟把所有活跃 session 的 unique `cwd` 上传一次。手机从 `GET /v1/devices/<macDeviceId>/projects` 拉取，填充启动 sheet 里的"最近项目"选择器。无需手动配置。

#### Echo 去重

手机发 → server → CodeIsland 粘贴 → Claude 写 JSONL → 文件监听器看到"新用户消息" → 默认会重新上传 → 手机收到自己刚发的消息的副本。解法：Mac 端保留一个 60 秒 TTL 的 `(claudeUuid, text)` 环，MessageRelay 上传前消费一次匹配项就跳过。不改 server，不做 localId 协商。

#### 多 iPhone、多 server

一台 Mac 可以同时配对多部 iPhone —— 它们共用同一个 `shortCode`。从 iPhone 端看，一部手机也可以配对**不同 server 上**的多台 Mac；手机的 `LinkedMacs` 列表会按 Mac 存 `serverUrl`，点击不同 Mac 时自动切换 socket 连接。

</details>

## 终端支持

| 终端 | 检测 | 跳转 | 快捷回复 | 智能抑制 |
|------|------|------|---------|---------|
| cmux | 自动 | workspace 精确跳转 | ✅ | workspace 级别 |
| iTerm2 | 自动 | AppleScript | ✅ | session 级别 |
| Ghostty | 自动 | AppleScript | - | 窗口级别 |
| Terminal.app | 自动 | 激活 | ✅ | tab 级别 |
| Warp | 自动 | 激活 | - | - |
| Kitty | 自动 | CLI | - | - |
| WezTerm | 自动 | CLI | - | - |
| VS Code | 自动 | 激活 | - | - |
| Cursor | 自动 | 激活 | - | - |
| Zed | 自动 | 激活 | - | - |

## 安装

从 [Releases](https://github.com/xmqywx/CodeIsland/releases) 下载最新 `.zip`，解压后拖到应用程序文件夹。

> **macOS 门禁提示：** 如果看到"Code Island 已损坏，无法打开"，在终端中运行：
> ```bash
> sudo xattr -rd com.apple.quarantine /Applications/Code\ Island.app
> ```

### 从源码构建

```bash
git clone https://github.com/xmqywx/CodeIsland.git
cd CodeIsland
xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland \
  -configuration Release CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" build
```

### 系统要求

- macOS 14+（Sonoma）
- 带刘海的 MacBook（外接显示器使用浮动模式）

## 参与贡献

欢迎参与！方式如下：

1. **提交 Bug** — 在 [Issues](https://github.com/xmqywx/CodeIsland/issues) 中描述问题和复现步骤
2. **提交 PR** — Fork 本仓库，新建分支，修改后提交 Pull Request
3. **建议功能** — 在 Issues 中提出，标记为 `enhancement`

我会亲自 Review 并合并所有 PR。请保持改动聚焦，附上清晰的说明。

## 联系方式

- **邮箱**: xmqywx@gmail.com

<img src="docs/wechat-qr-kris.jpg" width="180" alt="微信 - Kris" />  <img src="docs/wechat-qr.jpg" width="180" alt="微信 - Carey" />

## 致谢

基于 [Claude Island](https://github.com/farouqaldori/claude-island)（作者 farouqaldori）改造。

## 许可证

CC BY-NC 4.0 — 个人免费使用，禁止商业用途。
