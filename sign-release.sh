#!/usr/bin/env bash
# sign-release.sh — the POST-BUILD release-signing step.
#
# WHY THIS EXISTS
#   Building with `PRODUCT_DEFAULT_DEV_CERTIFICATE` signs every APK/APEX container with our own
#   private keys, but it can NEVER stamp `release-keys`. build/make/core/config.mk says so outright:
#
#       "test-keys" marks builds signed with the old test keys ... "dev-keys" marks builds signed
#       with non-default dev keys (usually private keys from a vendor directory). Both of these tags
#       will be removed and replaced with "release-keys" when the target-files is signed in a
#       post-build step.
#
#   That post-build step is `sign_target_files_apks`, and this script is it. Without it the build
#   honestly reports `dev-keys`, which detection apps (e.g. Duckdetector) flag — the field bug report
#   from 2026-07-20.
#
#   This is NOT a spoof. We really are signing with our own private release keys; `release-keys` is
#   simply what that state is called once the release flow has been run.
#
# WHAT IT TOUCHES
#   * Re-signs APKs / APEX containers with keys-priv (same keys the build already used).
#   * Rewrites, across EVERY partition: ro.*.build.tags -> release-keys, the trailing key field of
#     ro.*.build.fingerprint / .thumbprint / ro.bootimage.build.fingerprint, the last token of
#     ro.build.description, and strips the "-keys" suffix from ro.build.display.id.
#
# WHAT IT DELIBERATELY DOES NOT TOUCH
#   * AVB / verified boot. No --avb_*_key flag is passed, and sign_target_files_apks only replaces an
#     AVB key when one is given for that partition (OPTIONS.avb_keys defaults to {} and
#     ReplaceAvbPartitionSigningKey() returns early). The AVB chain therefore stays byte-identical,
#     which is what keeps the device at verifiedbootstate=green under the fenrir LK. Do NOT add AVB
#     flags here without re-reading JOURNAL 2026-07-19 ("AVB keys deliberately UNCHANGED").
#
# USAGE:  ./sign-release.sh [version-tag]      (default version tag: v3)

set -euo pipefail

TOP=/mnt/external_nvme/aospa
DEV=S666LN
PROD=aospa_${DEV}
KEYS="$TOP/vendor/aospa-priv/keys"
OUT="$TOP/out/target/product/$DEV"
HOSTBIN="$TOP/out/host/linux-x86/bin"
VTAG="${1:-v3}"
DATE="${DATE:-$(date +%Y%m%d)}"   # override to pin the artifact date to BUILD_NUMBER (e.g. across midnight)
NAME="aospa-beryl-unofficial-${DEV}-${DATE}-${VTAG}"

red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
grn() { printf '\033[0;32m%s\033[0m\n' "$*"; }

# The releasetools shell out to `java` for signapk; use the tree's hermetic JDK.
for J in "$TOP"/prebuilts/jdk/jdk*/linux-x86/bin; do
  [ -x "$J/java" ] && export PATH="$J:$PATH" && break
done
command -v java >/dev/null || { red "ERROR: no java on PATH (needed by signapk)"; exit 1; }

# MUST run from the tree root: META/apkcerts.txt names certificates by TREE-RELATIVE path
# (e.g. "vendor/aospa-priv/keys/releasekey"), and sign_target_files_apks hands those straight to
# signapk. Running from anywhere else fails with
#   java.io.FileNotFoundException: vendor/aospa-priv/keys/releasekey.x509.pem
cd "$TOP"

# /tmp on this box is a 7.5 GB RAM-backed tmpfs. add_img_to_target_files unzips the ~5 GB
# target-files AND the extracted partition trees into $TMPDIR, which blows straight past that and
# dies with "OSError: [Errno 28] No space left on device" (and eats RAM we need for the build).
# Point TMPDIR at the big disk instead.
export TMPDIR="${TMPDIR_OVERRIDE:-$TOP/tmp-release}"
mkdir -p "$TMPDIR"
avail_gb=$(df -BG --output=avail "$TMPDIR" | tail -1 | tr -dc '0-9')
[ "${avail_gb:-0}" -ge 40 ] || red "WARN: only ${avail_gb}G free on $TMPDIR — signing needs tens of GB"
grn "==> TMPDIR=$TMPDIR (${avail_gb}G free)"

TFDIR="$OUT/obj/PACKAGING/target_files_intermediates/${PROD}-target_files"
TF="$TFDIR.zip"
[ -d "$TFDIR" ] || { red "ERROR: target-files dir not found: $TFDIR (build with 'otapackage' first)"; exit 1; }
[ -d "$KEYS" ] || { red "ERROR: signing keys not staged: $KEYS (run apply-overlays.sh step 22)"; exit 1; }

# --- normalise stale AVB fingerprint args -------------------------------------------------------
# The AVB footer args in META/misc_info.txt embed the build fingerprint, and they go stale: they are
# expanded from a cached value that has no dependency on BUILD_NUMBER, so after a BUILD_NUMBER change
# they keep the OLD incremental ("eng.nobody" from a build made before BUILD_NUMBER was set) even
# though misc_info.txt itself is regenerated and every build.prop is correct. Same dependency-gap
# class as the honest3 vendor/build.prop lag (JOURNAL 2026-07-20).
# Left alone, every partition's AVB descriptor would advertise a fingerprint ending "eng.nobody",
# disagreeing with build.prop and looking like an engineering build to anything that reads AVB props.
# Authoritative value = build_fingerprint.txt (which IS correct).
FPFILE="$OUT/build_fingerprint.txt"
MISC="$TFDIR/META/misc_info.txt"
if [ -f "$FPFILE" ] && [ -f "$MISC" ]; then
  INCR=$(cut -d: -f2 "$FPFILE" | awk -F/ '{print $NF}')
  if [ -z "$INCR" ] || [ "$INCR" = "eng.nobody" ]; then
    red "WARN: build_fingerprint.txt has no usable incremental ('$INCR') — leaving misc_info alone"
  elif grep -q "eng\.nobody" "$MISC"; then
    n=$(grep -c "eng\.nobody" "$MISC")
    sed -i "s|/eng\.nobody:|/$INCR:|g" "$MISC"
    grn "==> [0/4] normalised $n stale AVB fingerprint arg(s) in misc_info.txt -> incremental '$INCR'"
  fi
fi

grn "==> [0/4] packaging target-files zip (same command the build uses)"
# The .list file holds TREE-RELATIVE paths (out/target/product/...), so -C and -r must be relative
# too, from $TOP. Passing absolute paths fails with: "Rel: can't make <abs> relative to <abs>".
REL_TFDIR="out/target/product/$DEV/obj/PACKAGING/target_files_intermediates/${PROD}-target_files"
"$TOP/out/host/linux-x86/bin/soong_zip" -d -o "$REL_TFDIR.zip" -C "$REL_TFDIR" -r "$REL_TFDIR.zip.list" -sha256

SIGNED="$OUT/${PROD}-target_files-signed.zip"
grn "==> [1/4] sign_target_files_apks  (tags: -test-keys -dev-keys +release-keys; AVB untouched)"
"$HOSTBIN/sign_target_files_apks" -v -d "$KEYS" "$TF" "$SIGNED"

grn "==> [2/4] ota_from_target_files -> ${NAME}.zip"
"$HOSTBIN/ota_from_target_files" --block "$SIGNED" "$OUT/${NAME}.zip"

grn "==> [3/4] img_from_target_files + super.img (fastboot path)"
"$HOSTBIN/img_from_target_files" "$SIGNED" "$OUT/${NAME}-images.zip"
"$HOSTBIN/build_super_image" "$SIGNED" "$OUT/${NAME}-super.img" || \
  red "WARN: build_super_image failed — the OTA zip is still the primary artifact"

grn "==> [4/4] verify"
TMPV="$(mktemp -d)"; trap 'rm -rf "$TMPV"' EXIT
unzip -o -q "$SIGNED" 'SYSTEM/build.prop' 'VENDOR/build.prop' 'PRODUCT/build.prop' \
  'SYSTEM_EXT/build.prop' 'ODM/build.prop' -d "$TMPV" 2>/dev/null || true
bad=0
while IFS= read -r bp; do
  tags=$(grep -h '^ro\..*\.build\.tags=' "$bp" 2>/dev/null | head -1)
  fp=$(grep -h '^ro\..*\.build\.fingerprint=' "$bp" 2>/dev/null | head -1)
  printf '   %-22s %s\n' "$(basename "$(dirname "$bp")")" "$tags"
  case "$tags" in *release-keys*) ;; *) red "     ^ NOT release-keys"; bad=1 ;; esac
  case "$fp" in *release-keys*) ;; *) red "     ^ fingerprint not release-keys: $fp"; bad=1 ;; esac
done < <(find "$TMPV" -name build.prop)
if grep -qa 'dev-keys' "$TMPV"/*/build.prop 2>/dev/null; then
  red "   WARN: a 'dev-keys' string still present in a build.prop"; bad=1
fi
# AVB descriptor props must agree with build.prop (no stale eng.nobody, no dev-keys)
unzip -o -q "$SIGNED" 'META/misc_info.txt' -d "$TMPV" 2>/dev/null || true
if [ -f "$TMPV/META/misc_info.txt" ]; then
  for pat in 'eng\.nobody' 'dev-keys'; do
    if grep -qa "$pat" "$TMPV/META/misc_info.txt"; then
      red "   WARN: AVB args still contain '$pat' ($(grep -ca "$pat" "$TMPV/META/misc_info.txt")x)"; bad=1
    fi
  done
  [ "$bad" -eq 0 ] && printf '   %-22s AVB fingerprint args clean\n' "misc_info.txt"
fi
sha256sum "$OUT/${NAME}.zip" | tee "$OUT/${NAME}.zip.sha256"
[ "$bad" -eq 0 ] && grn "==> RELEASE SIGNED OK: $OUT/${NAME}.zip" || red "==> VERIFY FAILED — do not ship"
exit "$bad"
