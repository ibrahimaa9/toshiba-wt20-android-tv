#!/usr/bin/env python3
"""Builds wt20-auto.cpio for the installer stick on Windows (no cpio/lz4 needed): the add-on ramdisk
that make-autoinstall.sh makes on the NAS. Same contents: init.recovery.virt.rc without "enable
recovery" plus the pc_auto_install service, and /system/bin/pc_auto_install.sh. The archive is a newc
cpio in an LZ4 legacy frame made of literal-only blocks (valid LZ4, just uncompressed), which is what
the kernel accepts after the LZ4 vendor ramdisk fragments.

Usage: make-stick-files.py <out dir> [<ota zip>]
    writes <out dir>/wt20-auto.cpio; with the zip (the one on the stick), the payload offset and
    headers are read from it (they change with every build), otherwise the built-in ones are used.
"""
import os, struct, sys, zipfile

ZIP_NAME = 'lineage-23.2-20261107-UNOFFICIAL-pc_x86_64.zip'  # build5 (final3 image)
PAYLOAD_OFFSET = 3611  # payload.bin data offset inside the zip (see make-autoinstall.sh)
HEADERS = '''FILE_HASH=WZzMCf1GAlbuj/xiy57DXv3/ZxlTtXzvhFJSb7RR7fk=
FILE_SIZE=1594886261
METADATA_HASH=sGa2qdLVE5jJtHM11vnOtqsIIbLRmuw/b8X9ZNFIhzA=
METADATA_SIZE=145730'''


def read_zip(path):
    """payload.bin's data offset and payload_properties.txt, what recovery computes at runtime."""
    z = zipfile.ZipFile(path)
    i = z.getinfo('payload.bin')
    assert i.compress_type == 0, 'payload.bin must be stored'
    with open(path, 'rb') as f:
        f.seek(i.header_offset)
        n, e = struct.unpack('<HH', f.read(30)[26:30])
    return os.path.basename(path), i.header_offset + 30 + n + e, z.read('payload_properties.txt').decode().strip()

INIT_RC = '''service preinstall_check /system/bin/preinstall_check
    user root
    group root system graphics
    seclabel u:r:recovery:s0
    oneshot
    disabled

on early-init && property:ro.boot.install=1
    stop recovery

on early-fs
    symlink /dev/block/by-name/BIOS /dev/block/by-name/BIOS_a
    symlink /dev/block/by-name/BIOS /dev/block/by-name/BIOS_b
    symlink /dev/block/by-name/EFI /dev/block/by-name/EFI_a
    symlink /dev/block/by-name/EFI /dev/block/by-name/EFI_b

on fs
    mkdir /mnt/vendor/_persist 0770 root root
    mount vfat /dev/block/by-name/persist /mnt/vendor/_persist rw sync shortname=lower uid=1000 gid=1000 dmask=007 fmask=117 context=u:object_r:persist_file:s0

on early-boot
    start vendor.boot-default

on property:ro.boot.install=1 && property:vendor.create_partition_table.finish=1
    exec u:r:flash_persist_partition:s0 -- /system/bin/sh -e /system/bin/flash_persist_partition.sh
    mount vfat /dev/block/by-name/persist /mnt/vendor/_persist rw sync shortname=lower uid=1000 gid=1000 dmask=007 fmask=117 context=u:object_r:persist_file:s0

on property:ro.boot.install=1 && property:vendor.create_partition_table.start=1 && property:init.svc.create_partition_table=stopped
    start preinstall_check

# wt20-auto.cpio: with a preset install disk, install the zip from the stick and reboot instead of
# showing the recovery menu (the tablet has no keyboard)
service pc_auto_install /system/bin/sh /system/bin/pc_auto_install.sh
    user root
    group root
    seclabel u:r:recovery:s0
    oneshot
    disabled

on property:ro.boot.install=1 && property:ro.boot.install_disk=* && property:vendor.preinstall_check.success=1
    start pc_auto_install

# wt20-auto.cpio: booted with androidboot.wt20_collect=1 (the stick has a wt20-collect file), copy the
# logs Android saved on the pc_logs partition to the stick and reboot
service pc_wt20_collect /system/bin/sh /system/bin/pc_wt20_collect.sh
    user root
    group root
    seclabel u:r:recovery:s0
    oneshot
    disabled

on boot && property:ro.boot.wt20_collect=1
    start pc_wt20_collect
'''

COLLECT = '''# Runs as recovery (wt20-auto.cpio) when the stick boots with androidboot.wt20_collect=1: copies the
# pc_logs partition (Android's dmesg + logcat of every clean reboot) and this boot's dmesg to the stick,
# removes the stick's wt20-collect flag and reboots to the installed system.
say() { echo "<0>wt20-collect: $*" > /dev/kmsg; }
fail() { say "ERROR: $*"; say "Choose Reboot in the recovery menu, or hold the power button."; exit 1; }

# USB sticks can show up a few seconds after init, so look for up to 60 s
disk=
tries=0
while [ -z "$disk" ] && [ $tries -lt 60 ]; do
    for sys in /sys/class/block/sd*; do
        name=${sys##*/}
        [ -e $sys/partition ] && continue
        if [ "$(dd if=/dev/block/$name bs=1 skip=82 count=5 2>/dev/null)" = "FAT32" ] &&
                [ "$(dd if=/dev/block/$name bs=1 skip=71 count=7 2>/dev/null)" = "install" ]; then
            disk=$name
            break
        fi
    done
    [ -n "$disk" ] || sleep 1
    tries=$((tries + 1))
done
[ -n "$disk" ] || fail "installer USB stick not found"
MNT=/tmp/wt20_stick
mkdir -p $MNT
grep -q " $MNT " /proc/mounts || mount -t vfat -o rw,noatime /dev/block/$disk $MNT || fail "cannot mount the stick"
OUT=$MNT/wt20-logs/pc_logs-$(date +%Y%m%d-%H%M%S)
mkdir -p $OUT
dmesg > $OUT/recovery-dmesg.txt 2>&1

for i in $(seq 1 50); do
    [ -e /dev/block/by-name/pc_logs ] && break
    sleep 0.2
done
PL=/tmp/wt20_pc_logs
mkdir -p $PL
if mount -t vfat -o ro /dev/block/by-name/pc_logs $PL; then
    cp -r $PL/. $OUT/ 2>/dev/null
    umount $PL
    say "copied the pc_logs partition to the stick: ${OUT#$MNT/}"
else
    say "could not mount the pc_logs partition"
fi
rm -f $MNT/wt20-collect
sync
umount $MNT
say "done, restarting into LineageOS in 5 seconds"
sleep 5
setprop sys.powerctl reboot
'''

SCRIPT_TEMPLATE = '''# Runs as recovery (wt20-auto.cpio) once pc_create_partition_table.sh is done: installs the OTA zip
# from the installer stick like recovery's "Apply update" (install.cpp SetUpAbUpdateCommands) and reboots.
# Level 0 shows on screen whatever the loglevel is.
say() { echo "<0>wt20-auto: $*" > /dev/kmsg; }
fail() { say "ERROR: $*"; say "Installation stopped. Hold the power button to turn the tablet off."; exit 1; }

ZIP_NAME="%(zip)s"
PAYLOAD_OFFSET=%(offset)d
HEADERS="%(headers)s"

say "disk partitioned, installing LineageOS from the USB stick..."

# The installer stick: a FAT32 superfloppy labelled "install" (as in pc_save_logs.sh)
# USB sticks can show up a few seconds after init, so look for up to 60 s
disk=
tries=0
while [ -z "$disk" ] && [ $tries -lt 60 ]; do
    for sys in /sys/class/block/sd*; do
        name=${sys##*/}
        [ -e $sys/partition ] && continue
        if [ "$(dd if=/dev/block/$name bs=1 skip=82 count=5 2>/dev/null)" = "FAT32" ] &&
                [ "$(dd if=/dev/block/$name bs=1 skip=71 count=7 2>/dev/null)" = "install" ]; then
            disk=$name
            break
        fi
    done
    [ -n "$disk" ] || sleep 1
    tries=$((tries + 1))
done
[ -n "$disk" ] || fail "installer USB stick not found"
MNT=/tmp/wt20_stick
mkdir -p $MNT
grep -q " $MNT " /proc/mounts || mount -t vfat -o rw,noatime /dev/block/$disk $MNT ||
    fail "cannot mount the USB stick ($disk)"
[ -f "$MNT/$ZIP_NAME" ] || fail "$ZIP_NAME not found on the USB stick"

# Logs go to the stick (wt20-logs/<n>/, to be read on another PC; the stick's FAT has little free
# space, so the update_engine log is cut) and to the pc_logs partition on the disk (readable later
# over ADB or with the wt20-collect flag) in case the stick is gone.
STAMP=$(date +%%Y%%m%%d-%%H%%M%%S)
save_logs() {
    mkdir -p /tmp/wt20_logs
    tail -c 400k /tmp/wt20_update.log > /tmp/wt20_logs/update_engine.log 2>/dev/null
    dmesg > /tmp/wt20_logs/dmesg.txt 2>&1
    cp /tmp/recovery.log /tmp/wt20_logs/recovery.log 2>/dev/null
    mkdir -p /tmp/wt20_pl
    if mount -t vfat -o rw /dev/block/by-name/pc_logs /tmp/wt20_pl 2>/dev/null; then
        mkdir -p /tmp/wt20_pl/install-$STAMP
        cp /tmp/wt20_logs/* /tmp/wt20_pl/install-$STAMP/ 2>/dev/null
        sync
        umount /tmp/wt20_pl
    fi
    if grep -q " $MNT " /proc/mounts || mount -t vfat -o rw,noatime /dev/block/$disk $MNT 2>/dev/null; then
        mkdir -p $MNT/wt20-logs/$STAMP
        cp /tmp/wt20_logs/* $MNT/wt20-logs/$STAMP/ 2>/dev/null
        sync
        say "logs saved on the USB stick in wt20-logs/$STAMP"
    else
        say "the USB stick is not reachable any more; logs are on the pc_logs partition"
    fi
}

# The installer needs the stick only for this copy: the zip goes to the (not yet formatted)
# userdata partition and update_engine reads it from there, so a stick that drops off the USB
# bus a few minutes in no longer breaks the installation.
ZIP_SIZE=$(stat -c %%s $MNT/$ZIP_NAME)
UD=/dev/block/by-name/userdata
[ -e $UD ] || fail "userdata partition not found"
# (size from sysfs: recovery may not use the BLKGETSIZE64 ioctl on userdata)
UD_SECTORS=$(cat /sys/class/block/$(basename $(readlink -f $UD))/size)
[ "${UD_SECTORS:-0}" -gt $(( (ZIP_SIZE + 1048576) / 512 )) ] || fail "userdata is too small for the zip ($UD_SECTORS sectors)"
say "copying the system package from $disk to the internal disk ($((ZIP_SIZE / 1048576)) MB), about 2 minutes..."
if ! dd if=$MNT/$ZIP_NAME of=$UD bs=4M conv=fsync 2> /tmp/wt20_dd.log; then
    tail -n 3 /tmp/wt20_dd.log | while read -r line; do say "$line"; done
    save_logs
    fail "could not read the package from the USB stick (is the stick or the USB port faulty?)"
fi
say "copied, checking the copy..."
# Compare against the stick once more: cheap insurance against a flaky stick or USB port
if ! cmp -n $ZIP_SIZE $UD $MNT/$ZIP_NAME > /tmp/wt20_cmp.log 2>&1; then
    tail -n 2 /tmp/wt20_cmp.log | while read -r line; do say "$line"; done
    save_logs
    fail "the copy differs from the USB stick: faulty stick or USB port"
fi
sync
umount $MNT 2>/dev/null

say "writing the system to the internal disk, this takes a few minutes, do not turn off"
# (no --size: update_engine takes the payload size from FILE_SIZE in the headers)
if /system/bin/update_engine_sideload --payload=file://$UD --offset=$PAYLOAD_OFFSET \\
        --headers="$HEADERS" > /tmp/wt20_update.log 2>&1; then
    ok=1
else
    ok=0
fi
# Clear the start of userdata again so Android formats it on first boot (pc_clear_partitions.sh)
dd if=/dev/zero of=$UD bs=1M count=4 conv=fsync 2>/dev/null

if [ "$ok" = "1" ]; then
    say "LineageOS installed. Restarting in 10 seconds; you can remove the USB stick."
    save_logs
    # GRUB on the stick boots from the disk instead of reinstalling when this file exists
    if grep -q " $MNT " /proc/mounts; then
        echo "installed $(date)" > $MNT/wt20-installed
        sync
        umount $MNT
    fi
    sleep 10
    setprop sys.powerctl reboot
else
    grep -i "error\\|fail\\|ErrorCode" /tmp/wt20_update.log | grep -v "death re\\|unlinking" | tail -n 10 | cut -c1-300 |
        while read -r line; do say "$line"; done
    save_logs
    umount $MNT 2>/dev/null
    fail "update_engine_sideload failed"
fi
'''


def cpio_newc(entries):
    """entries: list of (name, mode, data or None for a directory); returns the archive bytes."""
    out = bytearray()
    ino = 1
    for name, mode, data in entries + [('TRAILER!!!', 0, b'')]:
        if data is None:
            data = b''
        nameb = name.encode() + b'\0'
        fields = [ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(nameb), 0]
        out += b'070701' + ''.join('%08X' % f for f in fields).encode()
        out += nameb
        out += b'\0' * (-len(out) % 4)
        out += data
        out += b'\0' * (-len(out) % 4)
        ino += 1
    return bytes(out)


def lz4_legacy_literal(data):
    """LZ4 legacy frame (what `lz4 -l` writes) holding data as literal-only blocks."""
    out = bytearray(struct.pack('<I', 0x184C2102))
    for i in range(0, len(data), 8 << 20):
        chunk = data[i:i + (8 << 20)]
        n = len(chunk)
        if n < 15:
            block = bytes([n << 4]) + chunk
        else:
            rest = n - 15
            block = bytes([0xF0]) + b'\xff' * (rest // 255) + bytes([rest % 255]) + chunk
        out += struct.pack('<I', len(block)) + block
    return bytes(out)


def lz4_legacy_decode_literal(buf):
    """Decoder for the literal-only frames above (self-check)."""
    assert struct.unpack('<I', buf[:4])[0] == 0x184C2102
    pos, out = 4, bytearray()
    while pos < len(buf):
        size = struct.unpack('<I', buf[pos:pos + 4])[0]
        block = buf[pos + 4:pos + 4 + size]
        pos += 4 + size
        n = block[0] >> 4
        j = 1
        if n == 15:
            while block[j] == 255:
                n += 255
                j += 1
            n += block[j]
            j += 1
        assert j + n == len(block), 'block is not a single literal sequence'
        out += block[j:j + n]
    return bytes(out)


# Fixed pc_create_partition_table.sh (always rewrites super's metadata after an erase: the old
# install's 4 GB metadata survived sgdisk --zap-all and the 10 GB OTA failed). Overrides the one in
# the recovery ramdisk until the next build includes it.
PART_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src-mods', 'device', 'pc',
                           'pc_x86_64', 'configs', 'scripts', 'pc_create_partition_table.sh')


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    zip_name, offset, headers = ZIP_NAME, PAYLOAD_OFFSET, HEADERS
    if len(sys.argv) > 2:
        zip_name, offset, headers = read_zip(sys.argv[2])
    print('zip %s, payload offset %d' % (zip_name, offset))
    script = SCRIPT_TEMPLATE % {'zip': zip_name, 'offset': offset, 'headers': headers}
    archive = cpio_newc([
        ('init.recovery.virt.rc', 0o100644, INIT_RC.encode()),
        ('system', 0o040755, None),
        ('system/bin', 0o040755, None),
        ('system/bin/pc_auto_install.sh', 0o100755, script.encode()),
        ('system/bin/pc_wt20_collect.sh', 0o100755, COLLECT.encode()),
        ('system/bin/pc_create_partition_table.sh', 0o100755, open(PART_SCRIPT, 'rb').read().replace(b'\r\n', b'\n')),
    ])
    frame = lz4_legacy_literal(archive)
    assert lz4_legacy_decode_literal(frame) == archive
    path = os.path.join(outdir, 'wt20-auto.cpio')
    with open(path, 'wb') as f:
        f.write(frame)
    print('%s: %d bytes (cpio %d bytes)' % (path, len(frame), len(archive)))


if __name__ == '__main__':
    main()
