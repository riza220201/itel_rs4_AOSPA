#
# Copyright (C) 2026 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

# AOSPA's aospa-target.mk inherits device/qcom/common/common.mk, which hard-errors if
# TARGET_BOARD_PLATFORM is unset at product-config time ("please define in your device
# makefile so it's accessible to QCOM common"). This is a MediaTek device, so define it
# here: common.mk then self-excludes its entire QCOM block (mt6789 is not in
# QCOM_BOARD_PLATFORMS), pulling in none of the QCOM/RFS/QTI packages. Must precede the
# aospa-target inherit below.
TARGET_BOARD_PLATFORM := mt6789

# AOSPA's default manifest syncs ~40 QCOM/codeaurora vendor+hardware repos (dead weight on a
# MediaTek device, but soong analyzes every Android.bp in the tree). Several QCOM modules
# header_lib on `qti_kernel_headers`, which LineageOS's hardware/google/pixel defines inside its
# own soong namespace `hardware/google/pixel/kernel_headers`. The root namespace can't read it by
# default → "qti_kernel_headers ... can be found in [hardware/google/pixel/kernel_headers]" and
# soong bootstrap fails. Import that namespace so those deps resolve. The QCOM modules stay
# unbuilt (not in PRODUCT_PACKAGES; analysis resolves deps but only compiles what's installed).
# (Repos referencing a genuinely-absent namespace like hardware/qcom/display are removed via the
# local manifest instead — importing can't fix a namespace that exists nowhere.)
PRODUCT_SOONG_NAMESPACES += hardware/google/pixel/kernel_headers

# ── Release signing (2026-07-19, RC) ──────────────────────────────────────────────────────
# Point the default dev certificate at our own release keys instead of the public AOSP testkey.
# Two effects, both wanted for a distributable build:
#   1. Every APK + APEX container is signed with OUR key (not the world-readable AOSP test-keys —
#      whoever holds those can sign a platform-privileged app/update, a real risk for a public ROM).
#   2. build/make/core/config.mk: DEFAULT_SYSTEM_DEV_CERTIFICATE != .../security/testkey ⇒ the build
#      is stamped BUILD_KEYS=release ⇒ ro.build.tags=release-keys. Combined with `lunch …-user`
#      (ro.build.type=user, ro.debuggable=0) the REAL props finally match the spoofed
#      BuildFingerprint/BuildDesc above (…:user/release-keys) — the clean RC the journal called for.
# Keys are no-password RSA-2048 (required for non-interactive signapk during `m`), generated with
# development/tools/make_key, kept private in ~/itel_rs4_AOSPA/keys-priv/ (gitignored) and staged
# into vendor/aospa-priv/keys/ by apply-overlays.sh. AVB/verified-boot keys are deliberately NOT
# changed here — the device boots green under the fenrir LK with the stock AVB chain, and Play
# Integrity certification depends on that green state; only APK/OTA signing changes.
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/aospa-priv/keys/releasekey

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from S666LN device
$(call inherit-product, device/itel/S666LN/device.mk)

# Inherit from the AOSPA configuration.
$(call inherit-product, vendor/aospa/target/product/aospa-target.mk)

BOARD_VENDOR := Itel
PRODUCT_NAME := aospa_S666LN
PRODUCT_DEVICE := S666LN
PRODUCT_MANUFACTURER := ITEL
PRODUCT_BRAND := Itel
PRODUCT_MODEL := itel S666LN

PRODUCT_GMS_CLIENTID_BASE := android-transsion
PRODUCT_SYSTEM_NAME := S666LN-OP
PRODUCT_SYSTEM_DEVICE := S666LN

# HONEST fingerprint (2026-07-20): we deliberately DO NOT spoof the fingerprint to the stock Android-13
# certified string. ro.build.fingerprint + the per-partition fingerprints derive truthfully from the real
# build -> Itel/.../S666LN:16/<AOSPA build id>/...:user/dev-keys (version AND tags now match reality;
# internally consistent). WHY: the previous A13-fingerprint-on-A16-OS mismatch is the leading suspect for
# strict Play-Integrity token validators (Privy e-KYC liveness inside BRImo) rejecting the device, even
# though banking login / by.U / Play Protect "certified" all accepted the A13 spoof. The working RS4
# LineageOS ports pass Privy, so on this device either an honest fingerprint + hardware attestation
# carries Play-Integrity DEVICE, or they spoof a CONSISTENT A16 cert. TRADEOFF UNDER TEST: Play Protect
# may now read "uncertified" -> re-verify banking + by.U + BRImo face-verify; if banking regresses, fall
# back to a consistent A16 certified fingerprint instead of the A13 one.

# Bootanimation resolution (720 x 1612 panel)
TARGET_BOOT_ANIMATION_RES := 720

# Camera (device tree ships ApertureOverlay; Lineage adds Aperture globally, AOSPA does not)
PRODUCT_PACKAGES += \
    Aperture

# ── 32-bit Mali GLES/Vulkan + MTK gralloc mapper (AOSPA port fix, 2026-07-18) ──────────────
# The KimelaZX vendor repo only extracted the 64-bit GPU stack; /vendor/lib/egl was empty of
# drivers, so every 32-bit process touching EGL aborted ("couldn't find an OpenGL ES
# implementation" — mediaserver32 crash-loop, 32-bit apps/games unrenderable). Blobs harvested
# from stock itel-RS4-S666LN-28 vendor (DT_NEEDED closure verified against the built image).
# PRODUCT_COPY_FILES (not cc_prebuilt) on purpose: kati-only, no soong re-analysis;
# BoardConfig already sets BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true.
PRODUCT_COPY_FILES += \
    vendor/itel/S666LN/proprietary/vendor/lib/egl/mt6789/libGLES_mali.so:$(TARGET_COPY_OUT_VENDOR)/lib/egl/libGLES_mali.so \
    vendor/itel/S666LN/proprietary/vendor/lib/egl/mt6789/libGLES_mali.so:$(TARGET_COPY_OUT_VENDOR)/lib/egl/mt6789/libGLES_mali.so \
    vendor/itel/S666LN/proprietary/vendor/lib/hw/mt6789/vulkan.mali.so:$(TARGET_COPY_OUT_VENDOR)/lib/hw/vulkan.mali.so \
    vendor/itel/S666LN/proprietary/vendor/lib/hw/mt6789/vulkan.mali.so:$(TARGET_COPY_OUT_VENDOR)/lib/hw/mt6789/vulkan.mali.so \
    vendor/itel/S666LN/proprietary/vendor/lib/hw/mt6789/android.hardware.graphics.mapper@4.0-impl-mediatek.so:$(TARGET_COPY_OUT_VENDOR)/lib/hw/android.hardware.graphics.mapper@4.0-impl-mediatek.so \
    vendor/itel/S666LN/proprietary/vendor/lib/hw/mt6789/android.hardware.graphics.mapper@4.0-impl-mediatek.so:$(TARGET_COPY_OUT_VENDOR)/lib/hw/mt6789/android.hardware.graphics.mapper@4.0-impl-mediatek.so \
    vendor/itel/S666LN/proprietary/vendor/lib/hw/mt6789/gralloc.common.so:$(TARGET_COPY_OUT_VENDOR)/lib/hw/gralloc.common.so \
    vendor/itel/S666LN/proprietary/vendor/lib/hw/mt6789/gralloc.common.so:$(TARGET_COPY_OUT_VENDOR)/lib/hw/mt6789/gralloc.common.so \
    vendor/itel/S666LN/proprietary/vendor/lib/arm.graphics-V1-ndk_platform.so:$(TARGET_COPY_OUT_VENDOR)/lib/arm.graphics-V1-ndk_platform.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libged.so:$(TARGET_COPY_OUT_VENDOR)/lib/libged.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libgpu_aux.so:$(TARGET_COPY_OUT_VENDOR)/lib/libgpu_aux.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libgpud.so:$(TARGET_COPY_OUT_VENDOR)/lib/libgpud.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libgralloc_extra.so:$(TARGET_COPY_OUT_VENDOR)/lib/libgralloc_extra.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libgralloc_metadata.so:$(TARGET_COPY_OUT_VENDOR)/lib/libgralloc_metadata.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libgralloctypes_mtk.so:$(TARGET_COPY_OUT_VENDOR)/lib/libgralloctypes_mtk.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libdpframework.so:$(TARGET_COPY_OUT_VENDOR)/lib/libdpframework.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libaiselector.so:$(TARGET_COPY_OUT_VENDOR)/lib/libaiselector.so \
    vendor/itel/S666LN/proprietary/vendor/lib/libpq_prot.so:$(TARGET_COPY_OUT_VENDOR)/lib/libpq_prot.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.pq@2.0.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.pq@2.0.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mmagent@1.0.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mmagent@1.0.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mms@1.0.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mms@1.0.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mms@1.1.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mms@1.1.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mms@1.2.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mms@1.2.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mms@1.3.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mms@1.3.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mms@1.4.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mms@1.4.so \
    vendor/itel/S666LN/proprietary/vendor/lib/vendor.mediatek.hardware.mms@1.5.so:$(TARGET_COPY_OUT_VENDOR)/lib/vendor.mediatek.hardware.mms@1.5.so
