# Android TV 16 on the Toshiba Portégé WT20, dual boot with Windows

This project turns a **Toshiba Portégé WT20-B** tablet into an Android TV box for a TV connected
over HDMI. Windows stays installed next to it. It is an unofficial **LineageOS 23.2 TV** build
(Android 16) with the Google TV home screen. You control it with an air mouse or a remote.

It builds on the WT20 tablet port,
[toshiba-wt20-lineageos](https://github.com/ibrahimaa9/toshiba-wt20-lineageos): same kernel, drivers and hardware video
decoding, but packaged as Android TV.

## What you get

- **Android TV 16 with the Google TV home screen, Play Store (TV), Gboard TV and Google TV
  services.** These come from Google's official Android 16 Google TV emulator image. The
  setup wizard is skipped (`ro.setupwizard.mode=DISABLED`, as on that image).
- **Dual boot.** At power-on, a 5-second menu shows. Android TV starts by default, and you
  can choose Windows. Restarting from Windows comes back to Android. Windows and its files are
  not touched.
- **TV output.** The external display turns on by itself, with no "mirror display?" prompt.
  The image is 1080p at Android TV density (320). The tablet's own screen stays dark while
  HDMI is connected. Set `persist.wt20.tv.panel_off=0` to keep it on.
- **Video.** H.264, VP8 and MPEG-2 decode on the HD 5300 (VA-API). VP9 and AV1 have no
  hardware support on Broadwell, so their software decoders are disabled and YouTube streams
  H.264 instead of burning the CPU.
- **Sound over HDMI.**

**Known limitations**

- No Widevine DRM, so Netflix, Disney+ and similar apps will not play HD (or at all). Use
  the TV's own apps for those.
- The device is not Google-certified. Register its GSF ID at
  <https://www.google.com/android/uncertified> if Play says so. See the
  [tablet README](https://github.com/ibrahimaa9/toshiba-wt20-lineageos#google-certification). Features that need a certified
  device (built-in Chromecast, some streaming apps) may not work.
- No HDMI-CEC: Broadwell's HDMI port has no CEC line, so the TV remote cannot control it.
- Wi-Fi regulatory country is set to Iraq (`ro.boot.wificountrycode=IQ`). Change it in
  `device/pc/wt20/wt20.mk` if you build it yourself.
- `userdebug` build, signed with test keys.
- **Testing:** this exact public build was boot-tested in a virtual machine. The dual-boot
  installer and the Android TV system were tested on a real WT20 connected to an LG TV with
  earlier builds of the same tree.

## Download

Build of 2026-11-18 (MediaFire):

| File | What it is |
|---|---|
| [`lineage-23.2-20261118-UNOFFICIAL-pc_x86_64_tv-wt20-tv-dual.img`](https://www.mediafire.com/file/vhkdkeem96859om/lineage-23.2-20261118-UNOFFICIAL-pc_x86_64_tv-wt20-tv-dual.img/file) (1.32 GB) | The dual-boot installer stick: the Android TV system, the unattended "install next to Windows" entry, and a `windows` folder with the preparation scripts. |

Check the file against [`SHA256SUMS`](SHA256SUMS) after you download it
(`sha256sum -c SHA256SUMS`, or `certutil -hashfile <file> SHA256` on Windows).

## Install

The full steps are in [`dualboot/windows/README-EN.txt`](dualboot/windows/README-EN.txt), which
is also on the stick. In short:

1. Write the image to a USB stick (4 GB or larger) with [Rufus](https://rufus.ie) (DD mode) or
   [balenaEtcher](https://etcher.balena.io). Plug it in with an OTG adapter.
2. Turn off Secure Boot.
3. In Windows, run `windows\prepare-windows.cmd` from the stick. It shrinks C: by 40 GB,
   turns off hibernation and Fast Startup, and adds the boot chooser before Windows Boot Manager.
4. Restart from the stick: Advanced startup > Use a device > EFI USB Device. On a WT20 the
   install starts by itself after 20 seconds. **It only uses the free space and erases nothing.**
   It takes about 10 minutes and restarts into Android TV.

> Back up first anyway. The partitioning was written for the WT20's single SATA disk and tested
> on two tablets. To undo everything, run `undo-dualboot.cmd` in Windows, then delete the
> Android partitions in Disk Management and extend C:.

### How the dual boot works

- `prepare-windows.ps1` copies a small GRUB "boot chooser" (`grubx64.efi`, built by
  `dualboot/mkstub.sh` from `dualboot/files/wt20-stub.cfg`) to `\EFI\wt20` on the Windows EFI
  partition and adds a boot entry for it first. If Android is installed, it starts Android's
  GRUB. Otherwise it starts Windows.
- The installer creates Android's partitions as GPT entries 21–33 in the largest free space
  (`androidboot.install_erase=2`). It checks every by-name link before it writes anything.
  Windows' partitions 1–4 stay byte-for-byte the same.
- Android's GRUB shows a "Windows" entry when it finds Windows' boot manager.

## Build it yourself

1. Set up and patch the tablet tree as described in
   [toshiba-wt20-lineageos](https://github.com/ibrahimaa9/toshiba-wt20-lineageos#build-it-yourself).
2. Add the TV product: copy `device/pc/pc_x86_64_tv` into the tree (`~/los/device/pc/`).
3. Generate the Google TV apps (`vendor/gapps_tv`). Get the official image yourself:
   `system-images;android-36;google-tv;x86_64` in the Android SDK manager. Mount its
   `system`, `product` and `system_ext` images, collect the apps with `scripts/emu-collect-tv.sh`
   (edit its paths), and run `scripts/gen-gapps.py <collected dir> ~/los/vendor/gapps_tv`.
   `scripts/privapp-check.py` checks that every privileged app has its permissions allowlisted.
   Google's apps may not be redistributed, so they are not in this repository.
4. Build: `scripts/build-tv.sh` (`breakfast pc_x86_64_tv userdebug && m`).
5. Make the dual-boot stick. Copy `dualboot/` to `~/dual`, build the boot chooser with
   `bash ~/dual/mkstub.sh`, then run
   `PRODUCT=pc_x86_64_tv bash ~/dual/make-tv-stick.sh ~/dual`, which writes
   `~/images/<name>-wt20-tv-dual.img`.

## What is in this repository

| Path | Contents |
|---|---|
| `device/pc/pc_x86_64_tv/` | The Android TV product: `atv_base.mk`, LineageOS's TV config, the WT20 additions, and Google TV apps from `vendor/gapps_tv`. |
| `dualboot/` | The stick builder (`make-tv-stick.sh`), the unattended installer's ramdisk add-on (`tools/make-stick-files.py`), the boot chooser (`mkstub.sh`, `files/wt20-stub.cfg`), and the Windows scripts (`windows/`). |
| `scripts/` | The TV build, Google TV app collection, and privileged-permission check. |

The TV-specific parts of the WT20 device tree are in the tablet repository's `device/pc/wt20`:
`wt20_atv.sh` (TV setup and the dark panel), `tv-overlay/`, `privapp-permissions-wt20-tv.xml`,
and the `WT20_ATV` switches in `options.mk`.

## Licenses and credits

Our own code is Apache-2.0. The boot chooser is GNU GRUB (GPL-3.0), built from LineageOS's
`prebuilts/bootmgr`. See the [tablet repository](https://github.com/ibrahimaa9/toshiba-wt20-lineageos#licenses-and-credits)
for the rest. Not affiliated with Toshiba, Google or LineageOS. Use it at your own risk.
