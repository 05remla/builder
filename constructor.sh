#!/bin/bash
# constructor.sh -
# part of the linux builder scripts
# developed by 05remla@gmail.com
# modified 18 may 2019 @ 01:20
#
# -------------------- ToDo ---------------------------
# [ ] add build info file that gets initialized
#     durring start_build - tracks build specific
#     notes. offers a description in console
#     while building
# [ ] add audible queues for completion
# [ ] remove color from information statements
# [ ] add better logging features
# [ ] add menu for cutting down on size of product
#     Ex. delete locales, delete manpages, etc...
# [X] fix all formation in builder scripts
#     remove whitespace, tab and space consistancy
# [X] fix initrd extraction
# [X] add color to all user prompts
# [ ] fix package install list scripts_in
# [ ] fix deleting of package install list
# [ ] fix handling of squashfs extra compression
# [ ] fix handling of boot method creation
# [ ] fix handling of iso file creation
# [ ] add more iso booting methods
# [ ] generate checksum for finished product
# [ ] fix tool checking in setup to use 'which' command
# [ ] fix cache_packages to cache those not already
#     cached only
# [ ] under customize: specify options directly
#     Ex. customize bin inc sci sce
# [ ] recreate filesystem manifests and information
# [ ] incorperate config file variables based on distro
#     for interoperability between distros
#     Ex. live session dir and initrd found in
#         differant locations based on distro

export TEST_BUILDER_DIR=$(dirname $(readlink -f ${0}))

if [[ "$(id -u)" != "0" ]]; then
  echo "This script must be run as root. Exiting."
  echo; exit
fi



##---------------------FUNCTIONS-------------------------------##
function LOGGER()
{
  # Ex. cat file.txt 2>&1 | LOGGER test.log
  logfile=$1
  date_data=($(echo $(date)))
  dtg="${date_data[2]}${date_data[1]}${date_data[5]}@${date_data[3]}"
  printf "[$dtg] " >> $logfile
  tee -a $logfile
}


function SET_CHROOT()
{
  if [[ ! -f "/tmp/proj_chroot_config" ]]; then
    echo "Setting up chroot environment..."
    echo
    sudo mount --bind /dev/ ${EXT_SQUASH_FS}/dev    #POSSIBLE ISSUES WITH UNMOUNTING?
    sudo chroot ${EXT_SQUASH_FS} mount -t proc none /proc
    sudo chroot ${EXT_SQUASH_FS} mount -t sysfs none /sys
    sudo chroot ${EXT_SQUASH_FS} mount -t devpts none /dev/pts
    sudo cp /etc/resolv.conf ${EXT_SQUASH_FS}/etc/
    sudo cp /etc/hosts ${EXT_SQUASH_FS}/etc/
    sudo mkdir -p ${EXT_SQUASH_FS}/var/lib/dbus
    sudo dbus-uuidgen > ${EXT_SQUASH_FS}/var/lib/dbus/machine-id
    sudo cp ${EXT_SQUASH_FS}/var/lib/dbus/machine-id ${EXT_SQUASH_FS}/etc/machine-id
    sudo chroot ${EXT_SQUASH_FS} dpkg-divert --local --rename --add /sbin/initctl
    sudo echo "1" > "/tmp/proj_chroot_config"
  fi
}



function CLEAN_CHROOT()
{
  for i in $(mount | grep -w ${EXT_SQUASH_FS} | awk '{print $3}' | tr "\n" " ")
  do
    umount $i
  done

  if [[ -f "/tmp/proj_chroot_config" ]]; then
    sudo rm "/tmp/proj_chroot_config"
  fi
}


function CLEAN_BUILD()
{
  # remove all build related files
  # rm -rf 
}


function CLEAN_SQUASHFS()
{
  if [[ $(ls "${EXT_SQUASH_FS}/var/cache/apt/archives" | wc -l) > 2 ]]; then
    printf "${CLI_GREEN}would you like to cache packages first${CLI_RESET}?: "
    read option
    if [[ $option == "yes" ]]; then
      CACHE_PACKAGES
    fi
  fi

  DTG=$(date | awk '{print $3$2$6"-"$4}' | tr ":" ".")
  sudo mkdir -p "${LOG_DIR}/${DTG}"
  sudo cp -r "${EXT_SQUASH_FS}/var/log" "${LOG_DIR}/${DTG}" 2>/dev/null
  sudo chroot ${EXT_SQUASH_FS} apt-get -y clean
  sudo chroot ${EXT_SQUASH_FS} apt-get -y autoremove
  sudo chroot ${EXT_SQUASH_FS} rm /var/lib/dbus/machine-id 2>/dev/null
  sudo chroot ${EXT_SQUASH_FS} dpkg-divert --rename --remove /sbin/initctl
  sleep 1

  for i in "/tmp/*" "/etc/resolv.conf" "/etc/hosts" \
           "/root/.bash_history" "/var/log/*" "/vmlinuz" \
           "/initrd.img"
  do
    echo "Removing ${EXT_SQUASH_FS}${i}..."
    sudo rm -rf "${EXT_SQUASH_FS}${i}" 2>/dev/null
  done

  if [[ -f ${CLEAN_FILE} ]]; then
    while read line
    do
      echo "Removing ${line}..."
      sudo rm -rf $line 2>/dev/null
    done <${CLEAN_FILE}
  fi

  sudo rm ${CLEAN_FILE}
}



function SETUP()
{
  # MAKE DIRECTORIES
  for i in "${SYS_BUILD_HOME} ${GCONF_DIR} ${SCRIPTS_IN_DIR} \
            ${BINARY_PACKAGES} ${INCLUDE_DIR} ${ORIGINAL_IMAGE_DIR} \
            ${CACHE_DIR} ${SCRIPTS_EX_DIR} ${KERNEL_DIR} ${BUILD_CACHE} \
            ${NEW_ISO} ${LOG_DIR}"
  do
    mkdir -p $i
    sudo chmod 777 $i
  done

  # CHECK TOOLS/PACKAGES
  for i in "genisoimage xorriso sys-linux initramfs-tools"
  do
    check=$(dpkg-query -W --showformat='${Package}\n' $i | wc -w)
    if [[ ! ${check} -gt 0 ]]; then
      printf "${CLI_RED}We couldn't find ${i}..."
      printf "install ${i}?: ${CLI_RESET}"
      read input
      if [[ ${input} == "yes" ]]; then
        apt-get --force-yes -y install ${i}
      fi
    fi
  done
}


function CACHE_PACKAGES()
{
  echo "Caching packages"
  for alpha in {a..z}
  do
    cp -v ${EXT_SQUASH_FS}/var/cache/apt/archives/${alpha}*.deb ${CACHE_DIR}/ 2>/dev/null
  done

  for num in {0..9}
  do
    cp -v ${EXT_SQUASH_FS}/var/cache/apt/archives/${num}*.deb ${CACHE_DIR}/ 2>/dev/null
  done
}


function RESTORE_CACHED_PACKAGES()
{
  printf "${CLI_GREEN}Restoring cached packages${CLI_RESET}...\n"
  sudo mkdir -p ${EXT_SQUASH_FS}/var/cache/apt/archives/
  for alpha in {a..z}
  do
    cp ${CACHE_DIR}/${alpha}* ${EXT_SQUASH_FS}/var/cache/apt/archives/ 2>/dev/null
  done

  for num in {0..9}
  do
    cp ${CACHE_DIR}/${num}* ${EXT_SQUASH_FS}/var/cache/apt/archives/ 2>/dev/null
  done
}


function GET_KERNEL()
{
  tmpstr=$(ls /boot/initrd*)
  str=${tmpstr[0]}
  kernel=${str:17:-1}
  echo ${kernel}
}

export -f CACHE_PACKAGES
export -f RESTORE_CACHED_PACKAGES
export -f SET_CHROOT
export -f CLEAN_CHROOT
export -f CLEAN_SQUASHFS
export -f LOGGER
export -f SETUP
export -f GET_KERNEL



if [[ $1 == "clean_chroot" ]]; then
  CLEAN_CHROOT
  exit
fi


if [[ -d ${EXT_SQUASH_FS} ]]; then
  if [[ $1 == "customize" ]] || [[ $1 == "chroot" ]]; then
    SET_CHROOT
  fi
fi


if [[ "$1" == "chroot" ]]; then
  echo "COPY AND PASTE"
  echo "export HOME=/root"
  echo "export LC_ALL=C"
  echo
  sudo chroot ${EXT_SQUASH_FS}
  exit

elif [[ "$1" == "clean_squashfs" ]]; then
  CLEAN_SQUASHFS
  exit

elif [[ "$1" == "setup" ]]; then
  SETUP
  echo "If you recieved no error messages that means all is well."
  exit

elif [[ $1 == "restore_cached_packages" ]]; then
  RESTORE_CACHED_PACKAGES
  exit

elif [[ -z "$1" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  cat "${SYS_BUILD_HOME}/BUILDER_SCRIPTS/help_file.rc"
fi



for i in "${1}"
do
  case $i in
    #------------------------------------# BACKUP BUILD BASE #--------------------------------------------
    backup_build)
      printf "${CLI_GREEN}Name the build package: ${CLI_RESET}"
      read BuildName
      tar -zcvf ${BuildName}.tar.gz ${GCONF_DIR} ${CACHE_DIR} ${BINARY_PACKAGES} ${INCLUDE_DIR} ${SCRIPTS_IN_DIR} \
      ${SCRIPTS_EX_DIR} ${SOURCES_DIR} "${SYS_BUILD_HOME}/package_install_list.txt" "${SYS_BUILD_HOME}/notes.txt"
      mv ${BuildName}.tar.gz $BUILD_CACHE
    ;;



    #------------------------------------# RESTORE BUILD BASE #--------------------------------------------
    restore_build)
      x=0
      for i in $(ls $BUILD_CACHE | tr " " "\n")
      do
        echo " $i"
      done

      printf "\n${CLI_RED}Choose build to restore: ${CLI_RESET}"
      read package_basename

      package="$BUILD_CACHE/${package_basename}"
      if [[ ! -e $package ]]; then
        echo "${package_basename} does not exist."
        exit
      fi

      echo ${package}
      printf "${CLI_RED}You are about to delete your current build scripts and reources."
      printf "Are you sure you want to proceed?${CLI_RESET} [yes|no]: "
      read choice
      if [[ $choice == "yes" ]]; then
        rm -rf ${GCONF_DIR} ${CACHE_DIR} ${BINARY_PACKAGES} ${INCLUDE_DIR} ${SCRIPTS_IN_DIR} ${SCRIPTS_EX_DIR} ${SOURCES_DIR}
        tar -zxvf ${package} -C /
      fi
    ;;



    #------------------------------------# EXTRACT #--------------------------------------------
    start_build)
      printf "1) ${CLI_GREEN}use existing base${CLI_RESET}\n2) ${CLI_GREEN}start fresh? \n${CLI_RESET}[1,2]: "
      read option

      if [[ $option == 1 ]]; then
        ls_data=$(ls ${ORIGINAL_IMAGE_DIR})
        if [[ $(echo ${ls_data} | wc -l) -gt 1 ]]; then
          printf "${CLI_RED}too many file in base system directory. Exiting.${CLI_RESET}\n"
          exit
        fi

        if [[ $(echo ${ls_data} | wc -l) == 0 ]]; then
          printf "${CLI_RED}No base image found. Exiting.${CLI_RESET}\n"
          exit
        fi

        read -a ls_array <<< $(echo ${ls_data})
        package=$(echo ${ls_array[0]})
        extn="${package##*.}"

        if [[ $extn == "iso" ]]; then
          printf "${CLI_GREEN}ISO found, proceeding${CLI_RESET}...\n"
          BASE_ISO_IMAGE="$(ls ${ORIGINAL_IMAGE_DIR}/*.iso)"
          mkdir -p ${SYS_BUILD_HOME}/mnt
          sudo mount -o loop ${BASE_ISO_IMAGE} ${SYS_BUILD_HOME}/mnt > /dev/null 2>&1
          sudo rsync --exclude=/live/filesystem.squashfs -a ${SYS_BUILD_HOME}/mnt/ \
          ${EXT_ISO_CONTENTS}

          sudo unsquashfs ${SYS_BUILD_HOME}/mnt/live/filesystem.squashfs
          sudo mv squashfs-root ${EXT_SQUASH_FS}
          sudo umount ${SYS_BUILD_HOME}/mnt
        fi

        if [[ $extn == "gz" ]]; then
          printf "${CLI_GREEN}Archive found, proceeding${CLI_RESET}...\n"
          mkdir -p ${EXT_ISO_CONTENTS}
          mkdir -p ${EXT_SQUASH_FS}
          tar -zxf ${ORIGINAL_IMAGE_DIR}/${package} -C ${SYS_BUILD_HOME}
        fi

      elif [[ $option == 2 ]]; then
        printf "${CLI_GREEN}Generating base system...${CLI_RESET}\n"
        sudo debootstrap --arch=i386 --variant=minbase stretch ${EXT_SQUASH_FS} http://ftp.us.debian.org/debian/
        mkdir -p ${EXT_ISO_CONTENTS}
      fi

      if [[ -d ${CACHE_DIR} ]]; then
        if [[ $(ls ${CACHE_DIR} | wc -l) > 0 ]]; then
          printf "${CLI_GREEN}Cached packages detected. Would you like to restore them?${CLI_RESET}: "
          read input

          if [[ ${input} == "yes" ]]; then
            RESTORE_CACHED_PACKAGES
          fi
        fi
      fi
    ;;



    #--------------------------------# RESTORE CACHED PACKAGES #----------------------------------------
    restore_cached_packages)
      RESTORE_CACHED_PACKAGES
    ;;



    #--------------------------# CACHE PACKAGES FROM WITHIN CHROOT #--------------------------------------
    cache_packages)
      CACHE_PACKAGES
    ;;



    #-----------------------------# DELETE ISO AND SQUASHFS CONTENTS #----------------------------------------
    delete)
      printf "${CLI_RED}set to delete current build system files. proceed?${CLI_RESET}: "
      read option

      if [[ ${option} == "yes" ]]; then
        CLEAN_CHROOT
        printf "${CLI_GREEN}removing old build base${CLI_RESET}...\n"
        sudo rm -rf ${EXT_ISO_CONTENTS} ${EXT_SQUASH_FS}
      fi
    ;;



    #------------------------------------# CUSTOMIZE #--------------------------------------------
    customize)
        if [[ -z ${2} ]]; then
          MODE="all"
        else
          MODE="${2}"
        fi


        case "${MODE}" in
            #-----------------------------------------------------#
            #               BINARY PACKAGES                       #
            #-----------------------------------------------------#
            binary|all)
                if [[ $(ls ${BINARY_PACKAGES} | wc -l) -gt "0" ]]; then
                  mkdir -p ${EXT_SQUASH_FS}/binaries
                  sudo echo "${EXT_SQUASH_FS}/binaries" >> ${CLEAN_FILE}
                  cp ${BINARY_PACKAGES}/* ${EXT_SQUASH_FS}/binaries/

                  for i in $(ls ${EXT_SQUASH_FS}/binaries)
                  do
                    sudo chroot ${EXT_SQUASH_FS} dpkg -iE /binaries/${i}
                  done
                fi;
            ;;



            #-------------------------------------------------#
            #                   INCLUDES                      #
            #-------------------------------------------------#
            include|all)
                if [[ $(ls ${INCLUDE_DIR} | wc -l) -gt "0" ]]; then
                  echo "Moving items..."
                  if [[ -d ${INCLUDE_DIR}/etc/init.d ]];then
                    ls ${INCLUDE_DIR}/etc/init.d | tr " " "\n" > ${EXT_SQUASH_FS}/tmp/init_scripts.txt
                  fi
                  cp -R -p ${INCLUDE_DIR}/* ${EXT_SQUASH_FS}
                fi;
            ;;



            #-----------------------------------------------#
            #                  GCONF TWEAKS                 #
            #-----------------------------------------------#
            gconf|all)
                if [[ $(ls ${GCONF_DIR} | wc -l) -gt "0" ]]; then
                  echo "applying gconf configs"
                  sudo mkdir -p ${EXT_SQUASH_FS}/gconf
                  sudo echo "${EXT_SQUASH_FS}/gconf" >> ${CLEAN_FILE}
                  sudo cp ${GCONF_DIR}/*.xml ${EXT_SQUASH_FS}/gconf/
                  for j in $(ls ${EXT_SQUASH_FS}/gconf)
                  do
                    sudo chroot ${EXT_SQUASH_FS} gconftool-2 \
                    --direct --config-source \
                    xml:readwrite:/etc/gconf/gconf.xml.defaults \
                    --load /gconf/$j
                  done
                fi;
            ;;




            #-------------------------------------------------#
            #                 SCRIPTS EXTERNAL                #
            #-------------------------------------------------#
            scripts_ex|all)
                if [[ $(ls ${SCRIPTS_EX_DIR} | wc -l) -gt "0" ]]; then
                  if [[ -z "$3" ]]; then
                    script="all"

                  elif [[ "$3" == "list" ]]; then
                    ls ${SCRIPTS_EX_DIR}
                    echo; exit

                  else
                    script="$3"
                    if [[ ! -e ${SCRIPTS_EX_DIR}/${script} ]]; then
                      echo "${script} does not exist."
                      exit
                    fi
                  fi

                  if [[ "$script" == "all" ]]; then
                  # RUNNING ALL CUSTOMIZE SCRIPTS
                    for j in $(ls ${SCRIPTS_EX_DIR})
                    do
                      printf "${CLI_GREEN}running ${j}${CLI_RESET}\n"
                      case $j in
                        *.py)
                          # FIND A WAY TO HAVE SCRIPT SPECIRY PYTHON VERSION AND EXECUTE WITH ./
                          python3 "${SCRIPTS_EX_DIR}/$j"
                        ;;
                        *.sh)
                          bash "${SCRIPTS_EX_DIR}/$j"
                        ;;
                      esac
                    done
                  else

                  # RUNNING SPECIFIED SCRIPT ONLY
                    printf "${CLI_GREEN}running ${script}${CLI_RESET}\n"
                    case $script in
                      *.py)
                        python3 ${SCRIPTS_EX_DIR}/$script
                      ;;
                      *.sh)
                        bash ${SCRIPTS_EX_DIR}/$script
                      ;;
                    esac
                  fi
                fi
            ;;



            #-------------------------------------------------#
            #                 SCRIPTS INTERNAL                #
            #-------------------------------------------------#
            scripts_in|all)
                cp ${SYS_BUILD_HOME}/package_install_list.txt ${EXT_SQUASH_FS}
                sudo echo "${EXT_SQUASH_FS}/package_install_list.txt" >> ${CLEAN_FILE}

                if [[ $(ls ${SCRIPTS_IN_DIR} | wc -l) -gt "0" ]]; then
                    mkdir -p "${EXT_SQUASH_FS}/scripts"
                    sudo cp -r ${SCRIPTS_IN_DIR}/* ${EXT_SQUASH_FS}/scripts/
                    sudo echo "${EXT_SQUASH_FS}/scripts" >> ${CLEAN_FILE}
                    sudo chmod -R +x ${EXT_SQUASH_FS}/scripts

                    if [[ -z "$3" ]]; then
                      script="all"

                    elif [[ "$3" == "list" ]]; then
                      ls ${EXT_SQUASH_FS}/scripts
                      echo; exit

                    else
                      script="$3"
                      if [[ ! -e ${EXT_SQUASH_FS}/scripts/${script} ]]; then
                        echo "${script} does not exist."
                        exit
                      fi
                    fi

                    if [[ "$script" == "all" ]]; then
                    # RUNNING ALL CUSTOMIZE SCRIPTS
                      for j in $(ls ${EXT_SQUASH_FS}/scripts)
                      do
                        printf "${CLI_GREEN}running ${j}${CLI_RESET}\n"
                        case $j in
                          *.py)
                            # FIND A WAY TO HAVE SCRIPT SPECIFY PYTHON VERSION AND EXECUTE WITH ./
                            sudo chroot ${EXT_SQUASH_FS} python3 /scripts/$j
                          ;;
                          *.sh)
                            sudo chroot ${EXT_SQUASH_FS} bash /scripts/$j
                            #sudo mv "${EXT_SQUASH_FS}/tmp/package_installation.log" ${LOG_DIR}
                          ;;
                        esac
                      done
                    else

                    # RUNNING SPECIFIED SCRIPT ONLY
                      printf "${CLI_GREEN}running ${script}${CLI_RESET}\n"
                      case $script in
                        *.py)
                          sudo chroot ${EXT_SQUASH_FS} \
                          python3 /scripts/$script
                        ;;
                        *.sh)
                          sudo chroot ${EXT_SQUASH_FS} \
                          bash /scripts/$script
                        ;;
                      esac
                    fi
                fi
            ;;
        esac #CUSTOMIZE CASE LOOP

    ;;



    #------------------------------------# OPEN INITRD #--------------------------------------------
    open_initrd)
        # add initramfs tools command 'unmakeinitrd' here
        printf "${CLI_RED}Path and name of file: ${CLI_RESET}"
        read input

        if [[ -e ${input} ]] && [[ ${input} == *"${EXT_ISO_CONTENTS}"* ]]; then
          echo "working..."
          path=$(dirname "${input}")
          file=$(basename "${input}")
          extn="${file##*.}"
          echo $path $file $extn

          mkdir -p "${path}/tempdir"
          echo "${path}/tempdir" >> ${CLEAN_FILE}
          cd "${path}/tempdir"

        fi
    ;;



    #------------------------------------# PACKAGE INITRD #--------------------------------------------
    package_initrd)
        printf "${CLI_RED}Path to extracted initrd contents: ${CLI_RESET}"
        read input

        if [[ -e ${input} ]]; then
          echo "working..."
          cd ${input}
          echo "Compressing initrd package..."
          find . | cpio -o --format='newc' > ../initrd.img
          gzip -v9 ../initrd.img
          echo
        fi
    ;;



    #------------------------------------# SQUASHFS #--------------------------------------------
    squashfs)
        printf "${CLI_RED}use extra compression?: ${CLI_RESET}"
        read option

        if [[ -f "${EXT_ISO_CONTENTS}/live/filesystem.squashfs" ]]; then
          echo "deleting existing squashfs..."
          sudo rm ${EXT_ISO_CONTENTS}/live/filesystem.squashfs
        fi

        if [[ ${option} == "yes" ]]; then
          sudo mksquashfs ${EXT_SQUASH_FS} ${EXT_ISO_CONTENTS}/live/filesystem.squashfs -comp xz
        else
          sudo mksquashfs ${EXT_SQUASH_FS} ${EXT_ISO_CONTENTS}/live/filesystem.squashfs
        fi
    ;;



    #------------------------------------# MKISO #--------------------------------------------
    mkiso)
        printf "${CLI_GREEN}mkisofs for${CLI_RESET}...\n"
        echo "1. Grub/MBR boot"
        echo "2. UEFI boot"
        printf "> "
        read option

        if [[ -e ${NEW_ISO} ]]; then
          printf "${CLI_RED}Remove old iso?${CLI_RESET}: "
          read _remove
          if [[ $_remove == "no" ]]; then
            exit
          fi

          echo "Removing..."
          rm -rf ${NEW_ISO}
        fi

        if [[ $option == 1 ]] || [[ $option == 2 ]]; then
          if [[ -e "${SYS_BUILD_HOME}/store/init.sh" ]] && [[ ! -e ${EXT_ISO_CONTENTS}/init.sh ]]; then
            sudo cp "${SYS_BUILD_HOME}/store/init.sh" ${EXT_ISO_CONTENTS}
            sudo chmod +x ${EXT_ISO_CONTENTS}/init.sh
          fi

          cd ${EXT_ISO_CONTENTS}
          isohybrid_mbr="isolinux/isohdpfx.bin"
          efi_image="EFI/boot/bootx64.efi"
          boot_cat="isolinux/boot.cat"
          isolinux_bin="isolinux/isolinux.bin"

          # if [[ ! -e "${EXT_ISO_CONTENTS}${isohybrid_mbr}" ]]; then
          #   mkdir -p "${EXT_ISO_CONTENTS}${isohybrid_mbr}"
          #   cp "${SYS_BUILD_HOME}store/boot_files/isohdpfx.bin" "${EXT_ISO_CONTENTS}${isohybrid_mbr}"
          # fi
          #
          # if [[ ! -e "${EXT_ISO_CONTENTS}${efi_image}" ]]; then
          #   mkdir -p "${EXT_ISO_CONTENTS}${efi_image}"
          #   cp "${SYS_BUILD_HOME}store/boot_files/bootx64.efi" "${EXT_ISO_CONTENTS}${efi_image}"
          # fi
          #
          # if [[ ! -e "${EXT_ISO_CONTENTS}${boot_cat}" ]]; then
          #   mkdir -p "${EXT_ISO_CONTENTS}${boot_cat}"
          #   cp "${SYS_BUILD_HOME}store/boot_files/boot.cat" "${EXT_ISO_CONTENTS}${boot_cat}"
          # fi
          #
          # if [[ ! -e "${EXT_ISO_CONTENTS}${isolinux_bin}" ]]; then
          #   mkdir -p "${EXT_ISO_CONTENTS}${isolinux_bin}"
          #   cp "${SYS_BUILD_HOME}store/boot_files/isolinux.bin" "${EXT_ISO_CONTENTS}${isolinux_bin}"
          # fi

          if [[ $option == 1 ]]; then
            genisoimage -D -r -f -cache-inodes -J -l -b ${isolinux_bin} \
            -c ${boot_cat} -no-emul-boot -boot-load-size 4 -boot-info-table -o \
            ${NEW_ISO} .
          elif [[ $option == 2 ]]; then
            xorriso -as mkisofs -U -f -v -no-emul-boot -boot-load-size 4 -boot-info-table -iso-level 4 -b \
            isolinux/isolinux.bin -isohybrid-mbr isolinux/isohdpfx.bin -c isolinux/boot.cat -eltorito-alt-boot \
            -e EFI/boot/bootx64.efi -no-emul-boot -isohybrid-gpt-basdat -o ${NEW_ISO} .
          fi
        else
          echo
          echo "Please make a numerical choice (1|2). Exiting."
          exit
        fi
    ;;
  esac
done
