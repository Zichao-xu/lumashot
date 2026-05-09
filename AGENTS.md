# AGENTS.md

This repository is Lumashot. Any AI agent, automation, or contributor touching this project must follow these release rules.

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

If a release needs a fix after `v0.1.2-alpha`, the next distributed fix must be a new version, for example `v0.1.3-alpha`. Never recycle `v0.1.2-alpha` for new commits.

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

- The app checks GitHub Releases.
- When a newer release with a matching DMG asset exists, the app opens that DMG download URL for manual installation.
- The app must not silently download, install, or replace itself.
- Do not reintroduce Sparkle, `SUFeedURL`, appcast signing, or automatic installers unless the user explicitly requests that architecture again.

## Product Identity Rules

- Current product name: Lumashot.
- GPLv3 must be preserved.
- Upstream attribution to `sw33tLie/macshot` must be preserved where appropriate.
- The old name `macshot` may appear only in upstream attribution, license/history notes, legacy source paths, or historical changelog context.
- User-visible app names, menus, prompts, release titles, and new distribution assets should use Lumashot.

## Baseline

As of `v0.1.2-alpha`, the release asset is:

`Lumashot-darwin-arm64-0.1.2-alpha.dmg`

Any later distributed change must use a later version.
