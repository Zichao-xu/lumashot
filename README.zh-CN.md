中文 | [English](README.md)

# Lumashot

**一个面向现代 Mac 显示技术的极简而强大的截图工具。**

Lumashot 是 [sw33tLie/macshot](https://github.com/sw33tLie/macshot) 的一个 fork，专注于**现代显示器截图**和**原生 macOS 交互打磨**。

---

## 功能特性

- **原生 macOS 截图体验** — 全局快捷键、干净工具栏、类 macOS 动效，AppKit 原生实现，无 Electron
- **HEIC gain map HDR 截图导出** — 基于 ScreenCaptureKit 捕获，输出带 HEIC gain map 的 HDR 截图
- **SDR 与 HDR 兼容流程** — 同时支持 HDR（HEIC gain map）和标准（PNG/JPEG/HEIC SDR）导出
- **干净的工具栏交互与类 macOS 动效** — 精选标注工具，macOS 风格动效和体验
- **轻量标注工具** — 箭头、形状、文字、铅笔、马克笔、数字标记、擦除等
- **可自定义的捕获与导出行为** — 全局快捷键、文件格式、质量、剪贴板行为均可配置

---

## 当前重点

Lumashot 正在积极开发 **HDR gain map 捕获**功能 — 让 HEIC gain map 输出在 macOS 上真正可用。这包括 ScreenCaptureKit 集成、HEIF gain map 编码，以及确保在 SDR 和 HDR 显示器上的兼容性。该功能仍在实验阶段，尚未最终完成。

---

## 上游归属

本项目基于/ fork 自 [sw33tLie/macshot](https://github.com/sw33tLie/macshot)。我们保留完整归属和上游历史，同时开发 Lumashot 特有的 HDR 捕获、UI 打磨和可定制性功能。所有上游历史和 GPLv3 协议均被保留。

> Lumashot **不是**上游项目的替代品。上游拥有更广泛的功能集（滚动截图、屏幕录制、视频编辑器、OCR、上传集成等）。Lumashot 是一个专注于现代显示器截图和 HDR 方向的分支。

---

## 开发状态

实验性项目，开发进行中。HDR gain map 捕获功能仍在最终测试和打磨阶段。

---

## 安装

> **这是一个开发 fork。** 官方发布版本来自 [sw33tLie/macshot](https://github.com/sw33tLie/macshot)。如需安装本 fork 的 Lumashot，请从源码构建，或从 `main` 分支安装最新的 CI 构建产物。

**从上游安装（推荐大多数用户）：**

```bash
brew install --cask macshot
```

或从 [sw33tLie/macshot Releases](https://github.com/sw33tLie/macshot/releases) 下载最新 `.dmg`。

**从本 fork 构建：**

```bash
git clone https://github.com/Zichao-xu/lumashot.git
cd lumashot
xcodebuild -scheme macshot -configuration Release
# Result: build/macshot.app → copy to /Applications
```

---

## 快速开始

1. 启动 Lumashot — 它会出现在菜单栏中
2. 按 `Cmd+Shift+X` 开始截图
3. 拖选区域，使用工具栏标注，按 `Cmd+C` 复制
4. 按 `Esc` 取消

---

## 权限

Lumashot 需要**屏幕录制**权限。首次截图时 macOS 会自动提示授权。

---

## 系统要求

macOS 12.3（Monterey）或更高版本。

## 许可证

[GPLv3](LICENSE)

*本项目基于 [sw33tLie/macshot](https://github.com/sw33tLie/macshot)。对原始作者的完整归属已被保留。*
