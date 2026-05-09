# Contributing to Lumashot

Thanks for your interest in contributing! Lumashot is open to bug fixes, improvements, and new features.

## Before you start

- **Bug fixes:** Open a PR directly with a clear description of what's broken and how you fixed it.
- **New features / large changes:** Open an issue first to discuss the approach. This avoids wasted effort if the feature isn't fit for the project direction.
- **Small improvements** (UI polish, performance, code cleanup): PRs welcome without prior discussion.

## Quick Start (Humans & AI)

### 1. Clone & Open

```
git clone https://github.com/Zichao-xu/lumashot.git
cd lumashot
open macshot.xcodeproj          # Opens in Xcode
```

### 2. Read these files (in order)

| Order | File | Why |
|-------|------|-----|
| 1 | `AGENTS.md` | Release rules, product identity, what you must NOT break |
| 2 | `CLAUDE.md` | Architecture, file structure, coding conventions |
| 3 | `CONTRIBUTING.md` | This file — build, test, PR guidelines |

### 3. Build & Run

- Open `macshot.xcodeproj` in Xcode
- Select scheme `macshot` (Release or Debug)
- **Build & Run** (Cmd+R)
- Grant **Screen Recording** permission when prompted (System Settings → Privacy & Security → Screen & System Audio Recording)
- App appears in the **menu bar** (no dock icon by default)

### 4. Verify Screen Recording permission

After the `v0.1.4-alpha` fix, the permission detection works as follows:

1. On launch, `PermissionOnboardingController.checkPermissionSync` calls `CGPreflightScreenCaptureAccess()`
2. If already granted → app proceeds normally
3. If not granted → shows onboarding window with text-based instructions (no screenshots)
4. User clicks "Open Screen Recording Settings" → macOS Settings opens to the correct pane
5. After granting, the app auto-detects and proceeds

**If the onboarding keeps showing after you granted permission:**
- Quit Lumashot
- System Settings → Privacy & Security → Screen & System Audio Recording
- Remove Lumashot from the list
- Re-add `/Applications/Lumashot.app`
- Turn it on
- Re-launch Lumashot

## Project Identity (do NOT skip)

Lumashot is a **fork** of `sw33tLie/macshot`. Rules:

- **User-visible text** must say `Lumashot` (not `macshot`)
- **Bundle ID** is `com.zichao.lumashot`
- **Upstream attribution** (`sw33tLie/macshot`) must be preserved in LICENSE, comments, and history
- **Xcode project file** is still named `macshot.xcodeproj` and source lives in `macshot/` — do NOT rename these unless you know what you're doing (it breaks Xcode references)
- **entitlements** file is `macshot/Lumashot.entitlements` (renamed from `macshot.entitlements` in v0.1.4-alpha)

## Entitlements (CRITICAL)

The app is sandboxed. `macshot/Lumashot.entitlements` must contain:

```xml
com.apple.security.app-sandbox: true
com.apple.security.network.client: true
com.apple.security.files.user-selected.read-write: true
com.apple.security.files.bookmarks.app-scope: true
com.apple.security.device.screen-capture: true   <!-- THIS IS REQUIRED for ScreenCaptureKit -->
com.apple.security.device.audio-input: true
com.apple.security.device.camera: true
```

**Missing `com.apple.security.device.screen-capture` was the root cause of the v0.1.2-alpha permission bug.**
If you add new capabilities, update this file AND `AGENTS.md`.

## Architecture at a Glance

Menu-bar agent app. No main window. Global hotkey (default: `Cmd+Shift+X`) or menu bar click → fullscreen overlay → selection → annotation → output.

```
macshot/
├── AppDelegate.swift                     # App lifecycle, status bar, hotkey
├── Capture/
│   └── ScreenCaptureManager.swift      # Multi-screen capture via ScreenCaptureKit
├── UI/
│   ├── Overlay/OverlayView.swift      # Main interaction surface
│   ├── Windows/
│   │   └── PermissionOnboardingController.swift  # First-run permission guide
│   └── ...
├── Upload/
│   └── GoogleDriveUploader.swift     # OAuth2 upload (note: var was renamed macShotFolderID → lumashotFolderID)
├── Info.plist
└── Assets.xcassets/
    └── PermissionsGuide.imageset/     # Contains NO image now (text-based instructions since v0.1.4-alpha)
```

## Coding Conventions

- **Pure AppKit**, no SwiftUI (except `BeautifyRenderer` for mesh gradients on macOS 15+)
- **No new dependencies** unless absolutely necessary
- **Minimum target: macOS 12.3** — use `@available` guards for newer APIs
- Annotation tools implement `AnnotationToolHandler` protocol — don't add switch cases to `OverlayView`
- **Keyboard shortcuts:** Always use `event.keyCode` (hardware-based, layout-independent). Never `event.charactersIgnoringModifiers` for letter shortcuts.
- **Threading:** UI on main thread, capture/recording/OCR on background. Strict concurrency enforced in Release builds.

## Release & Versioning

**Read `AGENTS.md` before releasing. These are hard rules:**

1. **Published versions are immutable** — no tag moves, no force-push, no overwriting releases
2. **New fix → new version** (e.g. `v0.1.5-alpha` after `v0.1.4-alpha`)
3. **No Sparkle / appcast** — app checks GitHub Releases and opens DMG for manual install
4. **DMG naming:** `Lumashot-darwin-arm64-<version>.dmg`

### Release steps

1. Update `CHANGELOG.md` with your changes
2. Bump version in `macshot.xcodeproj/project.pbxproj`:
   - `MARKETING_VERSION = "0.1.5-alpha"`
   - `CURRENT_PROJECT_VERSION = 105`
3. Commit: `chore: bump version to v0.1.5-alpha`
4. Tag: `git tag v0.1.5-alpha && git push origin main --tags`
5. Create GitHub Release (prerelease if alpha/beta):
   ```
   gh release create v0.1.5-alpha -R Zichao-xu/lumashot \
     --title "Lumashot v0.1.5-alpha (Prerelease)" \
     --notes "..." --prerelease
   ```
6. Build signed DMG (Xcode Archive → Export .app → `hdiutil create`)
7. Upload DMG to the release:
   ```
   gh release upload v0.1.5-alpha \
     "Lumashot-darwin-arm64-0.1.5-alpha.dmg" \
     -R Zichao-xu/lumashot
   ```

## Guidelines

- **Pure AppKit.** No SwiftUI (except `BeautifyRenderer` which requires it for mesh gradients). No Electron, no web views.
- **No new dependencies** unless absolutely necessary. Prefer Apple frameworks.
- **Minimum target is macOS 12.3.** Use `@available` guards for newer APIs.
- **Test on single and multi-monitor setups** if your change touches coordinates, overlays, or screen capture.
- **Don't add features to the PR beyond what it claims to fix/add.** Keep PRs focused.
- **Match existing code style.** No SwiftLint, no formatter — just follow what's already there.

## PR Checklist

- [ ] Builds without warnings (check Release build for concurrency errors)
- [ ] Tested manually (there are no unit tests)
- [ ] Doesn't break existing behavior
- [ ] Commit message describes *what* and *why*
- [ ] `AGENTS.md` rules followed (no tag reuse, no overwriting releases)
- [ ] Entitlements updated if new capabilities added

## Questions?

Open an issue or start a discussion.
