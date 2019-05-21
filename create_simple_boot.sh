# script to be called from builder.sh to initialize variables
# builder.sh --script=create_simple_boot.sh
# 
# resulting file structure
# EXT_ISO_CONTENTS
#         `--------scratch
#         |            `----grub.cfg
#         |            `----core.img
#         |                 
#         `--------image
#                    `-----live
#                    |       `----squashfs
#                    |------CUSTOM_DEBIAN
#                    |------initrd.img
#                    `------vmlinuz
#
# grub 2 modules:
# acpi.mod          date.mod                     gcry_sha1.mod       loopback.mod         pbkdf2.mod          terminfo.mod
# affs.mod          datetime.mod                 gcry_sha256.mod     lsmmap.mod           pci.mod             test.mod
# afs_be.mod        dm_nv.mod                    gcry_sha512.mod     ls.mod               play.mod            tga.mod
# afs.mod           drivemap.mod                 gcry_tiger.mod      lspci.mod            png.mod             trig.mod
# aout.mod          echo.mod                     gcry_twofish.mod    lvm.mod              probe.mod           true.mod
# ata.mod           efiemu.mod                   gcry_whirlpool.mod  mdraid.mod           pxecmd.mod          udf.mod
# ata_pthru.mod     elf.mod                      gettext.mod         memdisk.mod          pxe.mod             ufs1.mod
# at_keyboard.mod   example_functional_test.mod  gfxmenu.mod         memrw.mod            raid5rec.mod        ufs2.mod
# befs_be.mod       ext2.mod                     gfxterm.mod         minicmd.mod          raid6rec.mod        uhci.mod
# befs.mod          extcmd.mod                   gptsync.mod         minix.mod            raid.mod            usb_keyboard.mod
# biosdisk.mod      fat.mod                      gzio.mod            mmap.mod             read.mod            usb.mod
# bitmap.mod        font.mod                     halt.mod            msdospart.mod        reboot.mod          usbms.mod
# bitmap_scale.mod  fshelp.mod                   handler.mod         multiboot2.mod       reiserfs.mod        usbtest.mod
# blocklist.mod     functional_test.mod          hashsum.mod         multiboot.mod        relocator.mod       vbeinfo.mod
# boot.mod          gcry_arcfour.mod             hdparm.mod          normal.mod           scsi.mod            vbe.mod
# bsd.mod           gcry_blowfish.mod            hello.mod           ntfscomp.mod         search_fs_file.mod  vbetest.mod
# bufio.mod         gcry_camellia.mod            help.mod            ntfs.mod             search_fs_uuid.mod  vga.mod
# cat.mod           gcry_cast5.mod               hexdump.mod         ohci.mod             search_label.mod    vga_text.mod
# chain.mod         gcry_crc.mod                 hfs.mod             part_acorn.mod       search.mod          video_fb.mod
# charset.mod       gcry_des.mod                 hfsplus.mod         part_amiga.mod       serial.mod          video.mod
# cmp.mod           gcry_md4.mod                 iso9660.mod         part_apple.mod       setjmp.mod          videotest.mod
# configfile.mod    gcry_md5.mod                 jfs.mod             part_gpt.mod         setpci.mod          xfs.mod
# cpio.mod          gcry_rfc2268.mod             jpeg.mod            part_msdos.mod       sfs.mod             xnu.mod
# cpuid.mod         gcry_rijndael.mod            keystatus.mod       part_sun.mod         sh.mod              xnu_uuid.mod
# crc.mod           gcry_rmd160.mod              linux16.mod         parttool.mod         sleep.mod
# crypto.mod        gcry_seed.mod                linux.mod           password.mod         tar.mod
# datehook.mod      gcry_serpent.mod             loadenv.mod         password_pbkdf2.mod  terminal.mod

mkdir -p "${EXT_ISO_CONTENTS}/image/live"
mkdir -p "${EXT_ISO_CONTENTS}/scratch"
cd "${EXT_ISO_CONTENTS}/scratch"
cp "${SYS_BUILD_HOME}/boot/grub.cfg" "${EXT_ISO_CONTENTS}/scratch"

item1=($(ls "${EXT_SQUASH_FS}/boot/init"*))
item2=($(ls "${EXT_SQUASH_FS}/boot/vmlinuz"*))
cp ${item1[0]} "${EXT_ISO_CONTENTS}/image/initrd.img"
cp ${item2[0]} "${EXT_ISO_CONTENTS}/image/vmlinuz"

touch "${EXT_ISO_CONTENTS}/image/DEBIAN_CUSTOM"

grub-mkstandalone --format=i386-pc --output=${EXT_ISO_CONTENTS}/scratch/core.img \
         --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
         --modules="linux normal iso9660 biosdisk search" --locales="" --fonts="" \
         "boot/grub/grub.cfg=${EXT_ISO_CONTENTS}/scratch/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img ${EXT_ISO_CONTENTS}/scratch/core.img \
> ${EXT_ISO_CONTENTS}/scratch/bios.img

if [[ -e "${SYS_BUILD_HOME}/debian-custom.iso" ]]; then
  rm -rf "${SYS_BUILD_HOME}/debian-custom.iso"
fi

xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "DEBIAN_CUSTOM" \
        --grub2-boot-info --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-boot boot/grub/bios.img -no-emul-boot -boot-load-size 4 \
        -boot-info-table --eltorito-catalog boot/grub/boot.cat -output \
        "${SYS_BUILD_HOME}/debian-custom.iso" -graft-points "${EXT_ISO_CONTENTS}/image" \
        /boot/grub/bios.img=${EXT_ISO_CONTENTS}/scratch/bios.img
