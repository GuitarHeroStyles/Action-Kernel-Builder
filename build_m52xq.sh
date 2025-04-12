#!/bin/bash
#
# Kernel Build Script - m52xq
# Coded by BlackMesa123 @2023
# Adapted by RisenID @2024
# Modified by saadelasfur @2025
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e
set -o allexport

# Set variables
WORK_DIR="$(git rev-parse --show-toplevel)"
SRC_DIR="$WORK_DIR/android_kernel_samsung_sm7325"
TC_DIR="$WORK_DIR/clang-toolchain"
OUT_DIR="$WORK_DIR/builds"
DATE="$(date +%Y%m%d)"
JOBS="$(nproc --all)"

[[ "$2" == "-n" || "$2" == "--next" ]] && NEXT_BUILD="true"
KSU_VER="v1.0.3"
[[ "$NEXT_BUILD" == "true" ]] && KSU_VER="v1.0.6"
RELEASE_VERSION="KSU_$KSU_VER-$DATE"
[[ "$NEXT_BUILD" == "true" ]] && RELEASE_VERSION="KSU-Next_$KSU_VER-$DATE"

BUILD_DATE="$(date +"%Y-%m-%d %H:%M:%S")"
BUILD_FP="samsung/m52xqxx/m52xq:11/RP1A.200720.012/M526BRXXS6CXJ1:user/release-keys"

MAKE_ARGS="
-j$JOBS \
-C $SRC_DIR \
O=$SRC_DIR/out \
ARCH=arm64 \
CLANG_TRIPLE=aarch64-linux-gnu- \
LLVM=1 \
LLVM_IAS=1 \
CROSS_COMPILE=$TC_DIR/bin/llvm-
"

export PATH="$TC_DIR/bin:$PATH"

# [
DETECT_BRANCH()
{
    cd "$SRC_DIR"
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"

    if [[ "$BRANCH" == "ksu" || "$BRANCH" == "ksu-next" ]]; then
        echo "----------------------------------------------"
        echo "OneUI Branch Detected..."
        BUILD_VARIANT="OneUI"
    elif [[ "$BRANCH" == "ksu-aosp" || "$BRANCH" == "ksu-aosp-next" ]]; then
        echo "----------------------------------------------"
        echo "AOSP Branch Detected..."
        BUILD_VARIANT="AOSP"
    else
        echo "----------------------------------------------"
        echo "Branch not recognized..."
        exit 1
    fi
    cd "$WORK_DIR"
}

CLEAN_SOURCE()
{
    echo "----------------------------------------------"
    echo "Cleaning up sources..."
    rm -rf "$SRC_DIR/out"
}

BUILD_KERNEL()
{
    cd "$SRC_DIR"
    echo "----------------------------------------------"
    [[ -d "$SRC_DIR/out" ]] && echo "Starting \"$BUILD_VARIANT\" kernel build... (DIRTY)" || echo "Starting \"$BUILD_VARIANT\" kernel build..."
    echo ""
    export LOCALVERSION="-shadow-$KSU_VER-m52xq"
    mkdir -p "$SRC_DIR/out"
    rm -rf "$SRC_DIR/out/arch/arm64/boot/dts/samsung"
    make $MAKE_ARGS CC="ccache clang" vendor/$DEFCONFIG
    echo ""
    # Make kernel
    make $MAKE_ARGS CC="ccache clang"
    echo ""
    cd "$WORK_DIR"
}

REGEN_DEFCONFIG()
{
    cd "$SRC_DIR"
    echo "----------------------------------------------"
    [[ -d "$SRC_DIR/out" ]] && echo "Starting \"$BUILD_VARIANT\" kernel build... (DIRTY)" || echo "Starting \"$BUILD_VARIANT\" kernel build..."
    echo ""
    mkdir -p "$SRC_DIR/out"
    rm -rf "$SRC_DIR/out/arch/arm64/boot/dts/samsung"
    rm -f "$SRC_DIR/out/.config"
    make $MAKE_ARGS CC="ccache clang" vendor/$DEFCONFIG
    echo ""
    # Regen defconfig
    cp "$SRC_DIR/out/.config" "$SRC_DIR/arch/arm64/configs/vendor/$DEFCONFIG"
    echo ""
    cd "$WORK_DIR"
}

BUILD_MODULES()
{
    cd "$SRC_DIR"
    echo "----------------------------------------------"
    echo "Building kernel modules..."
    echo ""
    make $MAKE_ARGS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install
    echo ""
    mkdir -p "$OUT_DIR/out/zip/vendor/bin"
    cp "$WORK_DIR/target/common/modprobe/vendor_modprobe.sh" "$OUT_DIR/out/zip/vendor/bin/vendor_modprobe.sh"
    mkdir -p "$OUT_DIR/out/zip/vendor/lib/modules"
    find "$SRC_DIR/out/modules" -name "*.ko" -exec cp "{}" "$OUT_DIR/out/zip/vendor/lib/modules" ";"
    MOD_DIR="$(find "$SRC_DIR/out/modules/lib/modules" -maxdepth 1 -type d -name "5.4*" | head -n 1)"
    cp "$MOD_DIR"/modules.{alias,dep,softdep} "$OUT_DIR/out/zip/vendor/lib/modules"
    cp "$MOD_DIR"/modules.order "$OUT_DIR/out/zip/vendor/lib/modules/modules.load"
    sed -i "s/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g" "$OUT_DIR/out/zip/vendor/lib/modules/modules.dep"
    sed -i "s/.*\///g" "$OUT_DIR/out/zip/vendor/lib/modules/modules.load"
    rm -rf "$SRC_DIR/out/modules"
    cd "$WORK_DIR"
}

PACK_BOOT_IMG()
{
    echo "----------------------------------------------"
    echo "Packing \"$BUILD_VARIANT\" boot.img..."
    rm -rf "$OUT_DIR/tmp"
    mkdir -p "$OUT_DIR/tmp"
    # Copy and unpack stock boot.img
    cp "$WORK_DIR/target/m52xq/images/boot.img" "$OUT_DIR/tmp/boot.img"
    cd "$OUT_DIR/tmp"
    avbtool erase_footer --image boot.img
    magiskboot unpack -h boot.img
    # Replace stock kernel image
    rm -f "$OUT_DIR/tmp/kernel"
    cp "$SRC_DIR/out/arch/arm64/boot/Image" "$OUT_DIR/tmp/kernel"
    # SELinux permissive
    #cmdline="$(head -n 1 header)"
    #cmdline="$cmdline androidboot.selinux=permissive"
    #sed '1 c\"$cmdline"' header > header_new
    #rm -f header
    #mv header_new header
    # Repack and copy in out folder
    magiskboot repack boot.img boot_new.img
    mv "$OUT_DIR/tmp/boot_new.img" "$OUT_DIR/out/zip/mesa/boot.img"
    # Clean :3
    rm -rf "$OUT_DIR/tmp"
    cd "$WORK_DIR"
}

PACK_DTBO_IMG()
{
    echo "----------------------------------------------"
    echo "Packing \"$BUILD_VARIANT\" dtbo.img..."
    # Uncomment this to use firmware extracted dtbo
    #cp "$WORK_DIR/target/m52xq/images/dtbo.img" "$OUT_DIR/out/zip/mesa/dtbo.img"
    cp "$SRC_DIR/out/arch/arm64/boot/dtbo.img" "$OUT_DIR/out/zip/mesa/dtbo.img"
}

PACK_VENDOR_BOOT_IMG()
{
    echo "----------------------------------------------"
    echo "Packing \"$BUILD_VARIANT\" vendor_boot.img..."
    rm -rf "$OUT_DIR/tmp"
    mkdir -p "$OUT_DIR/tmp"
    # Copy and unpack stock vendor_boot.img
    cp "$WORK_DIR/target/m52xq/images/vendor_boot.img" "$OUT_DIR/tmp/vendor_boot.img"
    cd "$OUT_DIR/tmp"
    avbtool erase_footer --image vendor_boot.img
    magiskboot unpack -h vendor_boot.img
    # Replace KernelRPValue
    sed '1 c\name='"$RP_REV"'' header > header_new
    rm -f header
    mv header_new header
    # Replace stock DTB
    rm -f "$OUT_DIR/tmp/dtb"
    cp "$SRC_DIR/out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$OUT_DIR/tmp/dtb"
    # Replace stock fstab
    if [[ "$CUSTOM_FSTAB" == "true" ]]; then
        mkdir ramdisk
        cpio -idm < "ramdisk.cpio" -D ramdisk && rm "ramdisk.cpio"
        rm -f "$OUT_DIR/tmp/ramdisk/first_stage_ramdisk/fstab.qcom"
        cp "$WORK_DIR/target/common/fstab/fstab.qcom" "$OUT_DIR/tmp/ramdisk/first_stage_ramdisk/fstab.qcom"
        sudo bash -c "
            chown -R root:root \"ramdisk\"
            find \"ramdisk\" -type d -exec chmod 755 {} \;
            find \"ramdisk\" -type f -exec chmod 644 {} \;
            find \"ramdisk\" -exec setfattr -n security.selinux -v \"u:object_r:rootfs:s0\" {} \;
        "
        find "ramdisk" -print0 | sudo cpio --null -o -H newc --owner root:root > "ramdisk.cpio"
        sudo rm -rf ramdisk
    fi
    # SELinux permissive
    #cmdline="$(head -n 2 header)"
    #cmdline="$cmdline androidboot.selinux=permissive"
    #sed '2 c\"$cmdline"' header > header_new
    #rm -f header
    #mv header_new header
    # Repack and copy in out folder
    magiskboot repack vendor_boot.img vendor_boot_new.img
    mv "$OUT_DIR/tmp/vendor_boot_new.img" "$OUT_DIR/out/zip/mesa/vendor_boot.img"
    # Clean :3
    rm -rf "$OUT_DIR/tmp"
    cd "$WORK_DIR"
}

MAKE_INSTALLER()
{
    if [[ "$NEXT_BUILD" == "true" ]]; then
        cp -r "$WORK_DIR/target/m52xq/template/ksu-next/META-INF" "$OUT_DIR/out/zip/META-INF"
    else
        cp -r "$WORK_DIR/target/m52xq/template/ksu/META-INF" "$OUT_DIR/out/zip/META-INF"
    fi
    sed -i \
        -e "s|ksu_version|$KSU_VER|g" \
        -e "s|build_var|$BUILD_VARIANT|g" \
        -e "s|build_date|$BUILD_DATE|g" \
        -e "s|build_fp|$BUILD_FP|g" \
        "$OUT_DIR/out/zip/META-INF/com/google/android/update-binary"
    cd "$OUT_DIR/out/zip"
    find . -exec env TZ=UTC touch -a -c -m -t 200901010000.00 {} \;
    if [[ -d "vendor" ]]; then
        7z a -tzip -mx=5 "${RELEASE_VERSION}_m52xq_${BUILD_VARIANT}.zip" mesa META-INF vendor
    else
        7z a -tzip -mx=5 "${RELEASE_VERSION}_m52xq_${BUILD_VARIANT}.zip" mesa META-INF
    fi
    mv "${RELEASE_VERSION}_m52xq_${BUILD_VARIANT}.zip" "$OUT_DIR/${RELEASE_VERSION}_m52xq_${BUILD_VARIANT}.zip"
}
# ]

clear

rm -rf "$OUT_DIR/out"

mkdir -p "$OUT_DIR"
mkdir -p "$OUT_DIR/out"
mkdir -p "$OUT_DIR/out/zip/mesa"

# Detect branch
DETECT_BRANCH

# Clean
[[ "$1" == "-c" || "$1" == "--clean" ]] && CLEAN_SOURCE

# Set vendor_boot build
[[ "$BUILD_VARIANT" == "OneUI" ]] && CUSTOM_FSTAB="true"

# m52xqxx
DEFCONFIG="m52xq_eur_open_defconfig"
RP_REV="SRPUF17B001"
BUILD_KERNEL
[[ "$NEXT_BUILD" != "true" ]] && BUILD_MODULES
PACK_BOOT_IMG
PACK_DTBO_IMG
PACK_VENDOR_BOOT_IMG

# Make installer
MAKE_INSTALLER

rm -rf "$OUT_DIR/out"
rm -f "$WORK_DIR/target/m52xq/images/*.img"

echo "----------------------------------------------"
