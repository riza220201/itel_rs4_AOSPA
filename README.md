# itel RS4 (S666LN) → AOSPA (Paranoid Android, Android 16)

Port recipe for building **AOSPA / Paranoid Android** (branch **beryl**, Android 16) for the
**itel RS4** (`S666LN`, MediaTek **MT6789 / Helio G99**), with a **custom kernel**
(`5.10.260-Riza-vanilla`) baked into `boot.img`.

This repo is the **recipe**, not the Android source tree — a set of overlays, a local manifest, and
idempotent scripts that graft the (LineageOS-shaped) KimelaZX/MillenniumOSS MT6789 device stack onto
AOSPA and fix every breakage encountered from `lunch` through packaging. A full `repo sync` +
`apply-overlays.sh` reproduces a flashable build.

## Layout

| Path | What |
|---|---|
| `local_manifests/S666LN.xml` | per-device manifest for AOSPA beryl (device/vendor/kernel/HAL repos, plus the LineageOS `hardware/google/pixel` + `device/lineage/sepolicy` we add and the QCOM repos we remove) |
| `device-aospa/` | the AOSPA product overlay (`aospa_S666LN.mk`, `AndroidProducts.mk`) + `common-kernel-Android.bp` (defines `generated_kernel_headers`) |
| `apply-overlays.sh` | idempotent — applies the custom kernel, lands the product, and every source/sepolicy/vintf/allowlist fixup. **Re-run after any `repo sync`.** |
| `apply-custom-kernel.sh` | swaps our prebuilt kernel `Image.gz` into `device/millennium/common-kernel/` (KMI-verified) |
| `kernel-stage/Image.gz` | the custom kernel prebuilt (from the sibling `itel-rs4-kernel` project) |
| `patch-vendorboot-qspa.py` | patches a foreign `vendor_boot` image (e.g. a custom recovery) with the QSPA cmdline param telephony needs — see [Custom recovery](#custom-recovery-orangefox) |
| `PORT-NOTES.md` | the living Lineage→AOSPA fixup checklist (what broke, why, how it's fixed) |
| `FLASHING.md` | install recipe (A/B layout, fenrir LK first, then the image set) — **DRAFT, verify before flashing** |

**Not in this repo:**
- **`s666ln-fenrir-signed.bin`** — the **mandatory** "fenrir" signed LK (suppresses bootloader
  orange-state; flash to `lk_a`/`lk_b`). It's a proprietary signed bootloader and is **not
  redistributed here** — obtain it from the device community (PenumbraGUI). Note: it's already the
  `lk` partition inside the released OTA zip (`radio/lk.img`), so an OTA install applies it anyway.
- `itel-RS4-S666LN-28.zip` — 5.8 GB stock firmware (blob/scatter reference; also the source of the
  32-bit MediaTek GPU blobs `apply-overlays.sh` step 21 stages — see that step to regenerate them).
The Android source tree and `out/` live at `/mnt/external_nvme/aospa`, not here.

## Reproduce

```sh
# 1. Source tree (needs ~300 GB free; heavy). beryl = AOSPA A16.
mkdir -p /mnt/external_nvme/aospa && cd /mnt/external_nvme/aospa
repo init -u https://github.com/AOSPA/manifest -b beryl --depth=1 --no-repo-verify
cp <this-repo>/local_manifests/S666LN.xml .repo/local_manifests/
repo sync -c --no-tags --optimized-fetch --force-sync -j6

# 2. Apply all overlays/fixups (idempotent; re-run after any future sync)
<this-repo>/apply-overlays.sh

# 3. Build (14 GB RAM needs a big swap — soong's working set is ~40 GB and swap-thrashes;
#    cap -j; only .bp changes force the ~1 h re-analysis)
source build/envsetup.sh
lunch aospa_S666LN-userdebug
m -j4                 # then: m superimage   (and: m otapackage for the flashable OTA zip)
```

Outputs land in `out/target/product/S666LN/`: `super.img`, `boot.img` (custom kernel),
`vendor_boot.img`, `dtbo.img`, `vbmeta{,_system,_vendor}.img`, and `aospa_S666LN-ota.zip`.

## Flash (device stays operator-driven)

Per `FLASHING.md`: **fenrir LK → `lk_a`/`lk_b` first**, then boot/vendor_boot/dtbo/vbmeta* + `super`
via fastboot/fastbootd, or sideload the OTA zip in recovery. The fenrir LK is what keeps Play
Integrity reachable — it is not optional.

## Custom recovery (OrangeFox)

⚠️ **On this device the recovery lives inside `vendor_boot`** (there is no separate `recovery`
partition), and `vendor_boot`'s kernel cmdline applies to **normal boots too**. This ROM ships a
required boot param there — `androidboot.vendor.qspa.modem=enabled` — that ungates the telephony
packages. **Flash a stock third-party `vendor_boot` (a custom recovery) without that param and
telephony breaks: no `TelephonyProvider` → phone process crash-loops → no SIM.**

So before flashing any foreign `vendor_boot`/recovery image, patch it:

```sh
# Injects the QSPA param into the image's header cmdline, in place, no repack.
python3 patch-vendorboot-qspa.py ofox.img

# Optional: make it a perfect superset (add the ROM's other cmdline params too) — the script
# only adds the QSPA param; edit the target cmdline in the script if you want the full set.
```

Then flash it to the **currently-active slot** (fastboot targets the bootloader's current slot,
which may differ from the running system's slot — flashing the wrong one leaves you booting the old
`vendor_boot`, i.e. "recovery didn't change"):

```sh
# check which slot is active first:  fastboot getvar current-slot
fastboot flash vendor_boot_a ofox.img   # or vendor_boot_b — match the active slot
```

**Note:** editing the image invalidates its AVB hash. On this device (test-key `vbmeta` + fenrir
LK) that is already the situation for any modified partition, so it flashes fine — but it is why a
custom recovery must go on a device already set up for the fenrir/unlocked flow.

Every OTA sideload rewrites `vendor_boot` on the target slot with the ROM's own (param intact), so
after an update, re-flash the patched recovery if you want to keep it.

## Notes on the environment

Built on a 14 GB-RAM box; the swap was raised to 80 GB because soong OOM'd at 40 GB. `PORT-NOTES.md`
carries the full Lineage→AOSPA fixup checklist (every breakage and its fix).
