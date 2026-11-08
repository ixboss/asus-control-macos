#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 ASUS Control for macOS Contributors
#
# Builds AsusBridge.kext on macOS using CommandLineTools Kernel.framework headers
# and libkmod / libkmodc++ / libclang_rt.cc_kext.

set -euo pipefail
cd "$(dirname "$0")/.."

SDK_PATH="$(xcrun --show-sdk-path)"
KERNEL_INC="$SDK_PATH/System/Library/Frameworks/Kernel.framework/Headers"
CLANG_RT_DIR="$(dirname "$(clang --print-libgcc-file-name)")"

LINK_MIN=$(otool -l "$SDK_PATH/usr/lib/libkmodc++.a" 2>/dev/null | awk '/minos/ {print $2; exit}')
LINK_MIN="${LINK_MIN:-12.0}"

COMMON_FLAGS=(
    -arch x86_64
    -mmacosx-version-min=12.0
    -O2 -g
    -mkernel
    -fno-builtin
    -fno-stack-protector
    -nostdlib
    -nostdlibinc
    -ffreestanding
    -DKERNEL
    -DKERNEL_PRIVATE
    -DDRIVER_PRIVATE
    -DAPPLE
    -DNeXT
    -I"$KERNEL_INC"
    -Ikexts/AsusBridge
)

CXXFLAGS=(
    -std=c++17
    -fapple-kext
    -fno-exceptions
    -fno-rtti
)

BUILD_DIR="build/kext"
OBJ_DIR="$BUILD_DIR/obj"
KEXT_OUT="$BUILD_DIR/AsusBridge.kext"

rm -rf "$KEXT_OUT" "$OBJ_DIR"
mkdir -p "$KEXT_OUT/Contents/MacOS" "$OBJ_DIR"

cp "kexts/AsusBridge/Info.plist" "$KEXT_OUT/Contents/Info.plist"

echo "[1/3] Compiling kmod_info.c..."
clang "${COMMON_FLAGS[@]}" -c "kexts/AsusBridge/kmod_info.c" -o "$OBJ_DIR/kmod_info.o"

echo "[2/3] Compiling AsusBridge.cpp..."
clang++ "${COMMON_FLAGS[@]}" "${CXXFLAGS[@]}" -c "kexts/AsusBridge/AsusBridge.cpp" -o "$OBJ_DIR/AsusBridge.o"

echo "[3/3] Linking AsusBridge.kext..."
clang++ -arch x86_64 -mmacosx-version-min="$LINK_MIN" -nostdlib \
    -Xlinker -kext -Xlinker -no_data_const \
    -L"$SDK_PATH/usr/lib" \
    "$SDK_PATH/usr/lib/libkmodc++.a" \
    "$SDK_PATH/usr/lib/libkmod.a" \
    "$CLANG_RT_DIR/libclang_rt.cc_kext.a" \
    "$OBJ_DIR/kmod_info.o" \
    "$OBJ_DIR/AsusBridge.o" \
    -o "$KEXT_OUT/Contents/MacOS/AsusBridge"

codesign -s - -f "$KEXT_OUT" 2>/dev/null || true

echo "Built $KEXT_OUT"
file "$KEXT_OUT/Contents/MacOS/AsusBridge"
echo "--- Undefined symbols check ---"
nm -um "$KEXT_OUT/Contents/MacOS/AsusBridge" | head -n 30 || true

# Also build AsusBridgeLive.kext for immediate directLoad without reboot when AsusBridge is already in AuxKC
LIVE_OUT="$BUILD_DIR/AsusBridgeLive.kext"
rm -rf "$LIVE_OUT"
mkdir -p "$LIVE_OUT/Contents/MacOS"
sed -e 's/org.asuscontrol.driver.AsusBridge/org.asuscontrol.driver.AsusBridgeLive/g' \
    -e 's/<string>AsusBridge<\/string>/<string>AsusBridgeLive<\/string>/g' \
    -e 's/<key>AsusBridge<\/key>/<key>AsusBridgeLive<\/key>/g' \
    -e 's/<key>IOProbeScore<\/key>/<key>IOMatchCategory<\/key><string>AsusBridgeLiveCategory<\/string><key>IOProbeScore<\/key>/g' \
    "kexts/AsusBridge/Info.plist" > "$LIVE_OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :IOKitPersonalities:AsusBridgeLive:IOMatchCategory string AsusBridgeLiveCategory" "$LIVE_OUT/Contents/Info.plist" 2>/dev/null || true

clang "${COMMON_FLAGS[@]}" -DASUS_BRIDGE_LIVE_CLASS=1 -c "kexts/AsusBridge/kmod_info.c" -o "$OBJ_DIR/kmod_info_live.o"
clang++ "${COMMON_FLAGS[@]}" "${CXXFLAGS[@]}" -DASUS_BRIDGE_LIVE_CLASS=1 -c "kexts/AsusBridge/AsusBridge.cpp" -o "$OBJ_DIR/AsusBridge_live.o"
clang++ -arch x86_64 -mmacosx-version-min="$LINK_MIN" -nostdlib \
    -Xlinker -kext -Xlinker -no_data_const \
    -L"$SDK_PATH/usr/lib" \
    "$SDK_PATH/usr/lib/libkmodc++.a" \
    "$SDK_PATH/usr/lib/libkmod.a" \
    "$CLANG_RT_DIR/libclang_rt.cc_kext.a" \
    "$OBJ_DIR/kmod_info_live.o" \
    "$OBJ_DIR/AsusBridge_live.o" \
    -o "$LIVE_OUT/Contents/MacOS/AsusBridgeLive"
codesign -s - -f "$LIVE_OUT" 2>/dev/null || true
echo "Built $LIVE_OUT"
