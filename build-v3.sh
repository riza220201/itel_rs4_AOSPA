#!/bin/bash
# build-v3.sh — launch the S666LN user build (droid + superimage + otapackage).
# Usage:  ./build-v3.sh [BUILD_NUMBER]   (default: today's date, YYYYMMDD)
# Detach: setsid nohup ./build-v3.sh > build-<date>.log 2>&1 &
# Follow with ./sign-release.sh <tag> for the release-keys signing pass.
#
# NOTE: deliberately NO `set -e`. AOSPA's vendorsetup runs barista.py which
# prints "No beans found for the device (S666LN)" and exits non-zero for our
# custom-ported device — that is harmless (S666LN has no official AOSPA
# beans.xml), but set -e would abort the whole build on it. We guard on the
# real signal instead: lunch must resolve TARGET_PRODUCT before we run `m`.
cd /mnt/external_nvme/aospa || exit 1
unset -f grep find rg 2>/dev/null || true

# ccache MUST match the prior build's environment. The prior 2:14 build ran with
# USE_CCACHE=1; leaving it unset changes every C++ compile command (drops the
# `ccache` prefix), which makes ninja treat every object as stale and rebuild the
# whole tree from cold (~152k actions). With ccache restored the commands match,
# so ninja skips the unchanged objects and rebuilds only what actually changed.
# Dir must pre-exist as a directory (nsjail bind-mounts it; a missing path becomes
# a FILE → "ccache: error: Not a directory"). See JOURNAL 2026-07-19.
export USE_CCACHE=1
export CCACHE_DIR=/home/riza/.cache/ccache
mkdir -p "$CCACHE_DIR"

source build/envsetup.sh
lunch aospa_S666LN-user
if [ -z "$TARGET_PRODUCT" ] || [ "$TARGET_BUILD_VARIANT" != "user" ]; then
    echo "FATAL: lunch did not resolve (TARGET_PRODUCT='$TARGET_PRODUCT' variant='$TARGET_BUILD_VARIANT')"
    exit 1
fi
echo "lunch OK: $TARGET_PRODUCT-$TARGET_BUILD_VARIANT release=$TARGET_RELEASE"
# BUILD_NUMBER is REQUIRED — without it the fingerprint degrades to eng.nobody.
BUILD_NUMBER="${1:-$(date +%Y%m%d)}" m droid superimage otapackage -j4
