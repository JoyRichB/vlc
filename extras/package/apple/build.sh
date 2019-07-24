#!/usr/bin/env bash
# Copyright (C) Marvin Scholz
#
# Script to help build VLC or libVLC for Apple OSes
# Supported OSes: macOS, tvOS, macOS
#
# Currently this script builds a full static library,
# with all modules and contribs combined into one .a
# file.
#
# Settings that need to be changed from time to time,
# like the target OS versions or contrib/configure options
# can be found in the build.conf file in the same folder.

# TODO:
# - Add packaging support and right options to build a macOS app
# - Support shared build where you get a dylib for libvlc,
#   libvlccore and dylibs for the individual modules.
# - Support a mixed shared build where you only have a
#   libvlc.dylib that includes libvlccore and the modules
#   statically.
# Proposed interface for this:
#   --buildmode=<fullstatic, pseudoshared, shared>
#        fullstatic: One resulting static library with libvlc and modules
#        pseudoshared: Shared library with all modules statically linked
#        shared: Shared libraries and modules

# Dir of this script
readonly VLC_SCRIPT_DIR="${BASH_SOURCE%/*}"

# Verify script run location
[ ! -f "$(pwd)/../src/libvlc.h" ] \
    && echo "ERROR: This script must be run from a" \
            "build subdirectory in the VLC source" >&2 \
    && exit 1

# Include vlc env script
. "$VLC_SCRIPT_DIR/../macosx/env.build.sh" "none"

# Include build config file
. "$VLC_SCRIPT_DIR/build.conf"

##########################################################
#                    Global variables                    #
##########################################################

# Name of this script
readonly VLC_SCRIPT_NAME=$(basename "$0")
# VLC source dir root
readonly VLC_SRC_DIR=$(vlcGetRootDir)
# VLC build dir
readonly VLC_BUILD_DIR=$(pwd)
# Whether verbose output is enabled or not
VLC_SCRIPT_VERBOSE=0
# Architecture of the host (OS that the result will run on)
VLC_HOST_ARCH=x86_64
# Host platform information
VLC_HOST_PLATFORM=
VLC_HOST_TRIPLET=
# Set to "1" when building for simulator
VLC_HOST_PLATFORM_SIMULATOR=
# The host OS name (without the simulator suffix)
# as used by the Apple tools for flags like the
# min version or clangs target option
VLC_HOST_OS=
# Lowest OS version (iOS, tvOS or macOS) to target
# Do NOT edit this to set a specific target, instead
# edit the VLC_DEPLOYMENT_TARGET_* variables above.
VLC_DEPLOYMENT_TARGET=
# Flags for linker and compiler that set the min target OS
# Those will be set by the set_deployment_target function
VLC_DEPLOYMENT_TARGET_LDFLAG=
VLC_DEPLOYMENT_TARGET_CFLAG=
# SDK name (optionally with version) to build with
# We default to macOS builds, so this is set to macosx
VLC_APPLE_SDK_NAME="macosx"
# SDK path
# Set in the validate_sdk_name function
VLC_APPLE_SDK_PATH=
# SDK version
# Set in the validate_sdk_name function
VLC_APPLE_SDK_VERSION=

##########################################################
#                    Helper functions                    #
##########################################################

# Print command line usage
usage()
{
    echo "Usage: $VLC_SCRIPT_NAME [--arch=ARCH]"
    echo " --arch=ARCH    architecture to build for"
    echo "                  (i386|x86_64|armv7|armv7s|arm64)"
    echo " --sdk=SDK      name of the SDK to build with (see 'xcodebuild -showsdks')"
    echo " --help         print this help"
}

# Print error message and terminate script with status 1
# Arguments:
#   Message to print
abort_err()
{
    echo "ERROR: $1" >&2
    exit 1
}

# Print message if verbose, else silent
# Globals:
#   VLC_SCRIPT_VERBOSE
# Arguments:
#   Message to print
verbose_msg()
{
    if [ "$VLC_SCRIPT_VERBOSE" -gt "0" ]; then
        echo "$1"
    fi
}

# Check if tool exists, if not error out
# Arguments:
#   Tool name to check for
check_tool()
{
    command -v "$1" >/dev/null 2>&1 || {
        abort_err "This script requires '$1' but it was not found"
    }
}

# Set the VLC_DEPLOYMENT_TARGET* flag options correctly
# Globals:
#   VLC_DEPLOYMENT_TARGET
#   VLC_DEPLOYMENT_TARGET_LDFLAG
#   VLC_DEPLOYMENT_TARGET_CFLAG
# Arguments:
#   Deployment target version
set_deployment_target()
{
    VLC_DEPLOYMENT_TARGET="$1"
    VLC_DEPLOYMENT_TARGET_LDFLAG="-Wl,-$VLC_HOST_OS"
    VLC_DEPLOYMENT_TARGET_CFLAG="-m$VLC_HOST_OS"

    if [ -n "$VLC_HOST_PLATFORM_SIMULATOR" ]; then
        VLC_DEPLOYMENT_TARGET_LDFLAG="${VLC_DEPLOYMENT_TARGET_LDFLAG}_simulator"
        VLC_DEPLOYMENT_TARGET_CFLAG="${VLC_DEPLOYMENT_TARGET_CFLAG}-simulator"
    fi

    VLC_DEPLOYMENT_TARGET_LDFLAG="${VLC_DEPLOYMENT_TARGET_LDFLAG}_version_min,${VLC_DEPLOYMENT_TARGET}"
    VLC_DEPLOYMENT_TARGET_CFLAG="${VLC_DEPLOYMENT_TARGET_CFLAG}-version-min=${VLC_DEPLOYMENT_TARGET}"
}

# Validates the architecture and sets VLC_HOST_ARCH
# Globals:
#   VLC_HOST_ARCH
# Arguments:
#   Architecture string
validate_architecture()
{
    case "$1" in
    i386|x86_64|armv7|armv7s|arm64)
        VLC_HOST_ARCH="$1"
        ;;
    aarch64)
        VLC_HOST_ARCH="arm64"
        ;;
    *)
        abort_err "Invalid architecture '$1'"
        ;;
    esac
}

# Take SDK name, verify it exists and populate
# VLC_HOST_*, VLC_APPLE_SDK_PATH variables based
# on the SDK and calls the set_deployment_target
# function with the rigth target version
# Globals:
#   VLC_DEPLOYMENT_TARGET_IOS
#   VLC_DEPLOYMENT_TARGET_TVOS
#   VLC_DEPLOYMENT_TARGET_MACOSX
# Arguments:
#   SDK name
validate_sdk_name()
{
    xcrun --sdk "$1" --show-sdk-path >/dev/null 2>&1 || {
        abort_err "Failed to find SDK '$1'"
    }

    VLC_APPLE_SDK_PATH="$(xcrun --sdk "$1" --show-sdk-path)"
    VLC_APPLE_SDK_VERSION="$(xcrun --sdk "$1" --show-sdk-version)"
    if [ ! -d "$VLC_APPLE_SDK_PATH" ]; then
        abort_err "SDK at '$VLC_APPLE_SDK_PATH' does not exist"
    fi

    case "$1" in
        iphoneos*)
            VLC_HOST_PLATFORM="iOS"
            VLC_HOST_OS="ios"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_IOS"
            ;;
        iphonesimulator*)
            VLC_HOST_PLATFORM="iOS-Simulator"
            VLC_HOST_PLATFORM_SIMULATOR="yes"
            VLC_HOST_OS="ios"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_IOS"
            ;;
        appletvos*)
            VLC_HOST_PLATFORM="tvOS"
            VLC_HOST_OS="tvos"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_TVOS"
            ;;
        appletvsimulator*)
            VLC_HOST_PLATFORM="tvOS-Simulator"
            VLC_HOST_PLATFORM_SIMULATOR="yes"
            VLC_HOST_OS="tvos"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_TVOS"
            ;;
        macosx*)
            VLC_HOST_PLATFORM="macOS"
            VLC_HOST_OS="macosx"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_MACOSX"
            ;;
        watch*)
            abort_err "Building for watchOS is not supported by this script"
            ;;
        *)
            abort_err "Unhandled SDK name '$1'"
            ;;
    esac
}

# Set env variables used to define compilers and flags
# Arguments:
#   Additional flags for use with C-like compilers
set_host_envvars()
{
    # Flags to be used for C-like compilers (C, C++, Obj-C)
    local clike_flags="$VLC_DEPLOYMENT_TARGET_CFLAG -arch $VLC_HOST_ARCH -isysroot $VLC_APPLE_SDK_PATH $1"

    export CPPFLAGS="-arch $VLC_HOST_ARCH -isysroot $VLC_APPLE_SDK_PATH"

    export CFLAGS="$clike_flags"
    export CXXFLAGS="$clike_flags"
    export OBJCFLAGS="$clike_flags"

    export LDFLAGS="$VLC_DEPLOYMENT_TARGET_LDFLAG -arch $VLC_HOST_ARCH"

    # Tools to be used
    export CC="clang"
    export CPP="clang -E"
    export CXX="clang++"
    export OBJC="clang"
    export LD="ld"
    export AR="ar"
    export STRIP="strip"
    export RANLIB="ranlib"
}

# Generate the source file with the needed array for
# the static VLC module list. This has to be compiled
# and linked into the static library
# Arguments:
#   Path of the output file
#   Array with module entry symbol names
gen_vlc_static_module_list()
{
    local output="$1"
    shift
    local symbol_array=( "$@" )
    touch "$output" || abort_err "Failure creating static module list file"

    local array_list
    local declarations_list

    for symbol in "${symbol_array[@]}"; do
        declarations_list+="VLC_ENTRY_FUNC(${symbol});\\n"
        array_list+="    ${symbol},\\n"
    done

    printf "\
#include <stddef.h>\\n\
#define VLC_ENTRY_FUNC(funcname)\
int funcname(int (*)(void *, void *, int, ...), void *)\\n\
%b\\n\
const void *vlc_static_modules[] = {\\n
%b
    NULL\\n
};" \
    "$declarations_list" "$array_list" >> "$output" \
      || abort_err "Failure writing static module list file"
}

##########################################################
#                  Main script logic                     #
##########################################################

# Parse arguments
while [ -n "$1" ]
do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --verbose)
            VLC_SCRIPT_VERBOSE=1
            ;;
        --arch=*)
            VLC_HOST_ARCH="${1#--arch=}"
            ;;
        --sdk=*)
            VLC_APPLE_SDK_NAME="${1#--sdk=}"
            ;;
        *)
            echo >&2 "ERROR: Unrecognized option '$1'"
            usage
            exit 1
            ;;
    esac
    shift
done

# Check for some required tools before proceeding
check_tool xcrun

# TODO: Better command to get SDK name if none is set:
# xcodebuild -sdk $(xcrun --show-sdk-path) -version | awk -F '[()]' '{ print $2; exit; }'
# Aditionally a lot more is reported by this command, so this needs some more
# awk parsing or something to get other values with just only query.

# Validate given SDK name
validate_sdk_name "$VLC_APPLE_SDK_NAME"

# Validate architecture argument
validate_architecture "$VLC_HOST_ARCH"

# Set triplet (query the compiler for this)
readonly VLC_HOST_TRIPLET="$(${CC:-cc} -arch "$VLC_HOST_ARCH" -dumpmachine)"
# Set pseudo-triplet
readonly VLC_PSEUDO_TRIPLET="${VLC_HOST_ARCH}-apple-${VLC_HOST_PLATFORM}_${VLC_DEPLOYMENT_TARGET}"
# Contrib install dir
readonly VLC_CONTRIB_INSTALL_DIR="$VLC_BUILD_DIR/contrib/$VLC_PSEUDO_TRIPLET"
# VLC install dir
readonly VLC_INSTALL_DIR="$VLC_BUILD_DIR/vlc-$VLC_PSEUDO_TRIPLET"

echo "Build configuration"
echo "  Platform:     $VLC_HOST_PLATFORM"
echo "  Architecture: $VLC_HOST_ARCH"
echo "  SDK Version:  $VLC_APPLE_SDK_VERSION"
echo ""

##########################################################
#                Prepare environment                     #
##########################################################

# Set PKG_CONFIG_LIBDIR to an empty string to prevent
# pkg-config from finding dependencies on the build
# machine, so that it only finds deps in contribs
export PKG_CONFIG_LIBDIR=""

# Add extras/tools to path
export PATH="$VLC_SRC_DIR/extras/tools/build/bin:$PATH"

# Do NOT set SDKROOT, as that is used by various Apple
# tools and clang and would lead to wrong results!
# Instead for now we set VLCSDKROOT which is needed
# to make the contrib script happy.
# TODO: Actually for macOS the contrib bootstrap script
# expects SDKROOT to be set, although we can't just do that
# due to the previously mentioned problem this causes.
export VLCSDKROOT="$VLC_APPLE_SDK_PATH"

# TODO: Adjust how that is handled in contrib script, to
# get rid of these env varibles that we need to set
if [ "$VLC_HOST_OS" = "ios" ]; then
    export BUILDFORIOS="yes"
elif [ "$VLC_HOST_OS" = "tvos" ]; then
    export BUILDFORIOS="yes"
    export BUILDFORTVOS="yes"
fi

# Default to "make" if there is no MAKE env variable
MAKE=${MAKE:-make}

# Attention! Do NOT use just "libtool" here and
# do NOT use the LIBTOOL env variable as this is
# expected to be Apple's libtool NOT GNU libtool!
APPL_LIBTOOL=$(xcrun -f libtool) \
  || abort_err "Failed to find Apple libtool with xcrun"

##########################################################
#                 Extras tools build                     #
##########################################################

echo "Building needed tools (if missing)"

cd "$VLC_SRC_DIR/extras/tools" || abort_err "Failed cd to tools dir"
./bootstrap || abort_err "Bootstrapping tools failed"
$MAKE || abort_err "Building tools failed"

echo ""

##########################################################
#                     Contribs build                     #
##########################################################

echo "Building contribs for $VLC_HOST_ARCH"

# For contribs set flag to error on partial availability
set_host_envvars "-Werror=partial-availability"

# Set symbol blacklist for autoconf
vlcSetSymbolEnvironment > /dev/null

# Combine settings from config file
VLC_CONTRIB_OPTIONS=( "${VLC_CONTRIB_OPTIONS_BASE[@]}" )

if [ "$VLC_HOST_OS" = "macosx" ]; then
    VLC_CONTRIB_OPTIONS+=( "${VLC_CONTRIB_OPTIONS_MACOSX[@]}" )
elif [ "$VLC_HOST_OS" = "ios" ]; then
    VLC_CONTRIB_OPTIONS+=( "${VLC_CONTRIB_OPTIONS_IOS[@]}" )
elif [ "$VLC_HOST_OS" = "tvos" ]; then
    VLC_CONTRIB_OPTIONS+=( "${VLC_CONTRIB_OPTIONS_TVOS[@]}" )
fi

# Create dir to build contribs in
cd "$VLC_SRC_DIR/contrib" || abort_err "Failed cd to contrib dir"
mkdir -p "contrib-$VLC_PSEUDO_TRIPLET"
cd "contrib-$VLC_PSEUDO_TRIPLET" || abort_err "Failed cd to contrib build dir"

# Create contrib install dir if it does not already exist
mkdir -p "$VLC_CONTRIB_INSTALL_DIR"

# Bootstrap contribs
../bootstrap \
    --host="$VLC_HOST_TRIPLET" \
    --prefix="$VLC_CONTRIB_INSTALL_DIR" \
    "${VLC_CONTRIB_OPTIONS[@]}" \
|| abort_err "Bootstrapping contribs failed"

$MAKE list

# Build contribs
$MAKE || abort_err "Building contribs failed"

echo ""

##########################################################
#                      VLC build                         #
##########################################################

echo "Building VLC for $VLC_HOST_ARCH"

# Set flags for VLC build
set_host_envvars "-g"

# Combine settings from config file
VLC_CONFIG_OPTIONS=( "${VLC_CONFIG_OPTIONS_BASE[@]}" )

if [ "$VLC_HOST_OS" = "macosx" ]; then
    VLC_CONFIG_OPTIONS+=( "${VLC_CONFIG_OPTIONS_MACOSX[@]}" )
elif [ "$VLC_HOST_OS" = "ios" ]; then
    VLC_CONFIG_OPTIONS+=( "${VLC_CONFIG_OPTIONS_IOS[@]}" )
elif [ "$VLC_HOST_OS" = "tvos" ]; then
    VLC_CONFIG_OPTIONS+=( "${VLC_CONFIG_OPTIONS_TVOS[@]}" )
fi

# Bootstrap VLC
cd "$VLC_SRC_DIR" || abort_err "Failed cd to VLC source dir"
./bootstrap

# Build
mkdir -p "${VLC_BUILD_DIR}/build/${VLC_PSEUDO_TRIPLET}"
cd "${VLC_BUILD_DIR}/build/${VLC_PSEUDO_TRIPLET}" || abort_err "Failed cd to VLC build dir"

# Create VLC install dir if it does not already exist
mkdir -p "$VLC_INSTALL_DIR"

../../../configure \
    --with-contrib="$VLC_CONTRIB_INSTALL_DIR" \
    --host="$VLC_HOST_TRIPLET" \
    --prefix="$VLC_INSTALL_DIR" \
    "${VLC_CONFIG_OPTIONS[@]}" \
 || abort_err "Configuring VLC failed"

$MAKE || abort_err "Building VLC failed"

$MAKE install || abort_err "Installing VLC failed"

echo ""

##########################################################
#                 Remove unused modules                  #
##########################################################

echo "Removing modules that are on the removal list"

# Combine settings from config file
VLC_MODULE_REMOVAL_LIST=( "${VLC_MODULE_REMOVAL_LIST_BASE[@]}" )

if [ "$VLC_HOST_OS" = "macosx" ]; then
    VLC_MODULE_REMOVAL_LIST+=( "${VLC_MODULE_REMOVAL_LIST_MACOSX[@]}" )
elif [ "$VLC_HOST_OS" = "ios" ]; then
    VLC_MODULE_REMOVAL_LIST+=( "${VLC_MODULE_REMOVAL_LIST_IOS[@]}" )
elif [ "$VLC_HOST_OS" = "tvos" ]; then
    VLC_MODULE_REMOVAL_LIST+=( "${VLC_MODULE_REMOVAL_LIST_TVOS[@]}" )
fi

for module in "${VLC_MODULE_REMOVAL_LIST[@]}"; do
    find "$VLC_INSTALL_DIR/lib/vlc/plugins" \
        -name "lib${module}_plugin.a" \
        -type f \
        -exec rm '{}' \;
done

echo ""

##########################################################
#        Compile object with static module list          #
##########################################################

echo "Compile VLC static modules list object"

mkdir -p "${VLC_BUILD_DIR}/build/${VLC_PSEUDO_TRIPLET}/build-sh"
cd "${VLC_BUILD_DIR}/build/${VLC_PSEUDO_TRIPLET}/build-sh" \
 || abort_err "Failed cd to VLC build-sh build dir"

# Collect paths of all static libraries needed (plugins and contribs)
VLC_STATIC_FILELIST_NAME="static-libs-list"
rm -f "$VLC_STATIC_FILELIST_NAME"
touch "$VLC_STATIC_FILELIST_NAME"

VLC_PLUGINS_SYMBOL_LIST=()

# Find all static plugins in build dir
while IFS=  read -r -d $'\0' plugin_path; do
    # Get module entry point symbol name (_vlc_entry__MODULEFULLNAME)
    nm_symbol_output=( $(nm "$plugin_path" | grep _vlc_entry__) ) \
      || abort_err "Failed to find module entry function in '$plugin_path'"

    symbol_name="${nm_symbol_output[2]:1}"
    VLC_PLUGINS_SYMBOL_LIST+=( "$symbol_name" )

    echo "$plugin_path" >> "$VLC_STATIC_FILELIST_NAME"

done < <(find "$VLC_INSTALL_DIR/lib/vlc/plugins" -name "*.a" -print0)

# Generate code with module list
VLC_STATIC_MODULELIST_NAME="static-module-list"
rm -f "${VLC_STATIC_MODULELIST_NAME}.c" "${VLC_STATIC_MODULELIST_NAME}.o"
gen_vlc_static_module_list "${VLC_STATIC_MODULELIST_NAME}.c" "${VLC_PLUGINS_SYMBOL_LIST[@]}"

${CC:-cc} -c "${VLC_STATIC_MODULELIST_NAME}.c" \
  || abort_err "Compiling module list file failed"

echo "${VLC_BUILD_DIR}/build/${VLC_PSEUDO_TRIPLET}/build-sh/${VLC_STATIC_MODULELIST_NAME}.o" \
  >> "$VLC_STATIC_FILELIST_NAME"

echo ""

##########################################################
#          Link together full static library             #
##########################################################

echo "Linking VLC modules and contribs statically"

echo "$VLC_INSTALL_DIR/lib/libvlc.a" >> "$VLC_STATIC_FILELIST_NAME"
echo "$VLC_INSTALL_DIR/lib/libvlccore.a" >> "$VLC_STATIC_FILELIST_NAME"
echo "$VLC_INSTALL_DIR/lib/vlc/libcompat.a" >> "$VLC_STATIC_FILELIST_NAME"

# Find all static contribs in build dir
find "$VLC_CONTRIB_INSTALL_DIR/lib" -name '*.a' -print >> "$VLC_STATIC_FILELIST_NAME" \
  || abort_err "Failed finding installed static contribs in '$VLC_CONTRIB_INSTALL_DIR/lib'"

# Link static libs together using libtool
$APPL_LIBTOOL -static \
    -no_warning_for_no_symbols \
    -filelist "$VLC_STATIC_FILELIST_NAME" \
    -o "libvlc-full-static.a" \
  || abort_err "Faile running Apple libtool to combine static libraries together"

echo ""
echo "Build succeeded!"
