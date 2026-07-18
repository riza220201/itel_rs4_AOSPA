#!/usr/bin/env bash
#
# apply-custom-kernel.sh — swap the AOSPA prebuilt GKI kernel for our custom
# itel-rs4-kernel build (5.10.260-Riza-vanilla by default).
#
# The ROM does NOT compile the kernel; BoardConfig.mk does:
#     COMMON_GKI_PATH := device/millennium/common-kernel
#     LOCAL_KERNEL    := $(COMMON_GKI_PATH)/Image.gz
#     PRODUCT_COPY_FILES += $(LOCAL_KERNEL):kernel
# so boot.img is assembled from device/millennium/common-kernel/Image.gz. We
# replace that file with ours. KMI-safe: our kernel reproduces
# module_layout 0x7c24b32d, the exact CRC all 198 S666LN vendor_dlkm modules
# demand (verified against device/itel/S666LN-kernel/vendor_dlkm), and it's the
# same Google GKI 5.10.260 base the stock prebuilt uses.
#
# IDEMPOTENT + re-runnable. A full `repo sync --force-sync` reverts the
# common-kernel project to stock — just re-run this afterwards, before `m`.
#
# Usage: apply-custom-kernel.sh [path/to/Image.gz] [ANDROID_TOP]
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_GZ="${1:-$SELF_DIR/kernel-stage/Image.gz}"
TOP="${2:-/mnt/external_nvme/aospa}"
DEST_DIR="$TOP/device/millennium/common-kernel"
DEST="$DEST_DIR/Image.gz"
EXPECT_REL="5.10.260-Riza-vanilla"   # change if applying a different variant

red(){ printf '\033[31m%s\033[0m\n' "$*"; }; grn(){ printf '\033[32m%s\033[0m\n' "$*"; }

[ -f "$SRC_GZ" ]  || { red "source kernel not found: $SRC_GZ"; exit 1; }
[ -d "$DEST_DIR" ] || { red "common-kernel not synced yet: $DEST_DIR"; exit 1; }

# Verify the source really is our kernel (fail loud, never ship the wrong Image).
# Capture the match (|| true) rather than `grep -q` in a pipe — grep -q exits
# early, SIGPIPEs zcat, and pipefail would wrongly report the check as failed.
SRC_REL="$(zcat "$SRC_GZ" | strings | grep -m1 -oE '5\.10\.[0-9]+-Riza-[a-z]+' || true)"
if [ "$SRC_REL" != "$EXPECT_REL" ]; then
  red "source Image.gz release is '${SRC_REL:-none}', expected '$EXPECT_REL' — refusing to install."; exit 1
fi

# Back up the stock prebuilt exactly once
if [ ! -f "$DEST.stock" ]; then
  cp -a "$DEST" "$DEST.stock"
  grn "backed up stock kernel -> $(basename "$DEST").stock ($(zcat "$DEST.stock" | strings | grep -m1 'Linux version 5.10' | cut -c1-60))"
fi

cp -f "$SRC_GZ" "$DEST"
INSTALLED_REL="$(zcat "$DEST" | strings | grep -m1 -oE '5\.10\.[0-9]+-Riza-[a-z]+' || true)"
grn "installed custom kernel: $INSTALLED_REL  ($(du -h "$DEST" | cut -f1))  -> $DEST"
grn "restore stock with: cp -f '$DEST.stock' '$DEST'"
