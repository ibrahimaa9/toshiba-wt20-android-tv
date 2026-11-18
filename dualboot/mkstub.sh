set -e
cd ~/los
G=prebuilts/bootmgr/grub/linux-x86/x86_64-efi
ls $G/bin | head -20
mkdir -p ~/dual/out
RUN="env PATH=prebuilts/bootmgr/tools/linux-x86/bin:$PATH LD_LIBRARY_PATH=prebuilts/bootmgr/lib64 prebuilts/bootmgr/lib64/ld-linux-x86-64.so.2"
MODS="normal chain search search_fs_file fat ntfs part_gpt part_msdos disk test echo sleep"
$RUN $G/bin/grub-mkstandalone -d $G/lib/grub/x86_64-efi --locales="" --fonts="" --themes="" --format=x86_64-efi \
    --output=$HOME/dual/out/wt20-stub.efi --install-modules="$MODS" --modules="$MODS" \
    "boot/grub/grub.cfg=$HOME/dual/files/wt20-stub.cfg"
printf 'set timeout=-1\necho "*** FAKE WINDOWS BOOT MANAGER (test) ***"\nsleep 3600\n' > /tmp/fakewin.cfg
$RUN $G/bin/grub-mkstandalone -d $G/lib/grub/x86_64-efi --locales="" --fonts="" --themes="" --format=x86_64-efi \
    --output=$HOME/dual/out/fake-bootmgfw.efi --install-modules="normal echo sleep" --modules="normal echo sleep" \
    "boot/grub/grub.cfg=/tmp/fakewin.cfg"
ls -la ~/dual/out; sha256sum ~/dual/out/*.efi
ls -la out/target/product/pc_x86_64/obj/GRUB* 2>/dev/null | head -3
