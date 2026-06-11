#!/bin/sh
# Bundle the llama.cpp engine into the app and sign it so the App Sandbox allows
# executing it. A downloaded engine in the container CANNOT be executed under the
# sandbox, so the engine must ship inside the (signed) app bundle and the helper
# must inherit the app's sandbox.
#
# This runs as a build phase BEFORE Xcode's own (final) code-sign, so it only
# copies + signs the engine itself; Xcode then signs the app and seals the
# already-signed engine into the bundle. (Re-signing the whole app here would
# fail, because the app's own binaries are not signed yet at this point.)
set -e

ENG_SRC="${SRCROOT}/Vendor/llama-engine"
if [ ! -d "$ENG_SRC" ]; then
    echo "warning: llama-engine not vendored at $ENG_SRC — local-model translation will be unavailable"
    exit 0
fi

APP="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}"
ENG_DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/llama-engine"
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:--}"

echo "Bundling llama engine → ${ENG_DST} (identity: ${IDENT})"
rm -rf "$ENG_DST"
/usr/bin/ditto "$ENG_SRC" "$ENG_DST"

# Sign innermost first: dylibs, then the helper (with an inherited sandbox).
# Xcode's subsequent automatic code-sign seals these into the app bundle.
find "$ENG_DST" -name '*.dylib' -type f -exec /usr/bin/codesign --force --timestamp=none -s "$IDENT" {} +
/usr/bin/codesign --force --timestamp=none -s "$IDENT" \
    --entitlements "${SRCROOT}/llama-engine.entitlements" "$ENG_DST/llama-server"

echo "llama engine bundled and signed."
