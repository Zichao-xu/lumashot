[中文](README.zh-CN.md) | English

# Lumashot

<p align="center">
  <img src="assets/logo.png" alt="Lumashot logo" width="200"/>
</p>

<p align="center">
  <b>Modern macOS screenshot tool with real HDR capture.</b><br>
  <br>
  Global hotkey, clean toolbar, native AppKit — plus HDR screenshot export with true HEIC gain map.<br>
  Forked from macshot, focused on modern display capture.
</p>

<p align="center">
  <a href="https://github.com/Zichao-xu/lumashot/releases/latest">Download</a> · <a href="https://github.com/Zichao-xu/lumashot/blob/main/CHANGELOG.md">Changelog</a> · <a href="https://github.com/Zichao-xu/lumashot/blob/main/PRIVACY.md">Privacy</a>
</p>

---

### Why Lumashot?

- **HDR screenshot with real HEIC gain map** — ScreenCaptureKit-based capture, true HDR output on HDR displays. No fake tone-mapping — genuine SDR base + HDR gain map.
- **Native macOS experience** — global hotkey, clean toolbar, AppKit-native without Electron. ~8 MB memory at idle.
- **SDR/HDR compatible workflow** — HDR and standard (PNG/JPEG/HEIC SDR) export in one seamless flow. Toggle HDR on the toolbar; Done gives you HEIC, off gives you PNG.
- **Lightweight annotation tools** — arrow, shape, text, pencil, marker, number, pixelate, measure, loupe.
- **Clean toolbar & polish** — macOS-style motion, continuous corner radius, Liquid Glass feel, animated transitions.
- **Customizable** — global hotkeys, file format, quality, clipboard behavior all configurable.

---

## Install (from this fork)

> **Note:** The upstream macshot has broader features (scroll capture, screen recording, video editor, OCR, cloud upload). Lumashot is a focused fork for modern display and HDR capture.

**Build from source:**
```bash
git clone https://github.com/Zichao-xu/lumashot.git
cd lumashot
xcodebuild -scheme macshot -configuration Release
# Result: build/macshot.app → copy to /Applications
```

Or download the latest alpha from [Releases](https://github.com/Zichao-xu/lumashot/releases).

**Upstream macshot (recommended for most users):**
```bash
brew install --cask macshot
```
Or download from [sw33tLie/macshot releases](https://github.com/sw33tLie/macshot/releases).

---

## Quick Start

1. Launch Lumashot — it appears in your menu bar
2. Press `Cmd+Shift+X` to capture
3. Drag to select, annotate with the toolbar, press `Cmd+C` to copy
4. Press `Esc` to cancel

**HDR mode:** Click the `HDR` button in the toolbar before clicking Done. The selection is captured as an HDR screenshot and saved as HEIC with gain map.

---

## Permissions

Lumashot requires **Screen Recording** permission. macOS will prompt you on first capture.

---

## Requirements

macOS 12.3 (Monterey) or later. HDR capture requires macOS 15 (Sequoia) or later and an HDR-capable display.

## License

[GPLv3](LICENSE)

*This project is based on [sw33tLie/macshot](https://github.com/sw33tLie/macshot). Full attribution to the original authors is preserved.*
