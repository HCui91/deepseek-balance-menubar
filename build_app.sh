#!/usr/bin/env bash
# Compile DeepSeekBalance.swift and bundle it as a macOS menu bar app
# (LSUIElement, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepSeekBalance"
BUILD_DIR="build"
DIST_DIR="dist/${APP_NAME}.app"
BIN_NAME="${APP_NAME}"

# Menu bar icon size and gap (in points). Adjust as needed.
ICON_HEIGHT=15   # icon height
ICON_GAP=1       # gap between icon and balance text

# 0. Generate the menu bar icon (transparent PNG, ICON_GAP reserved on the
#    right, with @2x retina variant).
if [ -f deepseek.ico ] && command -v magick >/dev/null 2>&1; then
  mkdir -p assets
  W1=$(( ICON_HEIGHT * 224 / 165 ))          # 1x width from source ratio 224:165
  W2=$(( ICON_HEIGHT * 2 * 224 / 165 ))      # 2x width
  magick deepseek.ico -trim +repage -resize "x${ICON_HEIGHT}" \
    -background none -gravity West -extent "$((W1 + ICON_GAP))x${ICON_HEIGHT}" assets/icon.png
  magick deepseek.ico -trim +repage -resize "x$((ICON_HEIGHT * 2))" \
    -background none -gravity West -extent "$((W2 + ICON_GAP * 2))x$((ICON_HEIGHT * 2))" assets/icon@2x.png
  echo "==> icons generated: ${ICON_HEIGHT}pt tall, ${ICON_GAP}px gap (icon.png ${W1}x${ICON_HEIGHT} + gap, icon@2x.png ${W2}x$((ICON_HEIGHT*2)) + gap)"
fi

# 1. Compile
mkdir -p "$BUILD_DIR"
echo "==> compiling with swiftc…"
swiftc -O -o "$BUILD_DIR/$BIN_NAME" DeepSeekBalance.swift

# 2. Bundle the .app
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/Contents/MacOS" "$DIST_DIR/Contents/Resources"

cp "$BUILD_DIR/$BIN_NAME" "$DIST_DIR/Contents/MacOS/$BIN_NAME"
[ -f assets/icon.png ]    && cp assets/icon.png    "$DIST_DIR/Contents/Resources/icon.png"
[ -f assets/icon@2x.png ] && cp assets/icon@2x.png "$DIST_DIR/Contents/Resources/icon@2x.png"

cat > "$DIST_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>DeepSeek Balance</string>
    <key>CFBundleIdentifier</key><string>dev.deepseek.balance</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$DIST_DIR" 2>/dev/null || true

echo "✅ build complete: $DIST_DIR"
echo "   run:       open $DIST_DIR"
echo "   self-check: $BUILD_DIR/$BIN_NAME --check"
