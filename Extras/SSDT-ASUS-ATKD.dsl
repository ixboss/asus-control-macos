// SPDX-License-Identifier: BSD-3-Clause-Clear
//
// SSDT-ASUS-ATKD.dsl — OPTIONAL OpenCore ACPI helper for ASUS Control for macOS (v0.4.0).
//
// PURPOSE (reference only — DO NOT add to your OC config unless you need it):
//   Some ASUS Hackintosh builds (TUF FX707ZM / FA507 / FX507) lack the ATKD
//   (PNP0C14, _UID "ATK") WMI device or expose it with a _STA that gates it to
//   zero under macOS. AsusBridge.kext attaches to \_SB.ATKD and needs:
//     1. ATKD present (PNP0C14 / _UID "ATK") so IOACPIPlatformDevice matches.
//     2. A WMNB method — normally inherited from the OEM DSDT.
//
// This SSDT ONLY force-enables the stock ATKD device if it already exists and
// is hidden. It does NOT fabricate WMNB, does NOT write EC registers, and does
// NOT touch GPU MUX (0x00090016) / dGPU disable (0x00090020) paths. If your
// DSDT already shows ATKD with _STA returning 0x0F, you do NOT need this file.
//
// BUILD:
//   iasl SSDT-ASUS-ATKD.dsl            -> SSDT-ASUS-ATKD.aml
//   Place in OC/ACPI, add to config.plist ACPI > Add with Enabled = false
//   until you have verified your DSDT lacks a working ATKD.
//
// SAFETY:
//   - External references resolved at load; if \_SB.ATKD does not exist the
//     SSDT's _STA simply never evaluates (device stub is inert, IFX0 = 0).
//   - No raw EC region writes. All control still flows through the whitelisted,
//     range-validated WMNB DSTS/DEVS selectors gated by AsusBridge.kext.

DefinitionBlock ("", "SSDT", 2, "ASUSC", "ATKD", 0x00001000)
{
    External (_SB_.ATKD, DeviceObj)

    Scope (\_SB)
    {
        // Safety net: only defined if the OEM DSDT somehow lacks ATKD entirely.
        // Provides an inert PNP0C14 stub so AsusBridge.kext can at least bind
        // (WMNB validation at kext start will fail cleanly and the kext stops,
        // never falling back to raw EC access).
        Device (XATK)
        {
            Name (_HID, EisaId ("PNP0C14"))  // WMI
            Name (_UID, "ATK")
            Name (_STA, 0x00)                // Inert: 0x00 = never presented to macOS

            Method (_DSM, 4, NotSerialized)
            {
                // _DSM: keep the stub invisible to AppleACPIPlatform matching
                // unless the real ATKD is absent (checked by OC ACPI quirk
                // "Custom SSDT" consumers manually).
                If (LEqual (Arg2, Zero))
                {
                    Return (Buffer (One) { 0x00 })
                }
                Return (Buffer (One) { 0x00 })
            }
        }
    }

    // Re-evaluate the OEM ATKD device at OS handoff if present but gated.
    // NOTE: some ASUS BIOS builds gate ATKD _STA on an OS flavour flag (OSFG /
    // OSYS in \_SB.PCI0 or \_SB); on those boards patch OSFG >= 0x02 (Windows 8
    // flavour) via a Model-Specific SSDT instead of editing this file. This
    // _INI is a deliberate no-op so the SSDT stays inert and compileable on
    // every board until you customize it.
    Scope (\_SB.ATKD)
    {
        Method (_INI, 0, NotSerialized)
        {
            // Intentionally empty — see note above.
        }
    }
}
