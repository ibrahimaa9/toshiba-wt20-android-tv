#!/bin/bash
# Runs as the build user INSIDE the chroot: builds the WT20 Android TV product
# (lineage_pc_x86_64_tv, apply22a): installer image + OTA zip in out/target/product/pc_x86_64_tv.
# Usage: build-tv.sh [make targets / flags...]      JOBS=N overrides the parallelism (default 8).
cd ~/los || exit 1
export LC_ALL=C
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$HOME/.ccache
echo "=== TV build start: $(date)"
source build/envsetup.sh
breakfast pc_x86_64_tv userdebug || { echo "BREAKFAST FAILED"; exit 1; }
m -j"${JOBS:-8}" "$@"
rc=$?
echo "=== build end: $(date), exit=$rc"
[ $rc -eq 0 ] && ls -la out/target/product/pc_x86_64_tv/*.img out/target/product/pc_x86_64_tv/*.zip 2>/dev/null
exit $rc
