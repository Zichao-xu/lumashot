#!/bin/sh
# Re-sign a built Lumashot.app with a stable signing identity.
#
# Why: ad-hoc / linker-only signatures give the app a designated requirement of
# "cdhash H<...>", which changes on every build. macOS TCC stores that
# requirement with the Screen Recording grant, so every new version looks like a
# different app — System Settings still shows the toggle ON, but the running app
# is treated as unauthorized. Signing with a fixed certificate makes the
# requirement "identifier + certificate leaf", so grants survive updates.
#
# The certificate is self-signed (no Apple Developer account). It does not need
# to be trusted: codesign signs with it, and TCC only matches the leaf hash.
#
# Usage: scripts/sign-app.sh path/to/Lumashot.app [identity]
#   identity defaults to $LUMASHOT_SIGN_IDENTITY, then "Lumashot Self-Signed".
set -e

APP="$1"
IDENT="${2:-${LUMASHOT_SIGN_IDENTITY:-Lumashot Self-Signed}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$APP" ] || { echo "usage: $0 path/to/Lumashot.app [identity]" >&2; exit 1; }

# An untrusted self-signed identity can't be looked up by name reliably;
# resolve it to its SHA-1 hash (also accepts a hash or "-" directly).
if [ "$IDENT" != "-" ] && ! echo "$IDENT" | grep -Eq '^[0-9A-Fa-f]{40}$'; then
    HASH=$(security find-identity -p codesigning ${LUMASHOT_SIGN_KEYCHAIN:+"$LUMASHOT_SIGN_KEYCHAIN"} \
        | awk -v n="\"$IDENT\"" 'index($0, n) { print $2; exit }')
    [ -n "$HASH" ] || { echo "error: signing identity \"$IDENT\" not found" >&2; exit 1; }
    IDENT="$HASH"
fi

SIGN="/usr/bin/codesign --force --timestamp=none -s $IDENT ${LUMASHOT_SIGN_KEYCHAIN:+--keychain $LUMASHOT_SIGN_KEYCHAIN}"
ENG="$APP/Contents/Resources/llama-engine"

# Innermost first: engine dylibs, then the sandbox-inheriting helper, then the app.
if [ -d "$ENG" ]; then
    find "$ENG" -name '*.dylib' -type f -exec $SIGN {} +
    $SIGN --entitlements "$ROOT/llama-engine.entitlements" "$ENG/llama-server"
fi
$SIGN --entitlements "$ROOT/Lumashot/Lumashot.entitlements" "$APP"

/usr/bin/codesign --verify --deep --strict "$APP"
echo "Signed $APP"
/usr/bin/codesign -d -r- "$APP" 2>&1 | grep designated
