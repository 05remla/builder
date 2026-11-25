#!/usr/bin/env bash
set -euo pipefail

export SYS_BUILD_HOME="${SYS_BUILD_HOME:-/home/leo/BUILDER}"
export BUILD_SCRIPTS="${SYS_BUILD_HOME}/BUILDER_SCRIPTS"
export EXT_ISO_CONTENTS="${SYS_BUILD_HOME}/ext_contents"
export EXT_SQUASH_FS="${SYS_BUILD_HOME}/ext_squashfs"
export GCONF_DIR="${SYS_BUILD_HOME}/gconf"
export NEW_ISO="${SYS_BUILD_HOME}/new.iso"
export CACHE_DIR="${SYS_BUILD_HOME}/cached_packages"
export BINARY_PACKAGES="${SYS_BUILD_HOME}/binary_packages"
export INCLUDE_DIR="${SYS_BUILD_HOME}/include"
export SCRIPTS_IN_DIR="${SYS_BUILD_HOME}/scripts_internal"
export SCRIPTS_EX_DIR="${SYS_BUILD_HOME}/scripts_external"
export SOURCES_DIR="${SYS_BUILD_HOME}/sources"
export ORIGINAL_IMAGE_DIR="${SYS_BUILD_HOME}/original_image"
export KERNEL_DIR="${SYS_BUILD_HOME}/kernel"
export BUILD_CACHE="${SYS_BUILD_HOME}/distro_build_cache"
export CLEAN_FILE="${EXT_SQUASH_FS}/clean_me.txt"
export LOG_DIR="${SYS_BUILD_HOME}/logs"
export LIVE_DIR="${LIVE_DIR:-live}"

usage() {
  cat <<EOF
builder.sh - variable and asset manager for build scripts

Usage:
  builder.sh [--script=<path>] [--shell=<cmd>] [script_args...]
  builder.sh --help | -h

Options:
  --script=PATH   Script to run (default: ${BUILD_SCRIPTS}/constructor.sh)
  --shell=CMD     Interpreter to use (default: bash)
  -h, --help      Show this help message

Examples:
  builder.sh --script=example.py --shell=python3
  builder.sh --script="../kernel/4.2.4/insert_into_and_install_kernel.sh" --shell=bash
  builder.sh start_build
EOF
  if [[ -f "${BUILD_SCRIPTS}/constructor.sh" ]]; then
    echo
    bash "${BUILD_SCRIPTS}/constructor.sh" --help || true
  fi
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

script=""
shell=""
pass_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script=*)
      script="${1#*=}"
      shift
      ;;
    --script)
      script="${2:?--script requires a value}"
      shift 2
      ;;
    --shell=*)
      shell="${1#*=}"
      shift
      ;;
    --shell)
      shell="${2:?--shell requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      pass_args+=("$@")
      break
      ;;
    *)
      pass_args+=("$1")
      shift
      ;;
  esac
done

script="${script:-${BUILD_SCRIPTS}/constructor.sh}"
shell="${shell:-bash}"

if ! command -v "$shell" >/dev/null 2>&1; then
  echo "Error: shell '$shell' not found in PATH." >&2
  exit 1
fi

if [[ ! -f "$script" ]]; then
  echo "Error: script '$script' not found." >&2
  exit 1
fi

exec "$shell" "$script" "${pass_args[@]}"
