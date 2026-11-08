// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 ASUS Control for macOS Contributors
// Kernel module descriptor for AsusBridge.kext

#include <mach/mach_types.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
#ifdef ASUS_BRIDGE_LIVE_CLASS
KMOD_EXPLICIT_DECL(org.asuscontrol.driver.AsusBridgeLive, "0.3.0", _start, _stop)
#else
KMOD_EXPLICIT_DECL(org.asuscontrol.driver.AsusBridge, "0.3.0", _start, _stop)
#endif
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
