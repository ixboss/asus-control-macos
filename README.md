# ASUS Control for macOS

Native macOS control suite and hardware management daemon for **ASUS ROG & TUF Gaming Laptops** (Hackintosh / macOS x86_64).

Designed as a lightweight, open-source macOS alternative to **ASUS Armoury Crate** and **G-Helper**, offering native performance profiles, direct Embedded Controller fan curve programming, battery lifespan preservation limits, display backlight synchronization, and hardware telemetry.

---

## ⚡ Features

* **Battery Health Charging Limits:** Directly configures maximum battery charge capacity (`60%`, `80%`, or `100%`) through ASUS ACPI/WMI (`0x00120057`) and `EC0.SRSC` to preserve lithium-ion cell longevity when plugged into AC power.
* **Firmware Thermal Profiles:** Native switching between **Silent**, **Performance (Balanced)**, and **Turbo** profiles via SMM `DEVS(0x00120075)`.
* **Automatic AC / Battery Switching:** Dynamically transitions between power profiles when the charger is connected or disconnected.
* **CPU Power Limits (PL1 SPL / PL2 SPPT):** Directly writes sustained (`EC0.PL1V` via `0x001200A3`) and burst (`EC0.PL2V` via `0x001200A0`) CPU wattage limits on supported Intel Alder Lake architectures.
* **8-Point Custom Fan Curves:** Read and program custom 8-point temperature-to-duty fan curves directly into Embedded Controller registers (`EC0.SFTC` for CPU / `EC0.SFTG` for GPU) with built-in hardware safety guardrails.
* **Display Backlight Control:** Hotkey-synchronized display brightness slider integrated with macOS `DisplayServices` and `NVRMBacklightHandler`.
* **Menu Bar Extra & Dashboard:** Clean native SwiftUI menu bar popover for quick toggles, alongside a full multi-tab system management dashboard.
* **CLI & Diagnostic Suite:** Includes `asusctl` for automated scripting and `asusctl-diag` for hardware probing and ACPI register inspection.

---

## 💻 Hardware & System Compatibility

> [!IMPORTANT]
> This project is designed specifically for **macOS on ASUS laptops (Hackintosh)**. It communicates with the proprietary ASUS ACPI interface (`ATKD.WMNB`) and the laptop's Embedded Controller (`EC0`).

### Verified Hardware (Primary Reference Device)
* **Model:** ASUS TUF Gaming F17 (`FX707ZM` / Board: `FX707ZM.316`)
* **Processor:** 12th Gen Intel Core i7-12700H (Alder Lake-P, 6P + 8E)
* **Dedicated GPU:** NVIDIA GeForce RTX 3060 Laptop GPU (Direct dGPU / Ultimate MUX Mode)
* **Integrated GPU:** Intel UHD Graphics (Load-only mode)
* **Internal Panel:** LGD066C (1080p @ 300Hz eDP)
* **Operating Systems:** macOS Ventura (13.x), macOS Sonoma (14.x), macOS Sequoia (15.x), and macOS Tahoe (26.x preview)
* **Bootloader:** OpenCore 0.9.x+ / 1.0.x+

### Other ASUS ROG / TUF Models
Support for other ASUS ROG Zephyrus, Strix, and TUF gaming models using the standard `ATKD.WMNB` ACPI interface is architecturally supported. If your model uses standard ASUS WMI calls (`0x00120075`, `0x00120057`, `0x00110024`), the battery, power profiles, and fan curves will work out of the box.

---

## 📦 What's Included

* **`ASUSControl.app`:** The graphical user interface (Menu Bar popover and main dashboard).
* **`AsusBridge.kext`:** A lightweight kernel extension that provides an authenticated, rate-limited user-client bridge between user-space macOS applications and ASUS ACPI/WMI (`ATKD.WMNB`).
* **`asusctl`:** Command-line tool for controlling battery limits, thermal profiles, fan curves, and power limits from Terminal or shell scripts.
* **`asusctl-diag`:** Read-only diagnostic inspector that validates your laptop's ACPI methods, WMI capabilities, and EC memory layout.
* **`asusctld`:** Background LaunchAgent that restores your settings upon macOS sleep/wake events and monitors AC power transitions.

---

## 🆕 What's New in v0.4.0

* **Kernel privilege separation (`AsusBridge.kext`):** read-only selectors (snapshot, telemetry, DSTS probes, EC state, curve reads) are available to any local user process, while all hardware writes require admin/root or the default-enabled `asusbridge_allow_user_writes` boot-arg (`=0` enforces admin-only). All write selectors are additionally rate-limited (100 ms floor) with strict buffer validation.
* **Zero-polling daemon (`asusctld`):** AC/Battery profile switching now uses `IOPSNotificationCreateRunLoopSource` (IOKit.ps) and wake restoration uses `NSWorkspace.didWakeNotification` — instantaneous, ~0 idle CPU wakeups (replaced the 0.5 s polling timer).
* **Live IPC sync:** `asusctl`, `asusctld`, and `ASUSControlApp` stay instantly in sync via `DistributedNotificationCenter` (`org.asuscontrol.settingsChanged`) on top of atomic `SettingsStore` persistence.
* **Dynamic multi-model capability resolver:** board/product identity is read from `IOPlatformExpertDevice` and matched by `CapabilityMatrixResolver` — FX707ZM remains the Tier-1 verified profile; TUF `FA507`/`FX507` and ROG Zephyrus/Strix resolve to Tier-2 (pending a read-only DSTS probe); unknown boards fall back to telemetry-only with all writes disabled.
* **Optional OpenCore helper:** `Extras/SSDT-ASUS-ATKD.dsl` (inert, reference-only) for builds whose OEM DSDT gates the ATKD WMI device.
* **Automated unit tests:** `swift test` now runs in CI (`Tests/ASUSControlCoreTests/`) covering ABI struct layouts, fan-curve guardrails, settings serialization, and capability matching; release packages include `SHA256SUMS.txt`.

---

## 🚀 Installation & Setup

### Prerequisites
1. **OpenCore Bootloader** properly configured for your ASUS laptop.
2. Root / Administrator privileges on macOS.
3. Developer Mode or AuxKC extension approval enabled (standard for Hackintosh setups).

---

### Step 1: Download the Latest Release
Download the latest `ASUSControl-Release.zip` from the [GitHub Releases](https://github.com/ixboss/asus-control-macos/releases) page.

Unzip the package. You will find:
* `ASUSControl.app`
* `AsusBridge.kext`
* `asusctl`
* `asusctl-diag`

---

### Step 2: Install the Application & CLI Tools

Drag `ASUSControl.app` into your `/Applications` folder, then install the CLI binaries to `/usr/local/bin`:

```bash
# Copy CLI tools to your PATH
sudo cp /Applications/ASUSControl.app/Contents/MacOS/asusctl /usr/local/bin/
sudo cp /Applications/ASUSControl.app/Contents/MacOS/asusctl-diag /usr/local/bin/

# Remove macOS quarantine attribute (if downloaded via browser)
sudo xattr -cr /Applications/ASUSControl.app
```

---

### Step 3: Install `AsusBridge.kext`

`AsusBridge.kext` can be loaded either through your OpenCore EFI (recommended) or via macOS Auxiliary Kernel Collections:

#### Method A: OpenCore EFI (Recommended for Permanent Stability)
1. Copy `AsusBridge.kext` to your EFI partition:
   ```
   EFI/OC/Kexts/AsusBridge.kext
   ```
2. Add `AsusBridge.kext` to your OpenCore `config.plist` under `Kernel -> Add` (ensuring `Enabled = true`).
3. Reboot your system.

#### Method B: Auxiliary Kernel Collection (Direct macOS Load)
```bash
sudo mkdir -p "/Library/Application Support/ASUSControl"
sudo cp -R build/kext/AsusBridge.kext "/Library/Application Support/ASUSControl/"
sudo chown -R root:wheel "/Library/Application Support/ASUSControl/AsusBridge.kext"
sudo chmod -R 755 "/Library/Application Support/ASUSControl/AsusBridge.kext"
sudo kmutil load --bundle-path "/Library/Application Support/ASUSControl/AsusBridge.kext"
```
*(If prompted by macOS, go to **System Settings -> Privacy & Security**, click **Allow** for developer `AsusBridge`, and restart your machine).*

---

## 🛠️ CLI Usage Guide (`asusctl`)

For automation, headless environments, or terminal enthusiasts:

```bash
# View complete live status (battery, profile, fans, power limits)
asusctl status

# Set battery charge limit (preserves battery lifespan)
asusctl battery limit 60
asusctl battery limit 80
asusctl battery limit 100

# Switch thermal performance profile
asusctl profile silent
asusctl profile balanced
asusctl profile turbo

# Set CPU Power Limits (Intel Alder Lake)
asusctl ppt set 45 65     # PL1 = 45W (Sustained), PL2 = 65W (Burst)
asusctl ppt reset          # Reset to profile default

# Read live 8-point fan curves
asusctl fan curves

# Reset fan control back to automatic firmware management
asusctl fan reset all
```

---

## 🔍 Hardware Diagnostic Tool (`asusctl-diag`)

To verify your laptop's ACPI methods and check compatibility:

```bash
# Run complete hardware diagnostic report (JSON)
asusctl-diag

# Probe live kernel bridge telemetry
asusctl-diag --bridge-probe
```

---

## ❓ Troubleshooting & Known Quirks

### 1. "Application cannot be opened because developer cannot be verified"
Because this open-source build is ad-hoc signed, macOS Gatekeeper may block it upon first launch. Run:
```bash
sudo xattr -cr /Applications/ASUSControl.app
```

### 2. Physical Keyboard RGB Lighting on ASUS TUF (Alder Lake)
* **Status:** On ASUS TUF Gaming laptops (such as `FX707ZM`), the ACPI WMI backend successfully latches and reports RGB modes and colors in the Embedded Controller. However, the physical keyboard LED circuit is governed by the ASUS ATK platform power gate and internal USB controller.
* When booting macOS without Windows ASUS system services having initialized the hardware rail, the physical LED power rail remains unpowered by the BIOS. Battery, fan curves, CPU wattage limits, and thermal profiles remain 100% operational.

### 3. Fans Don't Spin Down Immediately After Profile Change
When switching to **Silent** mode, fan RPMs ramp down gradually as the CPU package temperature drops below the firmware curve threshold points. This is standard ASUS Embedded Controller behavior.

---

## 🤝 Contributing

Contributions, bug reports, and hardware dumps from other ASUS laptop models are welcome!

1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/NewAsusModel`).
3. Commit your Changes (`git commit -m 'Add support for ROG Zephyrus G14 WMI table'`).
4. Push to the Branch (`git push origin feature/NewAsusModel`).
5. Open a Pull Request.

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 📜 License

Distributed under the **BSD 3-Clause Clear License**. See [LICENSE](LICENSE) for more information.
