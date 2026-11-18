#!/bin/bash
# Runs as the build user INSIDE the chroot, after a TV build (device/pc/wt20/TV_BUILD): makes the
# installer stick image for the second WT20, the one that keeps its Windows (dual boot).
#   ~/images/<name>-wt20-tv-dual.img   to be written to a USB stick as it is
# On top of the built installer image:
#   - /wt20-auto.cpio: the unattended installer (tools/make-stick-files.py, same as the first
#     tablet's stick), for the zip in this image;
#   - /boot/grub/grub.cfg: on a WT20 only, "install next to Windows" starts by itself after
#     20 s (androidboot.install_erase=2: free space only, nothing is erased); once installed
#     (/wt20-installed on the stick) the stick boots the disk instead. The interactive install
#     entry, which can erase a whole disk, is removed from this stick;
#   - /windows: prepare-windows.cmd and friends plus the boot chooser (grubx64.efi), to be run
#     from the stick on the tablet's Windows before the install.
# Usage: make-tv-stick.sh <dual dir, with tools/ src-mods/ windows/ out/wt20-stub.efi>
set -euo pipefail
DUAL=${1:-$HOME/dual}
# PRODUCT=pc_x86_64_tv for the Android TV product (apply22a, apply23a); default: the tablet product
# with the TV launcher (TV_BUILD)
PRODUCT=${PRODUCT:-pc_x86_64}
OUT=~/los/out/target/product/$PRODUCT
SRC=$(ls -t $OUT/lineage-23.2-*-$PRODUCT.img | head -1)
ZIP=${SRC%.img}.zip
[ -f "$ZIP" ] || { echo "no zip next to $SRC"; exit 1; }
mkdir -p ~/images
DST=~/images/$(basename "${SRC%.img}")-wt20-tv-dual.img
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The built image has next to no free space, and this stick also carries /windows and gets the
# install logs and the wt20-installed flag written to it: same contents in a FAT32 that is 32 MiB
# larger, formatted the way the build does (30-create_images.mk; the label is how the installer
# finds the stick).
mkdir "$WORK/root"
mcopy -s -n -i "$SRC" "::/*" "$WORK/root/"
[ -e "$WORK/root/.grub_kernel_version.cfg" ] || mcopy -n -i "$SRC" ::/.grub_kernel_version.cfg "$WORK/root/"
truncate -s $(( $(stat -c %s "$SRC") + 32 * 1048576 )) "$DST.tmp"
mformat -F -i "$DST.tmp" -v install ::
( cd "$WORK/root" && for f in * .grub_kernel_version.cfg; do mcopy -s -i "$DST.tmp" "$f" ::; done )
mkdir "$WORK/back"
mcopy -s -n -i "$DST.tmp" "::/*" "$WORK/back/"
[ -e "$WORK/back/.grub_kernel_version.cfg" ] || mcopy -n -i "$DST.tmp" ::/.grub_kernel_version.cfg "$WORK/back/"
diff -r "$WORK/root" "$WORK/back" || { echo "the enlarged image differs from the built one"; exit 1; }
rm -rf "$WORK/root" "$WORK/back"
mv "$DST.tmp" "$DST"

# the zip inside the image is the one the cpio's payload offset and hashes must describe
mcopy -n -i "$DST" "::/$(basename "$ZIP")" "$WORK/in-image.zip"
cmp "$WORK/in-image.zip" "$ZIP" || { echo "the zip in the image is not $ZIP"; exit 1; }
mv "$WORK/in-image.zip" "$WORK/$(basename "$ZIP")"

python3 "$DUAL/tools/make-stick-files.py" "$WORK" "$WORK/$(basename "$ZIP")"

mtype -i "$DST" ::/boot/grub/grub.cfg > "$WORK/grub.cfg"
python3 - "$WORK/grub.cfg" <<'EOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
assert 'gpt4 gpt9 gpt24' in text, 'this image was not built with apply20a (no gpt24 lookup)'
m = re.search(r'function boot_android_install \{\n(.*?)\n\}\n', text, re.S)
assert m, 'boot_android_install not found'
body = m.group(1)
assert '(vendor_boot)/bootconfig.bin' in body and 'androidboot.install=1' in body
auto_body = body.replace('(vendor_boot)/bootconfig.bin', '/wt20-auto.cpio (vendor_boot)/bootconfig.bin')
# the auto entries pass androidboot.install=1 themselves (the log collector must not install)
auto_body = auto_body.replace(' androidboot.install=1', '')
block = '''# Unattended dual-boot install for the Toshiba WT20 TV tablet (no keyboard), added by
# make-tv-stick.sh. The entry exists only on that machine, and it only ever uses free space.
function boot_android_install_auto {
%(auto_body)s
}

insmod smbios
insmod regexp
set system_product=
smbios --type 1 --get-string 5 --set system_product
if regexp 'WT20' "$system_product"; then
	# pc_auto_install.sh writes /wt20-installed on this stick when an install succeeded; a failed
	# one may leave the disk partitioned, so the disk itself cannot tell. Delete the file to
	# install again (over the Android partitions only).
	if [ -f /wt20-installed ]; then
		# Installed: make the tablet's GRUB boot the "Intel pre-Skylake GPU with workarounds"
		# entry (HD 5300 is Gen8), then boot the disk. Same as choosing it in the menu once.
		if [ -n "$partition_persist" ]; then
			set grub_android_default="advancedoptions-pc_x86_64>android-pc_x86_64-intelpreskylakewithworkarounds"
			save_env -f ${partition_persist}/grubenv grub_android_default
		fi
		set default=bootfromdisk
		set timeout=5
		# A wt20-collect file on the stick: copy Android's saved logs to the stick first
		if [ -f /wt20-collect ]; then
			set default=wt20-collect
			menuentry "Copy the tablet's logs to this stick, then boot from disk" --id wt20-collect --class text {
				boot_android_install_auto androidboot.wt20_collect=1 loglevel=1
			}
		fi
	else
		set default=wt20-auto
		set timeout=20
		menuentry "Install Android TV next to Windows (free space only, nothing is erased)" --id wt20-auto --class monitor-arrow-down {
			boot_android_install_auto androidboot.install=1 androidboot.install_disk=sda androidboot.install_erase=2 loglevel=1
		}
	fi
fi

''' % {'auto_body': auto_body}
# the interactive entry (it can erase a whole disk) goes away on this stick
m2 = re.search(r'menuentry "Install [^\n]*\{\n\tboot_android_install\n\}\n\n?', text)
assert m2, 'interactive install entry not found'
text = text[:m2.start()] + block + text[m2.end():]
old = 'menuentry "Boot from disk" --class harddisk {'
assert old in text
text = text.replace(old, 'menuentry "Boot from disk" --id bootfromdisk --class harddisk {')
open(path, 'w').write(text)
EOF

mcopy -o -i "$DST" "$WORK/grub.cfg" ::/boot/grub/grub.cfg
mcopy -o -i "$DST" "$WORK/wt20-auto.cpio" ::/wt20-auto.cpio
mmd -i "$DST" ::/windows 2>/dev/null || true
for f in $(cd "$DUAL/windows" && ls README-*.txt) prepare-windows.cmd prepare-windows.ps1 undo-dualboot.cmd undo-dualboot.ps1 boot-fix.cmd; do
    mcopy -o -i "$DST" "$DUAL/windows/$f" "::/windows/$f"
done
mcopy -o -i "$DST" "$DUAL/out/wt20-stub.efi" ::/windows/grubx64.efi
echo "--- patched part of grub.cfg:"
mtype -i "$DST" ::/boot/grub/grub.cfg | sed -n '/Unattended dual-boot/,/^menuentry "Boot from disk"/p'
echo "--- stick contents:"
mdir -i "$DST" ::/ ; mdir -i "$DST" ::/windows
cd ~/images && sha256sum "$(basename "$DST")" | tee -a SHA256SUMS
echo "IMAGE=$DST"
