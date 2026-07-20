# PORT-NOTES.md — Lineage device tree → AOSPA (beryl / Android 16) fixups

Living checklist for grafting `KimelaZX/device_itel_S666LN` (lineage-23.2) onto AOSPA beryl.
Status: ✅ done · ⚠️ prepared (apply at build) · 🔎 anticipated (confirm at first `m`).
Verified against the synced tree + AOSPA/LineageOS sources on 2026-07-16 (pre-first-build).

## ✅ Product makefile (done)
- `lineage_S666LN.mk` inherits `vendor/lineage/config/common_full_phone.mk` (absent in AOSPA).
- Replaced with `aospa_S666LN.mk` inheriting `vendor/aospa/target/product/aospa-target.mk`
  (the real AOSPA per-device pattern, copied from `aospa_phone2.mk`). `AndroidProducts.mk`
  registers ONLY `aospa_S666LN`, so no Lineage product makefile is parsed → nothing pulls the
  missing `vendor/lineage`. Landed by `apply-overlays.sh`.

## ✅ Camera / Aperture (done)
- AOSPA beryl already ships `packages/apps/Aperture` (LineageOS Aperture @ lineage-23.0) —
  exactly what the device's `overlay-lineage/ApertureOverlay` RRO targets. Dropped our
  duplicate `<project>` from the local manifest (duplicate path breaks `repo sync`); the
  product pulls it via `PRODUCT_PACKAGES += Aperture`.

## ⚠️ Lineage Health charging-control service (CONFIRMED break — fix prepared)
- `device.mk` PRODUCT_PACKAGES has `vendor.lineage.health-service.default`; `BoardConfig.mk`
  sets the `lineage_health` soong namespace (charging-control paths for this device).
- AOSPA ships only the **interface** `vendor.lineage.health` (`vendor/aospa/interfaces/health`,
  `owner: lineage`) — NOT the **service** binary. The service lives in
  `LineageOS/android_hardware_lineage_interfaces` (`health/aidl/default/`), which AOSPA does
  not include → `m` will fail: module `vendor.lineage.health-service.default` not defined.
  Grep of the whole synced tree confirms 0 definitions.
- **Caveat if we just add that Lineage repo:** its `health/aidl/Android.bp` ALSO defines the
  `vendor.lineage.health` aidl_interface → duplicate-module conflict with AOSPA's copy.
- **Fix options:**
  - **(A first-build) Drop the line** — comment `vendor.lineage.health-service.default` out of
    `device.mk`. Device boots; only battery charge-limit control is inactive. The orphaned
    `soong_config_set lineage_health` lines are harmless (no module reads the namespace).
    `apply-overlays.sh` does this (clearly marked, reversible).
  - **(B proper, follow-up) Add the service without the dup interface** — add
    `LineageOS/android_hardware_lineage_interfaces` @ `lineage-23.2` at
    `hardware/lineage/interfaces`, then overlay-remove its `health/aidl/Android.bp` so only the
    `default/` service builds, importing AOSPA's `vendor.lineage.health-V2-ndk`. Restore the
    device.mk line. Do this once the device boots, to get charging control back.
- Chosen: **A for the first boot, B as the follow-up.**

## 🔎 BoardConfigReservedSize (likely benign)
- `BoardConfig.mk`: `-include vendor/lineage/config/BoardConfigReservedSize.mk` — the `-include`
  means it's silently skipped when absent (AOSPA has no vendor/lineage). Build won't break;
  partition reserved sizes fall back to defaults. Watch for image-overflow at packaging; if it
  overflows, set the reserved sizes explicitly in BoardConfig or add an aospa equivalent.

## 🔎 Other device.mk packages (scanned — look clean)
- Only Lineage-flavored entries are the health service (above), `SettingsResTarget` /
  `SettingsProviderResTarget` (the device's OWN `overlay/` RRO targets — fine), and
  `ApertureOverlay` (handled). No Lineage apps (Jelly/Eleven/Etar/…) are pulled → low risk.
- `TARGET_DISABLE_EPPE` (in the retired lineage mk) is Lineage-only; not in aospa_S666LN.mk.

## ✅ AOSPA is QCOM-coupled — MediaTek fix (CONFIRMED break at `lunch`, FIXED)
- `vendor/aospa/target/product/aospa-target.mk:175` unconditionally
  `$(call inherit-product, device/qcom/common/common.mk)`, which **hard-`$(error)`s** at
  product-config time if `TARGET_BOARD_PLATFORM` is unset ("please define in your device
  makefile so it's accessible to QCOM common"). AOSPA assumes every device is Qualcomm.
- **Fix (minimal, zero AOSPA-file patching):** set `TARGET_BOARD_PLATFORM := mt6789` in
  `aospa_S666LN.mk` **before** the aospa-target inherit. common.mk then runs but self-excludes
  its ENTIRE body — all the QSPA/RFS/QTI/`ro.soc.manufacturer=QTI` packages live inside
  `ifeq ($(call is-board-platform-in-list,$(QCOM_BOARD_PLATFORMS)),true)`, and mt6789 ∉ that
  list. Landed in `device-aospa/aospa_S666LN.mk` (via `apply-overlays.sh`).
- The board side was already guarded: `BoardConfigAOSPA.mk:14` includes `BoardConfigQcom.mk`
  only `ifeq is-board-platform-in-list QCOM_BOARD_PLATFORMS` → skipped for us. No change needed.
- `SnapdragonClang.mk` (aospa-target:203) is a no-op here: it only sets `SDCLANG_LTO_DEFS`, a var
  consumed solely by QCOM-board-gated LTO machinery. Left as-is.
- The QTI/CLO `PRODUCT_PACKAGES` (extphonelib, qti-telephony-*, libqti_vndfwk_detect, tcmiface,
  telephony-ext, ims-ext-common) are NOT guarded but **do build** — their soong modules exist in
  the synced tree (`vendor/codeaurora/commonsys`, `vendor/qcom/opensource/*`). Left in; dead
  weight on a MediaTek device but harmless. Guard later if they ever conflict.

## ✅ device/lineage/sepolicy (CONFIRMED break at board config, FIXED)
- `device/mediatek/sepolicy_vndr/SEPolicy.mk:4` includes
  `device/lineage/sepolicy/libperfmgr/sepolicy.mk` (libperfmgr power-HAL sepolicy). AOSPA does
  not ship `device/lineage/sepolicy`. It's the ONLY `device/lineage/*` ref in the whole tree.
- **Fix:** added `LineageOS/android_device_lineage_sepolicy` @ `lineage-23.0` (remote `github`,
  the branch AOSPA beryl uses for its other LineageOS repos) at `device/lineage/sepolicy` to the
  local manifest `S666LN.xml`; synced. The included .mk just appends
  `device/lineage/sepolicy/libperfmgr/vendor` to `BOARD_VENDOR_SEPOLICY_DIRS`; rest unused.

## 🖥️ ENV-SPECIFIC (not a tree bug): shell aliases/functions shadowing `grep`/`find`/`rg`
- If your shell profile defines `grep`/`find`/`rg` as **functions or aliases** (some setups reroute
  them through wrappers like ugrep), AOSPA's `lunch` misbehaves: `build/make/envsetup.sh` does
  `local legacy=$(echo $1 | grep "-")` for legacy-combo parsing; a wrapper that treats `"-"` as an
  operand rather than a pattern errors out → `legacy` empty → lunch mis-parses
  `aospa_S666LN-userdebug` as a whole product name → "Cannot locate config makefile".
- **Fix:** run `unset -f grep find rg` (or `unalias`) in the SAME shell before
  `source build/envsetup.sh && lunch && m`. Non-interactive scripts like `apply-overlays.sh` and
  `m`'s build-rule subshells start clean → unaffected; only the interactive shell running lunch
  needs it. Real GNU grep is at `/usr/bin/grep`.

## ✅ COMPILE-phase fixes (surface only during the ninja compile, not analysis)
Each of these is a `.bp`/source change → triggers the ~1 h soong re-analysis on resume; ninja then
resumes from cache. All wired into apply-overlays.sh (idempotent).
- **ccache "Not a directory"** (HOST, not tree): the first full build died at action 61 because
  `/home/riza/.cache/ccache` was a 0-byte file (nsjail created it, dir didn't pre-exist). `rm -f` +
  `mkdir -p` it, pass `CCACHE_DIR=/home/riza/.cache/ccache` explicitly in the build env. See JOURNAL.
- **libaudioclient_shim / AudioTrack.cpp** (`hardware/lineage/compat`, AOSPA's own repo, ~47%):
  used `AudioTrack::legacy_callback_t` (a member typedef absent from Android-16 `frameworks/av`
  AudioTrack) for `mCallback` + the `LegacyCallbackWrapper` ctor, while the rest of the file uses
  the file-scope `legacy_callback_t` it defines up top. Fix: drop the `AudioTrack::` qualifier
  (`sed 's/AudioTrack::legacy_callback_t/legacy_callback_t/g'`). apply-overlays.sh step 7.
- **sepolicy vendor_sysfs_battery_supply / vendor_sysfs_usb_supply** (~63%, kati/checkpolicy):
  `vendor/aospa/sepolicy/vendor/hal_lineage_health_default.te` references these QCOM-only sysfs
  types; MediaTek sepolicy lacks them → vendor sepolicy won't compile. Define them in the device
  vendor sepolicy (append to `device/itel/S666LN/sepolicy/vendor/file.te`; inert since the health
  service is disabled). apply-overlays.sh step 8. (Appending to an EXISTING .te avoids a soong
  re-analysis — sepolicy .te is a ninja input, not a soong glob change.)
- **libtinyxml2-v34** (~63%, check_elf_file): 3 MediaTek audio/rt blobs (audio.primary.mediatek,
  librt_extamp_intf, +1) are DT_NEEDED against `libtinyxml2-v34.so` — a VNDK-34-versioned libtinyxml2
  soname LineageOS supplied via the VNDK-34 snapshot. AOSPA (A16) dropped VNDK; no such module
  exists → soong can't resolve `shared_libs: ["libtinyxml2-v34"]` (analysis) and check_elf flags the
  unmatched DT_NEEDED (build). **Do NOT rewrite the blobs to plain libtinyxml2** — the .so's
  DT_NEEDED is hard-linked, so that breaks check_elf AND runtime. Instead DEFINE `libtinyxml2-v34` by
  building libtinyxml2's code under the -v34 soname (`cc_library_shared { whole_static_libs:
  ["libtinyxml2"] }`), in the blobs' own namespace (`vendor/itel/S666LN/Android.bp`, alongside the
  working `libalsautils-v31`). apply-overlays.sh step 4. (Other versioned deps — libutils-v31,
  libbinder-v31, libhidlbase-v31, libstagefright_foundation-v33, libalsautils-v31 — are already
  provided as prebuilt .so in device/vendor/itel; only libtinyxml2-v34 was missing.)

## 🔎 SELinux / sepolicy
- Device sepolicy includes `device/mediatek/sepolicy_vndr` (MillenniumOSS `sixteen-qpr2-rebase`,
  synced). AOSPA + MTK sepolicy neverallow deltas may surface at build — fix per error.

## ✅ Kernel (done, separate)
- Custom `5.10.260-Riza-vanilla` swapped into `device/millennium/common-kernel/Image.gz`
  (KMI 0x7c24b32d, matches the 198 vendor_dlkm). See JOURNAL. `apply-overlays.sh` re-applies.

## Host build prereqs
- Present: git, git-lfs, python3, make, m4, zip, unzip, rsync, bc, bison, flex, gperf, openssl,
  xmllint, lz4, zstd, hermetic jdk21; RAM 14G + **40G swap** (ok with capped `-j`).
- **Missing (operator to install — no passwordless sudo):** `ccache` (rebuild speed) and
  `xsltproc` (some build steps). One-liner: `sudo apt install -y ccache xsltproc`.
  32-bit libs (lib32z1/libncurses5) are NOT needed for Android 16 (soong is hermetic).

## 📱 ON-DEVICE FIX ROUND 2 (2026-07-18) — apply-overlays.sh steps 13–16, all live-validated

Theme confirmed again: **AOSPA ships Qualcomm-flavored packages/daemons; on MediaTek they gate off
or fail.** All three "broken subsystem" bugs were exactly this (none were MediaTek-side).

1. **Telephony/SIM (step 13):** AOSPA telephony APKs (TelephonyProvider/Mms/Stk/CarrierDefaultApp/
   ImsServiceEntitlement/AlternativeNetworkAccess) carry `<overlay requiredSystemPropertyName=
   "ro.boot.vendor.qspa.modem" value="enabled">` — unset ⇒ PackageManager SKIPS the APKs.
   Fix: `BOARD_KERNEL_CMDLINE += androidboot.vendor.qspa.modem=enabled` (v4 build moves androidboot.*
   into vendor_boot bootconfig). Option A validated live: both SIMs LOADED, carriers by.U + XL, no
   QSPA side effects (QSPA services aren't built for mt6789; self-overlay stays disabled).
   Option B (sed the `<overlay>` gating out of the 6 manifests) kept as fallback only.
2. **Sensors (step 14):** hals.conf listed two PHANTOM libs (Lineage-only `@2.0-subhal-impl-1.0` —
   absent from MillenniumOSS hardware/mediatek `sixteen`; and sensors.dynamic_sensor_hal) ⇒ multihal
   loaded 0 subhals. Point it at the stock blob subhal
   `/vendor/lib64/hw/android.hardware.sensors@2.X-subhal-mediatek.so` (already installed by
   vendor tree, exports sensorsHalGetSubHal). Kernel/SCP side was NEVER broken (21 sensors in
   /proc/hf_manager). Validated: 22 sensors running.
3. **WiFi (step 15):** libwifi-hal IS the MediaTek build (MTK HAL = QCA fork ⇒ misleading logs; old
   qcwcn-override theory DISPROVEN — nothing includes qti-wlan.mk). Real bug: AOSPA's QTI-patched
   wpa_supplicant fatally exits when SELinux denies registering
   `vendor.qti.hardware.wifi.supplicant.ISupplicantVendor/default` (unlabeled name). Fix: label it
   `hal_wifi_supplicant_service` in device vendor service_contexts (mirrors device/qcom/sepolicy_vndr).
   Validated permissive: supplicant stable, scan returns APs on 2.4+5 GHz.
4. **avc spam (step 16):** dontaudit system_server/cameraserver reads of `vendor_default_prop`
   (nonexistent QC props; allow would hit the treble sysprop neverallow) + new `ghost_vendor_service`
   type for the never-registered `vendor.qti...IServicetracker` and `vendor.perfservice` lookups
   (mtkpower is a stub by design — maintainer parity). SYSTEM_EXT private sepolicy.

**Still open (minor):** GMS SafetyCenter FC (AdvancedProtection source mismatch, GMS-internal,
background-only). Interactive HW verification pending post-reflash: call/data, WiFi join, GPS lock,
BT pair, camera capture, fingerprint enroll (TEE was a one-shot crash; keymint/Widevine verified
working), PE/PD fast charge with a wall charger.

## 🔐 Play Integrity / build fingerprint (bug report 2026-07-18 — fix staged for next build)

**Symptom:** integrity checkers report the device **fingerprint is invalid** → device only reaches
BASIC (fails DEVICE), and STRONG is out of reach.

**Root cause:** the device tree overrides the PER-PARTITION fingerprints to the stock certified
value via `PRODUCT_BUILD_PROP_OVERRIDES += BuildFingerprint=...`
(`ro.system/vendor/product/odm/...build.fingerprint` = `Itel/S666LN-OP/itel-S666LN:13/
TP1A.220624.014/251212V1661:user/release-keys`). BUT the **primary `ro.build.fingerprint`** — the
one `Build.FINGERPRINT` and Play Integrity actually read — is **not written to any build.prop**, so
`init` derives it at runtime (`property_derive_build_fingerprint`, only when unset) from the live
props: `brand/name/device : version.release / build.id / version.incremental : type / tags`. Those
are the real AOSPA A16 values, so it derives an invalid `Itel/S666LN-OP/S666LN:16/BQ2A…:
userdebug/test-keys`.

**Fix (staged in `device-aospa/aospa_S666LN.mk`, VERIFY on next build):** set `ro.build.fingerprint`
explicitly via `PRODUCT_SYSTEM_PROPERTIES` to the stock string → init skips the derive.
Check after building: `adb shell getprop ro.build.fingerprint` must equal the stock value, and an
integrity checker should then show a VALID fingerprint.

**Expectation setting (important, tell users):**
- This fix targets **BASIC → DEVICE** integrity (valid certified fingerprint + fenrir green boot).
- **STRONG is NOT obtainable from a fingerprint fix.** STRONG requires hardware-backed key
  attestation with a keybox Google trusts (TEE/RKP). On an unlocked-bootloader custom ROM that means
  a valid spoofed keybox via a root module (e.g. TrickyStore) — which needs KernelSU/Magisk (the
  ksunext kernel variant exists but this build ships rootless vanilla). So: fingerprint fix ⇒ DEVICE;
  STRONG needs the root+keybox route and is a separate, optional decision.
- For a proper release, also consider building the **user** variant + **release-key** signing so
  `ro.build.type`/`ro.build.tags` stop reading `userdebug`/`test-keys` (some checkers flag those too).

---

## ✅ Camera RAW / DNG without root (2026-07-20 — apply-overlays.sh step 23)

The RS4's camera hardware supports RAW, but the stock MediaTek HAL blobs don't advertise RAW
capability to Camera2, so on AOSP-based ROMs no app can shoot DNG. The community workaround is the
**`Itel_RS4_RAW_v2` Magisk module**, which overlays two camera-HAL libraries at `/vendor/lib64/`.
That fixes it only for rooted users — and this ROM ships rootless by design.

**Fix: stage the same two libraries into the vendor tree** so every user gets RAW with no root:

| lib | installed to |
|---|---|
| `libmtkcam_3rdparty.customer.so` | `/vendor/lib64/mt6789/` |
| `libmtkcam_metastore.so` | `/vendor/lib64/mt6789/` |

Note the path: the Magisk module drops its copies in `/vendor/lib64/`, where they only take effect by
shadowing the linker search path. The vendor tree installs these libs to `/vendor/lib64/mt6789/`
(`relative_install_path: "mt6789"` in `vendor/itel/S666LN/Android.bp`), which is the canonical
location the HAL loads them from — so replacing them there is both simpler and more robust.

**Drop-in safety — verified against the stock blobs before staging:**
- Identical `SONAME` and identical `DT_NEEDED` lists (16 and 35 entries), and identical exported
  symbol sets (706 dynamic symbols, none added or removed). So soong's `check_elf_file` passes with
  the existing `cc_prebuilt_library_shared` definitions unchanged — no `Android.bp` edit needed.
- `libmtkcam_3rdparty.customer.so` is the **same binary** as stock (identical GNU build ID) with a
  **10-byte** `.text` patch: one `b.ne` at file offset `+0x34ef4` replaced by `NOP`, plus two
  immediates changed (`mov w9,#8 / mov w8,#3` → `mov w9,#1 / mov w8,#17`).
- `libmtkcam_metastore.so` is a **different build of the same library** (build ID differs, ~66% of
  `.text` differs, but file and section sizes are identical — the same functions emitted in a
  different order). Its compiled-in image-sensor metadata set is **identical** to stock: the same 75
  `imgsensor_metadata/*` sensor configurations, same names, no additions or removals.

**No app change is needed.** Aperture already implements DNG capture
(`ImageCapture.OUTPUT_FORMAT_RAW` / `OUTPUT_FORMAT_RAW_JPEG`, MIME `image/x-adobe-dng`, with an
`enableRawImageCapture` preference), so the RAW option surfaces in the camera app as soon as the HAL
advertises the capability.

**Build cost:** blob-only change ⇒ kati + image packaging re-run, **no soong re-analysis**.

**Obtaining the blobs:** not redistributed in this repo (proprietary MediaTek code, same policy as
`blobs32/` and the fenrir LK). Extract `system/vendor/lib64/*.so` from the `Itel_RS4_RAW_v2` module
into `blobs-camera-raw/`; `apply-overlays.sh` step 23 stages them and keeps the stock originals as
`*.so.stock` next to the replaced files (restore those to revert).

**On-device verification after flashing:**
- `adb shell dumpsys media.camera | grep -i -A2 "REQUEST_AVAILABLE_CAPABILITIES"` should list RAW.
- Aperture → settings should offer the RAW/DNG photo format, and a capture should produce a `.dng`.
- Regression-check the normal path too: rear + front stills, video, and the fingerprint-unlock
  camera-free paths should be unaffected.

---

## ✅ GMS SafetyCenter force-close (2026-07-20 — apply-overlays.sh step 24)

The one bug advertised as a known issue in the v2 release notes. `com.google.android.gms` force-closes
on every boot with:

```
IllegalArgumentException: Unexpected safety source: AdvancedProtection
```

**Root cause.** This build ships the **AOSP** mainline Permission module (`com.android.permission`),
whose SafetyCenter config declares only AOSP safety sources. GMS ships and expects **Google's**
variant of that module, whose config additionally declares the Android-16 "Advanced Protection"
source. GMS calls `SafetyCenterManager.setSafetySourceData("AdvancedProtection", …)`;
`SafetySourceDataValidator.validateRequest()` looks the id up in the config, gets `null`, and throws
(`SafetySourceDataValidator.java:85`). Nothing on the device is actually broken — but GMS crashes.

**Fix.** Declare the source so the call is accepted, in
`packages/modules/Permission/SafetyCenter/Resources/res/raw*/safety_center_config.xml`:

```xml
<dynamic-safety-source
    id="AdvancedProtection"
    packageName="com.google.android.gms"
    profile="all_profiles"
    initialDisplayState="hidden"/>
```

Deliberately minimal, and every attribute choice is forced by `SafetySource.Builder.build()`:
- `initialDisplayState="hidden"` ⇒ `titleRequired` is `isDynamicNotHidden || isDynamicHiddenWithSearch
  || isStatic`, all false, so **title, summary and intentAction are all not required** — no new string
  resources, and the UI is unchanged.
- When GMS does push data, `SafetySourceStatus.Builder` requires non-null title and summary, so the
  rendered entry takes its text from GMS rather than the config.
- `maxSeverityLevel` omitted ⇒ defaults to `Integer.MAX_VALUE`, so GMS cannot trip the "exceeds max
  severity" throw either.
- Placed in `AndroidAdvancedSources`, which is **stateful** (no `statelessIconType`); a stateless
  group throws if a source reports any severity above `UNSPECIFIED`.
- `profile="all_profiles"` is the permissive choice — `primary_profile_only` would throw
  "Unexpected profile type" if GMS ever pushed for a work or private profile.

The step patches every `raw*/safety_center_config.xml` that has the `AndroidAdvancedSources` group,
validates the result with ElementTree before writing, and is idempotent. Modifying an existing
resource file (rather than adding one to a glob) keeps the rebuild **ninja-incremental**.

## ✅ QTI servicetracker log flood (2026-07-20 — apply-overlays.sh step 25)

`system_server` floods the log every boot: ~5,555× `avc: denied { find }
vendor.qti.hardware.servicetracker::IServicetracker` (HIDL) plus the AIDL variant, and **each denial
also surfaces as a SecurityException**.

**Root cause.** AOSPA carries QTI patches in `ActiveServices.java` that report every service lifecycle
event to Qualcomm's Servicetracker HAL, which does not exist on MediaTek.
`getServicetrackerInstance()` re-probes it on **every service event**, because a failed probe leaves
`mServicetracker` null and there is no "already tried" state. The AIDL path is already latched
(`mIsAIDLSupported`, set once from `ServiceManager.isDeclared` in the constructor); the HIDL path is
not — hence thousands of lookups per boot.

**Why the earlier sepolicy work wasn't enough.** Step 16 (`quiet_qcom_ghosts`) only `dontaudit`s the
denials. A denied `find` still returns `EX_SECURITY` from servicemanager
(`ServiceManager.cpp::canFindService`), so the SecurityException kept being thrown and logged —
`dontaudit` silences the kernel avc line, not the exception. Removing the lookups is the actual fix;
the `dontaudit` rules stay as belt-and-suspenders.

**Fix.** Latch "not present" (`sServicetrackerUnavailable` / `sServicetrackerAidlUnavailable`) so each
interface is probed at most once per boot. Behaviour is unchanged on a device that *has* the HAL (the
first probe succeeds and the latch never trips); on this device it can never appear. Log/CPU noise
only — but it makes future logcat diagnosis dramatically easier.

## 🔎 MTK GPS `GET_RTC_FAIL` spam (cosmetic — not fixed, deliberately)

`mnld` logs `MTK_GPS_MSG_FIX_READY,GET_RTC_FAIL` at roughly 1 Hz while GNSS is active. The string and
the `mtk_gps_get_rtc_info` symbol live **inside the proprietary `/vendor/bin/mnld` binary**, and the
message fires on `FIX_READY` — i.e. fixes are being produced, only the RTC-info side call fails. No
source to fix, and patching a blob blind is not worth it for a log line. Confirm GPS lock works
outdoors; if it does, this is pure noise.

---

## ✅ `dev-keys` → `release-keys`: the post-build signing step (2026-07-20 — `sign-release.sh`)

**Field bug report:** on the released honest build, the Duckdetector app still flags the device
because the fingerprint and `ro.build.tags` read **`dev-keys`**.

**This is not a bug in our signing — it is a step we never ran.** `build/make/core/config.mk` spells
it out:

> The "test-keys" tag marks builds signed with the old test keys, which are available in the SDK.
> "dev-keys" marks builds signed with non-default dev keys (usually private keys from a vendor
> directory). **Both of these tags will be removed and replaced with "release-keys" when the
> target-files is signed in a post-build step.**

So in-tree `PRODUCT_DEFAULT_DEV_CERTIFICATE` signing can only ever produce `dev-keys`, no matter how
private the key is. `release-keys` comes exclusively from `sign_target_files_apks`.

**Fix:** `./sign-release.sh [version-tag]`, run after a build that included `otapackage`. It runs the
real release flow on the target-files and regenerates the OTA (plus fastboot images and super) from
the signed result.

What the signing pass changes (verified by reading `sign_target_files_apks.py`, not assumed):
- `OPTIONS.tag_changes` defaults to `("-test-keys", "-dev-keys", "+release-keys")` (line 217).
- `RewriteProps()` rewrites, across **every** partition: all `ro.*.build.tags`; the trailing key field
  of all `ro.*.build.fingerprint` / `.build.thumbprint` and `ro.bootimage.build.fingerprint`; the last
  token of `ro.build.description`; and strips the `-keys` suffix from `ro.build.display.id`. Because
  it walks every prop file, all partitions flip together — this cannot reproduce the honest3-class bug
  where `vendor/build.prop` lagged behind the others.

**AVB is deliberately untouched.** `sign-release.sh` passes **no** `--avb_*_key` flags.
`OPTIONS.avb_keys` defaults to `{}` and `ReplaceAvbPartitionSigningKey()` returns early for any
partition without a key, so the AVB chain stays byte-identical and the device keeps
`verifiedbootstate=green` under the fenrir LK. **Do not add AVB flags to this script** without
re-reading the 2026-07-19 journal decision ("AVB keys deliberately UNCHANGED") — re-keying AVB risks
the green state that Play Integrity leans on, for no gain.

**This remains honest.** We genuinely sign with our own private release keys; `release-keys` is what
that state is called once the standard release process has been run. Unlike the retired A13
fingerprint spoof, nothing false is asserted.

**Fallback (second choice, not used):** patch the `BUILD_KEYS` branch in `config.mk` so our key
directory yields `release-keys` directly. One line and consistent by construction, but it needs a
full rebuild and would hit the known `vendor/build.prop` BUILD_NUMBER staleness trap.
