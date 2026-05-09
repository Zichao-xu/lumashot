[中文](README.zh-CN.md) | English

# Lumashot

**A minimal yet powerful macOS screenshot tool for modern displays.**

Lumashot is a fork of [sw33tLie/macshot](https://github.com/sw33tLie/macshot) focused on **modern display capture** and **native macOS interaction polish**.

---

## Features

- **Native macOS screenshot experience** — global hotkey, clean toolbar, macOS-like motion, AppKit-native without Electron
- **HDR screenshot export with HEIC gain map** — ScreenCaptureKit-based capture, genuine HDR output for HDR displays
- **SDR/HDR compatible workflow** — both HDR and standard (PNG/JPEG/HEIC SDR) export in one workflow
- **Clean toolbar interaction** — focused annotation tools, macOS-like motion and feel
- **Lightweight annotation tools** — arrow, shape, text, pencil, marker, number, censor, and more
- **Customizable capture and export behavior** — global hotkeys, file format, quality, clipboard behavior all configurable

---

## Current Focus

Lumashot is actively developing **HDR gain map capture** — making HEIC gain map output practical on macOS. This involves ScreenCaptureKit integration, HEIF gain map encoding, and ensuring compatibility across SDR and HDR displays. This work is experimental and still being finalized.

---

## Upstream Attribution

This project is based on / forked from [sw33tLie/macshot](https://github.com/sw33tLie/macshot). We keep full attribution and upstream history while developing Lumashot-specific HDR capture, UI polish, and customization features. All upstream history and GPLv3 license are preserved.

> Lumashot is **not** a replacement for the upstream project. The upstream has a broader feature set (scroll capture, screen recording, video editor, OCR, upload integrations). Lumashot is a focused fork for modern display capture and HDR-specific development.

---

## Development Status

Experimental / work in progress. HDR gain map capture is still being finalized and tested.

---

## Install

> **This is a development fork.** Official releases come from [sw33tLie/macshot](https://github.com/sw33tLie/macshot). To install Lumashot from this fork, build from source or install the latest CI artifact from the `main` branch.

**From upstream (recommended for most users):**

```bash
brew install --cask macshot
```

Or download the latest `.dmg` from [sw33tLie/macshot Releases](https://github.com/sw33tLie/macshot/releases).

**Build from this fork:**

```bash
git clone https://github.com/Zichao-xu/lumashot.git
cd lumashot
xcodebuild -scheme macshot -configuration Release
# Result: build/macshot.app → copy to /Applications
```

---

## Quick Start

1. Launch Lumashot — it appears in your menu bar
2. Press `Cmd+Shift+X` to capture
3. Drag to select, annotate with the toolbar, press `Cmd+C` to copy
4. Press `Esc` to cancel

---

## Permissions

Lumashot requires **Screen Recording** permission. macOS will prompt you on first capture.

---

## Requirements

macOS 12.3 (Monterey) or later.

## License

[GPLv3](LICENSE)

*This project is based on [sw33tLie/macshot](https://github.com/sw33tLie/macshot). Full attribution to the original authors is preserved.*
