// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 ASUS Control for macOS Contributors
//
// Phase 2-6 ABI (v2) for AsusBridge.kext on ASUS TUF Gaming F17 (FX707ZM).
// Provides read-only telemetry + strictly range-validated, whitelisted DEVS control selectors.

#ifndef ASUS_BRIDGE_ABI_H
#define ASUS_BRIDGE_ABI_H

#include <stdint.h>

#define ASUS_BRIDGE_SERVICE_NAME "AsusBridge"
#define ASUS_BRIDGE_ABI_VERSION  2u

// IOConnectCallMethod selectors
enum {
    // Out: AsusBridgeSnapshot (structure output)
    kAsusBridgeSelectorGetSnapshot       = 0,

    // In: scalar[0] = fanIndex (0 = CPU 0x00110024, 1 = GPU 0x00110025),
    //     scalar[1] = profileIndex (0 = Balanced/Performance, 1 = Turbo, 2 = Silent)
    // Out: AsusBridgeFanCurve (structure output, 16 bytes: 8 temps °C + 8 duty %)
    kAsusBridgeSelectorReadFanCurve      = 1,

    // In: scalar[0] = whitelisted WMI device ID for single-shot DSTS read probe
    // Out: scalar[0] = raw 32-bit DSTS return value, scalar[1] = evaluation status (1 = ok, 0 = failed)
    kAsusBridgeSelectorReadSingleDSTS    = 2,

    // In: scalar[0] = charge limit percentage (60..100)
    // Out: scalar[0] = raw DEVS return value
    kAsusBridgeSelectorSetChargeLimit    = 3,

    // In: scalar[0] = thermal profile (0 = Balanced/Performance, 1 = Turbo, 2 = Silent)
    // Out: scalar[0] = raw DEVS return value
    kAsusBridgeSelectorSetThermalProfile = 4,

    // In: scalar[0] = fanIndex (0 = CPU 0x00110024, 1 = GPU 0x00110025),
    //     scalar[1] = resetToAuto (1 = reset EC0.FMAE to 0, 0 = apply AsusBridgeFanCurve structureInput)
    //     structureInput = AsusBridgeFanCurve (16 bytes)
    kAsusBridgeSelectorWriteFanCurve     = 5,

    // In: scalar[0] = pl1SPLWatts (15..90W AC / 15..45W Batt),
    //     scalar[1] = pl2SPPTWatts (25..115W AC / 25..60W Batt)
    // Out: scalar[0] = raw PL1 DEVS return, scalar[1] = raw PL2 DEVS return
    kAsusBridgeSelectorSetPPTLimits      = 6,

    // In: scalar[0] = mode (0=Static, 1=Breathe, 2=ColorCycle, 3=Strobe),
    //     scalar[1] = r (0..255), scalar[2] = g (0..255), scalar[3] = b (0..255),
    //     scalar[4] = speed (0=Slow, 1=Medium, 2=Fast), scalar[5] = flags (0..0xFF, default 0x0F)
    // Out: scalar[0] = raw 0x00100056 return, scalar[1] = raw 0x00100057 return
    kAsusBridgeSelectorSetTufRGB         = 7,

    // In: scalar[0] = whitelisted SKEY / hotkey code (0xC4, 0xC5, 0xB3, 0xAE, 0x10, 0x20, 0x86, 0x87)
    // Out: scalar[0] = raw DEVS return
    kAsusBridgeSelectorTriggerSKEY       = 8,

    // In: scalar[0] = brightness level (0 = Off, 1 = Low, 2 = Medium, 3 = High)
    // Out: scalar[0] = raw DEVS(0x00050021, 0x80 | level) return, scalar[1] = raw DSTS(0x00050021) readback
    kAsusBridgeSelectorSetKbdBrightness  = 9,

    // In: none
    // Out: AsusBridgeECState (structure output, 64 bytes: live hardware readback from EC0 ERAM/ERM2 + WMI DSTS)
    kAsusBridgeSelectorGetECState        = 10,
};

// WMNB Method IDs (ASCII little-endian fourcc)
#define ASUS_WMI_METHOD_INIT 0x54494E49u // "INIT"
#define ASUS_WMI_METHOD_SFUN 0x4E554653u // "SFUN"
#define ASUS_WMI_METHOD_DSTS 0x53545344u // "DSTS"
#define ASUS_WMI_METHOD_DEVS 0x53564544u // "DEVS"

#define ASUS_WMI_UNSUPPORTED  0xFFFFFFFEu
#define ASUS_WMI_DSTS_PRESENT 0x00010000u

// FX707ZM Verified WMI Device IDs (from FX707ZM.316 DSDT.aml)
#define FX707ZM_DEV_CPU_TEMP    0x00120094u // DSTS -> EC0.CTMP + 0x10000 (offset 0x6aef1)
#define FX707ZM_DEV_CPU_FAN     0x00110013u // DSTS -> CPU Fan RPM (offset 0x6ad55)
#define FX707ZM_DEV_GPU_FAN     0x00110014u // DSTS -> GPU Fan RPM (offset 0x6addc)
#define FX707ZM_DEV_CPU_CURVE   0x00110024u // DSTS/DEVS -> EC0.CFCV / EC0.SFTC (offset 0x6b003 / 0x6b6c2)
#define FX707ZM_DEV_GPU_CURVE   0x00110025u // DSTS/DEVS -> EC0.GFCV / EC0.SFTG (offset 0x6b06a / 0x6b70a)
#define FX707ZM_DEV_PPT_PL2     0x001200A0u // DSTS/DEVS -> EC0.PL2V (offset 0x6b1c0 / 0x6b77c)
#define FX707ZM_DEV_PPT_PL1     0x001200A3u // DSTS/DEVS -> EC0.PL1V (offset 0x6b1f6 / 0x6b7c7)
#define FX707ZM_DEV_GPU_MUX     0x00090016u // DSTS -> DGPM + 0x10000 (offset 0x6b26c) [READ-ONLY]
#define FX707ZM_DEV_DGPU_STATE  0x00090020u // DSTS -> CUMA + 0x10000 (offset 0x6b29a) [READ-ONLY]
#define FX707ZM_DEV_KBD_BL      0x0010005Bu // DSTS -> EC0.KBLS | 0x10000 (offset 0x6ad33)
#define FX707ZM_DEV_SKEY        0x00100021u // DEVS -> EC0.SKEY (offset 0x6b329)
#define FX707ZM_DEV_BLCT        0x00050011u // DSTS -> BLCT + 0x10000

// FX707ZM SMM/SMI Delegated Device IDs (WCHK -> W15H)
#define FX707ZM_DEV_KBD_BRT     0x00050021u // TUF Keyboard Backlight Brightness (0x80 | 0..3) via W15H
#define FX707ZM_DEV_CHARGE_LIM  0x00120057u // EC0.RSOC via W15H & EC0.SRSC
#define FX707ZM_DEV_THRP_PROF   0x00120075u // EC0.THRP via W15H (0=Balanced, 1=Turbo, 2=Silent)
#define FX707ZM_DEV_TUF_RGB_1   0x00100056u // TUF RGB mode/color/speed via W15H
#define FX707ZM_DEV_TUF_RGB_2   0x00100057u // TUF RGB state/save via W15H
#define FX707ZM_DEV_TUF_RGB_3   0x0010005Au // TUF RGB mode2 fallback via W15H

// FX707ZM Embedded Controller MMIO Regions (from FX707ZM.316 DSDT.aml)
#define FX707ZM_EC_ERAM_PHYS    0xFE108300ULL
#define FX707ZM_EC_ERM2_PHYS    0xFE108B00ULL

#pragma pack(push, 4)
typedef struct AsusBridgeSnapshot {
    uint32_t abiVersion;            // [0]  ASUS_BRIDGE_ABI_VERSION (2)
    uint32_t initRaw;               // [1]  WMNB("INIT") return value at kext start
    uint32_t sfunRaw;               // [2]  WMNB("SFUN") supported function bitmask
    uint32_t onACPower;             // [3]  ACAD._PSR (1 = AC, 0 = Battery)
    uint32_t ecOk;                  // [4]  EC0.ECOK (1 = EC region ready)
    uint32_t cpuTempCelsius;        // [5]  Decoded from 0x00120094 (raw & 0xFFFF)
    uint32_t cpuTempRawDSTS;        // [6]  Raw 0x00120094 DSTS
    uint32_t cpuFanRPM;             // [7]  Decoded from 0x00110013 ((raw & 0xFFFF) * 100)
    uint32_t cpuFanRawDSTS;         // [8]  Raw 0x00110013 DSTS
    uint32_t gpuFanRPM;             // [9]  Decoded from 0x00110014 ((raw & 0xFFFF) * 100)
    uint32_t gpuFanRawDSTS;         // [10] Raw 0x00110014 DSTS
    uint32_t muxStateRawDSTS;       // [11] Raw 0x00090016 DSTS (0x10000 = Ultimate, 0x10001 = Optimus/Standard)
    uint32_t dgpuStateRawDSTS;      // [12] Raw 0x00090020 DSTS
    uint32_t pptPL1RawDSTS;         // [13] Raw 0x001200A3 DSTS
    uint32_t pptPL2RawDSTS;         // [14] Raw 0x001200A0 DSTS
    uint32_t kbdBacklightRawDSTS;   // [15] Raw 0x0010005B DSTS (EC0.KBLS | 0x10000)
    uint32_t hotkeySequence;        // [16] Count of ATKD / EDP1 notifications received
    uint32_t lastHotkeyCode;        // [17] Last ATKD _WED(0xFF) or EDP1 (0x86/0x87) notification code
    uint32_t currentChargeLimit;    // [18] Active charge limit % (60..100, default 100)
    uint32_t currentThermalProfile; // [19] Active thermal profile (0=Balanced, 1=Turbo, 2=Silent)
    uint32_t customFanActive;       // [20] Bitmask: bit 0 = CPU custom curve active, bit 1 = GPU custom curve active
    uint32_t currentPL1Watts;       // [21] Active PL1 (SPL) in Watts (0 = firmware default)
    uint32_t currentPL2Watts;       // [22] Active PL2 (SPPT) in Watts (0 = firmware default)
    uint32_t currentKbdBrightness;  // [23] Active keyboard backlight level (0..3)
    uint32_t currentRGBMode;        // [24] Active TUF RGB mode (0=Static, 1=Breathe, 2=ColorCycle, 3=Strobe)
    uint32_t currentRGBColorPacked; // [25] Active TUF RGB color ((R << 16) | (G << 8) | B)
    uint32_t currentRGBSpeed;       // [26] Active TUF RGB speed (0=Slow, 1=Medium, 2=Fast)
} AsusBridgeSnapshot;

typedef struct AsusBridgeFanCurve {
    uint8_t temperatures[8];        // 8 temperature points in °C (CTP0..7 / GTP0..7)
    uint8_t duties[8];              // 8 fan duty points in % or raw EC scale (SCT0..7 / SGT0..7)
} AsusBridgeFanCurve;

typedef struct AsusBridgeECState {
    uint32_t ecMappedOK;            // [0]  1 if ERAM (0xFE108300) & ERM2 (0xFE108B00) are mapped
    uint32_t eramFTBL;              // [1]  ERAM[0x06] Thermal Fan Table (0=Balanced, 1=Turbo, 2=Silent)
    uint32_t eramTHRP;              // [2]  ERAM[0xAE] Thermal Profile register
    uint32_t eramRSOC;              // [3]  ERAM[0x77] Battery Charge Limit % (RSOC, e.g. 60, 80, 100)
    uint32_t eramFMAE;              // [4]  (ERAM[0xCA] >> 2) & 1 Manual Fan Curve Active bit
    uint32_t eramKBLByte;           // [5]  ERAM[0x5B] Keyboard backlight bits (KBLO bit 4, KBHI bit 5)
    uint32_t eramTUFAByte;          // [6]  ERAM[0x5E] NOAC bit 0, TUFA bits 6..7
    uint32_t erm2KBLT;              // [7]  ERM2[0x24] Keyboard Light Control (KBLT)
    uint32_t erm2KBLM;              // [8]  ERM2[0x28] Keyboard RGB Mode (KBLM)
    uint32_t erm2KBSP;              // [9]  ERM2[0x22] Keyboard RGB Speed (KBSP)
    uint32_t erm2KBS1;              // [10] ERM2[0x2B] Keyboard RGB Red (KBS1)
    uint32_t erm2KBS2;              // [11] ERM2[0x2C] Keyboard RGB Green (KBS2)
    uint32_t erm2KBS3;              // [12] ERM2[0x2D] Keyboard RGB Blue (KBS3)
    uint32_t erm2KBBS;              // [13] ERM2[0x2E] Keyboard Backlight Brightness State (KBBS)
    uint32_t erm2PL1V;              // [14] ERM2[0x8E] CPU PL1 Watts in EC (PL1V)
    uint32_t erm2PL2V;              // [15] ERM2[0x8F] CPU PL2 Watts in EC (PL2V)
} AsusBridgeECState;
#pragma pack(pop)

#endif // ASUS_BRIDGE_ABI_H
