# Contributing to ASUS Control for macOS

Thank you for your interest in contributing to ASUS Control for macOS! This project is an open-source native macOS control suite and ACPI bridge for ASUS ROG & TUF gaming laptops running macOS Hackintosh.

## Table of Contents
- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Hardware Testing & DSTS Dumps](#hardware-testing--dsts-dumps)
  - [Submitting Pull Requests](#submitting-pull-requests)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [License](#license)

---

## Code of Conduct
We are committed to providing a friendly, safe, and welcoming environment for all contributors, regardless of experience level, background, or identity. Please be respectful and constructive in all communications.

---

## How Can I Contribute?

### Reporting Bugs
If you encounter a bug, crash, or unexpected behavior:
1. Search existing [GitHub Issues](https://github.com/ixboss/asus-control-macos/issues) to ensure it hasn't already been reported.
2. If opening a new issue, include:
   - **Laptop Model:** (e.g., ASUS TUF Gaming F17 FX707ZM)
   - **BIOS Version:** (e.g., FX707ZM.316)
   - **macOS Version:** (e.g., macOS Sonoma 14.5, Sequoia 15.1)
   - **OpenCore Version & ACPI Configuration:** (Whether SSDT-AsusSMC or custom tables are present)
   - **Diagnostic Dump:** Output from `asusctl-diag --bridge-probe` or `asusctl info`.
   - **Kernel Logs:** Relevant output from `log show --predicate 'sender CONTAINS "AsusBridge"' --last 10m`.

### Suggesting Features
Feature requests are welcome! When proposing features, please keep in mind:
- ACPI features depend on ASUS WMI device availability (`ATK0100`, `ASUS010`, or `PNP0C14` via method `WMNB`).
- Include any known ACPI device IDs, methods, or Linux kernel equivalents (`asus-wmi` or `asusctl` source links).

### Hardware Testing & DSTS Dumps
Because ASUS implements different ACPI methods across different ROG/TUF model generations (Zephyrus, Strix, TUF Dash, TUF Gaming), diagnostic dumps from new models are extremely valuable:
```bash
# Run read-only diagnostic probe
asusctl-diag --bridge-probe
```
Submit your model and the probe output to a GitHub Issue or Discussion.

### Submitting Pull Requests
1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Make your changes and test thoroughly on your local machine.
3. Commit with clear, descriptive messages following [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat: Add support for ROG AniMe Matrix control`
   - `fix: Correct thermal profile index mapping for 2024 TUF models`
   - `docs: Update installation guide for macOS Sequoia`
4. Push to your fork and submit a Pull Request against `main`.

---

## Development Setup

### Prerequisites
- macOS 13.0+
- Xcode 15+ and Command Line Tools (`xcode-select --install`)
- Swift 5.9+ toolchain

### Building the Project
```bash
# Clone the repository
git clone https://github.com/ixboss/asus-control-macos.git
cd asus-control-macos

# Compile Swift targets (core, daemon, CLI, diag)
swift build

# Build the kernel extension
./scripts/build-kext.sh

# Build the native macOS menu bar & dashboard app
./scripts/build-app.sh
```

---

## Coding Standards
- **Swift:** Follow standard Swift API Design Guidelines. Keep code formatted, modular, and use async/await where applicable.
- **Kext (C++):** AsusBridge is an IOKit kernel extension.
  - Adhere to strict IOKit memory management rules (`OSSafeReleaseNULL`, retain counts).
  - Never link private KPIs (`com.apple.kpi.private`); only use public symbols (`com.apple.kpi.iokit`, `com.apple.kpi.libkern`, `com.apple.kpi.mach`).
  - Keep ACPI evaluations robust against missing devices and unexpected return object types.
- **English Language:** All user-facing strings, logs, UI labels, comments, and commit messages must be in English.

---

## License
By contributing to ASUS Control for macOS, you agree that your contributions will be licensed under the [BSD 3-Clause Clear License](LICENSE).
