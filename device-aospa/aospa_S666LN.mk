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

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="sys_tssi_64_armv82_itel-user 13 TP1A.220624.014 974711 release-keys" \
    BuildFingerprint=Itel/S666LN-OP/itel-S666LN:13/TP1A.220624.014/251212V1661:user/release-keys \
    DeviceName=$(PRODUCT_SYSTEM_DEVICE) \
    DeviceProduct=$(PRODUCT_SYSTEM_NAME)

# Play Integrity / fingerprint validity (2026-07-18): the BuildFingerprint override above only sets
# the PER-PARTITION fingerprints (ro.system/vendor/product.build.fingerprint). The PRIMARY
# ro.build.fingerprint — the one Build.FINGERPRINT and Play Integrity read — is not written to
# build.prop, so init derives it at runtime from the live props (brand/name/device : release / id /
# incremental : type / tags) → an invalid "…:16/BQ2A…:userdebug/test-keys" string. Set it
# explicitly to the stock certified value so init skips the derive (it only derives when unset).
# VERIFY on the next build: `adb shell getprop ro.build.fingerprint` must equal the stock string.
PRODUCT_SYSTEM_PROPERTIES += \
    ro.build.fingerprint=Itel/S666LN-OP/itel-S666LN:13/TP1A.220624.014/251212V1661:user/release-keys

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
