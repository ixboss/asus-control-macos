#!/bin/zsh
# Stage AsusBridge.kext v0.3.0 (TUF RGB 0x00100057 Byte-2 Awake Fix + 0x00050021 Brightness + EC0 MMIO Readback)
set -e
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

echo "=== Staging AsusBridge.kext v0.3.0 ==="
sudo rm -rf /tmp/AsusBridge.kext
sudo cp -R "$REPO_DIR/build/kext/AsusBridge.kext" /tmp/AsusBridge.kext
sudo chown -R root:wheel /tmp/AsusBridge.kext
sudo chmod -R 755 /tmp/AsusBridge.kext

sudo mkdir -p "/Library/Application Support/ASUSControl"
sudo rm -rf "/Library/Application Support/ASUSControl/AsusBridge.kext"
sudo cp -R "$REPO_DIR/build/kext/AsusBridge.kext" "/Library/Application Support/ASUSControl/AsusBridge.kext"
sudo chown -R root:wheel "/Library/Application Support/ASUSControl/AsusBridge.kext"
sudo chmod -R 755 "/Library/Application Support/ASUSControl/AsusBridge.kext"

echo "=== Requesting macOS AuxiliaryKernelCollection Update ==="
sudo kextutil -v "/Library/Application Support/ASUSControl/AsusBridge.kext" || true
echo ""
echo "إذا ظهرت رسالة الموافقة، افتح:"
echo "System Settings -> Privacy & Security -> Allow (AsusBridge) -> Restart"
