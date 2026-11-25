#!/usr/bin/env bash
# constructor.sh - part of the Linux builder scripts
set -euo pipefail

export TEST_BUILDER_DIR
TEST_BUILDER_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Colors (disabled when stdout is not a TTY)
if [[ -t 1 ]]; then
  CLI_GREEN='\033[0;32m'
  CLI_RED='\033[0;31m'
  CLI_YELLOW='\033[0;33m'
  CLI_RESET='\033[0m'
else
  CLI_GREEN=''
  CLI_RED=''
  CLI_YELLOW=''
  CLI_RESET=''
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root. Exiting." >&2
  exit 1
fi

# Guard against running standalone with unset/empty critical paths
: "${SYS_BUILD_HOME:?SYS_BUILD_HOME must be set (run via builder.sh)}"
: "${EXT_SQUASH_FS:?EXT_SQUASH_FS must be set}"
: "${EXT_ISO_CONTENTS:?EXT_ISO_CONTENTS must be set}"
: "${CLEAN_FILE:=${EXT_SQUASH_FS}/clean_me.txt}"
: "${LIVE_DIR:=live}"

CHROOT_LOCK="/tmp/proj_chroot_config"

##--------------------- HELPERS -------------------------------##
confirm() {
  local prompt="$1"
  local reply
  read -r -p "${prompt} [y/N]: " reply
  [[ "${reply,,}" =~ ^(y|yes)$ ]]
}

LOGGER() {
  local logfile="$1"
  local dtg
  dtg="$(date '+%d%b%Y@%H:%M:%S')"
  mkdir -p "$(dirname "$logfile")"
  awk -v ts="[$dtg] " '{ print ts $0; fflush(); }' | tee -a "$logfile"
}

SET_CHROOT() {
  if [[ ! -f "$CHROOT_LOCK" ]]; then
    echo "Setting up chroot environment..."
    mount --bind /dev "${EXT_SQUASH_FS}/dev"
    mount -t proc none "${EXT_SQUASH_FS}/proc"
    mount -t sysfs none "${EXT_SQUASH_FS}/sys"
    mount -t devpts none "${EXT_SQUASH_FS}/dev/pts"

    cp -f /etc/resolv.conf "${EXT_SQUASH_FS}/etc/"
    cp -f /etc/hosts "${EXT_SQUASH_FS}/etc/"

    mkdir -p "${EXT_SQUASH_FS}/var/lib/dbus"
    dbus-uuidgen > "${EXT_SQUASH_FS}/var/lib/dbus/machine-id"
    cp -f "${EXT_SQUASH_FS}/var/lib/dbus/machine-id" "${EXT_SQUASH_FS}/etc/machine-id"

    chroot "${EXT_SQUASH_FS}" dpkg-divert --local --rename --add /sbin/initctl || true
    echo "1" > "$CHROOT_LOCK"
  fi
}

CLEAN_CHROOT() {
  local mnt
  # Unmount deepest nested mountpoints first
  while IFS= read -r mnt; do
    [[ -n "$mnt" ]] && umount -lf "$mnt" || true
  done < <(mount | awk -v root="${EXT_SQUASH_FS}" '$3 == root || index($3, root "/") == 1 {print $3}' | sort -r)

  rm -f "$CHROOT_LOCK"
}

CACHE_PACKAGES() {
  echo "Caching packages..."
  mkdir -p "${CACHE_DIR}"
  shopt -s nullglob
  local debs=("${EXT_SQUASH_FS}/var/cache/apt/archives/"*.deb)
  shopt -u nullglob

  if [[ ${#debs[@]} -gt 0 ]]; then
    cp -nv "${debs[@]}" "${CACHE_DIR}/"
  else
    echo "No .deb packages found to cache."
  fi
}

RESTORE_CACHED_PACKAGES() {
  printf "${CLI_GREEN}Restoring cached packages...${CLI_RESET}\n"
  mkdir -p "${EXT_SQUASH_FS}/var/cache/apt/archives/"
  shopt -s nullglob
  local debs=("${CACHE_DIR}/"*.deb)
  shopt -u nullglob

  if [[ ${#debs[@]} -gt 0 ]]; then
    cp -n "${debs[@]}" "${EXT_SQUASH_FS}/var/cache/apt/archives/"
  fi
}

CLEAN_SQUASHFS() {
  shopt -s nullglob
  local archives=("${EXT_SQUASH_FS}/var/cache/apt/archives/"*.deb)
  shopt -u nullglob

  if [[ ${#archives[@]} -gt 0 ]]; then
    if confirm "$(printf "${CLI_GREEN}Would you like to cache packages first?${CLI_RESET}")"; then
      CACHE_PACKAGES
    fi
  fi

  local dtg
  dtg="$(date '+%d%b%Y-%H.%M.%S')"
  mkdir -p "${LOG_DIR}/${dtg}"
  if [[ -d "${EXT_SQUASH_FS}/var/log" ]]; then
    cp -r "${EXT_SQUASH_FS}/var/log" "${LOG_DIR}/${dtg}/" 2>/dev/null || true
  fi

  chroot "${EXT_SQUASH_FS}" apt-get -y clean
  chroot "${EXT_SQUASH_FS}" apt-get -y autoremove
  rm -f "${EXT_SQUASH_FS}/var/lib/dbus/machine-id"
  chroot "${EXT_SQUASH_FS}" dpkg-divert --rename --remove /sbin/initctl || true

  rm -rf "${EXT_SQUASH_FS}/tmp/"* \
         "${EXT_SQUASH_FS}/var/log/"* \
         "${EXT_SQUASH_FS}/etc/resolv.conf" \
         "${EXT_SQUASH_FS}/etc/hosts" \
         "${EXT_SQUASH_FS}/root/.bash_history" \
         "${EXT_SQUASH_FS}/vmlinuz" \
         "${EXT_SQUASH_FS}/initrd.img"

  if [[ -f "${CLEAN_FILE}" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "Removing ${line}..."
      rm -rf "$line"
    done < "${CLEAN_FILE}"
    rm -f "${CLEAN_FILE}"
  fi
}

SETUP() {
  local dirs=(
    "${SYS_BUILD_HOME}" "${GCONF_DIR}" "${SCRIPTS_IN_DIR}"
    "${BINARY_PACKAGES}" "${INCLUDE_DIR}" "${ORIGINAL_IMAGE_DIR}"
    "${CACHE_DIR}" "${SCRIPTS_EX_DIR}" "${KERNEL_DIR}"
    "${BUILD_CACHE}" "${LOG_DIR}"
  )

  for dir in "${dirs[@]}"; do
    mkdir -p "$dir"
    chmod 755 "$dir"
  done

  local pkgs=(genisoimage xorriso syslinux isolinux initramfs-tools squashfs-tools debootstrap)
  local missing=()
  for pkg in "${pkgs[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf "${CLI_RED}Missing packages: %s${CLI_RESET}\n" "${missing[*]}"
    if confirm "Install missing packages now?"; then
      apt-get update && apt-get install -y "${missing[@]}"
    fi
  fi
}

GET_KERNEL() {
  shopt -s nullglob
  local initrds=("${EXT_SQUASH_FS}/boot/initrd.img-"* /boot/initrd.img-*)
  shopt -u nullglob
  if [[ ${#initrds[@]} -eq 0 ]]; then
    echo "Error: no initrd image found." >&2
    return 1
  fi
  local base
  base="$(basename "${initrds[0]}")"
  echo "${base#initrd.img-}"
}

run_script_file() {
  local filepath="$1"
  local use_chroot="${2:-false}"

  printf "${CLI_GREEN}Running %s${CLI_RESET}\n" "$(basename "$filepath")"
  case "$filepath" in
    *.py)
      if [[ "$use_chroot" == "true" ]]; then
        chroot "${EXT_SQUASH_FS}" python3 "$filepath"
      else
        python3 "$filepath"
      fi
      ;;
    *.sh)
      if [[ "$use_chroot" == "true" ]]; then
        chroot "${EXT_SQUASH_FS}" bash "$filepath"
      else
        bash "$filepath"
      fi
      ;;
    *)
      printf "${CLI_YELLOW}Skipping unsupported script type: %s${CLI_RESET}\n" "$filepath"
      ;;
  esac
}

customize_binary() {
  shopt -s nullglob
  local bins=("${BINARY_PACKAGES}/"*.deb)
  shopt -u nullglob
  [[ ${#bins[@]} -eq 0 ]] && return 0

  mkdir -p "${EXT_SQUASH_FS}/binaries"
  echo "${EXT_SQUASH_FS}/binaries" >> "${CLEAN_FILE}"
  cp "${bins[@]}" "${EXT_SQUASH_FS}/binaries/"

  for deb in "${EXT_SQUASH_FS}/binaries/"*.deb; do
    chroot "${EXT_SQUASH_FS}" dpkg -iE "/binaries/$(basename "$deb")"
  done
}

customize_include() {
  shopt -s nullglob
  local items=("${INCLUDE_DIR}/"*)
  shopt -u nullglob
  [[ ${#items[@]} -eq 0 ]] && return 0

  echo "Copying include files..."
  if [[ -d "${INCLUDE_DIR}/etc/init.d" ]]; then
    ls -1 "${INCLUDE_DIR}/etc/init.d" > "${EXT_SQUASH_FS}/tmp/init_scripts.txt"
  fi
  cp -Rp "${INCLUDE_DIR}/." "${EXT_SQUASH_FS}/"
}

customize_gconf() {
  shopt -s nullglob
  local xmls=("${GCONF_DIR}/"*.xml)
  shopt -u nullglob
  [[ ${#xmls[@]} -eq 0 ]] && return 0

  echo "Applying gconf configs..."
  mkdir -p "${EXT_SQUASH_FS}/gconf"
  echo "${EXT_SQUASH_FS}/gconf" >> "${CLEAN_FILE}"
  cp "${xmls[@]}" "${EXT_SQUASH_FS}/gconf/"

  for xml in "${EXT_SQUASH_FS}/gconf/"*.xml; do
    chroot "${EXT_SQUASH_FS}" gconftool-2 \
      --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.defaults \
      --load "/gconf/$(basename "$xml")"
  done
}

customize_scripts_ex() {
  local target="${1:-all}"
  shopt -s nullglob
  local scripts=("${SCRIPTS_EX_DIR}/"*)
  shopt -u nullglob
  [[ ${#scripts[@]} -eq 0 ]] && return 0

  if [[ "$target" == "list" ]]; then
    ls -1 "${SCRIPTS_EX_DIR}"
    return 0
  elif [[ "$target" != "all" ]]; then
    local path="${SCRIPTS_EX_DIR}/${target}"
    [[ -e "$path" ]] || { echo "Error: '${target}' does not exist." >&2; exit 1; }
    run_script_file "$path" false
    return 0
  fi

  for s in "${scripts[@]}"; do
    [[ -f "$s" ]] && run_script_file "$s" false
  done
}

customize_scripts_in() {
  local target="${1:-all}"
  if [[ -f "${SYS_BUILD_HOME}/package_install_list.txt" ]]; then
    cp "${SYS_BUILD_HOME}/package_install_list.txt" "${EXT_SQUASH_FS}/"
    echo "${EXT_SQUASH_FS}/package_install_list.txt" >> "${CLEAN_FILE}"
  fi

  shopt -s nullglob
  local scripts=("${SCRIPTS_IN_DIR}/"*)
  shopt -u nullglob
  [[ ${#scripts[@]} -eq 0 ]] && return 0

  mkdir -p "${EXT_SQUASH_FS}/scripts"
  cp -r "${SCRIPTS_IN_DIR}/." "${EXT_SQUASH_FS}/scripts/"
  echo "${EXT_SQUASH_FS}/scripts" >> "${CLEAN_FILE}"
  chmod -R +x "${EXT_SQUASH_FS}/scripts"

  if [[ "$target" == "list" ]]; then
    ls -1 "${EXT_SQUASH_FS}/scripts"
    return 0
  elif [[ "$target" != "all" ]]; then
    [[ -e "${EXT_SQUASH_FS}/scripts/${target}" ]] || { echo "Error: '${target}' does not exist." >&2; exit 1; }
    run_script_file "/scripts/${target}" true
    return 0
  fi

  for s in "${EXT_SQUASH_FS}/scripts/"*; do
    [[ -f "$s" ]] && run_script_file "/scripts/$(basename "$s")" true
  done
}

export -f CACHE_PACKAGES RESTORE_CACHED_PACKAGES SET_CHROOT CLEAN_CHROOT CLEAN_SQUASHFS LOGGER SETUP GET_KERNEL

##--------------------- COMMAND DISPATCH -------------------------------##
cmd="${1:-}"

if [[ -z "$cmd" || "$cmd" == "--help" || "$cmd" == "-h" ]]; then
  if [[ -f "${BUILD_SCRIPTS}/help_file.rc" ]]; then
    cat "${BUILD_SCRIPTS}/help_file.rc"
  else
    echo "Usage: constructor.sh {setup|start_build|customize|chroot|clean_chroot|clean_squashfs|squashfs|mkiso|cache_packages|restore_cached_packages|backup_build|restore_build|open_initrd|package_initrd|delete}"
  fi
  exit 0
fi

if [[ -d "${EXT_SQUASH_FS}" ]] && [[ "$cmd" == "customize" || "$cmd" == "chroot" ]]; then
  SET_CHROOT
fi

case "$cmd" in
  clean_chroot)
    CLEAN_CHROOT
    ;;

  chroot)
    echo "Inside chroot, you may want:"
    echo "  export HOME=/root LC_ALL=C"
    echo
    chroot "${EXT_SQUASH_FS}" /bin/bash
    ;;

  clean_squashfs)
    CLEAN_SQUASHFS
    ;;

  setup)
    SETUP
    echo "Setup complete."
    ;;

  cache_packages)
    CACHE_PACKAGES
    ;;

  restore_cached_packages)
    RESTORE_CACHED_PACKAGES
    ;;

  backup_build)
    read -r -p "$(printf "${CLI_GREEN}Name the build package: ${CLI_RESET}")" BuildName
    [[ -n "$BuildName" ]] || { echo "Build name cannot be empty." >&2; exit 1; }
    mkdir -p "${BUILD_CACHE}"
    tar -zcvf "${BUILD_CACHE}/${BuildName}.tar.gz" -C "${SYS_BUILD_HOME}" \
      gconf cached_packages binary_packages include scripts_internal \
      scripts_external sources package_install_list.txt notes.txt 2>/dev/null || true
    ;;

  restore_build)
    ls -1 "${BUILD_CACHE}"
    read -r -p "$(printf "\n${CLI_RED}Choose build to restore: ${CLI_RESET}")" package_basename
    package="${BUILD_CACHE}/${package_basename}"
    [[ -f "$package" ]] || { echo "${package_basename} does not exist." >&2; exit 1; }

    if confirm "$(printf "${CLI_RED}Delete current build scripts/resources and restore ${package_basename}?${CLI_RESET}")"; then
      rm -rf "${GCONF_DIR}" "${CACHE_DIR}" "${BINARY_PACKAGES}" "${INCLUDE_DIR}" \
             "${SCRIPTS_IN_DIR}" "${SCRIPTS_EX_DIR}" "${SOURCES_DIR}"
      tar -zxvf "$package" -C "${SYS_BUILD_HOME}"
    fi
    ;;

  start_build)
    printf "1) ${CLI_GREEN}Use existing base${CLI_RESET}\n2) ${CLI_GREEN}Start fresh (debootstrap)${CLI_RESET}\n"
    read -r -p "[1,2]: " option

    if [[ "$option" == "1" ]]; then
      shopt -s nullglob
      base_files=("${ORIGINAL_IMAGE_DIR}/"*)
      shopt -u nullglob

      if [[ ${#base_files[@]} -gt 1 ]]; then
        printf "${CLI_RED}Too many files in %s. Exiting.${CLI_RESET}\n" "${ORIGINAL_IMAGE_DIR}" >&2
        exit 1
      elif [[ ${#base_files[@]} -eq 0 ]]; then
        printf "${CLI_RED}No base image found in %s. Exiting.${CLI_RESET}\n" "${ORIGINAL_IMAGE_DIR}" >&2
        exit 1
      fi

      package="${base_files[0]}"
      case "${package##*.}" in
        iso)
          printf "${CLI_GREEN}ISO found, extracting...${CLI_RESET}\n"
          mnt_dir="${SYS_BUILD_HOME}/mnt"
          mkdir -p "$mnt_dir" "${EXT_ISO_CONTENTS}" "${EXT_SQUASH_FS}"
          trap 'umount -lf "'"$mnt_dir"'" 2>/dev/null || true' EXIT
          mount -o loop "$package" "$mnt_dir"
          rsync -a "${mnt_dir}/" "${EXT_ISO_CONTENTS}/"
          umount "$mnt_dir"
          trap - EXIT

          squash_src="$(find "${EXT_ISO_CONTENTS}" -name 'filesystem.squashfs' -print -quit)"
          [[ -n "$squash_src" ]] || { echo "filesystem.squashfs not found in ISO." >&2; exit 1; }
          unsquashfs -f -d "${EXT_SQUASH_FS}" "$squash_src"
          ;;
        gz|tgz)
          printf "${CLI_GREEN}Archive found, extracting...${CLI_RESET}\n"
          mkdir -p "${EXT_ISO_CONTENTS}" "${EXT_SQUASH_FS}"
          tar -zxf "$package" -C "${SYS_BUILD_HOME}"
          ;;
        *)
          echo "Unsupported base image format: $package" >&2
          exit 1
          ;;
      esac

    elif [[ "$option" == "2" ]]; then
      ARCH="${ARCH:-amd64}"
      SUITE="${SUITE:-bookworm}"
      printf "${CLI_GREEN}Generating base system (%s / %s)...${CLI_RESET}\n" "$ARCH" "$SUITE"
      mkdir -p "${EXT_ISO_CONTENTS}" "${EXT_SQUASH_FS}"
      debootstrap --arch="$ARCH" --variant=minbase "$SUITE" "${EXT_SQUASH_FS}" http://deb.debian.org/debian/
    else
      echo "Invalid choice." >&2
      exit 1
    fi

    if [[ -d "${CACHE_DIR}" ]] && [[ -n "$(ls -A "${CACHE_DIR}" 2>/dev/null)" ]]; then
      if confirm "$(printf "${CLI_GREEN}Cached packages detected. Restore them?${CLI_RESET}")"; then
        RESTORE_CACHED_PACKAGES
      fi
    fi
    ;;

  delete)
    if confirm "$(printf "${CLI_RED}Delete current build system files?${CLI_RESET}")"; then
      CLEAN_CHROOT
      printf "${CLI_GREEN}Removing old build base...${CLI_RESET}\n"
      rm -rf "${EXT_ISO_CONTENTS}" "${EXT_SQUASH_FS}"
    fi
    ;;

  customize)
    shift
    modes=("$@")
    [[ ${#modes[@]} -eq 0 ]] && modes=("all")

    for mode in "${modes[@]}"; do
      case "$mode" in
        all)
          customize_binary
          customize_include
          customize_gconf
          customize_scripts_ex "all"
          customize_scripts_in "all"
          ;;
        bin|binary)    customize_binary ;;
        inc|include)   customize_include ;;
        gconf)         customize_gconf ;;
        sce|scripts_ex) customize_scripts_ex "${2:-all}"; break ;;
        sci|scripts_in) customize_scripts_in "${2:-all}"; break ;;
        *)
          echo "Unknown customize mode: $mode" >&2
          exit 1
          ;;
      esac
    done
    ;;

  open_initrd)
    read -r -p "$(printf "${CLI_RED}Path and name of initrd file: ${CLI_RESET}")" input
    if [[ -f "$input" ]] && [[ "$input" == "${EXT_ISO_CONTENTS}"* ]]; then
      workdir="$(dirname "$input")/tempdir"
      mkdir -p "$workdir"
      echo "$workdir" >> "${CLEAN_FILE}"
      if command -v unmkinitramfs >/dev/null 2>&1; then
        unmkinitramfs "$input" "$workdir"
      else
        (cd "$workdir" && zcat "$input" | cpio -idmv)
      fi
      echo "Extracted to: $workdir"
    else
      echo "Invalid initrd path (must exist inside ${EXT_ISO_CONTENTS})." >&2
      exit 1
    fi
    ;;

  package_initrd)
    read -r -p "$(printf "${CLI_RED}Path to extracted initrd contents: ${CLI_RESET}")" input
    [[ -d "$input" ]] || { echo "Directory not found: $input" >&2; exit 1; }
    (
      cd "$input"
      echo "Compressing initrd package..."
      find . -print0 | cpio --null -o --format=newc | gzip -9 > ../initrd.img.gz
    )
    echo "Created $(dirname "$input")/initrd.img.gz"
    ;;

  squashfs)
    mkdir -p "${EXT_ISO_CONTENTS}/${LIVE_DIR}"
    squash_out="${EXT_ISO_CONTENTS}/${LIVE_DIR}/filesystem.squashfs"
    rm -f "$squash_out"

    if confirm "$(printf "${CLI_RED}Use extra xz compression?${CLI_RESET}")"; then
      mksquashfs "${EXT_SQUASH_FS}" "$squash_out" -comp xz
    else
      mksquashfs "${EXT_SQUASH_FS}" "$squash_out"
    fi
    ;;

  mkiso)
    printf "${CLI_GREEN}Create ISO for:${CLI_RESET}\n1. Grub/MBR boot\n2. UEFI + Hybrid boot\n"
    read -r -p "> " option

    if [[ -e "${NEW_ISO}" ]]; then
      if confirm "$(printf "${CLI_RED}Remove existing ${NEW_ISO}?${CLI_RESET}")"; then
        rm -rf "${NEW_ISO}"
      else
        exit 0
      fi
    fi

    if [[ "$option" != "1" && "$option" != "2" ]]; then
      echo "Please choose 1 or 2." >&2
      exit 1
    fi

    if [[ -e "${SYS_BUILD_HOME}/store/init.sh" && ! -e "${EXT_ISO_CONTENTS}/init.sh" ]]; then
      cp "${SYS_BUILD_HOME}/store/init.sh" "${EXT_ISO_CONTENTS}/"
      chmod +x "${EXT_ISO_CONTENTS}/init.sh"
    fi

    cd "${EXT_ISO_CONTENTS}"
    if [[ "$option" == "1" ]]; then
      genisoimage -D -r -f -cache-inodes -J -l \
        -b isolinux/isolinux.bin -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -o "${NEW_ISO}" .
    else
      xorriso -as mkisofs -U -f -v -iso-level 4 \
        -b isolinux/isolinux.bin -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr isolinux/isohdpfx.bin \
        -eltorito-alt-boot -e EFI/boot/bootx64.efi -no-emul-boot \
        -isohybrid-gpt-basdat -o "${NEW_ISO}" .
    fi

    sha256sum "${NEW_ISO}" > "${NEW_ISO}.sha256"
    printf "${CLI_GREEN}ISO created: %s (checksum: %s.sha256)${CLI_RESET}\n" "${NEW_ISO}" "${NEW_ISO}"
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
