# macshot

<p align="center">
  <img src="assets/logo.svg" alt="macshot logo" width="200"/>
</p>

<p align="center">
  <b>A minimal yet powerful macOS screenshot tool focused on native experience, customization, and modern HDR capture.</b><br>
</p>

<p align="center">
  <a href="https://github.com/sw33tLie/macshot/releases/latest">Download</a> · <a href="https://github.com/sw33tLie/macshot/blob/main/CHANGELOG.md">Changelog</a> · <a href="https://github.com/sw33tLie/macshot/blob/main/PRIVACY.md">Privacy</a>
</p>

<p align="center">
  <img src="assets/preview.png" alt="macshot demo" width="700"/>
</p>

<p align="center">
  <img src="assets/preview-editor.png" alt="macshot video editor — timeline with cut, speed, freeze, zoom and censor effects" width="700"/>
</p>

---

### What is macshot?

macshot is a fork of [sw33tLie/macshot](https://github.com/sw33tLie/macshot) focused on **HDR screenshot capture** and **native macOS interaction polish**. The upstream project is a full-featured screenshot tool with 18+ annotation tools, screen recording, OCR, and more. macshot inherits that foundation and narrows its scope to:

- **HDR screenshot export** — ScreenCaptureKit-based capture with HEIC gain map output for genuine HDR display compatibility
- **SDR + HDR dual path** — both HDR (HEIC gain map) and standard (PNG/JPEG/HEIC SDR) export in one workflow
- **Native macOS feel** — clean toolbar interaction, macOS-like motion, AppKit-native implementation without Electron
- **Lightweight annotation** — focused set of annotation tools covering the most common workflows
- **File URL clipboard** — copy file references directly instead of raw image data, enabling smooth integration with other apps

### Current Focus

macshot is actively developing **HDR gain map capture** — making HEIC gain map output practical on macOS. This involves ScreenCaptureKit integration, HEIF gain map encoding, and ensuring compatibility across SDR and HDR displays. This work is experimental and still being finalized.

### Upstream Attribution

This project is forked from [sw33tLie/macshot](https://github.com/sw33tLie/macshot) and keeps full attribution to the upstream project. All upstream history and GPLv3 license are preserved. macshot develops fork-specific features (HDR capture, UI polish, customization) while remaining compatible with upstream releases.

> macshot is **not** a replacement for the upstream project. The upstream has a broader feature set (scroll capture, screen recording, video editor, OCR, upload integrations). macshot is a focused fork for HDR-specific development.

### Development Status

Experimental / work in progress. HDR gain map capture is still being finalized and tested.

---

## Install

> **This is a development fork.** Official releases come from [sw33tLie/macshot](https://github.com/sw33tLie/macshot). To install macshot from this fork, build from source or install the latest CI artifact from the `feature/hdr-gainmap-finalize` branch.

**From upstream (recommended for most users):**
```bash
brew install --cask macshot
```
Or download the latest `.dmg` from [sw33tLie/macshot Releases](https://github.com/sw33tLie/macshot/releases).

---

## Quick Start

1. Launch macshot — it appears in your menu bar
2. Press `Cmd+Shift+X` to capture
3. Drag to select, annotate with the toolbar, press `Cmd+C` to copy
4. Press `Esc` to cancel

---

<details>
<summary><b>All Features</b> <em>(inherited from upstream · macshot focuses on capture & HDR)</em></summary>

> Full upstream features are preserved. macshot's current development is centered on capture and HDR output. Other features (scroll capture, screen recording, upload integrations) inherit upstream behavior.

### Capture
- **Instant capture** — global hotkey freezes your screen, select any region
- **Window snap** — hover over a window and click to capture it exactly; `Tab` toggles snap, `F` for full screen
- **Scroll capture** — auto-detects vertical or horizontal scrolling, stitches with Apple Vision, live preview panel beside the capture region
- **Capture delay** — 3/5/10/30 second countdown before capture, set via menu bar. Escape to cancel.
- **Multi-monitor** — captures all screens simultaneously; drag a selection across screens for a stitched image
- **Quick save** — `Cmd+Shift+S` to select and save/copy instantly without annotation. Enter key also saves/copies based on preference.
- **Quick OCR** — `Cmd+Shift+T` to select and extract text instantly

### Annotation Tools
- **Arrow** — 5 styles: single, thick/banner, double, open, tail; flip direction toggle; right-click to add anchor points for complex curves
- **Shapes** — rectangle and ellipse with 3 fill modes (stroke, stroke+fill, fill), corner radius slider
- **Text** — rich formatting (bold/italic/underline/strikethrough), resizable text box, left/center/right alignment, background fill & outline colors, click to re-edit
- **Pencil & Marker** — freeform drawing with optional smoothing; smart marker mode snaps to text lines via OCR
- **Numbered markers** — auto-incrementing (1/I/A/a formats), with optional pointer cone
- **Stamp / Emoji** — 21 quick emojis, 100+ in categorized picker, or load any image
- **Censor (Pixelate / Blur / Solid / Erase)** — unified redaction tool with 4 modes: pixelate, Gaussian blur, solid color fill, or smart erase that samples surrounding colors for invisible content removal. Auto-redact PII (emails, phones, credit cards, SSNs, API keys), auto-detect faces and people, or draw in "Text Only" mode to censor just the text in a region
- **Measure** — pixel ruler with px/pt toggle; hold `1` or `2` for auto-measure
- **Loupe** — 2x magnifier
- **Color sampler** — eyedropper to pick any color; right-click to copy hex; auto-saves to custom palette slots
- **Space to reposition** — hold Space while drawing to move the shape without changing its size
- **Rotation** — rotate shapes via handle, Shift for 90° snaps
- **Click-to-select** — click any annotation to select it, then edit properties (stroke, style, fill), drag to move, resize via handles, rotate, or delete — all without switching tools

### Screen Recording
- **MP4 (H.264)** up to 120fps or **GIF** (5/10/15fps)
- **System audio capture** — toggle on/off, excludes macshot's own sounds
- **Microphone recording** — record voice narration alongside screen capture (permission requested on first use)
- **Mouse click highlights** — visual ripple on clicks during recording
- **Selection border** — visible capture region outline during recording
- **Menu bar stop button** — stop recording from the menu bar icon (appears even if icon is hidden)
- **Quick settings popover** — change format, FPS, and post-recording action on the fly without opening Preferences
- **Video editor** — trim timeline, mute/strip audio, play/pause, save (with Save As), upload, reveal in Finder

### Output & Upload
- **Formats** — PNG, JPEG, HEIC, WebP with quality slider
- **Google Drive** — sign in once, uploads to a private "macshot" folder
- **imgbb** — anonymous image hosting with shareable links
- **S3-compatible** — upload to Cloudflare R2, AWS S3, MinIO, DigitalOcean Spaces, Backblaze B2, etc.
- **Retina downscale** — optional 1x export for smaller files
- **sRGB color profile** — optional embedding for cross-display consistency

### Editor Window
- Standalone resizable window with full annotation tools, beautify preview
- **Add Capture** — capture additional screen regions and compose them into a single image, drag to reposition
- Crop (with rule-of-thirds grid), flip H/V, zoom 0.1x–8x
- Top bar with pixel dimensions, zoom dropdown (presets, fit canvas, zoom in/out)

### Beautify
- macOS window frame with traffic lights, shadow, and gradient background
- 30 gradient styles including 7 mesh gradients (macOS 15+), adjustable padding/corner radius/shadow

### Image Effects (Adjust)
- Non-destructive CIFilter adjustments: Brightness, Contrast, Saturation, Sharpness
- 8 presets: Noir, Mono, Sepia, Chrome, Fade, Instant, Vivid
- Works independently or combined with Beautify
- Live preview in the overlay

### Other
- **OCR** — extract text with Apple Vision (auto-detects all languages on macOS 13+), auto-copy to clipboard, translate to 30+ languages, Google AI Search
- **Invert colors** — one-click color inversion, apply twice to revert
- **Background removal** — Apple Vision foreground mask (macOS 14+)
- **Pin to screen** — floating always-on-top window
- **Floating thumbnail** — auto-dismiss preview with Copy/Save/Pin/Edit/Upload
- **Screenshot history with editable annotations** — menu bar submenu + drop-down history panel (`Cmd+Shift+H`). Re-open any capture in the editor with live annotations preserved — edit, then press Done to save back. Drag-and-drop, Quick Look, and right-click actions
- **QR & barcode detection** — inline Open/Copy actions
- **Snap alignment guides** — annotations snap to midlines and edges
- **Auto-updates** via Sparkle
- **~8 MB memory** at idle

</details>

<details>
<summary><b>Keyboard Shortcuts</b></summary>

**Global hotkeys** (configurable in Preferences)

| Shortcut | Action |
|---|---|
| `Cmd+Shift+X` | Capture Area |
| `Cmd+Shift+F` | Capture Full Screen |
| `Cmd+Shift+S` | Quick Capture (instant save) |
| `Cmd+Shift+T` | Capture OCR (instant text extraction) |
| `Cmd+Shift+R` | Record Area |
| `Cmd+Shift+H` | Show History Panel |

**General** (during capture)

| Shortcut | Action |
|---|---|
| `Enter` | Confirm (save or copy based on preference) |
| `Cmd+C` | Copy to clipboard |
| `Cmd+S` | Save to file |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo |
| `Cmd+0` | Reset zoom to 1x |
| `Esc` | Cancel / close popover |
| `Delete` | Remove selected annotation |
| `Tab` | Toggle window snap mode |
| `F` | Capture full screen (snap mode) |
| `Shift` (while drawing) | Constrain to straight lines / perfect shapes |
| `Space` (while drawing) | Reposition shape without changing size |
| `Right-click` on line/arrow | Add anchor point for multi-point curves |

**Tool shortcuts** (active after selecting a region — customizable in Preferences > Shortcuts)

| Key | Tool |
|---|---|
| `A` | Arrow |
| `L` | Line |
| `P` | Pencil |
| `M` | Marker |
| `R` | Rectangle |
| `O` | Ellipse |
| `T` | Text |
| `N` | Number |
| `B` | Censor (Pixelate/Blur) |
| `I` | Color Sampler |
| `G` | Stamp / Emoji |
| `S` | Select & Edit |
| `E` | Open in Editor |

</details>

---

## Permissions

macshot requires **Screen Recording** permission. macOS will prompt you on first capture.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=sw33tLie/macshot&type=Date)](https://star-history.com/#sw33tLie/macshot&Date)

## Requirements

macOS 12.3 (Monterey) or later.

## License

[GPLv3](LICENSE)
