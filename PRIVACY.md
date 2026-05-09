# Privacy Policy

**Last updated:** May 9, 2026

## Overview

Lumashot is a free, open-source screenshot and screen recording tool for macOS. It is designed to run entirely on your device. We do not operate any servers, and we do not collect, store, or have access to any of your data.

## What Lumashot does NOT do

- **No telemetry or analytics** — Lumashot does not phone home, track usage, or send any data to us.
- **No data collection** — we do not collect personal information, usage statistics, crash reports, or any other data.
- **No server-side storage** — we do not operate any servers. All screenshots, recordings, and settings are stored locally on your Mac.
- **No access to your uploads** — when you upload to Google Drive, files go directly to your own Google Drive account. We cannot see, access, or download your files. When you upload to imgbb, files go directly to imgbb's servers under their privacy policy.

## Data stored on your device

Lumashot stores the following data locally on your Mac:

- **Screenshots and recordings** — saved to your chosen folder (default: Pictures).
- **Screenshot history** — recent captures stored in `~/Library/Application Support/com.zichao.lumashot/history/`. You control the history size in Preferences (set to 0 to disable).
- **Preferences** — settings stored in macOS UserDefaults.
- **Google Drive OAuth tokens** — if you sign in to Google Drive, authentication tokens are stored in `~/Library/Application Support/com.zichao.lumashot/gdrive_tokens.json` with owner-only permissions (0600). Tokens are used solely to upload files to your own Google Drive. You can sign out at any time in Preferences, which deletes the token file.

## Third-party services

Lumashot integrates with the following optional third-party services. Use of these services is entirely opt-in:

### Google Drive
- **Purpose:** Upload screenshots and recordings to your own Google Drive.
- **Scope:** `drive.file` — Lumashot can only access files it created in your Drive. It cannot read, list, or modify any other files in your Drive.
- **Data sent:** The image or video file you choose to upload, plus a filename.
- **Authentication:** OAuth 2.0. You sign in via Google's login page in your browser. Lumashot stores a refresh token locally (see above) to avoid repeated sign-ins.
- **Revoking access:** You can sign out in Lumashot Preferences, or revoke access at any time from [Google Account Permissions](https://myaccount.google.com/permissions).

### imgbb
- **Purpose:** Upload screenshots to imgbb for shareable image links.
- **Data sent:** The image file you choose to upload.
- **imgbb's privacy policy:** [https://imgbb.com/privacy](https://imgbb.com/privacy)

### GitHub Releases update checks
- **Purpose:** Check whether a newer Lumashot DMG has been published.
- **Data sent:** When automatic update checks are enabled, Lumashot requests `https://api.github.com/repos/Zichao-xu/lumashot/releases` about every 10 minutes. No telemetry payload is sent by Lumashot; GitHub receives the standard metadata that accompanies any HTTPS request.
- **Install behavior:** Lumashot does not auto-install updates. If a newer release is available, it opens the matching DMG download link in your browser.

## Permissions

Lumashot requests **Screen Recording** permission from macOS. This permission is required to capture screenshots and record your screen. macOS controls this permission — you can revoke it at any time in System Settings > Privacy & Security > Screen Recording.

## Open source

Lumashot is fully open source. You can inspect the complete source code at [https://github.com/Zichao-xu/lumashot](https://github.com/Zichao-xu/lumashot) to verify these claims.

## Contact

If you have questions about this privacy policy, open an issue at [https://github.com/Zichao-xu/lumashot/issues](https://github.com/Zichao-xu/lumashot/issues).
