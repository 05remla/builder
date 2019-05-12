export     SYS_BUILD_HOME="/root/IMAGE_BUILD_DIRECTORY"
export   EXT_ISO_CONTENTS="${SYS_BUILD_HOME}/ext_contents"
export      EXT_SQUASH_FS="${SYS_BUILD_HOME}/ext_squashfs"
export          GCONF_DIR="${SYS_BUILD_HOME}/gconf"
export            NEW_ISO="${SYS_BUILD_HOME}/new.iso"
export          CACHE_DIR="${SYS_BUILD_HOME}/cached_packages"
export    BINARY_PACKAGES="${SYS_BUILD_HOME}/binary_packages"
export        INCLUDE_DIR="${SYS_BUILD_HOME}/include"
export     SCRIPTS_IN_DIR="${SYS_BUILD_HOME}/scripts_internal"
export     SCRIPTS_EX_DIR="${SYS_BUILD_HOME}/scripts_external"
export        SOURCES_DIR="${SYS_BUILD_HOME}/sources"
export ORIGINAL_IMAGE_DIR="${SYS_BUILD_HOME}/original_image"
export         KERNEL_DIR="${SYS_BUILD_HOME}/kernel"
export        BUILD_CACHE="${SYS_BUILD_HOME}/distro_build_cache"
export         CLEAN_FILE="${EXT_SQUASH_FS}/clean_me.txt"
export            LOG_DIR="${SYS_BUILD_HOME}/logs"

function help()
{
	echo "       builder.sh"
	echo "          variable and asset manager;"
	echo "          used to initialize all build variables for any script (look at examples)"
	echo "          if shell not specified bash is the default"
	echo "          if script not specified constructor.sh is the default"
	echo
	echo "          --script=   : specify script to run"
	echo "          --shell=    : specify shell to run script in"
	echo "          --help      : this help printout"
	echo
	echo "        examples"
	echo "          builder.sh --script=example.py --shell=python3"
	echo "          builder.sh --script=\"../kernel/4.2.4/insert_into_and_install_kernel.sh\" --shell=bash"
	echo "          builder.sh extract"
	echo
	bash .constructor.sh --help
}

if [[ -z "$@" ]]; then
  help
  exit
fi

for arg in "$@"
do
  case $arg in
    --script=*)
      script=$(echo $arg | cut -d= -f2)
    ;;
    --shell=*)
      shell=$(echo $arg | cut -d= -f2)
    ;;
    --help|-h)
      help
	    exit
    ;;
  esac
done

if [[ -z ${script} ]]; then
	script=".constructor.sh"
fi

if [[ -z ${shell} ]]; then
  shell="bash"
fi

${shell} ${script} $@
