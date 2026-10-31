# Build environment for Asuswrt-Merlin / Broadcom HND 5.04behnd.4916 (Wi-Fi 7, kernel 5.15)
#
# Base: Ubuntu 22.04 — не смак, а вимога дерева.
# У hostTools/prebuilt лежать готові x86_64-інструменти збірки (lzop, mksquashfs, mkfs.ubifs,
# ubinize, lzmacmd, addvtoken), злінковані проти glibc 2.33/2.34:
#   readelf -V hostTools/prebuilt/RT-BE92U/lzop → max GLIBC_2.34
# На 20.04 (glibc 2.31) збірка падає саме на них:
#   hostTools/local_install/lzop: libc.so.6: version `GLIBC_2.34' not found
# 22.04 дає 2.35. python2 у 22.04 вже немає — і 5.15-дереву він не потрібен (є лише згадка
# в u-boot-2024.04/Makefile, не виклик).
#
# Тулчейни — з публічного RMerl/am-toolchains, запечені в /opt/toolchains так, як їх очікує
# make.toolchain: для PROFILE_KERNEL_VER=LINUX_5_15_0 + AARCH64 дерево бере
#   $(TOOLCHAIN_BASE)/crosstools-aarch64-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41
# а для 32-бітного userspace (PROFILE_ARCH=armhfp) — crosstools-arm-… і crosstools-arm_hf-… тієї ж версії.
# Ніяких монтувань ззовні: образ мусить бути самодостатнім, інакше CI невідтворюваний.
FROM ubuntu:22.04

ARG TOOLCHAINS_REPO=https://github.com/RMerl/am-toolchains.git
ARG TOOLCHAINS_REF=master

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TOOLCHAIN_BASE=/opt/toolchains \
    PATH=/opt/toolchains/bin:$PATH

# Пакети: список RMerl (його gist) мінус інтерактивні зручності (nano, manpages), плюс те,
# що потрібне саме 5.15-дереву — dtc, cpio, patchelf, lzma, 32-бітні бібліотеки для hostTools.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential make gcc g++ binutils-dev patch m4 bison flex gawk gperf \
        autoconf automake autopoint libtool libtool-bin libltdl-dev shtool autogen intltool \
        zlib1g-dev libncurses5 libncurses5-dev libtinfo5 libssl-dev libglib2.0-dev libyaml-dev \
        liblzma-dev lzma xz-utils liblzo2-dev uuid-dev libpopt-dev \
        libc6-i386 lib32stdc++6 lib32z1 libc6-dev-i386 \
        device-tree-compiler u-boot-tools mtd-utils cpio patchelf dos2unix \
        texinfo xsltproc docbook-xsl sharutils gengetopt \
        bc rsync sudo zip unzip wget curl ca-certificates xxd gdisk wireless-regdb \
        git git-lfs software-properties-common \
        python3 python3-packaging python-is-python3 golang cmake \
    && ln -sf bash /bin/sh \
    && curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/bin/repo \
    && chmod +x /usr/bin/repo \
    && rm -rf /var/lib/apt/lists/*

# Тулчейни gcc 13.2 / glibc 2.38 / binutils 2.41 (ядро 5.15). Sparse-клон тягне лише потрібні каталоги:
# повний am-toolchains — ~1 ГБ на десяток тулчейнів, а для 4916 треба рівно три.
RUN git clone --filter=blob:none --no-checkout --depth 1 -b "${TOOLCHAINS_REF}" "${TOOLCHAINS_REPO}" /tmp/am \
    && cd /tmp/am \
    && git sparse-checkout init --cone \
    && git sparse-checkout set brcm-arm-hnd \
    && git checkout \
    && mkdir -p /opt/toolchains \
    && mv brcm-arm-hnd/crosstools-aarch64-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41 \
          brcm-arm-hnd/crosstools-arm-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41 \
          brcm-arm-hnd/crosstools-arm_hf-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41 \
          /opt/toolchains/ \
    && rm -rf /tmp/am \
    && ls -d /opt/toolchains/* \
    && /opt/toolchains/crosstools-aarch64-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41/bin/aarch64-buildroot-linux-gnu-gcc --version | head -1

COPY env/hnd-515.sh /opt/env/hnd-515.sh
RUN chmod +x /opt/env/hnd-515.sh

WORKDIR /build
CMD ["/bin/bash"]
