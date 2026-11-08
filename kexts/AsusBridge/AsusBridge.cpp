// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 ASUS Control for macOS Contributors
//
// AsusBridge.kext v0.2.0 (ABI v2) for ASUS TUF Gaming F17 (FX707ZM).
// Attaches to \_SB.ATKD (PNP0C14, _UID "ATK") and exposes an IOUserClient for:
//   - Whitelisted WMNB ("INIT", "SFUN", "DSTS") telemetry and 8-point fan curve reads
//   - Strictly range-validated WMNB ("DEVS") control selectors:
//       * Battery charge limit (60..100%) via 0x00120057 + EC0.SRSC
//       * Thermal profile (0=Balanced, 1=Turbo [AC only], 2=Silent) via 0x00120075
//       * 8-point CPU/GPU custom fan curves & auto reset via 0x00110024 / 0x00110025
//       * CPU Power Limits PL1 (0x001200A3 -> EC0.PL1V) & PL2 (0x001200A0 -> EC0.PL2V)
//       * TUF Gaming RGB lighting (0x00100056 & 0x00100057)
//       * Whitelisted hotkey / EC0.SKEY triggers (0x00100021)
//   - Listening to ATKD / PEGP.EDP1 hotkey notifications (including Fn+F7/F8 0x86/0x87)
//
// Strictly forbidden: GPU MUX (0x00090016) or dGPU disable (0x00090020) writes are NEVER exposed.

#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <kern/thread_call.h>
#include <stdarg.h>
#include <string.h>
#include "asus_bridge_abi.h"

#ifdef ASUS_BRIDGE_LIVE_CLASS
#define AsusBridge           AsusBridgeLive
#define AsusBridgeUserClient AsusBridgeLiveUserClient
#endif

class AsusBridge : public IOService {
    OSDeclareDefaultStructors(AsusBridge)

public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type,
                           OSDictionary *properties, IOUserClient **handler) override;

    IOACPIPlatformDevice *atkd = nullptr;
    IOACPIPlatformDevice *acad = nullptr;
    IOACPIPlatformDevice *ec0  = nullptr;
    IOACPIPlatformDevice *edp1 = nullptr;
    IOMemoryDescriptor *eramDesc = nullptr;
    IOMemoryMap        *eramMap  = nullptr;
    volatile uint8_t   *eramPtr  = nullptr;
    IOMemoryDescriptor *erm2Desc = nullptr;
    IOMemoryMap        *erm2Map  = nullptr;
    volatile uint8_t   *erm2Ptr  = nullptr;
    IOLock *lock = nullptr;

    uint32_t initRaw = 0;
    uint32_t sfunRaw = 0;
    uint32_t hotkeySequence = 0;
    uint32_t lastHotkeyCode = 0;

    // Active / cached control state
    uint32_t currentChargeLimit    = 100;
    uint32_t currentThermalProfile = 0;
    uint32_t customFanActive       = 0;
    uint32_t currentPL1Watts       = 0;
    uint32_t currentPL2Watts       = 0;
    uint32_t currentKbdBrightness  = 2;
    uint32_t currentRGBMode        = 0;
    uint32_t currentRGBColorPacked = 0x00FFAA00u; // Default TUF Amber
    uint32_t currentRGBSpeed       = 1;

    IONotifier *atkdNotifier = nullptr;
    IONotifier *edp1Notifier = nullptr;
    thread_call_t eventCall  = nullptr;

    char logBuf[1536] = {0};
    size_t logLen = 0;

    void logMsg(const char *fmt, ...) __attribute__((format(printf, 2, 3)));
    bool evaluateWMNBObject(uint32_t methodID, const uint32_t args[5], OSObject **resultOut);
    bool evaluateWMNBInt(uint32_t methodID, uint32_t arg0, uint32_t arg1, uint32_t *resultOut);
    bool evaluateWMNBInt5(uint32_t methodID, const uint32_t args[5], uint32_t *resultOut);
    bool evaluateDSTS(uint32_t devID, uint32_t *resultOut);
    bool isWhitelistedDSTS(uint32_t devID) const;

    void findCompanionACPIDevices();
    uint32_t readACPowerState();
    uint32_t readECOKState();

    void populateSnapshot(AsusBridgeSnapshot *out);
    void populateECState(AsusBridgeECState *out);
    IOReturn readFanCurve(uint32_t fanIndex, uint32_t profileIndex, AsusBridgeFanCurve *out);
    IOReturn readSingleWhitelistedDSTS(uint32_t devID, uint32_t *rawOut, uint32_t *okOut);

    // Phase 2-5 Validated Control Methods
    IOReturn setChargeLimit(uint32_t limit, uint32_t *rawOut);
    IOReturn setThermalProfile(uint32_t profile, uint32_t *rawOut);
    IOReturn writeFanCurve(uint32_t fanIndex, uint32_t resetToAuto, const AsusBridgeFanCurve *curve);
    IOReturn setPPTLimits(uint32_t pl1Watts, uint32_t pl2Watts, uint32_t *rawPL1Out, uint32_t *rawPL2Out);
    IOReturn setTufRGB(uint32_t mode, uint32_t r, uint32_t g, uint32_t b, uint32_t speed, uint32_t flags,
                       uint32_t *rawOut1, uint32_t *rawOut2);
    IOReturn setKbdBrightness(uint32_t level, uint32_t *rawDevsOut, uint32_t *rawDstsOut);
    IOReturn triggerSKEY(uint32_t keyCode, uint32_t *rawOut);

    void drainATKDEvents();
};

OSDefineMetaClassAndStructors(AsusBridge, IOService)

static IOACPIPlatformDevice *findACPIDeviceByName(const char *targetName)
{
    const IORegistryPlane *acpiPlane = IORegistryEntry::getPlane("IOACPIPlane");
    if (!acpiPlane) return nullptr;
    IORegistryEntry *root = IORegistryEntry::fromPath("/", acpiPlane);
    if (!root) return nullptr;

    IOACPIPlatformDevice *found = nullptr;
    IORegistryIterator *iter = IORegistryIterator::iterateOver(root, acpiPlane, kIORegistryIterateRecursively);
    if (iter) {
        while (IORegistryEntry *entry = iter->getNextObject()) {
            IOACPIPlatformDevice *dev = OSDynamicCast(IOACPIPlatformDevice, entry);
            if (!dev) continue;
            const char *name = dev->getName(acpiPlane);
            if (name && strcmp(name, targetName) == 0) {
                dev->retain();
                found = dev;
                break;
            }
        }
        iter->release();
    }
    root->release();
    return found;
}

void AsusBridge::logMsg(const char *fmt, ...)
{
    char line[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);

    IOLog("AsusBridge: %s\n", line);

    size_t n = strlen(line);
    if (logLen + n + 2 >= sizeof(logBuf)) {
        size_t cut = 0;
        while (cut < logLen && (logLen - cut) + n + 2 >= sizeof(logBuf)) {
            while (cut < logLen && logBuf[cut] != ';') cut++;
            if (cut < logLen) cut++;
        }
        memmove(logBuf, logBuf + cut, logLen - cut);
        logLen -= cut;
    }
    memcpy(logBuf + logLen, line, n);
    logLen += n;
    logBuf[logLen++] = ';';
    logBuf[logLen] = '\0';
    setProperty("asus-bridge-log", logBuf);
}

// FX707ZM DSDT WMNB begins with CreateDWordField(Arg2, 0x10, IIA4), requiring a 20-byte (5-DWORD) buffer.
bool AsusBridge::evaluateWMNBObject(uint32_t methodID, const uint32_t args[5], OSObject **resultOut)
{
    if (!atkd) return false;
    OSNumber *inst = OSNumber::withNumber(0ull, 32);
    OSNumber *mid  = OSNumber::withNumber((unsigned long long)methodID, 32);
    OSData   *buf  = OSData::withBytes(args, 5 * sizeof(uint32_t));
    bool ok = false;

    if (inst && mid && buf) {
        OSObject *params[3] = { inst, mid, buf };
        ok = (atkd->evaluateObject("WMNB", resultOut, params, 3) == kIOReturnSuccess);
    }
    if (inst) inst->release();
    if (mid)  mid->release();
    if (buf)  buf->release();
    return ok;
}

bool AsusBridge::evaluateWMNBInt5(uint32_t methodID, const uint32_t args[5], uint32_t *resultOut)
{
    OSObject *obj = nullptr;
    bool ok = evaluateWMNBObject(methodID, args, &obj);
    OSNumber *num = obj ? OSDynamicCast(OSNumber, obj) : nullptr;
    if (num) {
        if (resultOut) *resultOut = num->unsigned32BitValue();
        obj->release();
        return ok;
    }
    OSData *data = obj ? OSDynamicCast(OSData, obj) : nullptr;
    if (data && data->getLength() >= 7 && args[0] == FX707ZM_DEV_KBD_BL) {
        const uint8_t *b = (const uint8_t *)data->getBytesNoCopy();
        // EC0.KBLS() DUBF: b[0]=1, b[1]=KBLM(mode), b[2..4]=RGB, b[5]=KBSP(speed), b[6]=KBBS(brightness)
        uint32_t packed = ASUS_WMI_DSTS_PRESENT | ((uint32_t)(b[1] & 0x0Fu) << 8) | (uint32_t)(b[6] & 0x0Fu);
        if (resultOut) *resultOut = packed;
        obj->release();
        return ok;
    }
    if (resultOut) *resultOut = 0;
    if (obj) obj->release();
    return false;
}

bool AsusBridge::evaluateWMNBInt(uint32_t methodID, uint32_t arg0, uint32_t arg1, uint32_t *resultOut)
{
    uint32_t args[5] = { arg0, arg1, 0, 0, 0 };
    return evaluateWMNBInt5(methodID, args, resultOut);
}

bool AsusBridge::evaluateDSTS(uint32_t devID, uint32_t *resultOut)
{
    uint32_t val = 0;
    bool ok = evaluateWMNBInt(ASUS_WMI_METHOD_DSTS, devID, 0, &val);
    if (resultOut) *resultOut = val;
    return ok && val != ASUS_WMI_UNSUPPORTED && val != ~0u;
}

bool AsusBridge::isWhitelistedDSTS(uint32_t devID) const
{
    switch (devID) {
    case FX707ZM_DEV_CPU_TEMP:
    case FX707ZM_DEV_CPU_FAN:
    case FX707ZM_DEV_GPU_FAN:
    case FX707ZM_DEV_CPU_CURVE:
    case FX707ZM_DEV_GPU_CURVE:
    case FX707ZM_DEV_PPT_PL2:
    case FX707ZM_DEV_PPT_PL1:
    case FX707ZM_DEV_GPU_MUX:
    case FX707ZM_DEV_DGPU_STATE:
    case FX707ZM_DEV_KBD_BL:
    case FX707ZM_DEV_KBD_BRT:
    case FX707ZM_DEV_BLCT:
    case FX707ZM_DEV_CHARGE_LIM:
    case FX707ZM_DEV_THRP_PROF:
    case FX707ZM_DEV_TUF_RGB_1:
    case FX707ZM_DEV_TUF_RGB_2:
    case FX707ZM_DEV_TUF_RGB_3:
        return true;
    default:
        return false;
    }
}

void AsusBridge::findCompanionACPIDevices()
{
    acad = findACPIDeviceByName("ACAD");
    ec0  = findACPIDeviceByName("EC0");
    edp1 = findACPIDeviceByName("EDP1");
    logMsg("companion ACPI: ACAD=%s EC0=%s EDP1=%s",
           acad ? "yes" : "no", ec0 ? "yes" : "no", edp1 ? "yes" : "no");
}

uint32_t AsusBridge::readACPowerState()
{
    if (!acad) return 0;
    UInt32 psr = 0;
    if (acad->evaluateInteger("_PSR", &psr) == kIOReturnSuccess) {
        return psr != 0 ? 1u : 0u;
    }
    return 0;
}

uint32_t AsusBridge::readECOKState()
{
    if (!ec0) return 0;
    UInt32 ecok = 0;
    if (ec0->evaluateInteger("ECOK", &ecok) == kIOReturnSuccess) {
        return ecok;
    }
    return 0;
}

void AsusBridge::populateSnapshot(AsusBridgeSnapshot *out)
{
    memset(out, 0, sizeof(AsusBridgeSnapshot));
    out->abiVersion = ASUS_BRIDGE_ABI_VERSION;
    out->initRaw    = initRaw;
    out->sfunRaw    = sfunRaw;
    out->onACPower  = readACPowerState();
    out->ecOk       = readECOKState();

    uint32_t raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_CPU_TEMP, &raw)) {
        out->cpuTempRawDSTS = raw;
        if (raw & ASUS_WMI_DSTS_PRESENT) {
            out->cpuTempCelsius = raw & 0xFFFFu;
        }
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_CPU_FAN, &raw)) {
        out->cpuFanRawDSTS = raw;
        if (raw & ASUS_WMI_DSTS_PRESENT) {
            out->cpuFanRPM = (raw & 0xFFFFu) * 100u;
        }
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_GPU_FAN, &raw)) {
        out->gpuFanRawDSTS = raw;
        if (raw & ASUS_WMI_DSTS_PRESENT) {
            out->gpuFanRPM = (raw & 0xFFFFu) * 100u;
        }
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_GPU_MUX, &raw)) {
        out->muxStateRawDSTS = raw;
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_DGPU_STATE, &raw)) {
        out->dgpuStateRawDSTS = raw;
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_PPT_PL1, &raw)) {
        out->pptPL1RawDSTS = raw;
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_PPT_PL2, &raw)) {
        out->pptPL2RawDSTS = raw;
    }

    raw = 0;
    if (evaluateDSTS(FX707ZM_DEV_KBD_BRT, &raw) && (raw & ASUS_WMI_DSTS_PRESENT)) {
        out->kbdBacklightRawDSTS = raw;
        currentKbdBrightness = raw & 0x3u;
    } else if (evaluateDSTS(FX707ZM_DEV_KBD_BL, &raw)) {
        out->kbdBacklightRawDSTS = raw;
        if (raw & ASUS_WMI_DSTS_PRESENT) {
            currentKbdBrightness = raw & 0x3u;
        }
    }

    if (eramPtr) {
        uint8_t rsoc = eramPtr[0x77];
        if (rsoc >= 60 && rsoc <= 100) {
            currentChargeLimit = rsoc;
        }
        uint8_t ftbl = eramPtr[0x06];
        if (ftbl <= 2) {
            currentThermalProfile = ftbl;
        }
    }

    out->hotkeySequence        = hotkeySequence;
    out->lastHotkeyCode        = lastHotkeyCode;
    out->currentChargeLimit    = currentChargeLimit;
    out->currentThermalProfile = currentThermalProfile;
    out->customFanActive       = customFanActive;
    out->currentPL1Watts       = currentPL1Watts;
    out->currentPL2Watts       = currentPL2Watts;
    out->currentKbdBrightness  = currentKbdBrightness;
    out->currentRGBMode        = currentRGBMode;
    out->currentRGBColorPacked = currentRGBColorPacked;
    out->currentRGBSpeed       = currentRGBSpeed;
}

void AsusBridge::populateECState(AsusBridgeECState *out)
{
    memset(out, 0, sizeof(AsusBridgeECState));
    if (eramPtr && erm2Ptr) {
        out->ecMappedOK   = 1u;
        out->eramFTBL     = eramPtr[0x06];
        out->eramTHRP     = eramPtr[0xAE];
        out->eramRSOC     = eramPtr[0x77];
        out->eramFMAE     = (eramPtr[0xCA] >> 2) & 0x1u;
        out->eramKBLByte  = eramPtr[0x5B];
        out->eramTUFAByte = eramPtr[0x5E];
        out->erm2KBSP     = erm2Ptr[0x22];
        out->erm2KBLT     = erm2Ptr[0x24];
        out->erm2KBLM     = erm2Ptr[0x28];
        out->erm2KBS1     = erm2Ptr[0x2B];
        out->erm2KBS2     = erm2Ptr[0x2C];
        out->erm2KBS3     = erm2Ptr[0x2D];
        out->erm2KBBS     = erm2Ptr[0x2E];
        out->erm2PL1V     = erm2Ptr[0x8E];
        out->erm2PL2V     = erm2Ptr[0x8F];
    }
}

IOReturn AsusBridge::readFanCurve(uint32_t fanIndex, uint32_t profileIndex, AsusBridgeFanCurve *out)
{
    if (fanIndex > 1 || profileIndex > 2 || !out) return kIOReturnBadArgument;
    uint32_t devID = (fanIndex == 0) ? FX707ZM_DEV_CPU_CURVE : FX707ZM_DEV_GPU_CURVE;
    uint32_t args[5] = { devID, profileIndex, 0, 0, 0 };
    OSObject *obj = nullptr;
    bool ok = evaluateWMNBObject(ASUS_WMI_METHOD_DSTS, args, &obj);
    OSData *data = obj ? OSDynamicCast(OSData, obj) : nullptr;
    IOReturn ret = kIOReturnIOError;
    if (ok && data && data->getLength() >= sizeof(AsusBridgeFanCurve)) {
        memcpy(out, data->getBytesNoCopy(), sizeof(AsusBridgeFanCurve));
        ret = kIOReturnSuccess;
    }
    if (obj) obj->release();
    return ret;
}

IOReturn AsusBridge::readSingleWhitelistedDSTS(uint32_t devID, uint32_t *rawOut, uint32_t *okOut)
{
    if (!isWhitelistedDSTS(devID)) return kIOReturnNotPermitted;
    uint32_t val = 0;
    bool ok = evaluateWMNBInt(ASUS_WMI_METHOD_DSTS, devID, 0, &val);
    if (rawOut) *rawOut = val;
    if (okOut)  *okOut  = ok ? 1u : 0u;
    logMsg("probe DSTS 0x%08x -> ok=%d val=0x%08x", devID, ok ? 1 : 0, val);
    return kIOReturnSuccess;
}

// -------------------------------------------------------------------------------------------------
// Phase 2-5 Validated Control Methods
// -------------------------------------------------------------------------------------------------

IOReturn AsusBridge::setChargeLimit(uint32_t limit, uint32_t *rawOut)
{
    if (limit < 60 || limit > 100) {
        logMsg("reject charge limit %u (allowed 60..100)", limit);
        return kIOReturnBadArgument;
    }
    uint32_t raw = 0;
    bool ok = evaluateWMNBInt(ASUS_WMI_METHOD_DEVS, FX707ZM_DEV_CHARGE_LIM, limit, &raw);

    // Also write EC0.ERAM.RSOC (offset 0x77) directly if mapped so EC hardware state is guaranteed
    if (eramPtr) {
        eramPtr[0x77] = (uint8_t)limit;
    }

    if (!ok || raw == ASUS_WMI_UNSUPPORTED) {
        logMsg("DEVS 0x00120057(%u) failed raw=0x%08x", limit, raw);
        return kIOReturnIOError;
    }
    uint32_t ecRsoc = eramPtr ? (uint32_t)eramPtr[0x77] : limit;
    currentChargeLimit = limit;
    setProperty("asus-charge-limit", currentChargeLimit, 32);
    setProperty("asus-ec-rsoc", ecRsoc, 32);
    if (rawOut) *rawOut = raw;
    logMsg("DEVS 0x00120057(%u%%) -> 0x%08x (EC0.RSOC=%u%%)", limit, raw, ecRsoc);
    return kIOReturnSuccess;
}

IOReturn AsusBridge::setThermalProfile(uint32_t profile, uint32_t *rawOut)
{
    if (profile > 2) {
        logMsg("reject thermal profile %u (allowed 0=Balanced, 1=Turbo, 2=Silent)", profile);
        return kIOReturnBadArgument;
    }
    if (profile == 1 && readACPowerState() == 0) {
        logMsg("reject Turbo profile (1) while on Battery power");
        return kIOReturnNotPermitted;
    }
    uint32_t raw = 0;
    bool ok = evaluateWMNBInt(ASUS_WMI_METHOD_DEVS, FX707ZM_DEV_THRP_PROF, profile, &raw);

    // Also update EC0.ERAM.FTBL (0x06) & THRP (0xAE) if mapped
    if (eramPtr) {
        eramPtr[0x06] = (uint8_t)profile;
        eramPtr[0xAE] = (uint8_t)profile;
    }

    if (!ok || raw == ASUS_WMI_UNSUPPORTED) {
        logMsg("DEVS 0x00120075(%u) failed raw=0x%08x", profile, raw);
        return kIOReturnIOError;
    }
    uint32_t ecFtbl = eramPtr ? (uint32_t)eramPtr[0x06] : profile;
    uint32_t ecThrp = eramPtr ? (uint32_t)eramPtr[0xAE] : profile;
    currentThermalProfile = profile;
    customFanActive = 0; // Firmware profile switch resets EC0.FMAE
    setProperty("asus-thermal-profile", currentThermalProfile, 32);
    setProperty("asus-ec-ftbl", ecFtbl, 32);
    setProperty("asus-ec-thrp", ecThrp, 32);
    if (rawOut) *rawOut = raw;
    logMsg("DEVS 0x00120075(profile=%u) -> 0x%08x (EC0.FTBL=%u THRP=%u)", profile, raw, ecFtbl, ecThrp);
    return kIOReturnSuccess;
}

IOReturn AsusBridge::writeFanCurve(uint32_t fanIndex, uint32_t resetToAuto, const AsusBridgeFanCurve *curve)
{
    if (fanIndex > 1) return kIOReturnBadArgument;
    uint32_t devID = (fanIndex == 0) ? FX707ZM_DEV_CPU_CURVE : FX707ZM_DEV_GPU_CURVE;

    if (resetToAuto != 0) {
        uint32_t args[5] = { devID, 0, 0, 0, 0 };
        uint32_t raw = 0;
        bool ok = evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, args, &raw);
        if (!ok || raw == ASUS_WMI_UNSUPPORTED) return kIOReturnIOError;
        customFanActive &= ~(1u << fanIndex);
        logMsg("DEVS 0x%08x reset auto fan -> 0x%08x", devID, raw);
        return kIOReturnSuccess;
    }

    if (!curve) return kIOReturnBadArgument;

    // Validate monotonic temperatures (20..105 °C) and monotonic duties (0..100 %, top point >= 40%)
    for (int i = 0; i < 8; i++) {
        uint8_t t = curve->temperatures[i];
        uint8_t d = curve->duties[i];
        if (t < 20 || t > 105 || d > 100) {
            logMsg("reject fan curve pt %d: t=%uC d=%u%%", i, t, d);
            return kIOReturnBadArgument;
        }
        if (i > 0) {
            if (t < curve->temperatures[i - 1] || d < curve->duties[i - 1]) {
                logMsg("reject non-monotonic fan curve at pt %d", i);
                return kIOReturnBadArgument;
            }
        }
    }
    if (curve->duties[7] < 40) {
        logMsg("reject fan curve: point 7 duty %u%% < 40%% safety floor", curve->duties[7]);
        return kIOReturnBadArgument;
    }

    uint32_t t0_3 = ((uint32_t)curve->temperatures[0]) |
                    ((uint32_t)curve->temperatures[1] << 8) |
                    ((uint32_t)curve->temperatures[2] << 16) |
                    ((uint32_t)curve->temperatures[3] << 24);
    uint32_t t4_7 = ((uint32_t)curve->temperatures[4]) |
                    ((uint32_t)curve->temperatures[5] << 8) |
                    ((uint32_t)curve->temperatures[6] << 16) |
                    ((uint32_t)curve->temperatures[7] << 24);
    uint32_t d0_3 = ((uint32_t)curve->duties[0]) |
                    ((uint32_t)curve->duties[1] << 8) |
                    ((uint32_t)curve->duties[2] << 16) |
                    ((uint32_t)curve->duties[3] << 24);
    uint32_t d4_7 = ((uint32_t)curve->duties[4]) |
                    ((uint32_t)curve->duties[5] << 8) |
                    ((uint32_t)curve->duties[6] << 16) |
                    ((uint32_t)curve->duties[7] << 24);

    uint32_t args[5] = { devID, t0_3, t4_7, d0_3, d4_7 };
    uint32_t raw = 0;
    bool ok = evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, args, &raw);
    if (!ok || raw == ASUS_WMI_UNSUPPORTED) {
        logMsg("DEVS 0x%08x write curve failed raw=0x%08x", devID, raw);
        return kIOReturnIOError;
    }
    customFanActive |= (1u << fanIndex);
    logMsg("DEVS 0x%08x write curve ok -> 0x%08x", devID, raw);
    return kIOReturnSuccess;
}

IOReturn AsusBridge::setPPTLimits(uint32_t pl1Watts, uint32_t pl2Watts, uint32_t *rawPL1Out, uint32_t *rawPL2Out)
{
    uint32_t onAC = readACPowerState();
    uint32_t maxPL1 = onAC ? 90u : 45u;
    uint32_t maxPL2 = onAC ? 115u : 60u;

    if (pl1Watts < 15 || pl1Watts > maxPL1 || pl2Watts < 25 || pl2Watts > maxPL2 || pl2Watts < pl1Watts) {
        logMsg("reject PPT PL1=%uW PL2=%uW (onAC=%u max=%u/%u)", pl1Watts, pl2Watts, onAC, maxPL1, maxPL2);
        return kIOReturnBadArgument;
    }

    // FX707ZM DSDT: 0x001200A3 -> EC0.PL1V (offset 0x6b7c7), 0x001200A0 -> EC0.PL2V (offset 0x6b77c)
    uint32_t r1 = 0, r2 = 0;
    bool ok1 = evaluateWMNBInt(ASUS_WMI_METHOD_DEVS, FX707ZM_DEV_PPT_PL1, pl1Watts, &r1);
    bool ok2 = evaluateWMNBInt(ASUS_WMI_METHOD_DEVS, FX707ZM_DEV_PPT_PL2, pl2Watts, &r2);
    if (!ok1 || !ok2 || r1 == ASUS_WMI_UNSUPPORTED || r2 == ASUS_WMI_UNSUPPORTED) {
        logMsg("DEVS PPT failed r1=0x%08x r2=0x%08x", r1, r2);
        return kIOReturnIOError;
    }
    currentPL1Watts = pl1Watts;
    currentPL2Watts = pl2Watts;
    setProperty("asus-pl1-watts", currentPL1Watts, 32);
    setProperty("asus-pl2-watts", currentPL2Watts, 32);
    if (rawPL1Out) *rawPL1Out = r1;
    if (rawPL2Out) *rawPL2Out = r2;
    logMsg("DEVS PPT PL1=%uW(0x%08x) PL2=%uW(0x%08x)", pl1Watts, r1, pl2Watts, r2);
    return kIOReturnSuccess;
}

IOReturn AsusBridge::setTufRGB(uint32_t mode, uint32_t r, uint32_t g, uint32_t b, uint32_t speed, uint32_t flags,
                               uint32_t *rawOut1, uint32_t *rawOut2)
{
    if (mode > 3 || r > 255 || g > 255 || b > 255 || speed > 2) {
        logMsg("reject TUF RGB mode=%u rgb=(%u,%u,%u) speed=%u", mode, r, g, b, speed);
        return kIOReturnBadArgument;
    }
    uint32_t speedByte = 0xEBu; // Medium
    if (speed == 0) speedByte = 0xE1u;      // Slow
    else if (speed == 2) speedByte = 0xF5u; // Fast

    // Step 1: Ensure TUF Keyboard RGB Power State (0x00100057) is enabled for Boot + Awake:
    // Linux asus-wmi & G-Helper format: 0xBD | (cmd << 8) | (stateFlags << 16)
    // cmd = 0x05 (apply + save), stateFlags = 0x0F (Boot + Awake enabled)
    uint32_t stateFlags = (flags == 0) ? 0x0Fu : (flags & 0xFFu);
    uint32_t stateWord  = 0xBDu | (0x05u << 8) | (stateFlags << 16);
    uint32_t argsState[5] = { FX707ZM_DEV_TUF_RGB_2, stateWord, 0, 0, 0 };
    uint32_t out2 = 0;
    bool ok2 = evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, argsState, &out2);

    // Step 2: Stage (0xB3) and Commit/Apply (0xB4) on 0x00100056 (and fallback 0x0010005A if needed)
    uint32_t word1B3 = 0xB3u | ((mode & 0xFFu) << 8) | ((r & 0xFFu) << 16) | ((g & 0xFFu) << 24);
    uint32_t word1B4 = 0xB4u | ((mode & 0xFFu) << 8) | ((r & 0xFFu) << 16) | ((g & 0xFFu) << 24);
    uint32_t word2   = (b & 0xFFu) | ((speedByte & 0xFFu) << 8);

    uint32_t argsB3[5] = { FX707ZM_DEV_TUF_RGB_1, word1B3, word2, 0, 0 };
    uint32_t argsB4[5] = { FX707ZM_DEV_TUF_RGB_1, word1B4, word2, 0, 0 };
    uint32_t outB3 = 0, outB4 = 0;
    bool okB3 = evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, argsB3, &outB3);
    bool okB4 = evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, argsB4, &outB4);

    if (!okB4 || outB4 != 1) {
        uint32_t args2B3[5] = { FX707ZM_DEV_TUF_RGB_3, word1B3, word2, 0, 0 };
        uint32_t args2B4[5] = { FX707ZM_DEV_TUF_RGB_3, word1B4, word2, 0, 0 };
        uint32_t fB3 = 0, fB4 = 0;
        evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, args2B3, &fB3);
        evaluateWMNBInt5(ASUS_WMI_METHOD_DEVS, args2B4, &fB4);
    }

    // Step 3: Mirror into EC0.ERM2 RGB fields (KBLM, KBS1..3, KBSP, KBLT) so EC0.KBLS readback is always in sync
    if (erm2Ptr) {
        erm2Ptr[0x28] = (uint8_t)(mode & 0xFFu);      // KBLM
        erm2Ptr[0x2B] = (uint8_t)(r & 0xFFu);         // KBS1
        erm2Ptr[0x2C] = (uint8_t)(g & 0xFFu);         // KBS2
        erm2Ptr[0x2D] = (uint8_t)(b & 0xFFu);         // KBS3
        erm2Ptr[0x22] = (uint8_t)(speedByte & 0xFFu); // KBSP
        if (r > 0 || g > 0 || b > 0) {
            erm2Ptr[0x24] = 0x01u;                    // KBLT
        }
    }

    if ((!okB3 && !okB4) || (outB3 == ASUS_WMI_UNSUPPORTED && outB4 == ASUS_WMI_UNSUPPORTED)) {
        logMsg("DEVS TUF RGB failed outB3=0x%08x outB4=0x%08x out2=0x%08x", outB3, outB4, out2);
        return kIOReturnIOError;
    }

    uint32_t out1 = (outB4 != 0 && outB4 != ASUS_WMI_UNSUPPORTED) ? outB4 : outB3;
    currentRGBMode        = mode;
    currentRGBColorPacked = ((r & 0xFFu) << 16) | ((g & 0xFFu) << 8) | (b & 0xFFu);
    currentRGBSpeed       = speed;
    setProperty("asus-rgb-mode", currentRGBMode, 32);
    setProperty("asus-rgb-color", currentRGBColorPacked, 32);
    setProperty("asus-rgb-speed", currentRGBSpeed, 32);
    if (rawOut1) *rawOut1 = out1;
    if (rawOut2) *rawOut2 = out2;
    logMsg("DEVS TUF RGB mode=%u #%02X%02X%02X speed=%u -> B3=0x%x B4=0x%x state=0x%x",
           mode, r, g, b, speed, outB3, outB4, out2);
    return kIOReturnSuccess;
}

IOReturn AsusBridge::setKbdBrightness(uint32_t level, uint32_t *rawDevsOut, uint32_t *rawDstsOut)
{
    if (level > 3) {
        logMsg("reject kbd brightness %u (allowed 0..3)", level);
        return kIOReturnBadArgument;
    }
    uint32_t param = 0x80u | (level & 0x7Fu);
    uint32_t rawDevs = 0;
    bool okDevs = evaluateWMNBInt(ASUS_WMI_METHOD_DEVS, FX707ZM_DEV_KBD_BRT, param, &rawDevs);

    // Also update ERM2.KBBS (0x2E) & ERAM[0x5B] KBLO/KBHI bits if mapped
    if (erm2Ptr) {
        erm2Ptr[0x2E] = (uint8_t)level;
        erm2Ptr[0x24] = (level > 0) ? 0x01u : 0x00u;
    }

    uint32_t rawDsts = 0;
    evaluateDSTS(FX707ZM_DEV_KBD_BRT, &rawDsts);

    currentKbdBrightness = level;
    setProperty("asus-kbd-brightness", currentKbdBrightness, 32);
    if (rawDevsOut) *rawDevsOut = rawDevs;
    if (rawDstsOut) *rawDstsOut = rawDsts;
    logMsg("DEVS 0x00050021(0x%02x, lvl=%u) -> devs=0x%08x dsts=0x%08x (ok=%d)",
           param, level, rawDevs, rawDsts, okDevs ? 1 : 0);
    return kIOReturnSuccess;
}

IOReturn AsusBridge::triggerSKEY(uint32_t keyCode, uint32_t *rawOut)
{
    switch (keyCode) {
    case 0xC4u: // Keyboard Backlight Up
    case 0xC5u: // Keyboard Backlight Down
    case 0xB3u: // Aura Mode Next
    case 0xAEu: // Fan / Performance Profile Cycle
    case 0x10u: // Display Brightness Down (ATKD)
    case 0x20u: // Display Brightness Up (ATKD)
        break;
    case 0x86u: // EDP1 Brightness Up notification
    case 0x87u: // EDP1 Brightness Down notification
        lastHotkeyCode = keyCode;
        hotkeySequence++;
        if (rawOut) *rawOut = 1u;
        logMsg("simulated EDP1 brightness event 0x%02x (seq=%u)", keyCode, hotkeySequence);
        return kIOReturnSuccess;
    default:
        return kIOReturnNotPermitted;
    }

    uint32_t raw = 0;
    bool ok = evaluateWMNBInt(ASUS_WMI_METHOD_DEVS, FX707ZM_DEV_SKEY, keyCode, &raw);
    if (!ok || raw == ASUS_WMI_UNSUPPORTED) {
        return kIOReturnIOError;
    }
    if (keyCode == 0xC4u && currentKbdBrightness < 3) currentKbdBrightness++;
    if (keyCode == 0xC5u && currentKbdBrightness > 0) currentKbdBrightness--;
    if (rawOut) *rawOut = raw;
    logMsg("DEVS SKEY(0x%02x) -> 0x%08x (kbdLvl=%u)", keyCode, raw, currentKbdBrightness);
    return kIOReturnSuccess;
}

void AsusBridge::drainATKDEvents()
{
    IOLockLock(lock);
    for (int i = 0; i < 16; i++) {
        OSNumber *arg = OSNumber::withNumber(0xFFull, 32);
        OSObject *params[1] = { arg };
        OSObject *obj = nullptr;
        IOReturn r = arg ? atkd->evaluateObject("_WED", &obj, params, 1) : kIOReturnNoMemory;
        if (arg) arg->release();
        OSNumber *num = obj ? OSDynamicCast(OSNumber, obj) : nullptr;
        uint64_t code = num ? num->unsigned64BitValue() : ~0ull;
        if (obj) obj->release();
        if (r != kIOReturnSuccess || code == 0 || code > 0xFFFFu) break;
        lastHotkeyCode = (uint32_t)code;
        hotkeySequence++;
        logMsg("ATKD _WED event 0x%02x (seq=%u)", lastHotkeyCode, hotkeySequence);
    }
    IOLockUnlock(lock);
}

static void atkdEventThread(thread_call_param_t p0, thread_call_param_t)
{
    AsusBridge *self = (AsusBridge *)p0;
    if (self) self->drainATKDEvents();
}

static IOReturn atkdInterestHandler(void *target, void *, UInt32 type, IOService *, void *arg, vm_size_t)
{
    AsusBridge *self = (AsusBridge *)target;
    if (self && type == kIOACPIMessageDeviceNotification && arg) {
        UInt32 notifyCode = *(UInt32 *)arg;
        if (notifyCode == 0xFF && self->eventCall) {
            thread_call_enter(self->eventCall);
        } else {
            IOLockLock(self->lock);
            self->lastHotkeyCode = notifyCode;
            self->hotkeySequence++;
            self->logMsg("ATKD direct notify 0x%02x (seq=%u)", notifyCode, self->hotkeySequence);
            IOLockUnlock(self->lock);
        }
    }
    return kIOReturnSuccess;
}

static IOReturn edp1InterestHandler(void *target, void *, UInt32 type, IOService *, void *arg, vm_size_t)
{
    AsusBridge *self = (AsusBridge *)target;
    if (self && type == kIOACPIMessageDeviceNotification && arg) {
        UInt32 notifyCode = *(UInt32 *)arg;
        IOLockLock(self->lock);
        self->lastHotkeyCode = notifyCode;
        self->hotkeySequence++;
        self->logMsg("PEGP.EDP1 brightness notify 0x%02x (seq=%u)", notifyCode, self->hotkeySequence);
        IOLockUnlock(self->lock);
    }
    return kIOReturnSuccess;
}

// -------------------------------------------------------------------------------------------------
// IOUserClient
// -------------------------------------------------------------------------------------------------
class AsusBridgeUserClient : public IOUserClient {
    OSDeclareDefaultStructors(AsusBridgeUserClient)

public:
    bool initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                            IOExternalMethodDispatch *dispatch, OSObject *target, void *reference) override;

private:
    AsusBridge *bridge = nullptr;
    bool isAuthorized = false;
};

OSDefineMetaClassAndStructors(AsusBridgeUserClient, IOUserClient)

bool AsusBridgeUserClient::initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties)
{
    if (!IOUserClient::initWithTask(owningTask, securityToken, type, properties)) return false;
    isAuthorized = (clientHasPrivilege(owningTask, kIOClientPrivilegeAdministrator) == kIOReturnSuccess) ||
                   (clientHasPrivilege(owningTask, kIOClientPrivilegeLocalUser) == kIOReturnSuccess);
    return true;
}

bool AsusBridgeUserClient::start(IOService *provider)
{
    bridge = OSDynamicCast(AsusBridge, provider);
    return bridge && IOUserClient::start(provider);
}

IOReturn AsusBridgeUserClient::clientClose()
{
    terminate();
    return kIOReturnSuccess;
}

IOReturn AsusBridgeUserClient::externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                              IOExternalMethodDispatch *, OSObject *, void *)
{
    if (!bridge || !args || !bridge->lock) return kIOReturnNotAttached;
    if (!isAuthorized) return kIOReturnNotPrivileged;

    switch (selector) {
    case kAsusBridgeSelectorGetSnapshot: {
        if (!args->structureOutput || args->structureOutputSize < sizeof(AsusBridgeSnapshot)) {
            return kIOReturnBadArgument;
        }
        AsusBridgeSnapshot snap;
        IOLockLock(bridge->lock);
        bridge->populateSnapshot(&snap);
        IOLockUnlock(bridge->lock);
        memcpy(args->structureOutput, &snap, sizeof(AsusBridgeSnapshot));
        args->structureOutputSize = sizeof(AsusBridgeSnapshot);
        return kIOReturnSuccess;
    }

    case kAsusBridgeSelectorReadFanCurve: {
        if (args->scalarInputCount != 2 || !args->structureOutput ||
            args->structureOutputSize < sizeof(AsusBridgeFanCurve)) {
            return kIOReturnBadArgument;
        }
        AsusBridgeFanCurve curve;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->readFanCurve((uint32_t)args->scalarInput[0],
                                          (uint32_t)args->scalarInput[1],
                                          &curve);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            memcpy(args->structureOutput, &curve, sizeof(AsusBridgeFanCurve));
            args->structureOutputSize = sizeof(AsusBridgeFanCurve);
        }
        return r;
    }

    case kAsusBridgeSelectorReadSingleDSTS: {
        if (args->scalarInputCount != 1 || !args->scalarOutput || args->scalarOutputCount < 2) {
            return kIOReturnBadArgument;
        }
        uint32_t raw = 0, ok = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->readSingleWhitelistedDSTS((uint32_t)args->scalarInput[0], &raw, &ok);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = raw;
            args->scalarOutput[1] = ok;
        }
        return r;
    }

    case kAsusBridgeSelectorSetChargeLimit: {
        if (args->scalarInputCount != 1 || !args->scalarOutput || args->scalarOutputCount < 1) {
            return kIOReturnBadArgument;
        }
        uint32_t raw = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->setChargeLimit((uint32_t)args->scalarInput[0], &raw);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = raw;
        }
        return r;
    }

    case kAsusBridgeSelectorSetThermalProfile: {
        if (args->scalarInputCount != 1 || !args->scalarOutput || args->scalarOutputCount < 1) {
            return kIOReturnBadArgument;
        }
        uint32_t raw = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->setThermalProfile((uint32_t)args->scalarInput[0], &raw);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = raw;
        }
        return r;
    }

    case kAsusBridgeSelectorWriteFanCurve: {
        if (args->scalarInputCount != 2) return kIOReturnBadArgument;
        uint32_t fanIdx = (uint32_t)args->scalarInput[0];
        uint32_t resetToAuto = (uint32_t)args->scalarInput[1];
        const AsusBridgeFanCurve *curvePtr = nullptr;
        if (resetToAuto == 0) {
            if (!args->structureInput || args->structureInputSize < sizeof(AsusBridgeFanCurve)) {
                return kIOReturnBadArgument;
            }
            curvePtr = (const AsusBridgeFanCurve *)args->structureInput;
        }
        IOLockLock(bridge->lock);
        IOReturn r = bridge->writeFanCurve(fanIdx, resetToAuto, curvePtr);
        IOLockUnlock(bridge->lock);
        return r;
    }

    case kAsusBridgeSelectorSetPPTLimits: {
        if (args->scalarInputCount != 2 || !args->scalarOutput || args->scalarOutputCount < 2) {
            return kIOReturnBadArgument;
        }
        uint32_t r1 = 0, r2 = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->setPPTLimits((uint32_t)args->scalarInput[0],
                                          (uint32_t)args->scalarInput[1],
                                          &r1, &r2);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = r1;
            args->scalarOutput[1] = r2;
        }
        return r;
    }

    case kAsusBridgeSelectorSetTufRGB: {
        if (args->scalarInputCount != 6 || !args->scalarOutput || args->scalarOutputCount < 2) {
            return kIOReturnBadArgument;
        }
        uint32_t out1 = 0, out2 = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->setTufRGB((uint32_t)args->scalarInput[0],
                                       (uint32_t)args->scalarInput[1],
                                       (uint32_t)args->scalarInput[2],
                                       (uint32_t)args->scalarInput[3],
                                       (uint32_t)args->scalarInput[4],
                                       (uint32_t)args->scalarInput[5],
                                       &out1, &out2);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = out1;
            args->scalarOutput[1] = out2;
        }
        return r;
    }

    case kAsusBridgeSelectorTriggerSKEY: {
        if (args->scalarInputCount != 1 || !args->scalarOutput || args->scalarOutputCount < 1) {
            return kIOReturnBadArgument;
        }
        uint32_t raw = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->triggerSKEY((uint32_t)args->scalarInput[0], &raw);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = raw;
        }
        return r;
    }

    case kAsusBridgeSelectorSetKbdBrightness: {
        if (args->scalarInputCount != 1 || !args->scalarOutput || args->scalarOutputCount < 2) {
            return kIOReturnBadArgument;
        }
        uint32_t rDevs = 0, rDsts = 0;
        IOLockLock(bridge->lock);
        IOReturn r = bridge->setKbdBrightness((uint32_t)args->scalarInput[0], &rDevs, &rDsts);
        IOLockUnlock(bridge->lock);
        if (r == kIOReturnSuccess) {
            args->scalarOutput[0] = rDevs;
            args->scalarOutput[1] = rDsts;
        }
        return r;
    }

    case kAsusBridgeSelectorGetECState: {
        if (!args->structureOutput || args->structureOutputSize < sizeof(AsusBridgeECState)) {
            return kIOReturnBadArgument;
        }
        AsusBridgeECState ecState;
        IOLockLock(bridge->lock);
        bridge->populateECState(&ecState);
        IOLockUnlock(bridge->lock);
        memcpy(args->structureOutput, &ecState, sizeof(AsusBridgeECState));
        args->structureOutputSize = sizeof(AsusBridgeECState);
        return kIOReturnSuccess;
    }

    default:
        return kIOReturnUnsupported;
    }
}

IOReturn AsusBridge::newUserClient(task_t owningTask, void *securityID, UInt32 type,
                                   OSDictionary *properties, IOUserClient **handler)
{
    if (!handler) return kIOReturnBadArgument;
    AsusBridgeUserClient *uc = OSTypeAlloc(AsusBridgeUserClient);
    if (!uc) return kIOReturnNoMemory;
    if (!uc->initWithTask(owningTask, securityID, type, properties)) {
        uc->release();
        return kIOReturnError;
    }
    if (!uc->attach(this)) {
        uc->release();
        return kIOReturnError;
    }
    if (!uc->start(this)) {
        uc->detach(this);
        uc->release();
        return kIOReturnError;
    }
    *handler = uc;
    return kIOReturnSuccess;
}

bool AsusBridge::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;

    atkd = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!atkd) return false;

    if (atkd->validateObject("WMNB") != kIOReturnSuccess) {
        IOLog("AsusBridge: WMNB method not found on %s\n", atkd->getName());
        return false;
    }

    lock = IOLockAlloc();
    if (!lock) return false;

    eramDesc = IOMemoryDescriptor::withPhysicalAddress(FX707ZM_EC_ERAM_PHYS, 0x100, kIODirectionInOut);
    if (eramDesc) {
        eramMap = eramDesc->map(kIOMapInhibitCache);
        if (eramMap) {
            eramPtr = (volatile uint8_t *)eramMap->getVirtualAddress();
        }
    }
    erm2Desc = IOMemoryDescriptor::withPhysicalAddress(FX707ZM_EC_ERM2_PHYS, 0x100, kIODirectionInOut);
    if (erm2Desc) {
        erm2Map = erm2Desc->map(kIOMapInhibitCache);
        if (erm2Map) {
            erm2Ptr = (volatile uint8_t *)erm2Map->getVirtualAddress();
        }
    }
    logMsg("EC MMIO mapped: ERAM=%s ERM2=%s", eramPtr ? "yes" : "no", erm2Ptr ? "yes" : "no");

    uint32_t r = 0;
    if (evaluateWMNBInt(ASUS_WMI_METHOD_INIT, 0, 0, &r)) {
        initRaw = r;
        logMsg("INIT=0x%08x", initRaw);
    } else {
        logMsg("INIT evaluation failed");
    }

    r = 0;
    if (evaluateWMNBInt(ASUS_WMI_METHOD_SFUN, 0, 0, &r)) {
        sfunRaw = r;
        logMsg("SFUN=0x%08x", sfunRaw);
    } else {
        logMsg("SFUN evaluation failed");
    }

    findCompanionACPIDevices();

    eventCall = thread_call_allocate(atkdEventThread, this);
    if (eventCall) {
        atkdNotifier = atkd->registerInterest(gIOGeneralInterest, atkdInterestHandler, this);
    }
    if (edp1) {
        edp1Notifier = edp1->registerInterest(gIOGeneralInterest, edp1InterestHandler, this);
    }

    AsusBridgeSnapshot initialSnap;
    populateSnapshot(&initialSnap);
    if (eramPtr) {
        setProperty("asus-ec-rsoc", (uint32_t)eramPtr[0x77], 32);
        setProperty("asus-ec-ftbl", (uint32_t)eramPtr[0x06], 32);
        setProperty("asus-ec-thrp", (uint32_t)eramPtr[0xAE], 32);
    }
    logMsg("v0.3.0 ready: temp=%uC cpuFan=%u gpuFan=%u mux=0x%08x rsoc=%u ftbl=%u",
           initialSnap.cpuTempCelsius, initialSnap.cpuFanRPM,
           initialSnap.gpuFanRPM, initialSnap.muxStateRawDSTS,
           eramPtr ? eramPtr[0x77] : 0, eramPtr ? eramPtr[0x06] : 0);

#ifdef ASUS_BRIDGE_LIVE_CLASS
    setProperty("IOUserClientClass", "AsusBridgeLiveUserClient");
#else
    setProperty("IOUserClientClass", "AsusBridgeUserClient");
#endif
    registerService();
    return true;
}

void AsusBridge::stop(IOService *provider)
{
    if (atkdNotifier) {
        atkdNotifier->remove();
        atkdNotifier = nullptr;
    }
    if (edp1Notifier) {
        edp1Notifier->remove();
        edp1Notifier = nullptr;
    }
    if (eventCall) {
        thread_call_cancel(eventCall);
        thread_call_free(eventCall);
        eventCall = nullptr;
    }
    if (eramMap) {
        eramMap->release();
        eramMap = nullptr;
        eramPtr = nullptr;
    }
    if (eramDesc) {
        eramDesc->release();
        eramDesc = nullptr;
    }
    if (erm2Map) {
        erm2Map->release();
        erm2Map = nullptr;
        erm2Ptr = nullptr;
    }
    if (erm2Desc) {
        erm2Desc->release();
        erm2Desc = nullptr;
    }
    if (acad) {
        acad->release();
        acad = nullptr;
    }
    if (ec0) {
        ec0->release();
        ec0 = nullptr;
    }
    if (edp1) {
        edp1->release();
        edp1 = nullptr;
    }
    if (lock) {
        IOLockFree(lock);
        lock = nullptr;
    }
    IOService::stop(provider);
}
