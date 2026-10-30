#!/bin/bash
# Оточення для збірки HND 5.04behnd.4916 (RT-BE92U): gcc 13.2, glibc 2.38, ядро 5.15.
#
# Префікси й імена каталогів тут не вигадані — вони взяті з make.toolchain:
#   TOOLCHAIN_PREFIX_LINUX_5_15_0_AARCH64 := aarch64-buildroot-linux-gnu
#   TOOLCHAIN_PREFIX_LINUX_5_15_0_ARM     := arm-buildroot-linux-gnueabi
#   TOOLCHAIN_PREFIX_LINUX_5_15_0_ARMHFP  := arm-buildroot-linux-gnueabihf
# і з самого тулчейну RMerl/am-toolchains: виконувані файли лежать у <toolchain>/bin, не в usr/bin.
#
# kernel 5.15 → AARCH64 (PROFILE_KARCH=aarch64), userspace → 32-бітний ARMHFP
# (PROFILE_ARCH=armhfp), тому в PATH потрібні всі три, інакше частина дерева мовчки
# збереться не тим компілятором або впаде на «command not found».

export TOOLCHAIN_BASE=/opt/toolchains

_tc_a64="${TOOLCHAIN_BASE}/crosstools-aarch64-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41"
_tc_arm="${TOOLCHAIN_BASE}/crosstools-arm-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41"
_tc_hf="${TOOLCHAIN_BASE}/crosstools-arm_hf-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41"

for _tc in "$_tc_a64" "$_tc_arm" "$_tc_hf"; do
    if [ ! -d "${_tc}/bin" ]; then
        echo "hnd-515.sh: немає тулчейну ${_tc}" >&2
        return 1 2>/dev/null || exit 1
    fi
done

export PATH="${_tc_a64}/bin:${_tc_arm}/bin:${_tc_hf}/bin:${PATH}"
export LD_LIBRARY_PATH="${_tc_a64}/lib:${_tc_arm}/lib:${_tc_hf}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export CROSS_COMPILE=aarch64-buildroot-linux-gnu-
export ARCH=arm64

# Прикраси збірки: ядро вшиває ці рядки у власну версію (uname -v), тому CI передає свої.
: "${KBUILD_BUILD_USER:=builder}"
: "${KBUILD_BUILD_HOST:=gh-actions}"
export KBUILD_BUILD_USER KBUILD_BUILD_HOST
export LINUX_COMPILE_BY="${KBUILD_BUILD_USER}"
export LINUX_COMPILE_HOST="${KBUILD_BUILD_HOST}"
