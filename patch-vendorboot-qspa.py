#!/usr/bin/env python3
"""patch-vendorboot-qspa.py — append androidboot.vendor.qspa.modem=enabled to the header
cmdline of a vendor_boot image (v3/v4), in place, no repack.

Why: on the S666LN AOSPA port, that cmdline param ungates AOSPA's QSPA telephony packages
(no param -> PackageManager skips TelephonyProvider -> phone crash-loop -> no SIM). Any
third-party vendor_boot (e.g. a custom recovery) must carry it too. Run this on the image
BEFORE flashing:  python3 patch-vendorboot-qspa.py <vendor_boot.img>

The cmdline lives at a fixed offset (28) as a 2048-byte NUL-padded field in the
vendor_boot v3/v4 header — an in-place edit, so ramdisk tables etc. are untouched.
NOTE: editing invalidates the image's AVB hash — same caveat as flashing any modified
vendor_boot; on this device (test-key vbmeta + fenrir LK) that is the existing situation.
"""
import sys

PARAM = b"androidboot.vendor.qspa.modem=enabled"
CMDLINE_OFF, CMDLINE_LEN = 28, 2048

def main(path):
    with open(path, "r+b") as f:
        if f.read(8) != b"VNDRBOOT":
            sys.exit(f"ERROR: {path} is not a vendor_boot image (bad magic)")
        f.seek(CMDLINE_OFF)
        raw = f.read(CMDLINE_LEN)
        cmdline = raw.rstrip(b"\x00")
        if PARAM in cmdline:
            print(f"already present — no change: {cmdline.decode()}")
            return
        new = cmdline + (b" " if cmdline else b"") + PARAM
        if len(new) > CMDLINE_LEN:
            sys.exit("ERROR: cmdline would exceed 2048 bytes")
        f.seek(CMDLINE_OFF)
        f.write(new.ljust(CMDLINE_LEN, b"\x00"))
        print(f"patched: {new.decode()}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
