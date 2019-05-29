#!/bin/bash
items=$(ls "${EXT_SQUASH_FS}/boot/init"*)
if [[ $(echo $items | wc -w) == 1 ]]; then
  #item1=($(ls "${EXT_SQUASH_FS}/boot/init"*))
  #item2=($(ls "${EXT_SQUASH_FS}/boot/vmlinuz"*))
  
else
  xx=1
  versions=""
  for i in $items
  do
    ver=$($i | cut -d- -f2)
    versions="${versions} ${ver}"
    echo "${xx}. ${ver}"
  done
  echo "which kernel will you use: "
  read option
  ver=$(echo $versions | cut -d" " -f${option})

  cd "${EXT_SQUASH_FS}/boot"
  files=$(ls *"${ver}"*)

rm -rf item1
rm -rf item2
mkdir -p "${EXT_SQUASH_FS}/kernel_install"
cp -r "${SYS_BUILD_HOME}/kernel" "${EXT_SQUASH_FS}/kernel_install"
chroot "${EXT_SQUASH_FS}" dpkg -i "/kernel_install/*.deb" | tee -a /var/log/kernel_install.log
chroot "${EXT_SQUASH_FS}" update-initramfs -u
chroot "${EXT_SQUASH_FS}"
