#!/bin/bash
# Runs as root on the NAS host: picks the Google TV apps out of Google's official Android 16
# Google TV emulator image (system-images;android-36;google-tv;x86_64, r04, BT2A.260319.001,
# partitions mounted read-only at /mnt/emutv/{system,product,system_ext}) into an "extracted"
# tree for gen-gapps.py (vendor/gapps_tv), for the WT20 Android TV product.
# Left out on purpose:
#   - the image's platform-signed apps (TvSystemUI, TvSettingsTwoPanel, TvManagedProvisioning,
#     GooglePackageInstaller_tv, TvFeedbackConsent): signed with Google's dev keys, not ours;
#     the build makes its own from source (device/google/atv)
#   - emulator parts (EmulatorRadioConfig, Ranchu/goldfish overlays and permissions)
#   - WebView/Trichrome, talkback, SettingsIntelligence, TvProvision: the tree has its own
#   - AOSP-named overlays the tree also builds (TvFrameworkOverlay, TvSettingsProviderOverlay...)
#   - mediashell's own SELinux domain (product_seapp_contexts): it runs as priv_app here
set -euo pipefail
E=/mnt/emutv
T=/mnt/wt20build/rootfs/tmp/host/gapps-tv/system
for p in product system_ext; do mountpoint -q $E/$p || { echo "$E/$p is not mounted"; exit 1; }; done
rm -rf "$T"; mkdir -p "$T"
app() {  # app <partition> <kind> <dir in image>
    mkdir -p "$T/$1/$2/$3"
    cp "$E/$1/$2/$3/$3.apk" "$T/$1/$2/$3/$3.apk"
}
for a in PrebuiltGmsCorePano Tubesky TVLauncherXPrebuilt TVDreamXPrebuilt AtvRemoteService \
         AndroidMediaShell LiveTv ConfigUpdater TvContextAgenticServices; do
    app product priv-app $a
done
for a in LatinIMEGoogleTvPrebuilt GoogleTTS PlayGamesPano GoogleCalendarSyncAdapter; do
    app product app $a
done
app system_ext priv-app GoogleServicesFramework
d() { mkdir -p "$T/$1"; }
d product/etc/permissions; d product/etc/sysconfig; d product/etc/default-permissions
d product/etc/security/fsverity; d product/overlay; d system_ext/etc/permissions
cp $E/product/etc/permissions/{privapp-permissions-google-p,privapp-permissions-atv-product,privapp-permissions-atv-amati-product,split-permissions-google}.xml "$T/product/etc/permissions/"
# (not atv-component-overrides.xml: device/google/atv installs its own)
cp $E/product/etc/sysconfig/{google,google_build,google_atv,amati_experience,google-hiddenapi-package-whitelist,google-staged-installer-whitelist}.xml "$T/product/etc/sysconfig/"
cp $E/product/etc/default-permissions/{default-atv-permissions,default-atv-amati-permissions}.xml "$T/product/etc/default-permissions/"
cp $E/product/etc/security/fsverity/*.der "$T/product/etc/security/fsverity/"
for o in GoogleTvConfigOverlayX GTVSSettingsProviderOverlayX TvSystemUiConfigOverlayX \
         TvSettingsGmsResOverlay TvSettingsGoogleResOverlay; do
    # (not TvWifiOverlayGoogle: device/google/atv builds a module of that name)
    cp "$E/product/overlay/$o.apk" "$T/product/overlay/"
done
ls $E/system_ext/etc/permissions/ | grep -i google | while read -r f; do cp "$E/system_ext/etc/permissions/$f" "$T/system_ext/etc/permissions/"; done
chown -R 1000:1000 "$(dirname "$T")"
du -sh "$T"; find "$T" -type f | sed "s|$T/||" | sort
