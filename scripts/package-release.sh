#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-v0.3.0}"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/ASUSControl-$VERSION"

echo "=== Packaging ASUS Control for macOS ($VERSION) ==="

# 1. Clean staging directory
rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR/bin"

# 2. Build binaries if needed
if [ ! -d "$ROOT_DIR/build/ASUSControl.app" ]; then
    echo "Building ASUSControl.app..."
    ./scripts/build-app.sh
fi

if [ ! -d "$ROOT_DIR/build/kext/AsusBridge.kext" ]; then
    echo "Building AsusBridge.kext..."
    ./scripts/build-kext.sh
fi

# 3. Copy Application & Kext
echo "Copying application and kernel extension..."
cp -R "$ROOT_DIR/build/ASUSControl.app" "$STAGE_DIR/"
cp -R "$ROOT_DIR/build/kext/AsusBridge.kext" "$STAGE_DIR/"

# 4. Copy CLI Tools
echo "Copying CLI binaries..."
cp "$ROOT_DIR/.build/debug/asusctl" "$STAGE_DIR/bin/" 2>/dev/null || cp "$ROOT_DIR/.build/release/asusctl" "$STAGE_DIR/bin/"
cp "$ROOT_DIR/.build/debug/asusctl-diag" "$STAGE_DIR/bin/" 2>/dev/null || cp "$ROOT_DIR/.build/release/asusctl-diag" "$STAGE_DIR/bin/"
cp "$ROOT_DIR/.build/debug/asusctld" "$STAGE_DIR/bin/" 2>/dev/null || cp "$ROOT_DIR/.build/release/asusctld" "$STAGE_DIR/bin/"

# 5. Copy Documentation
cp "$ROOT_DIR/README.md" "$STAGE_DIR/"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/"

# 6. Create convenient installer helper
cat > "$STAGE_DIR/install.sh" << 'EOF'
#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================="
echo "   ASUS Control for macOS Installer"
echo "============================================="

echo "[1/3] Installing ASUSControl.app to /Applications..."
sudo rm -rf /Applications/ASUSControl.app
sudo cp -R "$DIR/ASUSControl.app" /Applications/ASUSControl.app

echo "[2/3] Installing CLI binaries to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo cp "$DIR/bin/asusctl" /usr/local/bin/
sudo cp "$DIR/bin/asusctl-diag" /usr/local/bin/
sudo cp "$DIR/bin/asusctld" /usr/local/bin/
sudo chmod +x /usr/local/bin/asusctl /usr/local/bin/asusctl-diag /usr/local/bin/asusctld

echo "[3/3] Setting up LaunchAgent for background daemon..."
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$LAUNCH_AGENTS_DIR/org.asuscontrol.daemon.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.asuscontrol.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/asusctld</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

launchctl unload "$LAUNCH_AGENTS_DIR/org.asuscontrol.daemon.plist" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/org.asuscontrol.daemon.plist" 2>/dev/null || true

echo ""
echo "Installation complete!"
echo "- Open /Applications/ASUSControl.app to launch the menu bar & dashboard."
echo "- For AsusBridge.kext: copy AsusBridge.kext into your EFI/OC/Kexts/ folder and add it to config.plist."
echo "============================================="
EOF
chmod +x "$STAGE_DIR/install.sh"

# 7. Create ZIP archive
ZIP_NAME="ASUSControl-$VERSION.zip"
echo "Creating $ZIP_NAME..."
cd "$DIST_DIR"
zip -rq "$ZIP_NAME" "ASUSControl-$VERSION"

echo "Release package created successfully: $DIST_DIR/$ZIP_NAME"
ls -lh "$DIST_DIR/$ZIP_NAME"
