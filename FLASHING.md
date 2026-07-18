# FLASHING.md — itel RS4 (S666LN, MT6789) · AOSPA install recipe

**DRAFT plan** derived from the stock partition layout (`MT6789_Android_scatter.txt`) +
`BoardConfig.mk` + the fenrir-LK requirement. Not yet executed end-to-end on this device —
**verify each step and keep full backups before flashing.** A wrong LK/preloader/vbmeta write
can hard-brick. Nothing here is run by the tooling; the operator flashes.

## Device facts
- MediaTek **MT6789 / Helio G99**, **Virtual A/B** (slots _a/_b), GKI boot header **v4**.
- Relevant partitions (from the stock scatter): `lk_a/lk_b` (bootloader, 4 MB each),
  `boot_a/b`, `init_boot_a/b`, `vendor_boot_a/b`, `dtbo_a/b`, `vbmeta_a/b`,
  `vbmeta_system_a/b`, `vbmeta_vendor_a/b`, dynamic **`super`** (system/system_ext/product/
  vendor/vendor_dlkm/odm_dlkm), `userdata`, `metadata`.
- AVB: test-key signed (`external/avb/test/data/testkey_rsa2048.pem`).

## 🔴 Step 0 — the mandatory fenrir LK (do NOT skip)
The RS4 shows bootloader **orange state** on an unlocked bootloader, which blocks Play
Integrity STRONG. Flash `s666ln-fenrir-signed.bin` to the **`lk`** partition (both slots) to
suppress it. Fenrir (2,495,376 B) is a +240 B drop-in over stock `lk.img` (2,495,136 B); fits
the 4 MB `lk` partition.
```
fastboot flash lk_a s666ln-fenrir-signed.bin
fastboot flash lk_b s666ln-fenrir-signed.bin
```
(Or via SP Flash Tool / mtkclient with the stock scatter, `lk` region only, in download mode.)

## Step 1 — prerequisites
- Bootloader **unlocked** (`fastboot flashing unlock` — wipes userdata; done once).
- **Back up** current `boot`, `vendor_boot`, `dtbo`, `lk`, `vbmeta*`, and a full stock dump —
  the stock firmware zip (`itel-RS4-S666LN-28.zip`) is the recovery baseline.
- AOSPA build outputs (after `m`): under `out/target/product/S666LN/` —
  `boot.img`, `init_boot.img`, `vendor_boot.img`, `dtbo.img`, `super.img` (or
  `super_empty.img` + logical images), `vbmeta.img`, `vbmeta_system.img`, `vbmeta_vendor.img`.
  (Our **custom kernel is already inside `boot.img`** — no separate kernel flash.)

## Step 2 — flash the ROM (fastboot / fastbootd, unlocked)
```
# bootloader (fastboot mode)
fastboot flash boot_a        boot.img
fastboot flash boot_b        boot.img
fastboot flash init_boot_a   init_boot.img
fastboot flash init_boot_b   init_boot.img
fastboot flash vendor_boot_a vendor_boot.img
fastboot flash vendor_boot_b vendor_boot.img
fastboot flash dtbo_a        dtbo.img
fastboot flash dtbo_b        dtbo.img

# vbmeta chain — disable verity/verification (unlocked + test-keys)
fastboot flash vbmeta_a         --disable-verity --disable-verification vbmeta.img
fastboot flash vbmeta_b         --disable-verity --disable-verification vbmeta.img
fastboot flash vbmeta_system_a  --disable-verity --disable-verification vbmeta_system.img
fastboot flash vbmeta_system_b  --disable-verity --disable-verification vbmeta_system.img
fastboot flash vbmeta_vendor_a  --disable-verity --disable-verification vbmeta_vendor.img
fastboot flash vbmeta_vendor_b  --disable-verity --disable-verification vbmeta_vendor.img

# dynamic partitions (fastbootd)
fastboot reboot fastboot
fastboot flash super super.img          # or: fastboot flash super super_empty.img, then flash logical images

# wipe + boot
fastboot -w
fastboot reboot
```

## Notes / open questions to finalize with real images
- **super:** whether `m` emits a monolithic `super.img` or `super_empty.img` + per-logical
  images depends on the lunch/`-w` flow; adjust Step 2's super line accordingly.
- **Recovery:** this device has **no dedicated recovery partition** — recovery ramdisk rides in
  `vendor_boot` (`BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT`). To use OrangeFox/TWRP, flash
  its `vendor_boot`/`boot` per that project (kept separate from this ROM flash).
- **Kernel note (recovery):** built-in ZRAM bricks recovery on this Helio G99 (recovery shares
  the boot kernel) — our vanilla kernel already ships ZRAM **off**, so this is a non-issue here
  (documented in `~/itel-rs4-kernel/JOURNAL.md`).
- **Fenrir persists** across ROM flashes (it's the `lk`, untouched by Step 2). Re-flash it only
  if you restore stock or dirty the `lk` partition.
- **Integrity:** fenrir removes orange state; passing STRONG also needs the userspace side
  (proper keybox / MTK attestation) — out of scope for the flash, tracked separately.
