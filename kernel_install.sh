#!/bin/bash
# echo "kernel directory?"
# printf "> "
# read option

# kerns=($(ls "${option}/initrd"*))
# if [[ -z ${kerns} ]]; then
  # echo "no kernels in ${option}. exiting..."
  # exit
# fi

# indx=0
# versions=""
# while [[ ! -z ${kerns[indx]} ]]; do
  # ver=$(echo ${kerns[$indx]} | cut -d- -f2)
  # versions="${versions} ${ver}"
  # ((indx++))
# done

# indx=0
# for i in $versions
# do
  # echo "${indx}. ${i}"
  # ((indx++))
# done
# echo

# echo "select kernel version"
# printf "[#]> "
# read option

# version=($(echo $versions))
# selected_kernel="${versions[$option]}"
# echo "you selected ${selected_kernel}"
# echo "proceed?"
# read option

# if [[ $option == "yes" ]]; then
  # ls "/boot/init"*"${selected_kernel}"*
  # ls "/boot/vmlinuz"*"${selected_kernel}"*
# fi

rm -rf "${EXT_SQUASH_FS}/boot/init"*
rm -rf "${EXT_SQUASH_FS}/boot/vmlinuz"*

mkdir -p "${EXT_SQUASH_FS}/kernel_install"
cp -r "${SYS_BUILD_HOME}/kernel" "${EXT_SQUASH_FS}/kernel_install"
chroot "${EXT_SQUASH_FS}" dpkg -i "/kernel_install/*.deb" | tee -a /var/log/kernel_install.log
chroot "${EXT_SQUASH_FS}" update-initramfs -u
