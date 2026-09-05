#!/bin/bash
#
# Builds the Mermaid renderer (rust/mermaid-shim, a C ABI over merman) into
# Frameworks/libmermaid_shim.dylib.
#
# Both `swift test` and `xcodebuild` link against that dylib, so this has to
# run before either of them. There is deliberately no fallback: if the dylib
# is absent the link fails, loudly, rather than silently shipping an app whose
# Mermaid blocks render as nothing.
#
# Apple silicon only — release.yml builds ARCHS="arm64".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CRATE_DIR="$PROJECT_DIR/rust/mermaid-shim"
TARGET="aarch64-apple-darwin"
DEST_DIR="$PROJECT_DIR/Frameworks"
DYLIB="libmermaid_shim.dylib"

if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust from https://rustup.rs to build the Mermaid renderer." >&2
    exit 1
fi

if ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
    echo "Installing Rust target $TARGET…"
    rustup target add "$TARGET"
fi

echo "Building $DYLIB ($TARGET, release)…"
# --locked: Cargo.lock is committed and merman is a pinned pre-1.0 alpha.
# A silent dependency bump is exactly the failure this pin exists to prevent.
cargo build \
    --manifest-path "$CRATE_DIR/Cargo.toml" \
    --target "$TARGET" \
    --release \
    --locked

BUILT="$CRATE_DIR/target/$TARGET/release/$DYLIB"
if [ ! -f "$BUILT" ]; then
    echo "error: cargo reported success but $BUILT is missing." >&2
    exit 1
fi

mkdir -p "$DEST_DIR"
cp "$BUILT" "$DEST_DIR/$DYLIB"

# The app embeds one copy in Contents/Frameworks and both the app and the
# Quick Look extension find it through their @rpath. Without this the dylib
# would record its absolute build path and the shipped app would fail to load
# it on any other machine.
install_name_tool -id "@rpath/$DYLIB" "$DEST_DIR/$DYLIB"

# The ad-hoc signature is invalidated by the install-name rewrite above.
# Re-sign so the dylib loads; the release build re-signs it with the real
# Developer ID identity when it embeds it.
codesign --force --sign - "$DEST_DIR/$DYLIB" 2>/dev/null

echo "Built $DEST_DIR/$DYLIB ($(du -h "$DEST_DIR/$DYLIB" | cut -f1))"
