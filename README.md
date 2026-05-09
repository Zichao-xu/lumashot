# macshot

<p align="center">
  <img src="assets/logo.svg" alt="macshot logo" width="200"/>
</p>

<p align="center">
  <b>A minimal yet powerful macOS screenshot tool focused on native experience, customization, and modern HDR capture.</b><br>
  <b>一款轻量而强大的 macOS 截图工具，专注于原生体验、高度可定制和现代 HDR 截图。</b><br>
</p>

<p align="center">
  <a href="https://github.com/sw33tLie/macshot/releases/latest">Download</a> · <a href="https://github.com/sw33tLie/macshot/blob/main/CHANGELOG.md">Changelog</a> · <a href="https://github.com/sw33tLie/macshot/blob/main/PRIVACY.md">Privacy</a>
</p>

<p align="center">
  <img src="assets/preview.png" alt="macshot demo" width="700"/>
</p>

<p align="center">
  <img src="assets/preview-editor.png" alt="macshot video editor" width="700"/>
</p>

---

## What is macshot? / macshot 是什么？

macshot is a fork of [sw33tLie/macshot](https://github.com/sw33tLie/macshot) focused on **HDR screenshot capture** and **native macOS interaction polish**. The upstream project is a full-featured screenshot tool with 18+ annotation tools, screen recording, OCR, and more. macshot inherits that foundation and focuses on:

macshot 是 [sw33tLie/macshot](https://github.com/sw33tLie/macshot) 的一个 fork，专注于 **HDR 截图捕获**和**原生 macOS 交互打磨**。上游项目是一个功能完整的截图工具，拥有 18+ 标注工具、屏幕录制、OCR 等。macshot 继承了这一基础，并聚焦于：

- **HDR screenshot export** — ScreenCaptureKit-based capture with HEIC gain map output for genuine HDR display compatibility
- **HDR 截图导出** — 基于 ScreenCaptureKit 捕获，输出带 HEIC gain map 的截图，兼容真正 HDR 显示
- **SDR + HDR dual path** — both HDR (HEIC gain map) and standard (PNG/JPEG/HEIC SDR) export in one workflow
- **SDR + HDR 双路径** — 同时支持 HDR（HEIC gain map）和标准（PNG/JPEG/HEIC SDR）导出
- **Native macOS feel** — clean toolbar interaction, macOS-like motion, AppKit-native implementation without Electron
- **原生 macOS 体验** — 干净的工具栏交互、类 macOS 动效，基于 AppKit 原生实现，无 Electron
- **Lightweight annotation** — focused set of annotation tools covering the most common workflows
- **轻量标注** — 精选标注工具，覆盖最常见工作流
- **File URL clipboard** — copy file references directly instead of raw image data, enabling smooth integration with other apps
- **文件 URL 剪贴板** — 直接复制文件引用而非原始图像数据，与其他 App 无缝集成

---

## Current Focus / 当前重点

macshot is actively developing **HDR gain map capture** — making HEIC gain map output practical on macOS. This involves ScreenCaptureKit integration, HEIF gain map encoding, and ensuring compatibility across SDR and HDR displays. This work is experimental and still being finalized.

macshot 正在积极开发 **HDR gain map 捕获**功能 — 让 HEIC gain map 输出在 macOS 上真正可用。这包括 ScreenCaptureKit 集成、HEIF gain map 编码，以及确保在 SDR 和 HDR 显示器上的兼容性。该功能仍在实验阶段，尚未最终完成。

---

## Upstream Attribution / 上游归属

This project is forked from [sw33tLie/macshot](https://github.com/sw33tLie/macshot) and keeps full attribution to the upstream project. All upstream history and GPLv3 license are preserved. macshot develops fork-specific features (HDR capture, UI polish, customization) while remaining compatible with upstream releases.

本项目 fork 自 [sw33tLie/macshot](https://github.com/sw33tLie/macshot)，并保留对上游项目的完整归属。所有上游历史和 GPLv3 协议均被保留。macshot 开发 fork 特有的功能（HDR 捕获、UI 打磨、可定制性），同时保持与上游版本的兼容性。

> macshot is **not** a replacement for the upstream project. The upstream has a broader feature set (scroll capture, screen recording, video editor, OCR, upload integrations). macshot is a focused fork for HDR-specific development.
>
> macshot **不是**上游项目的替代品。上游拥有更广泛的功能集（滚动截图、屏幕录制、视频编辑器、OCR、上传集成等）。macshot 是一个专注于 HDR 方向的分支。

---

## Development Status / 开发状态

Experimental / work in progress. HDR gain map capture is still being finalized and tested.

实验性项目，开发进行中。HDR gain map 捕获功能仍在最终测试和打磨阶段。

---

## Install / 安装

> **This is a development fork.** Official releases come from [sw33tLie/macshot](https://github.com/sw33tLie/macshot). To install macshot from this fork, build from source or install the latest CI artifact from the `feature/hdr-gainmap-finalize` branch.
>
> **这是一个开发 fork。** 官方发布版本来自 [sw33tLie/macshot](https://github.com/sw33tLie/macshot)。如需安装本 fork 的 macshot，请从源码构建，或从 `feature/hdr-gainmap-finalize` 分支安装最新的 CI 构建产物。

**From upstream (recommended for most users) / 从上游安装（推荐大多数用户）：**

```bash
brew install --cask macshot
```

Or download the latest `.dmg` from [sw33tLie/macshot Releases](https://github.com/sw33tLie/macshot/releases).
或从 [sw33tLie/macshot Releases](https://github.com/sw33tLie/macshot/releases) 下载最新 `.dmg`。

**Build from this fork / 从本 fork 构建：**

```bash
git clone https://github.com/Zichao-xu/macshot.git
cd macshot
xcodebuild -scheme macshot -configuration Release
# Result: build/macshot.app → copy to /Applications
```

---

## Quick Start / 快速开始

1. Launch macshot — it appears in your menu bar / 启动 macshot — 它会出现在菜单栏中
2. Press `Cmd+Shift+X` to capture / 按 `Cmd+Shift+X` 开始截图
3. Drag to select, annotate with the toolbar, press `Cmd+C` to copy / 拖选区域，使用工具栏标注，按 `Cmd+C` 复制
4. Press `Esc` to cancel / 按 `Esc` 取消

---

<details>
<summary><b>All Features / 全部功能</b> <em>(inherited from upstream · macshot focuses on capture & HDR / 继承自上游 · macshot 专注于截图 & HDR)</em></summary>

### Capture / 截图

- **Instant capture** — global hotkey freezes your screen, select any region
- **即时截图** — 全局快捷键冻结屏幕，选择任意区域
- **Window snap** — hover over a window and click to capture it exactly; `Tab` toggles snap, `F` for full screen
- **窗口捕捉** — 悬停在窗口上点击即可精准捕获；`Tab` 切换捕捉模式，`F` 全屏捕获
- **Scroll capture** — auto-detects vertical or horizontal scrolling, stitches with Apple Vision, live preview panel beside the capture region
- **滚动截图** — 自动检测垂直或水平滚动，使用 Apple Vision 拼接，实时预览面板显示在捕获区域旁边
- **Capture delay** — 3/5/10/30 second countdown before capture, set via menu bar. Escape to cancel
- **捕获延时** — 3/5/10/30 秒倒计时后捕获，通过菜单栏设置，按 Escape 取消
- **Multi-monitor** — captures all screens simultaneously; drag a selection across screens for a stitched image
- **多显示器** — 同时捕获所有屏幕；跨屏幕拖选区域可拼接为一张图像
- **Quick save** — `Cmd+Shift+S` to select and save/copy instantly without annotation
- **快速保存** — `Cmd+Shift+S` 选中区域后立即保存/复制，无需标注
- **Quick OCR** — `Cmd+Shift+T` to select and extract text instantly
- **快速 OCR** — `Cmd+Shift+T` 选中区域后立即提取文字

### Annotation Tools / 标注工具

- **Arrow** — 5 styles: single, thick/banner, double, open, tail; flip direction toggle; right-click to add anchor points
- **箭头** — 5 种样式：单箭头、粗箭头/标题栏、双箭头、开口箭头、尾翼箭头；可翻转方向；右键添加锚点
- **Shapes** — rectangle and ellipse with 3 fill modes (stroke, stroke+fill, fill), corner radius slider
- **形状** — 矩形和椭圆，3 种填充模式（描边、描边+填充、填充），圆角滑块可调
- **Text** — rich formatting (bold/italic/underline/strikethrough), resizable text box, alignment, background fill
- **文字** — 丰富格式（粗体/斜体/下划线/删除线），可调整文本框大小，对齐方式，背景填充
- **Pencil & Marker** — freeform drawing with optional smoothing; smart marker mode snaps to text lines via OCR
- **铅笔和马克笔** — 自由绘制，可选平滑；智能马克笔模式通过 OCR 吸附到文字行
- **Numbered markers** — auto-incrementing (1/I/A/a formats), with optional pointer cone
- **数字标记** — 自动递增（1/I/A/a 格式），可选指针锥
- **Stamp / Emoji** — 21 quick emojis, 100+ in categorized picker, or load any image
- **图章/表情符号** — 21 个快速表情符号，分类选择器中有 100+ 个，或加载任意图片
- **Censor** — pixelate, blur, solid color, or smart erase; auto-redact PII (emails, phones, credit cards)
- **擦除/打码** — 像素化、模糊、纯色填充或智能擦除；自动打码 PII（邮箱、电话、信用卡号）
- **Measure** — pixel ruler with px/pt toggle; hold `1` or `2` for auto-measure
- **测量** — 像素标尺，支持 px/pt 切换；按住 `1` 或 `2` 自动测量
- **Loupe** — 2x magnifier
- **放大镜** — 2 倍放大
- **Color sampler** — eyedropper to pick any color; right-click to copy hex
- **取色器** — 吸管工具选取任意颜色；右键复制十六进制值

### Screen Recording / 屏幕录制

- **MP4 (H.264)** up to 120fps or **GIF** (5/10/15fps)
- **MP4 (H.264)** 最高 120fps，或 **GIF**（5/10/15fps）
- **System audio capture** — toggle on/off, excludes macshot's own sounds
- **系统音频捕获** — 可开关，排除 macshot 自身的声音
- **Microphone recording** — record voice narration alongside screen capture
- **麦克风录制** — 屏幕捕获同时录制语音旁白
- **Video editor** — trim timeline, mute/strip audio, play/pause, save, upload
- **视频编辑器** — 剪辑时间线、静音/去除音频、播放/暂停、保存、上传

### Output & Upload / 输出与上传

- **Formats** — PNG, JPEG, HEIC, WebP with quality slider
- **格式** — PNG、JPEG、HEIC、WebP，带质量滑块
- **Google Drive** — sign in once, uploads to a private "macshot" folder
- **Google Drive** — 登录一次，上传到私有 "macshot" 文件夹
- **S3-compatible** — upload to Cloudflare R2, AWS S3, MinIO, etc.
- **兼容 S3** — 上传到 Cloudflare R2、AWS S3、MinIO 等
- **Retina downscale** — optional 1x export for smaller files
- **Retina 缩小** — 可选 1x 导出以减小文件大小

### Other / 其他功能

- **OCR** — extract text with Apple Vision, auto-copy to clipboard, translate to 30+ languages
- **OCR** — 使用 Apple Vision 提取文字，自动复制到剪贴板，翻译为 30+ 种语言
- **Background removal** — Apple Vision foreground mask (macOS 14+)
- **背景移除** — Apple Vision 前景遮罩（macOS 14+）
- **Screenshot history** — menu bar submenu + drop-down history panel (`Cmd+Shift+H`)
- **截图历史** — 菜单栏子菜单 + 下拉历史面板（`Cmd+Shift+H`）
- **Auto-updates** via Sparkle
- **自动更新** — 通过 Sparkle 实现

</details>

---

<details>
<summary><b>Keyboard Shortcuts / 键盘快捷键</b></summary>

**Global hotkeys / 全局快捷键** (configurable in Preferences / 可在偏好设置中自定义)

| Shortcut / 快捷键 | Action / 操作 |
|---|---|
| `Cmd+Shift+X` | Capture Area / 区域截图 |
| `Cmd+Shift+F` | Capture Full Screen / 全屏截图 |
| `Cmd+Shift+S` | Quick Capture (instant save) / 快速截图（立即保存） |
| `Cmd+Shift+T` | Capture OCR (instant text extraction) / 截图 OCR（立即提取文字） |
| `Cmd+Shift+R` | Record Area / 区域录制 |
| `Cmd+Shift+H` | Show History Panel / 显示历史面板 |

**General / 通用** (during capture / 截图过程中)

| Shortcut / 快捷键 | Action / 操作 |
|---|---|
| `Enter` | Confirm (save or copy) / 确认（保存或复制） |
| `Cmd+C` | Copy to clipboard / 复制到剪贴板 |
| `Cmd+S` | Save to file / 保存到文件 |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo / 撤销 / 重做 |
| `Esc` | Cancel / 取消 |
| `Tab` | Toggle window snap mode / 切换窗口捕捉模式 |
| `F` | Capture full screen (snap mode) / 全屏捕获（捕捉模式） |
| `Shift` (while drawing) | Constrain to straight lines / 约束为直线 |
| `Space` (while drawing) | Reposition shape / 重新定位形状 |

**Tool shortcuts / 工具快捷键** (active after selecting a region / 选中区域后可用 — customizable / 可自定义)

| Key / 按键 | Tool / 工具 |
|---|---|
| `A` | Arrow / 箭头 |
| `L` | Line / 直线 |
| `P` | Pencil / 铅笔 |
| `M` | Marker / 马克笔 |
| `R` | Rectangle / 矩形 |
| `O` | Ellipse / 椭圆 |
| `T` | Text / 文字 |
| `N` | Number / 数字标记 |
| `B` | Censor (Pixelate/Blur) / 打码（像素化/模糊） |
| `I` | Color Sampler / 取色器 |
| `G` | Stamp / Emoji / 图章 / 表情符号 |
| `S` | Select & Edit / 选择并编辑 |
| `E` | Open in Editor / 在编辑器中打开 |

</details>

---

## Permissions / 权限

macshot requires **Screen Recording** permission. macOS will prompt you on first capture.
macshot 需要**屏幕录制**权限。首次截图时 macOS 会自动提示授权。

---

## Star History / Star 历史

[![Star History Chart](https://api.star-history.com/svg?repos=sw33tLie/macshot&type=Date)](https://star-history.com/#sw33tLie/macshot&Date)

## Requirements / 系统要求

macOS 12.3 (Monterey) or later / macOS 12.3（Monterey）或更高版本。

## License / 许可证

[GPLv3](LICENSE)
