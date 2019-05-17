#!/bin/bash

export TEST_BUILDER_DIR=$(dirname $(readlink -f ${0}))

if [[ "$(id -u)" != "0" ]]; then
    echo "This script must be run as root. Exiting."
    echo; exit
fi



##---------------------FUNCTIONS-------------------------------##
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



function CLEAN()
{
    DTG=$(date | awk '{print $3$2$6"-"$4}' | tr ":" ".")
    sudo mkdir "${LOG_DIR}/${DTG}"
    sudo cp -r "${EXT_SQUASH_FS}/var/log/*" "${LOG_DIR}/${DTG}"
    sudo chroot ${EXT_SQUASH_FS} apt-get -y clean
    sudo chroot ${EXT_SQUASH_FS} apt-get -y autoremove
    sudo chroot ${EXT_SQUASH_FS} rm /var/lib/dbus/machine-id
    sudo chroot ${EXT_SQUASH_FS} dpkg-divert --rename --remove /sbin/initctl
    sleep 1

    for i in "/tmp/*" "/etc/resolv.conf" "/etc/hosts" \
             "/root/.bash_history" "/var/log/*" "/vmlinuz" \
             "/initrd.img"
    do
        echo "Removing ${EXT_SQUASH_FS}${i}..."
        sudo rm -rf "${EXT_SQUASH_FS}${i}"
    done

    if [[ -f ${CLEAN_FILE} ]]; then
        while read line
        do
                        echo "Removing ${line}..."
            sudo rm -rf $line
        done <${CLEAN_FILE}
    fi

    sudo rm ${CLEAN_FILE}
    #sudo chroot ${EXT_SQUASH_FS} ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
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
    for i in "genisoimage xorriso sys-linux"
    do
        check=$(dpkg-query -W --showformat='${Package}\n' $i | wc -w)
        if [[ ! ${check} -gt 0 ]]; then
            echo "We couldn't find ${i}..."
            echo "install ${i}?"
            read input
            if [[ ${input} == "yes" ]]; then
                apt-get --force-yes -y install ${i}
            fi
        fi
    done
}



function RESTORE_CACHED_PACKAGES()
{
    echo "Restoring cached packages"
    sudo mkdir -p ${EXT_SQUASH_FS}/var/cache/apt/archives/
    for alpha in {a..z}
    do
        cp -v ${CACHE_DIR}/${alpha}* ${EXT_SQUASH_FS}/var/cache/apt/archives/
    done
}

export -f RESTORE_CACHED_PACKAGES
export -f SET_CHROOT
export -f CLEAN_CHROOT
export -f CLEAN
export -f SETUP




if [[ $1 == "clean_chroot" ]]; then
    CLEAN_CHROOT
    exit
fi

# ADD IF $1 CUSTOMIZE OR CHROOT
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

elif [[ "$1" == "clean" ]]; then
    CLEAN
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
            echo "Name of the build?"
            printf "> "
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

            printf "\nChoose build to restore."
            printf "\n> "
            read package_basename

            package="$BUILD_CACHE/${package_basename}"
            if [[ ! -e $package ]]; then
                echo "${package_basename} does not exist."
                exit
            fi

            echo ${package}
            echo "You are about to delete your current build scripts and reources. Are you sure you want to proceed? [yes|no]"
            read choice
            if [[ $choice == "yes" ]]; then
                rm -rf ${GCONF_DIR} ${CACHE_DIR} ${BINARY_PACKAGES} ${INCLUDE_DIR} ${SCRIPTS_IN_DIR} ${SCRIPTS_EX_DIR} ${SOURCES_DIR}
                tar -zxvf ${package} -C /
            fi
        ;;



        #------------------------------------# EXTRACT #--------------------------------------------
        extract)
            BASE_ISO_IMAGE="$(ls ${ORIGINAL_IMAGE_DIR}/*.iso)"
            if [[ ! -e ${BASE_ISO_IMAGE} ]]; then
                echo "Check your base image directory. It should contain only one iso."
            fi

            mkdir -p ${SYS_BUILD_HOME}/mnt
            sudo mount -o loop ${BASE_ISO_IMAGE} ${SYS_BUILD_HOME}/mnt > /dev/null 2>&1
            sudo rsync --exclude=/live/filesystem.squashfs -a ${SYS_BUILD_HOME}/mnt/ \
            ${EXT_ISO_CONTENTS}

            #Ubuntu
            #sudo unsquashfs ${SYS_BUILD_HOME}/mnt/casper/filesystem.squashfs

            #Kali
            sudo unsquashfs ${SYS_BUILD_HOME}/mnt/live/filesystem.squashfs
            sudo mv squashfs-root ${EXT_SQUASH_FS}
            sudo umount ${SYS_BUILD_HOME}/mnt

            if [[ -d ${CACHE_DIR} ]]; then
                if [[ $(ls ${CACHE_DIR} | wc -l) > 0 ]]; then
                    echo "Cached packages detected. Would you like to restore them?"
                    read input

                    if [[ ${input} == "yes" ]]; then
                        RESTORE_CACHED_PACKAGES
                    fi
                fi
            fi
        ;;



        #--------------------------------# RESTORE CACHED PACKAGES #----------------------------------------
        restore_cached_packages)
            echo "Restoring cached packages"
            sudo mkdir -p ${EXT_SQUASH_FS}/var/cache/apt/archives/
                        for alpha in {a..z}
                        do
                            cp -v ${CACHE_DIR}/${alpha}* ${EXT_SQUASH_FS}/var/cache/apt/archives/
                        done
        ;;



        #--------------------------# CACHE PACKAGES FROM WITHIN CHROOT #--------------------------------------
        cache_packages)
            echo "Caching packages"
                        for alpha in {a..z}
                        do
                            cp -v ${EXT_SQUASH_FS}/var/cache/apt/archives/${alpha}*.deb ${CACHE_DIR}/
                        done

                        for num in {0..9}
                        do
                            cp -v ${EXT_SQUASH_FS}/var/cache/apt/archives/${num}*.deb ${CACHE_DIR}/
                        done
        ;;



        #-----------------------------# DELETE ISO AND SQUASHFS CONTENTS #----------------------------------------
        delete)
            CLEAN_CHROOT
            echo "Removing old build base..."
            sudo rm -rf ${EXT_ISO_CONTENTS} ${EXT_SQUASH_FS}
            echo "Complete."
        ;;



        #--------------------------------# TEST PACKAGE LIST #----------------------------------------
        test_package_list)
            File="${SYS_BUILD_HOME}/package_install_list.txt"
            while read line
            do
                #sort $File | grep $line | uniq --count | awk '{print $1,"occurance of", $2}'
                number=$(cat $File | grep -o "${line} " | wc -l)
                if [[ ${number} > 1 ]]; then
                    echo "${number} occurance of ${line}"
                fi
                echo "testing ${line} availability..."
                sudo apt-get -s -qq install $line > /dev/null
            done <$File
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
                        #RUNNING ALL CUSTOMIZE SCRIPTS
                            for j in $(ls ${SCRIPTS_EX_DIR})
                            do
                                echo "running ${j}"
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
                        #RUNNING SPECIFIED SCRIPT ONLY
                            echo "running ${script}"
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
                        #RUNNING ALL CUSTOMIZE SCRIPTS
                            for j in $(ls ${EXT_SQUASH_FS}/scripts)
                            do
                                echo "running ${j}"
                                case $j in
                                    *.py)
                                        # FIND A WAY TO HAVE SCRIPT SPECIFY PYTHON VERSION AND EXECUTE WITH ./
                                        sudo chroot ${EXT_SQUASH_FS} python3 /scripts/$j
                                    ;;
                                    *.sh)
                                        if [[ $j == "13_install_from_package_list.sh" ]];then
                                            cp ${SYS_BUILD_HOME}/package_install_list.txt ${EXT_SQUASH_FS}
                                        fi
                                        sudo chroot ${EXT_SQUASH_FS} bash /scripts/$j
                                        sudo mv "${EXT_SQUASH_FS}/tmp/package_installation.log" ${LOG_DIR}
                                    ;;
                                esac
                            done
                        else
                        #RUNNING SPECIFIED SCRIPT ONLY
                            echo "running ${script}"
                            case $script in
                                *.py)
                                    sudo chroot ${EXT_SQUASH_FS} \
                                    python3 /scripts/$script
                                ;;
                                *.sh)
                                    if [[ $script == "13_install_from_package_list.sh" ]];then
                                        cp ${SYS_BUILD_HOME}/package_install_list.txt ${EXT_SQUASH_FS}
                                    fi
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
            # Kali
            printf "Path and name of file: "
            read input

            if [[ -e ${input} ]] && [[ ${input} == *"${EXT_ISO_CONTENTS}"* ]]; then
                echo "working..."
                path=$(dirname "${input}")
                file=$(basename "${input}")
                extn="${file##*.}"

                mkdir -p "${path}/tempdir"
                echo "${path}/tempdir" >> ${CLEAN_FILE}
                cd "${path}/tempdir"

                if [[ ${extn} == "gz" ]]; then
                    gzip -d ../${file}
                    cpio -ivdum < ../initrd
                else
                    cpio -ivdum < ../${file}
                fi

                mv ../${file} ../"${file}.orig"
            fi

            # Ubuntu
            # mkdir -p ${EXT_ISO_CONTENTS}/casper/lztempdir
            # sudo echo "${EXT_ISO_CONTENTS}/casper/lztempdir" >> ${CLEAN_FILE}
            # cd ${EXT_ISO_CONTENTS}/casper/lztempdir
            # lzma -dc -S .lz ../initrd.lz | cpio -imvd --no-absolute-filenames
        ;;



        #------------------------------------# PACKAGE INITRD #--------------------------------------------
        package_initrd)
            # Ubuntu
            # cd ${EXT_ISO_CONTENTS}/casper/lztempdir
            # echo "Compressing initrd package..."
            # find . | cpio --quiet --dereference -o -H newc | lzma -7 > ../initrd.lz
            # echo "Removing extracted initrd contents (lztempdir)..."
            # cd .. && rm -rf ${EXT_ISO_CONTENTS}/casper/lztempdir
            # echo

            # Kali
            printf "Path to extracted initrd contents: "
            read input

            if [[ -e ${input} ]]; then
                echo "working..."
                cd ${input}
                echo "Compressing initrd package..."
                find . | cpio -o --format='newc' > ../initrd
                gzip -v9 ../initrd
                #echo "Removing extracted initrd contents (lztempdir)..."
                #cd .. && rm -rf "${input}"
                echo
            fi
        ;;



        #------------------------------------# SQUASHFS #--------------------------------------------
        squashfs)
            CLEAN
            CLEAN_CHROOT
            sleep 2
            CLEAN_CHROOT


            # Ubuntu
            # if [[ -f "${EXT_ISO_CONTENTS}/casper/filesystem.squashfs" ]]; then
            #   sudo rm ${EXT_ISO_CONTENTS}/casper/filesystem.squashfs
            # fi
            # sudo mksquashfs ${EXT_SQUASH_FS} ${EXT_ISO_CONTENTS}/casper/filesystem.squashfs

            # KALI
            if [[ -f "${EXT_ISO_CONTENTS}/live/filesystem.squashfs" ]]; then
                echo "deleting existing squashfs..."
                sudo rm ${EXT_ISO_CONTENTS}/live/filesystem.squashfs
            fi

            sudo mksquashfs -comp xz ${EXT_SQUASH_FS} ${EXT_ISO_CONTENTS}/live/filesystem.squashfs
            # RECREATE ALL FILESYSTEM MANIFESTS AND INFORMATIONAL FILES
            # sudo printf $(sudo du -sx --block-size=1 edit | cut -f1) > ${EXT_ISO_CONTENTS}/casper/filesystem.size
        ;;



        #------------------------------------# MKISO #--------------------------------------------
        mkiso)
            echo "mkisofs options to support..."
            echo "1. Grub/MBR boot"
            echo "2. UEFI boot"
            echo
            printf "> "
            read option

            if [[ -e ${NEW_ISO} ]]; then
                echo "Remove old iso?"
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

                #sudo rm md5sum.txt
                #sudo find -type f -print0 | sudo xargs -0 md5sum | sudo grep -v isolinux/boot.cat | sudo tee md5sum.txt
                cd ${EXT_ISO_CONTENTS}
                isohybrid_mbr="isolinux/isohdpfx.bin"
                efi_image="EFI/boot/bootx64.efi"
                boot_cat="isolinux/boot.cat"
                isolinux_bin="isolinux/isolinux.bin"

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
