# AGENTS.md

This repository is Lumashot. Any AI agent, automation, or contributor touching this project must follow these rules.

## Project Identity (MUST READ before any work)

- **Product name (user-visible):** Lumashot
- **Upstream:** forked from `sw33tLie/macshot`
- **Bundle ID:** `com.sw33tlie.macshot.macshot` (matches upstream for TCC stability)
- **.app bundle name:** `macshot.app` (matches upstream for TCC stability)
- **Xcode target name:** `macshot` (matches upstream, do not rename)
- **Upstream attribution** (`sw33tLie/macshot`) must be preserved in license, history comments, and upstream-referencing code

### Identity Split Rule

To maintain Screen Recording / TCC permission stability, the app uses a **dual identity**:

| Layer | Name | Reason |
|---|---|---|
| **Internal / TCC identity** | `com.sw33tlie.macshot.macshot` / `macshot.app` | Must match upstream so TCC recognizes the app consistently |
| **User-visible branding** | Lumashot | README, GitHub repo, Release titles, DMG filenames, About text, menu strings |

**Do NOT change the internal identity fields** (Bundle ID, PRODUCT_NAME, .app bundle name) unless the user explicitly requests it. Changing them breaks TCC permission grants.

Fields that use `macshot` (internal identity, do not change):
- `PRODUCT_BUNDLE_IDENTIFIER` in pbxproj
- `PRODUCT_NAME` / target name in pbxproj
- `CFBundleURLSchemes` in Info.plist
- Notification names, pasteboard types, keychain service names, data directory paths

Fields that use `Lumashot` (user-visible branding):
- README, GitHub repo name, Release titles
- DMG filename (e.g. `Lumashot-darwin-arm64-0.1.6-alpha.dmg`)
- `NSScreenCaptureUsageDescription` and other usage descriptions in Info.plist
- About window, Settings window text
- GitHub release checker URL (`Zichao-xu/lumashot`)

## Hard Release Rule

Published versions are immutable.

After any code, build, packaging, workflow, or user-visible product change that will be distributed to users, do not reuse an existing version. Create a new version.

This means:

- Do not move an existing tag.
- Do not force-push a tag.
- Do not delete and recreate a tag.
- Do not overwrite an existing GitHub Release.
- Do not replace, clobber, delete, or rename assets on an existing release.
- Do not edit old release notes to describe new behavior.
- Treat a pushed tag as immutable even if the GitHub Release has not been created yet.

If a release needs a fix after `v0.1.6-alpha`, the next distributed fix must be a new version, for example `v0.1.7-alpha`. Never recycle an existing version tag.

## Required Release Flow

Before releasing:

1. Inspect existing tags and releases on GitHub.
2. Choose a new version greater than every existing release/tag.
3. Update app version/build metadata for that new version.
4. Build and verify the app artifact.
5. Create a new tag for the new version.
6. Create a new GitHub Release for that tag.
7. Upload a new DMG asset with the new version in the filename.
8. Verify the downloaded release asset contains the expected app name, bundle identifier, version, and update behavior.

If any step would require modifying an old tag, old release, old asset, or old release notes, stop and ask the user. Do not improvise.

## Current Distribution Model

Lumashot does not use Sparkle hot updates or appcast releases.

Current update behavior:

- The app checks GitHub Releases (`Zichao-xu/lumashot`).
- When a newer release with a matching DMG asset exists, the app opens that DMG download URL for manual installation.
- The app must not silently download, install, or replace itself.
- Do not reintroduce Sparkle, `SUFeedURL`, appcast signing, or automatic installers unless the user explicitly requests that architecture again.

## Product Identity Rules

- Current user-visible product name: Lumashot.
- Internal identity (Bundle ID, .app name, target name): matches upstream `macshot` for TCC stability.
- GPLv3 must be preserved.
- Upstream attribution to `sw33tLie/macshot` must be preserved where appropriate.
- User-visible app names, menus, prompts, release titles, and new distribution assets should use Lumashot.
- The `macshot` name in internal identity fields (Bundle ID, target name, notification names, data paths) is intentional and must not be "cleaned up" to Lumashot.

## Baseline

As of `v0.1.6-alpha`, the release asset is:

`Lumashot-darwin-arm64-0.1.6-alpha.dmg`

The app inside is `macshot.app` with Bundle ID `com.sw33tlie.macshot.macshot`.

Any later distributed change must use a later version.

## For AI Agents (How to pick up this project)

1. **Read this file first.** It defines what you must not break.
2. **Read `CLAUDE.md`** for architecture, coding conventions, and the full file structure.
3. **Read `CONTRIBUTING.md`** for how to build, test, and release.
4. **Check git tags** (`git tag -l`) before creating a new version — never reuse a tag.
5. **Do not change internal identity fields** (Bundle ID, PRODUCT_NAME, .app name) — it breaks TCC permission grants.
6. **Test entitlement changes** by building and checking Screen Recording permission detection.
7. **Never rename the Xcode project** (`macshot.xcodeproj`) or the main source directory (`macshot/`) unless the user explicitly asks — it breaks Xcode references.
8. **The `PermissionsGuide.imageset` no longer contains an image** (removed in v0.1.4-alpha). `PermissionOnboardingController.swift` uses text-based instructions now. Do not add screenshots of system UI back.
9. **The entitlements file** is `macshot/macshot.entitlements`. It includes `com.apple.security.device.screen-capture` which upstream does not have — this is intentional and must be kept.
