#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Building Swift targets (ASUSControlCore, asusctl-diag, asusctl, asusctld, ASUSControlApp)..."
swift build

BIN_DIR="$ROOT_DIR/.build/debug"
APP_BUNDLE="$ROOT_DIR/build/ASUSControl.app"

echo "[2/4] Packaging macOS Application Bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/ASUSControlApp" "$APP_BUNDLE/Contents/MacOS/ASUSControlApp"
cp "$BIN_DIR/asusctl" "$APP_BUNDLE/Contents/MacOS/asusctl"
cp "$BIN_DIR/asusctld" "$APP_BUNDLE/Contents/MacOS/asusctld"
cp "$BIN_DIR/asusctl-diag" "$APP_BUNDLE/Contents/MacOS/asusctl-diag"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>ASUS Control</string>
    <key>CFBundleExecutable</key>
    <string>ASUSControlApp</string>
    <key>CFBundleIdentifier</key>
    <string>org.asuscontrol.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ASUS Control</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 ASUS Control for macOS (Open Source)</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE"

echo "[3/4] Installing ASUSControl.app to /Applications and CLI tools to /usr/local/bin..."
rm -rf "/Applications/ASUSControl.app"
cp -R "$APP_BUNDLE" "/Applications/ASUSControl.app"

echo "[4/4] Configuring LaunchAgent for asusctld background service..."
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$LAUNCH_AGENTS_DIR/org.asuscontrol.daemon.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.asuscontrol.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/ASUSControl.app/Contents/MacOS/asusctld</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.config/asus-control/asusctld.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.config/asus-control/asusctld.log</string>
</dict>
</plist>
EOF

echo "Done! Built and installed /Applications/ASUSControl.app"
