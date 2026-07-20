#!/usr/bin/env bash
#
# apply-overlays.sh — re-apply ALL our local modifications onto the freshly-synced
# AOSPA tree. Run once after `repo init`/`repo sync`, and again after any future
# `repo sync --force-sync` (which reverts tracked files in the KimelaZX/AOSPA repos).
#
# Idempotent. Two overlays:
#   1) custom kernel  -> device/millennium/common-kernel/Image.gz   (apply-custom-kernel.sh)
#   2) AOSPA product  -> device/itel/S666LN/{AndroidProducts.mk,aospa_S666LN.mk}
#
# The device tree is LineageOS-shaped (lineage_S666LN.mk inherits vendor/lineage,
# which AOSPA does not ship). We register ONLY the aospa product so no vendor/lineage
# product makefile is parsed. aospa_S666LN.mk inherits vendor/aospa's aospa-target.mk
# instead of Lineage's common_full_phone.mk. Remaining vendor/lineage references in
# the device tree (health HAL, BoardConfigReservedSize) are handled as build breakages
# surface — tracked in JOURNAL.md.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="${1:-/mnt/external_nvme/aospa}"
DEV="$TOP/device/itel/S666LN"
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }; red(){ printf '\033[31m%s\033[0m\n' "$*"; }

# 1) custom kernel
"$SELF_DIR/apply-custom-kernel.sh" "$SELF_DIR/kernel-stage/Image.gz" "$TOP"

# 2) AOSPA product
[ -d "$DEV" ] || { red "device tree not synced: $DEV"; exit 1; }
cp -f "$SELF_DIR/device-aospa/aospa_S666LN.mk" "$DEV/aospa_S666LN.mk"
cp -f "$SELF_DIR/device-aospa/AndroidProducts.mk" "$DEV/AndroidProducts.mk"
grn "landed AOSPA product: $DEV/{aospa_S666LN.mk,AndroidProducts.mk} (aospa_S666LN lunch target)"

# 2b) generated_kernel_headers — define the soong module from the prebuilt kernel UAPI
#     headers (ROM uses a prebuilt kernel, so soong doesn't auto-generate it; PowerOffAlarm
#     header_libs on it). See device-aospa/common-kernel-Android.bp.
CK_DIR="$TOP/device/millennium/common-kernel"
if [ -d "$CK_DIR/kernel-headers/usr/include" ]; then
  cp -f "$SELF_DIR/device-aospa/common-kernel-Android.bp" "$CK_DIR/Android.bp"
  grn "landed generated_kernel_headers: $CK_DIR/Android.bp (exports kernel-headers/usr/include)"
else
  red "WARN: $CK_DIR/kernel-headers/usr/include missing — generated_kernel_headers not landed"
fi

# 3) First-build fixup: AOSPA ships the vendor.lineage.health INTERFACE but not the
#    -service.default binary (LineageOS/android_hardware_lineage_interfaces). Comment the
#    PRODUCT_PACKAGES line so `m` doesn't fail on the missing module. Reversible; the proper
#    fix (add the service without the duplicate interface) is a post-boot follow-up — see
#    PORT-NOTES.md option B. Idempotent.
if grep -qE '^[[:space:]]+vendor\.lineage\.health-service\.default[[:space:]]*\\?$' "$DEV/device.mk"; then
  sed -i -E 's|^([[:space:]]+)(vendor\.lineage\.health-service\.default)([[:space:]]*\\?)$|\1# \2 \3 # AOSPA: service absent, see PORT-NOTES.md|' "$DEV/device.mk"
  grn "fixup: commented out vendor.lineage.health-service.default (missing on AOSPA)"
else
  grn "fixup: vendor.lineage.health-service.default already handled (skip)"
fi

# 4) Vendor blob dep fixup: 3 MediaTek audio/rt blobs (audio.primary.mediatek, librt_extamp_intf,
#    +1) are DT_NEEDED against libtinyxml2-v34.so — a VNDK-34-versioned libtinyxml2 soname. LineageOS
#    supplied it via the VNDK-34 snapshot; AOSPA (A16) dropped VNDK and ships no such module, so
#    soong can't resolve the shared_libs "libtinyxml2-v34" (analysis) AND check_elf_file flags the
#    unmatched DT_NEEDED (build) AND it'd be missing at runtime. Do NOT rewrite the blobs to plain
#    libtinyxml2 (breaks check_elf + runtime — the .so's DT_NEEDED is hard-coded). Instead DEFINE
#    libtinyxml2-v34 by building libtinyxml2's code under the -v34 name (whole_static_libs), in the
#    blobs' own namespace (vendor/itel/S666LN/Android.bp, where the working libalsautils-v31 lives).
#    Idempotent (marker guard). See PORT-NOTES.md.
VITEL_BP="$TOP/vendor/itel/S666LN/Android.bp"
if [ -f "$VITEL_BP" ] && ! grep -q 'name: "libtinyxml2-v34"' "$VITEL_BP"; then
  cat >> "$VITEL_BP" <<'EOF'

// AOSPA-COMPAT libtinyxml2-v34: build libtinyxml2's code under the VNDK-34-versioned soname
// (libtinyxml2-v34.so) that the MediaTek audio/rt blobs DT_NEEDED. AOSPA dropped VNDK so no
// snapshot provides it. See PORT-NOTES.md.
cc_library_shared {
    name: "libtinyxml2-v34",
    vendor: true,
    whole_static_libs: ["libtinyxml2"],
    shared_libs: ["liblog"],
    compile_multilib: "both",
}
EOF
  grn "fixup: defined libtinyxml2-v34 (whole_static_libs libtinyxml2) in vendor/itel Android.bp"
else
  grn "fixup: libtinyxml2-v34 module already handled (skip)"
fi

# 5) hardware/google/pixel (added for the pixel namespace + libperfmgr) also ships a Pixel touch
#    HAL in touch/ whose service deps on vendor.lineage.touch-V1-ndk — a LineageOS interface AOSPA
#    does not ship. Nothing in our product references that service (Pixel-hardware-specific; this
#    device uses MediaTek touch), so neutralize just that Android.bp so soong doesn't analyze it.
#    Idempotent (overwrites each run; restored by repo sync then re-neutered here).
PIXEL_TOUCH_BP="$TOP/hardware/google/pixel/touch/Android.bp"
if [ -f "$PIXEL_TOUCH_BP" ]; then
  printf '// Neutralized by apply-overlays.sh: the Pixel touch HAL depends on vendor.lineage.touch\n// (absent on AOSPA) and is unused on this MediaTek device. See PORT-NOTES.md.\n' > "$PIXEL_TOUCH_BP"
  grn "fixup: neutralized hardware/google/pixel/touch/Android.bp (pixel touch HAL, unused)"
else
  grn "fixup: pixel touch Android.bp absent (skip)"
fi

# 6) QCOM kernel/image build tasks hijack the MediaTek image build. core-utils symlinks
#    vendor/qcom/build/tasks/{generate_extra_images.mk -> device/qcom/common,
#    kernel_definitions.mk -> device/qcom/kernelscripts} into the kati task set. Those assume a
#    from-source Qualcomm kernel: generate_extra_images.mk adds a rule to REGENERATE
#    BOARD_PREBUILT_DTBOIMAGE (=device/itel/S666LN-kernel/dtbo.img) with mkdtimg -> "writing to
#    readonly directory"; kernel_definitions.mk overrides the dtb.img target. This device ships
#    PREBUILT dtb/dtbo which AOSP's standard BOARD_PREBUILT_DTBOIMAGE / BOARD_PREBUILT_DTBIMAGE_DIR
#    handling copies to $OUT. Neuter the two QCOM task files (the symlinks then resolve to no-ops;
#    survives sync via re-run). Idempotent (marker guard). See PORT-NOTES.md.
for f in "$TOP/device/qcom/common/generate_extra_images.mk" \
         "$TOP/device/qcom/kernelscripts/kernel_definitions.mk"; do
  if [ -f "$f" ]; then
    if ! head -1 "$f" 2>/dev/null | grep -q 'AOSPA-NEUTERED'; then
      printf '# AOSPA-NEUTERED (apply-overlays.sh): QCOM kernel/image task disabled for the MediaTek\n# S666LN prebuilt dtb/dtbo build. See PORT-NOTES.md.\n' > "$f"
      grn "fixup: neutered QCOM task $(basename "$f")"
    else
      grn "fixup: QCOM task $(basename "$f") already neutered (skip)"
    fi
  fi
done

# 7) libaudioclient_shim (AOSPA/android_hardware_lineage_compat) source fix: AudioTrack.cpp uses
#    AudioTrack::legacy_callback_t (a member typedef absent from Android-16 frameworks/av's
#    AudioTrack) for its mCallback field + LegacyCallbackWrapper ctor. The file already defines a
#    file-scope `legacy_callback_t` (same signature) and the rest of the file (createCallback,
#    newfnc) uses THAT. Drop the spurious AudioTrack:: qualifier on the 2 offending lines so it
#    matches. Idempotent. See PORT-NOTES.md.
ATRACK="$TOP/hardware/lineage/compat/libaudioclient/AudioTrack.cpp"
if [ -f "$ATRACK" ] && grep -q 'AudioTrack::legacy_callback_t' "$ATRACK"; then
  sed -i 's/AudioTrack::legacy_callback_t/legacy_callback_t/g' "$ATRACK"
  grn "fixup: AudioTrack.cpp AudioTrack::legacy_callback_t -> legacy_callback_t"
else
  grn "fixup: AudioTrack.cpp legacy_callback_t already handled (skip)"
fi

# 8) sepolicy: vendor/aospa/sepolicy/vendor/hal_lineage_health_default.te references QCOM-style
#    sysfs types (vendor_sysfs_battery_supply, vendor_sysfs_usb_supply) that only device/qcom
#    sepolicy defines — the MediaTek device sepolicy doesn't, so the vendor sepolicy fails to
#    compile ("unknown type"). Define them in the device vendor sepolicy (BOARD_VENDOR_SEPOLICY_DIRS
#    += device/itel/S666LN/sepolicy/vendor). Inert (LineageHealth service disabled). We APPEND to an
#    existing file.te (not a new file) so soong's glob cache stays valid -> no full re-analysis.
FT="$DEV/sepolicy/vendor/file.te"
if [ -f "$FT" ] && ! grep -q 'AOSPA-COMPAT battery/usb supply' "$FT"; then
  cat >> "$FT" <<'EOF'

# AOSPA-COMPAT battery/usb supply: define QCOM-style sysfs types AOSPA's hal_lineage_health_default
# references but MediaTek sepolicy lacks. Inert (health service disabled). See PORT-NOTES.md.
type vendor_sysfs_battery_supply, sysfs_type, fs_type;
type vendor_sysfs_usb_supply, sysfs_type, fs_type;
EOF
  grn "fixup: appended vendor_sysfs_battery/usb_supply types to device file.te"
else
  grn "fixup: sepolicy battery/usb supply types already handled (skip)"
fi

# 9) sepolicy property type: device/itel/S666LN/sepolicy/vendor/property_contexts maps
#    persist.vendor.camera.* / vendor.camera.sensor. to vendor_persist_camera_prop, which is defined
#    only in device/lineage/sepolicy/common/ — a dir NOT wired into the sepolicy build (only
#    .../libperfmgr is). So it's absent from the compiled policy -> property_info_checker fails.
#    Define ONLY it (vendor_camera_prop / vendor_fingerprint_prop are already in .../sepolicy/public
#    /property.te — redefining = duplicate-declaration error). Append to existing property.te -> no
#    soong re-analysis.
PT="$DEV/sepolicy/vendor/property.te"
if [ -f "$PT" ] && ! grep -q 'vendor_persist_camera_prop' "$PT"; then
  cat >> "$PT" <<'EOF'

# AOSPA-COMPAT: vendor_persist_camera_prop is defined only in device/lineage/sepolicy/common (not
# wired into the build), so it's missing from the compiled policy. Define it. See PORT-NOTES.md.
vendor_internal_prop(vendor_persist_camera_prop)
EOF
  grn "fixup: appended vendor_persist_camera_prop type to device property.te"
else
  grn "fixup: sepolicy vendor_persist_camera_prop type already handled (skip)"
fi

# 10) boot-jars package allowlist: check_boot_jars fails because two boot jars carry packages not in
#     build/soong/scripts/check_boot_jars/package_allowed_list.txt — framework.jar has
#     vendor.lineage.health.* (AOSPA compiles the vendor.lineage.health interface into framework) and
#     mediatek-common.jar has com.mediatek.common.* (device adds mediatek-common as a boot jar).
#     Allowlist com.mediatek.* + vendor.lineage.* (standard MTK/Lineage additions). Build-script data
#     file, not a .bp -> no soong re-analysis.
AL="$TOP/build/soong/scripts/check_boot_jars/package_allowed_list.txt"
if [ -f "$AL" ] && ! grep -q 'AOSPA S666LN port adds' "$AL"; then
  cat >> "$AL" <<'EOF'

# AOSPA S666LN port adds: mediatek-common boot jar (com.mediatek.*) + AOSPA's vendor.lineage.health
# interface classes compiled into framework.jar (vendor.lineage.*).
com\.mediatek
com\.mediatek\..*
vendor\.lineage
vendor\.lineage\..*
EOF
  grn "fixup: added com.mediatek.* + vendor.lineage.* to boot-jar allowlist"
else
  grn "fixup: boot-jar allowlist entries already handled (skip)"
fi

# 11) VINTF check_vintf_compatible: two HALs are in the device manifest but no framework compat
#     matrix covers them -> checkvintf INCOMPATIBLE. (a) vendor.aospa.power/IPowerFeature — AOSPA's
#     matrix covers it, but the device BoardConfig sets DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE
#     with := (override), dropping AOSPA's file. (b) vendor.qti.hardware.wifi.supplicant/
#     ISupplicantVendor — wpa_supplicant's QTI vendor AIDL manifest. Add both (optional) to the
#     device's own framework_compatibility_matrix.xml. It's a vintf input file -> no soong re-analysis.
FCM="$DEV/configs/vintf/framework_compatibility_matrix.xml"
if [ -f "$FCM" ] && ! grep -q 'vendor.aospa.power' "$FCM"; then
  python3 - "$FCM" <<'PY'
import sys
p = sys.argv[1]
add = """    <hal format="aidl" optional="true">
        <name>vendor.aospa.power</name>
        <interface>
            <name>IPowerFeature</name>
            <instance>default</instance>
        </interface>
    </hal>
    <hal format="aidl" optional="true">
        <name>vendor.qti.hardware.wifi.supplicant</name>
        <interface>
            <name>ISupplicantVendor</name>
            <instance>default</instance>
        </interface>
    </hal>
</compatibility-matrix>"""
s = open(p).read()
open(p, "w").write(s.replace("</compatibility-matrix>", add, 1))
PY
  grn "fixup: added vendor.aospa.power + qti wifi supplicant HALs to device framework compat matrix"
else
  grn "fixup: VINTF compat matrix HALs already handled (skip)"
fi

# 12) radio/firmware images for the OTA: vendor/itel/S666LN/Android.mk registers the MediaTek
#     firmware images (dpm/gz/lk/logo/mcupm/md1img/pi_img/scp/spmfw/sspm/tee/tkv) via the macro
#     `add-radio-file-sha1-checked` — which Android 16 RENAMED to `add-radio-file-checked` (same
#     signature). The old name is undefined -> silently a no-op -> INSTALLED_RADIOIMAGE_TARGET empty
#     -> `m otapackage` fails "Failed to find dpm.img" in CheckAbOtaImages (these partitions are in
#     AB_OTA_PARTITIONS via vendor BoardConfigVendor.mk). The images (real firmware, SHA1-verified;
#     radio/lk.img IS the fenrir LK) are already in vendor/itel/S666LN/radio/. Just fix the macro
#     name. Android.mk (kati) change -> soong stays incremental.
AMK="$TOP/vendor/itel/S666LN/Android.mk"
if [ -f "$AMK" ] && grep -q 'add-radio-file-sha1-checked' "$AMK"; then
  sed -i 's/add-radio-file-sha1-checked/add-radio-file-checked/g' "$AMK"
  grn "fixup: vendor/itel Android.mk add-radio-file-sha1-checked -> add-radio-file-checked (radio images for OTA)"
else
  grn "fixup: radio-file macro already handled (skip)"
fi

############################################
# ON-DEVICE FIX ROUND (2026-07-18) — all four live-validated over adb before landing.
############################################

# 13) TELEPHONY/SIM: AOSPA's telephony packages (TelephonyProvider/Mms/Stk/CarrierDefaultApp/
#     ImsServiceEntitlement/AlternativeNetworkAccess) are QTI "QSPA" variants whose manifests carry
#     <overlay ... requiredSystemPropertyName="ro.boot.vendor.qspa.modem" value="enabled">.
#     Unset on MediaTek -> PackageManager SKIPS the whole APK at scan -> no telephony/mms-sms
#     authority -> com.android.phone crash-loops -> radio never powers on -> "no SIM".
#     Fix (Option A, live-validated: setprop + framework restart -> both SIMs LOADED, carriers
#     visible, phone process stable, no QSPA side effects — the QSPA services themselves are not
#     built for mt6789): set the prop via bootconfig. androidboot.* entries in BOARD_KERNEL_CMDLINE
#     are moved into vendor_boot's bootconfig by the v4 boot build (proven: androidboot.serialconsole
#     from this same list shows in /proc/bootconfig on device). BoardConfig append -> kati re-run,
#     no soong .bp re-analysis.
BC="$DEV/BoardConfig.mk"
if [ -f "$BC" ] && ! grep -q 'vendor.qspa.modem' "$BC"; then
  cat >> "$BC" <<'EOF'

# AOSPA-COMPAT (apply-overlays.sh): ungate AOSPA's QSPA-flavored telephony packages on this
# MediaTek device — their manifests require ro.boot.vendor.qspa.modem=enabled or PackageManager
# skips the APKs entirely (no TelephonyProvider -> phone crash-loop -> no SIM). See PORT-NOTES.md.
BOARD_KERNEL_CMDLINE += androidboot.vendor.qspa.modem=enabled
EOF
  grn "fixup: BOARD_KERNEL_CMDLINE += androidboot.vendor.qspa.modem=enabled (telephony/SIM)"
else
  grn "fixup: qspa.modem bootconfig already handled (skip)"
fi

# 13b) TELEPHONY — Option B: PERMANENT de-gate that makes vendor_boot IRRELEVANT. Strip the QSPA
#      `<overlay ... requiredSystemPropertyName="ro.boot.vendor.qspa.modem" .../>` block from the 5
#      telephony manifests so the packages ALWAYS install, with ZERO dependency on any boot param.
#      This is the real fix for the "OrangeFox auto-reflashes vendor_boot after install -> wipes the
#      patched cmdline -> telephony breaks" trap (community expects vendor_boot not to matter, like
#      the Lineage-based RS4 ROMs). All 5 are PRIMARY packages (real <application>); the self-overlay
#      is purely AOSPA's QSPA gate hack, so removing it returns them to normal always-present
#      packages. Settings/TelephonyUtils.java reads the prop only for minor UI (takes the non-QSPA
#      path when unset = correct for MediaTek). Manifest edit -> rebuilds only those APKs, NO soong
#      re-analysis. Idempotent (guarded on the qspa string). See PORT-NOTES.md + JOURNAL.
#      TRANSITION NOTE: step 13 (the bootconfig param) is KEPT this build as a belt-and-suspenders
#      safety net. VERIFY telephony works on a STRIPPED/stock vendor_boot (no param) to prove
#      vendor_boot no longer matters, THEN next build: remove step 13, deprecate
#      patch-vendorboot-qspa.py, simplify the README recovery section.
for qm in \
  "packages/providers/TelephonyProvider/AndroidManifest.xml" \
  "packages/services/Mms/AndroidManifest.xml" \
  "packages/apps/Stk/AndroidManifest.xml" \
  "packages/apps/ImsServiceEntitlement/AndroidManifest.xml" \
  "packages/services/AlternativeNetworkAccess/AndroidManifest.xml"; do
  qf="$TOP/$qm"
  if [ -f "$qf" ] && grep -q 'ro.boot.vendor.qspa.modem' "$qf"; then
    perl -0777 -pi -e 's{\n?[ \t]*<overlay\b[^>]*ro\.boot\.vendor\.qspa\.modem[^>]*/>}{}g' "$qf"
    if grep -q 'ro.boot.vendor.qspa.modem' "$qf"; then
      red "ERROR: QSPA gate NOT stripped from $qm — inspect the manifest form manually"
    else
      grn "fixup: stripped QSPA overlay gate from $qm (telephony no longer needs vendor_boot param)"
    fi
  else
    grn "fixup: QSPA gate already stripped from $qm (skip)"
  fi
done

# 14) SENSORS: /vendor/etc/sensors/hals.conf (from device configs) lists
#     android.hardware.sensors@2.0-subhal-impl-1.0.so + sensors.dynamic_sensor_hal.so — NEITHER
#     exists in the AOSPA tree (the first is a Lineage hardware/mediatek module absent from the
#     MillenniumOSS 'sixteen' branch; the maintainer's own A16 branches have the same phantom refs).
#     The multihal therefore loaded ZERO subhals -> "No Sensors on the device". The REAL MediaTek
#     subhal is a stock vendor blob already installed by the vendor tree:
#     /vendor/lib64/hw/android.hardware.sensors@2.X-subhal-mediatek.so (exports sensorsHalGetSubHal,
#     wraps sensors.mediatek.V2.0 -> /dev/hf_manager, which registers 21 sensors kernel-side).
#     Live-validated via bind-mounted conf + HAL restart: 22 h/w sensors enumerated and running.
#     PRODUCT_COPY_FILES source content change -> vendor image repack only, no re-analysis.
HALSCONF="$DEV/configs/sensors/hals.conf"
if [ -f "$HALSCONF" ] && ! grep -q 'subhal-mediatek' "$HALSCONF"; then
  printf '/vendor/lib64/hw/android.hardware.sensors@2.X-subhal-mediatek.so\n' > "$HALSCONF"
  grn "fixup: hals.conf -> MediaTek blob subhal (sensors)"
else
  grn "fixup: hals.conf already handled (skip)"
fi

# 15) WIFI: AOSPA's QTI-patched wpa_supplicant registers an extra vendor AIDL service
#     (vendor.qti.hardware.wifi.supplicant.ISupplicantVendor/default). Unlabeled on this device it
#     maps to default_android_service -> SELinux denies the add -> wpa_supplicant treats that as
#     FATAL (exit 255) -> WiFi never comes up. (The old qcwcn-HAL theory was DISPROVEN on-device:
#     the built libwifi-hal.so IS the MediaTek variant — MTK's HAL is a QCA code fork, hence the
#     QCA-looking log tags. HAL + wlan0/wlan1 + wificond all work.) Live-validated: with the add
#     permitted, supplicant stays up and real scan results come back on 2.4+5 GHz.
#     Fix = label the service exactly as AOSPA's own Qualcomm devices do
#     (device/qcom/sepolicy_vndr/generic/vendor/common/service_contexts:61):
#     hal_wifi_supplicant_service is a standard AOSP public type whose add/find rules already exist.
SC="$DEV/sepolicy/vendor/service_contexts"
if ! grep -qs 'ISupplicantVendor' "$SC"; then
  cat >> "$SC" <<'EOF'
# AOSPA-COMPAT: QTI vendor AIDL service registered by AOSPA's wpa_supplicant; label it like
# device/qcom/sepolicy_vndr does or the denied add is fatal to supplicant startup (no WiFi).
vendor.qti.hardware.wifi.supplicant.ISupplicantVendor/default    u:object_r:hal_wifi_supplicant_service:s0
EOF
  grn "fixup: labeled QTI ISupplicantVendor service (WiFi supplicant)"
else
  grn "fixup: ISupplicantVendor service label already handled (skip)"
fi

# 16) SELINUX LOG-SPAM (QCOM framework contamination, all lookups of things that don't exist on
#     MediaTek — functionally harmless, but thousands of avc lines):
#     a) system_server display/power threads (+cameraserver) read QC-only vendor props that don't
#        exist here -> the read lands on the vendor_default_prop fallback context. An allow would
#        violate the treble sysprop neverallow (vendor_internal_prop), so dontaudit — the reads
#        return empty/default either way.
#     b) framework lookups of vendor.qti...IServicetracker + MTK vendor.perfservice (we ship the
#        mtkpower STUB, so it never registers): label the never-registered names with a dedicated
#        ghost type and dontaudit finds domain-wide.
#     Placed in the device's SYSTEM_EXT private sepolicy dir (compiles with system policy, so
#     system_server/domain/vendor_default_prop are all referencable).
QT="$DEV/sepolicy/private/quiet_qcom_ghosts.te"
if [ ! -f "$QT" ]; then
  cat > "$QT" <<'EOF'
# AOSPA-COMPAT (S666LN): silence avc spam from AOSPA's Qualcomm-flavored framework probing QC-only
# vendor props/services that do not exist on this MediaTek device. See PORT-NOTES.md.
dontaudit system_server vendor_default_prop:file { getattr open read map };
dontaudit cameraserver vendor_default_prop:file { getattr open read map };
type ghost_vendor_service, service_manager_type;
dontaudit domain ghost_vendor_service:service_manager find;

# MTK camera HAL probes the secure (SVP/WFD/protected) dma-heaps via cameraserver at init; normal
# camera use never needs them (capture verified working). Quiet the probe denials.
dontaudit cameraserver dmabuf_system_secure_heap_device:chr_file { open read };
# GMS polls adbd state props for its security telemetry; read is denied by design — quiet it.
dontaudit gmscore_app system_adbd_prop:file { getattr open read map };
EOF
  grn "fixup: added quiet_qcom_ghosts.te (dontaudit QC prop reads + ghost service type)"
else
  grn "fixup: quiet_qcom_ghosts.te already present (skip)"
fi
PSC="$DEV/sepolicy/private/service_contexts"
if ! grep -qs 'ghost_vendor_service' "$PSC"; then
  cat >> "$PSC" <<'EOF'
# AOSPA-COMPAT: never-registered service names the QC-flavored framework keeps looking up; label
# them so the finds hit the dontaudited ghost type instead of default_android_service spam.
vendor.qti.hardware.servicetrackeraidl.IServicetracker/default   u:object_r:ghost_vendor_service:s0
vendor.perfservice                                               u:object_r:ghost_vendor_service:s0
EOF
  grn "fixup: labeled servicetracker + vendor.perfservice as ghost_vendor_service"
else
  grn "fixup: ghost service_contexts already handled (skip)"
fi

# 17) BLUETOOTH AUDIO (a): AOSPA carries a QTI patch in hardware/interfaces/bluetooth/audio/aidl/
#     default/service.cpp ("QTI_BEGIN ... Reject AOSP HAL-Interface registration") that makes
#     createIBluetoothAudioProviderFactory() return STATUS_UNKNOWN_ERROR immediately — on QC devices
#     their proprietary BT-audio HAL replaces it; on MediaTek there is NO other provider, so A2DP
#     connects but no audio session can start ("Failed to setup the bluetooth audio HAL",
#     "APM failed to make available A2DP device"). Remove the sabotage block. .cpp change ->
#     ninja-incremental, no soong re-analysis.
BTAS="$TOP/hardware/interfaces/bluetooth/audio/aidl/default/service.cpp"
if [ -f "$BTAS" ] && grep -q 'Reject AOSP HAL-Interface registration' "$BTAS"; then
  # NOTE: the file carries TWO QTI marker pairs — one wrapping the early-return sabotage, one at
  # the very end of the file wrapping the function's closing brace. The range-delete removes BOTH
  # regions, so the closing brace must be restored afterwards (cost a build failure on 2026-07-18).
  sed -i '/QTI_BEGIN.*Reject AOSP HAL-Interface registration/,/QTI_END.*Reject AOSP HAL-Interface registration/d' "$BTAS"
  if [ "$(grep -c '{' "$BTAS")" != "$(grep -c '}' "$BTAS")" ]; then
    printf '}\n' >> "$BTAS"
  fi
  [ "$(grep -c '{' "$BTAS")" = "$(grep -c '}' "$BTAS")" ] \
    && grn "fixup: removed QTI 'Reject AOSP HAL registration' block (braces verified balanced)" \
    || red "ERROR: service.cpp braces unbalanced after QTI block removal — inspect manually"
else
  grn "fixup: BT audio QTI reject block already handled (skip)"
fi

# 18) BLUETOOTH AUDIO (b): nothing in this build CALLS createIBluetoothAudioProviderFactory —
#     the MTK BT HAL (hardware/mediatek/aidl/bluetooth) registers only IBluetoothHci. Make it also
#     load the AOSP impl lib (installed by device.mk as android.hardware.bluetooth.audio-impl:64)
#     via dlopen and register the provider factory. dlopen (not shared_libs) keeps Android.bp
#     untouched -> no soong re-analysis. Idempotent (marker).
MTKBTS="$TOP/hardware/mediatek/aidl/bluetooth/service.cpp"
if [ -f "$MTKBTS" ] && ! grep -q 'AOSPA-COMPAT bt-audio' "$MTKBTS"; then
  python3 - "$MTKBTS" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('#include "BluetoothHci.h"',
              '#include <dlfcn.h>\n\n#include "BluetoothHci.h"', 1)
snippet = """    // AOSPA-COMPAT bt-audio: register the AOSP IBluetoothAudioProviderFactory/default from
    // this process (no other process provides it on this MediaTek device; AOSPA's QTI builds
    // register a proprietary one instead). The impl lib is installed by device.mk.
    void* btaudio_impl = dlopen("android.hardware.bluetooth.audio-impl.so", RTLD_NOW);
    if (btaudio_impl != nullptr) {
        typedef binder_status_t (*createFactoryFn)();
        createFactoryFn fn = reinterpret_cast<createFactoryFn>(
            dlsym(btaudio_impl, "createIBluetoothAudioProviderFactory"));
        if (fn != nullptr) {
            binder_status_t st = fn();
            ALOGI("BluetoothAudioProviderFactory registration status=%d", st);
        } else {
            ALOGE("createIBluetoothAudioProviderFactory not found in impl lib");
        }
    } else {
        ALOGE("failed to dlopen android.hardware.bluetooth.audio-impl.so: %s", dlerror());
    }

    if (result == STATUS_OK) {"""
s = s.replace('    if (result == STATUS_OK) {', snippet, 1)
open(p, "w").write(s)
PY
  grep -q 'AOSPA-COMPAT bt-audio' "$MTKBTS" && grn "fixup: MTK BT service now registers the BT audio provider factory" || red "ERROR: MTK BT service.cpp patch did not apply"
else
  grn "fixup: MTK BT service bt-audio registration already handled (skip)"
fi

# 19) BLUETOOTH AUDIO (c): IBluetoothAudioProviderFactory/default is labeled hal_audio_service in
#     system service_contexts, and a system neverallow restricts the add to hal_audio_server
#     domains. Make mtk_hal_bluetooth a hal_audio server + wire binder both ways to the audio HAL
#     (audio.bluetooth.default runs inside hal_audio_default and connects to the factory).
#     Checked: no execute_no_trans/audio_device rules on mtk_hal_bluetooth -> hal_audio neverallows
#     are safe. APPEND to the EXISTING hal_audio_default.te — the device sepolicy dirs are soong
#     globs in A16, so a NEW .te file would force a full ~1h re-analysis; a content append doesn't.
BTTE="$DEV/sepolicy/vendor/hal_audio_default.te"
if [ -f "$BTTE" ] && ! grep -q 'AOSPA-COMPAT BT audio' "$BTTE"; then
  cat >> "$BTTE" <<'EOF'

# AOSPA-COMPAT BT audio (S666LN): the MTK BT HAL process registers the AOSP
# IBluetoothAudioProviderFactory/default (labeled hal_audio_service — only hal_audio servers may
# add it, per the system neverallow). audio.bluetooth.default (inside hal_audio_default) talks to
# the factory over binder. Appended to this EXISTING .te so the sepolicy soong glob stays unchanged
# (a new .te file would force a full ~1h re-analysis). See PORT-NOTES.md.
hal_server_domain(mtk_hal_bluetooth, hal_audio)
binder_call(hal_audio_default, mtk_hal_bluetooth)
binder_call(mtk_hal_bluetooth, hal_audio_default)
EOF
  grn "fixup: appended BT-audio server rules to hal_audio_default.te"
else
  grn "fixup: BT-audio sepolicy rules already handled (skip)"
fi

# 20) Drop Abstruct (operator opt-out): AOSPA bundles the paid Abstruct wallpaper app as a prebuilt
#     (vendor/aospa/prebuilt/Abstruct, PRODUCT_PACKAGES in aospa-target.mk). Comment the entry so it
#     isn't installed. .mk change -> kati re-run only (no soong analysis; the android_app_import
#     module still exists, just uninstalled). NOTE: if a previous build staged it, remove the stale
#     out/ staging dir before the next image build or it lingers in system/product.
ATM="$TOP/vendor/aospa/target/product/aospa-target.mk"
if [ -f "$ATM" ] && grep -qE '^[[:space:]]+Abstruct[[:space:]]*$' "$ATM"; then
  python3 - "$ATM" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("# Abstruct\nPRODUCT_PACKAGES += \\\n    Abstruct\n",
              "# Abstruct — removed for S666LN (operator opt-out, apply-overlays step 20)\n"
              "# PRODUCT_PACKAGES += \\\n#     Abstruct\n", 1)
open(p, "w").write(s)
PY
  grep -q 'Abstruct — removed' "$ATM" && grn "fixup: Abstruct excluded from PRODUCT_PACKAGES" || red "ERROR: Abstruct removal did not apply"
else
  grn "fixup: Abstruct already excluded (skip)"
fi

# 21) 32-BIT MALI GLES/VULKAN + MTK GRALLOC MAPPER: the vendor repo only extracted the 64-bit GPU
#     stack — /vendor/lib/egl had NO driver, so every 32-bit process touching EGL aborted
#     ("couldn't find an OpenGL ES implementation": mediaserver32 crash-loop, 50 tombstones;
#     32-bit apps/games unrenderable). Blobs harvested from the stock itel-RS4-S666LN-28 vendor
#     image (super.img → lpunpack → fsck.erofs), DT_NEEDED closure verified against the built
#     image (mali + vulkan + mapper + gralloc.common + 18 companion libs, ~30 MB). Kept in
#     $SELF_DIR/blobs32 (survives re-sync); rsynced into the tracked vendor repo here. Installed
#     via PRODUCT_COPY_FILES in aospa_S666LN.mk (kati-only; the device sets
#     BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES). See PORT-NOTES.md + JOURNAL 2026-07-18.
VLIB="$TOP/vendor/itel/S666LN/proprietary/vendor/lib"
if [ -d "$SELF_DIR/blobs32" ]; then
  mkdir -p "$VLIB/egl/mt6789" "$VLIB/hw/mt6789"
  cp -f "$SELF_DIR/blobs32/egl/mt6789/libGLES_mali.so" "$VLIB/egl/mt6789/"
  cp -f "$SELF_DIR/blobs32/hw/mt6789/"*.so "$VLIB/hw/mt6789/"
  cp -f "$SELF_DIR/blobs32/"*.so "$VLIB/"
  grn "fixup: 32-bit Mali/vulkan/mapper blobs staged into vendor tree ($(ls "$SELF_DIR/blobs32"/*.so | wc -l)+4 libs)"
else
  red "WARN: $SELF_DIR/blobs32 missing — 32-bit GPU blobs NOT staged"
fi

# 22) RELEASE SIGNING KEYS (2026-07-19, RC): stage our private release keys into the source tree so
#     aospa_S666LN.mk's `PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/aospa-priv/keys/releasekey`
#     resolves. Keys (releasekey/platform/shared/media/networkstack/nfc/bluetooth/sdk_sandbox/
#     cts_uicc_2021 + testkey, no-password RSA-2048) live in $SELF_DIR/keys-priv (gitignored, survives
#     re-sync). testkey == a copy of releasekey: system/sepolicy/private/keys.conf's [@RELEASE] tag
#     hardcodes $DEFAULT_SYSTEM_DEV_CERTIFICATE_dir/testkey.x509.pem, so the mac_permissions seinfo for
#     default-signed apps must equal our default cert. Missing testkey => "needed by
#     product_mac_permissions.xml, missing and no known rule to make it" (the rc3 build failure).
#     Keys are generated with development/tools/make_key. vendor/aospa-priv is NOT a manifest project,
#     so repo sync never touches it, but stage every run for robustness. Setting the default cert to a
#     non-testkey signs all APKs/APEX containers with our key and takes ro.build.tags OFF test-keys ->
#     dev-keys (verified on the rc7 build; the release-keys tag needs the formal sign_target_files_apks
#     re-sign flow, not in-tree signing — dev-keys still passes the "not test-keys" fraud/banking check).
#     See JOURNAL 2026-07-19 + PORT-NOTES "Release signing".
KEYDST="$TOP/vendor/aospa-priv/keys"
if [ -d "$SELF_DIR/keys-priv" ] && ls "$SELF_DIR/keys-priv"/releasekey.pk8 >/dev/null 2>&1; then
  mkdir -p "$KEYDST"
  cp -f "$SELF_DIR/keys-priv/"*.pk8 "$SELF_DIR/keys-priv/"*.x509.pem "$KEYDST/"
  chmod 600 "$KEYDST/"*.pk8
  grn "fixup: release signing keys staged into vendor/aospa-priv/keys ($(ls "$KEYDST"/*.pk8 | wc -l) keys)"
else
  red "WARN: $SELF_DIR/keys-priv/releasekey.pk8 missing — release keys NOT staged (build would fall back to testkey)"
fi

# 23) CAMERA RAW/DNG (2026-07-20): make the MTK camera HAL advertise RAW capability so Camera2 apps
#     can shoot DNG. The device supports it, but the stock blobs don't expose it — the community
#     workaround is the Itel_RS4_RAW_v2 Magisk module, which overlays two camera-HAL libs at
#     /vendor/lib64/. Staging them into the vendor tree gives every user the same result with NO ROOT,
#     and puts them at /vendor/lib64/mt6789/ (the canonical path these libs load from; the Magisk
#     module's /vendor/lib64/ copies only worked by shadowing the search path).
#     Drop-in safety was verified before staging: identical SONAME, identical DT_NEEDED (16 and 35
#     entries) and identical 706-symbol dynamic export sets vs stock => soong check_elf_file passes
#     with the existing Android.bp modules unchanged. libmtkcam_3rdparty.customer.so is the SAME
#     binary (same build ID) with a 10-byte .text patch (one b.ne -> NOP plus two immediates);
#     libmtkcam_metastore.so is a different build of the same source (identical sensor-metadata set).
#     Aperture already implements DNG capture (ImageCapture.OUTPUT_FORMAT_RAW), so the RAW toggle
#     appears in the camera app once the HAL advertises the capability — no app change needed.
#     Blob-only change => kati/packaging re-run, NO soong re-analysis.
#     See blobs-camera-raw/README.md + PORT-NOTES.md + JOURNAL 2026-07-20.
RAWSRC="$SELF_DIR/blobs-camera-raw"
RAWDST="$TOP/vendor/itel/S666LN/proprietary/vendor/lib64/mt6789"
if [ -d "$RAWSRC" ] && [ -d "$RAWDST" ]; then
  raw_n=0
  for so in libmtkcam_3rdparty.customer.so libmtkcam_metastore.so; do
    if [ ! -f "$RAWSRC/$so" ]; then
      red "WARN: $RAWSRC/$so missing — camera RAW blob NOT staged"
      continue
    fi
    # Back up the stock blob once, before the first overwrite (never re-take it: after step 23 has
    # run, the tree copy IS the patched one and a re-backup would destroy the stock reference).
    [ -f "$RAWDST/$so.stock" ] || cp -f "$RAWDST/$so" "$RAWDST/$so.stock"
    cp -f "$RAWSRC/$so" "$RAWDST/$so"
    raw_n=$((raw_n+1))
  done
  if [ "$raw_n" -eq 2 ]; then
    grn "fixup: camera RAW/DNG blobs staged into vendor tree (2 libs, stock kept as *.so.stock)"
  else
    red "ERROR: camera RAW staging incomplete ($raw_n/2 libs)"
  fi
else
  red "WARN: $RAWSRC or $RAWDST missing — camera RAW/DNG blobs NOT staged"
fi

# 24) GMS SAFETYCENTER FORCE-CLOSE (2026-07-20): the one bug advertised as "known issue" in the v2
#     release notes. `com.google.android.gms` FCs with
#     `IllegalArgumentException: Unexpected safety source: AdvancedProtection`.
#     ROOT CAUSE: this build ships the AOSP mainline Permission module (com.android.permission),
#     whose SafetyCenter config declares only AOSP safety sources. GMS ships Google's variant of that
#     module, whose config additionally declares the Android-16 "Advanced Protection" source. GMS
#     calls SafetyCenterManager.setSafetySourceData("AdvancedProtection", ...); SafetySourceDataValidator
#     .validateRequest() looks the id up in the config, gets null, and throws (SafetySourceDataValidator
#     .java:85) -> GMS crashes. Nothing on the device is actually broken, but it FCs on every boot.
#     FIX: declare the source so the call is accepted. Deliberately MINIMAL — a hidden dynamic source
#     with no strings and no intent:
#       * initialDisplayState="hidden" => per SafetySource.Builder.build(), title/summary/intentAction
#         are all NOT required (titleRequired = isDynamicNotHidden || isDynamicHiddenWithSearch ||
#         isStatic — all false here), so NO new string resources are needed and the UI is unchanged.
#       * when GMS does push data, SafetySourceStatus.Builder requires non-null title+summary, so the
#         rendered entry takes its text from GMS, not from the config.
#       * maxSeverityLevel is omitted => defaults to Integer.MAX_VALUE, so GMS cannot trip the
#         "exceeds max severity" throw either.
#       * placed in AndroidAdvancedSources, which is STATEFUL (no statelessIconType) — a stateless
#         group would throw if GMS reported any severity above UNSPECIFIED.
#       * profile="all_profiles" is the permissive choice: primary_profile_only would throw
#         "Unexpected profile type" if GMS ever pushed for a work/private profile.
#     Modifies an existing resource file (no new file in a glob) => ninja-incremental rebuild of the
#     com.android.permission APEX, NO ~1 h soong re-analysis. See PORT-NOTES.md + JOURNAL 2026-07-20.
SCCFG_N=0
for SCCFG in "$TOP"/packages/modules/Permission/SafetyCenter/Resources/res/raw*/safety_center_config.xml; do
  [ -f "$SCCFG" ] || continue
  grep -q 'id="AndroidAdvancedSources"' "$SCCFG" || continue
  if grep -q 'id="AdvancedProtection"' "$SCCFG"; then
    SCCFG_N=$((SCCFG_N+1)); continue
  fi
  python3 - "$SCCFG" <<'PY'
import sys, xml.etree.ElementTree as ET
p = sys.argv[1]
s = open(p).read()
anchor = '''        <safety-sources-group
            id="AndroidAdvancedSources"'''
if anchor not in s:
    sys.exit("anchor not found in " + p)
entry = '''            <!-- Declared so GMS's Advanced Protection push is accepted instead of throwing
                 "Unexpected safety source" and force-closing Play services. Hidden and string-free:
                 the entry only appears if GMS supplies data, and then uses GMS's own title/summary. -->
            <dynamic-safety-source
                id="AdvancedProtection"
                packageName="com.google.android.gms"
                profile="all_profiles"
                initialDisplayState="hidden"/>
'''
# insert as the first child of the AndroidAdvancedSources group
i = s.index(anchor)
j = s.index('>', s.index('title=', i)) + 1      # end of the group's opening tag
out = s[:j] + '\n' + entry.rstrip('\n') + s[j:]
ET.fromstring(out)                              # fail loudly rather than ship a broken config
open(p, 'w').write(out)
PY
  if grep -q 'id="AdvancedProtection"' "$SCCFG"; then
    SCCFG_N=$((SCCFG_N+1))
  else
    red "ERROR: AdvancedProtection source not inserted into $SCCFG"
  fi
done
if [ "$SCCFG_N" -gt 0 ]; then
  grn "fixup: GMS SafetyCenter AdvancedProtection source declared ($SCCFG_N config(s))"
else
  red "WARN: no safety_center_config.xml patched — GMS SafetyCenter FC not fixed"
fi

# 25) QTI SERVICETRACKER LOG FLOOD (2026-07-20): system_server floods the log every boot —
#     ~5,555x `avc: denied { find } vendor.qti.hardware.servicetracker::IServicetracker` (HIDL) plus
#     the AIDL variant, each denial ALSO surfacing as a SecurityException from ServiceManager.
#     ROOT CAUSE: AOSPA carries QTI patches in ActiveServices.java that report every service
#     lifecycle event to Qualcomm's Servicetracker HAL. That HAL does not exist on MediaTek, and
#     `getServicetrackerInstance()` re-probes it on EVERY service event, because the probe leaves
#     `mServicetracker` null and there is no "already tried" state. The AIDL path is already latched
#     (mIsAIDLSupported, set once from ServiceManager.isDeclared in the constructor); the HIDL path
#     is not — hence thousands of lookups per boot.
#     NOTE the earlier sepolicy work (step 16, quiet_qcom_ghosts) only DONTAUDITs the denials: a
#     denied `find` still returns EX_SECURITY from servicemanager (ServiceManager.cpp canFindService),
#     so the SecurityException kept being thrown and logged. dontaudit silences the kernel avc line,
#     not the exception. This step removes the lookups themselves, which is the actual fix; the
#     dontaudit rules stay as belt-and-suspenders.
#     FIX: latch "not present" so each interface is probed at most once per boot. Purely a
#     log/CPU-noise fix — behaviour is unchanged on a device that HAS the HAL (first probe succeeds
#     and the latch never trips); on this device the HAL can never appear, so latching is safe.
#     frameworks/base .java change => services.jar rebuild, NO soong re-analysis.
AS="$TOP/frameworks/base/services/core/java/com/android/server/am/ActiveServices.java"
if [ -f "$AS" ] && ! grep -q 'sServicetrackerUnavailable' "$AS"; then
  python3 - "$AS" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
orig = s

# 1) latch fields, declared next to the two HAL handles
fld_anchor = ("    private vendor.qti.hardware.servicetracker.V1_0.IServicetracker mServicetracker;\n"
              "    private vendor.qti.hardware.servicetrackeraidl.IServicetracker  mServicetracker_aidl;\n")
fld_new = fld_anchor + (
    "    // S666LN: the QTI Servicetracker HAL does not exist on MediaTek. Probe each interface at\n"
    "    // most once instead of on every service lifecycle event (thousands of denied lookups and\n"
    "    // SecurityExceptions per boot otherwise).\n"
    "    private static boolean sServicetrackerUnavailable = false;\n"
    "    private static boolean sServicetrackerAidlUnavailable = false;\n")
assert fld_anchor in s, "servicetracker field anchor not found"
s = s.replace(fld_anchor, fld_new, 1)

# 2) HIDL getter: early-out on the latch, and set it when the interface comes back absent
hidl_old = ("    private boolean getServicetrackerInstance() {\n"
            "        if (mServicetracker == null ) {\n")
hidl_new = ("    private boolean getServicetrackerInstance() {\n"
            "        if (sServicetrackerUnavailable) return false;\n"
            "        if (mServicetracker == null ) {\n")
assert hidl_old in s, "HIDL getter anchor not found"
s = s.replace(hidl_old, hidl_new, 1)

hidl_null_old = ("            if (mServicetracker == null) {\n"
                 "                if (DEBUG_SERVICE) Slog.w(TAG, \"servicetracker HIDL not available\");\n"
                 "                return false;\n"
                 "            }\n")
hidl_null_new = ("            if (mServicetracker == null) {\n"
                 "                if (DEBUG_SERVICE) Slog.w(TAG, \"servicetracker HIDL not available\");\n"
                 "                sServicetrackerUnavailable = true;\n"
                 "                return false;\n"
                 "            }\n")
assert hidl_null_old in s, "HIDL null-check anchor not found"
s = s.replace(hidl_null_old, hidl_null_new, 1)

# 3) AIDL getter: same treatment (mIsAIDLSupported already gates it, but latch the lookup too)
aidl_old = "        if (!mIsAIDLSupported) return false;\n"
aidl_new = "        if (!mIsAIDLSupported || sServicetrackerAidlUnavailable) return false;\n"
assert aidl_old in s, "AIDL gate anchor not found"
s = s.replace(aidl_old, aidl_new, 1)

aidl_null_old = ("            if (mServicetracker_aidl == null) {\n"
                 "                if (DEBUG_SERVICE) Slog.w(TAG, \"servicetracker AIDL not available\");\n"
                 "                return false;\n"
                 "            }\n")
aidl_null_new = ("            if (mServicetracker_aidl == null) {\n"
                 "                if (DEBUG_SERVICE) Slog.w(TAG, \"servicetracker AIDL not available\");\n"
                 "                sServicetrackerAidlUnavailable = true;\n"
                 "                return false;\n"
                 "            }\n")
assert aidl_null_old in s, "AIDL null-check anchor not found"
s = s.replace(aidl_null_old, aidl_null_new, 1)

assert s != orig
open(p, "w").write(s)
PY
  if grep -q 'sServicetrackerUnavailable' "$AS"; then
    grn "fixup: QTI servicetracker probes latched (kills the per-boot denial/SecurityException flood)"
  else
    red "ERROR: servicetracker latch did not apply"
  fi
else
  grn "fixup: QTI servicetracker probe latch already handled (skip)"
fi
