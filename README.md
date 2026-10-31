# asuswrt-builder — build image and CI for the RT-BE92U

*[Українською](README-uk.md)*

Two things live here: a **cross-toolchain image** and the **workflow that builds the firmware with it**.
The merlin tree is not forked — it is cloned during the run, so our changes always sit on top and it
stays obvious what we actually applied.

## Why a custom image instead of `gnuton/asuswrt-merlin-toolchains-docker`

- that image ships toolchains for kernels 4.1/4.19 (SDK 5.02 / 5.04axhnd), while `rt-be92u-main`
  needs **gcc 13.2 / glibc 2.38 / kernel 5.15**;
- its env script `bcm-hnd-ax-4.19be.sh` has no 5.15 counterpart, and you cannot add one from outside
  the image;
- our toolchain is **baked in**, not bind-mounted from the host. A bind mount makes the run
  irreproducible: today it mounts `brcm-arm-hnd` from master, tomorrow that is a different tree.

## What is inside

`Dockerfile` — Ubuntu 22.04, the package list from RMerl's own dev docker (the one he shared with
Asus), plus what the 5.15 tree specifically needs: `device-tree-compiler`, `cpio`, `patchelf`, `lzma`,
32-bit libraries for `hostTools/`.

Why 22.04 and not 20.04: the tree ships prebuilt x86_64 host tools under `hostTools/prebuilt/*`
(`lzop`, `mksquashfs`, `mkfs.ubifs`, `ubinize`, `lzmacmd`, `addvtoken`) linked against **glibc 2.34**.
On 20.04 (2.31) the build dies on `lzop` in `bootloaders/Makefile` — exactly the error in the log:

```
hostTools/local_install/lzop: libc.so.6: version `GLIBC_2.34' not found
```

22.04 provides glibc 2.35. `python2` is gone in 22.04, but the 5.15 tree does not need it — it only
appears in a comment inside `u-boot-2024.04/Makefile`.

Toolchains come from the public `RMerl/am-toolchains` via a sparse clone (the full repo is ~1 GB for a
dozen toolchains; we need three):

| arch | directory | why |
|---|---|---|
| aarch64 | `crosstools-aarch64-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41` | kernel 5.15 (`PROFILE_KARCH=aarch64`) |
| arm | `crosstools-arm-gcc-13.2-…` | 32-bit parts |
| arm_hf | `crosstools-arm_hf-gcc-13.2-…` | main userspace (`PROFILE_ARCH=armhfp`) |

`env/hnd-515.sh` does what `make.toolchain` will not: it puts the `bin/` directory of all three
toolchains on `PATH` (executables live in `bin/`, not `usr/bin/` — visible in the toolchain repo
itself), `lib/` on `LD_LIBRARY_PATH`, and exports `KBUILD_BUILD_USER/HOST`, from which the kernel
takes its `uname -v`.

The prefixes are not invented; they come from `make.toolchain`:
`aarch64-buildroot-linux-gnu` (line 260), `arm-buildroot-linux-gnueabi` (231),
`arm-buildroot-linux-gnueabihf` (216).

## Workflows

`image.yml` — builds the image and pushes it to `ghcr.io/<owner>/asuswrt-builder:4916-gcc13.2`.
Runs only when `Dockerfile`, `env/**` or the workflow itself changes.

`build.yml` — the actual build, `workflow_dispatch` with inputs:

- `ref` — merlin branch or tag (default `rt-be92u-main`; `3006.102.7` also works, but that tree is
  kernel 4.19 and needs a 4.19 env script);
- `model` — the `make` target, lowercase (`rt-be92u`);
- `build_user` / `build_host` — the "decorations" embedded in `uname -v`;
- `commit_manifest` — file with commit SHAs to cherry-pick (empty = skip; not needed for
  `rt-be92u-main`);
- `blob_commit` — merge commit to import `RT-BE92U` `prebuilt` blobs from (empty = skip);
- `dry_run` — prepare the tree without compiling.

The step order is deliberate:

1. **free disk space** — the runner root gives ~30–40 GB while the merlin tree alone is 11 GB;
2. **clone into `/mnt/build`** — `/mnt` is larger than the root filesystem on GitHub runners (the same
   trick gnuton uses: "prevents to run out of space");
3. cherry-pick / blob import — when requested;
4. `CHERRY-PICKS.txt` in `www/` — so the web UI shows what was built;
5. `docker run` of our image with `-v /mnt/build:/build`, inside: `source /opt/env/hnd-515.sh`,
   bypass `prebuild_checks.mk` (it wants Asus' closed-source tooling), `make rt-be92u`;
6. artifact validation and `upload-artifact`.

## Usage

1. Fork or push this repo (public — Actions minutes are free).
2. Actions → `image` → Run workflow (once, ~10–15 min for apt and toolchains).
3. Actions → `build` → Run workflow → pick `ref`/`model` → Run.
4. Artifact `RT-BE92U-<ref>` in the run, kept 14 days.

## Patches

`patches/jffs-to-tmp.patch` — move logs from `/jffs` to `/tmp`. The important part is not code but a
single line in `src-rt/target.mak`: `PSISTLOG=y` in the `HND-96765_BASE` block (line 406). That flag
makes `get_syslog_fname()`/`get_logfile_path()` (`shared/misc.c`) return `/jffs`, so syslogd writes
`/jffs/syslog.log{,-1}`. The rest touches `httpd/common.h`, `httpd/web.c`, `rc/common.c`,
`rc/watchdog.c`, `aaews/common.h`, `ssl_webs_download.sh`. Analysis and risks:
`patches/jffs-to-tmp.md` (Ukrainian).

The `Apply patches` step in `build.yml` applies everything under `patches/*.patch` **after**
cherry-pick and blob import (our changes on top) and fails loudly if a patch does not apply cleanly.

### Variant without `asd` and Ark

`patches/optional/no-asd-ark.patch`, four edits:

- `target.mak` (`RT-BE92U` block): `GTBOOSTER=n` instead of `GTBOOSTER=y` — the Ark engine is not
  built (`ark.ko`, `aqua.ko`, `ark.xdb`, `ark_service`, `arkctl`, `arklogd`, `-lark_db`).
- `router/Makefile`: `asd-install` becomes a no-op — the `asd` daemon and `libasd.so` **do not ship**.
  `ASD=y` stays on purpose: `RTCONFIG_LIBASC` (`libasc.so`) depends on it, and `rc` links `-lasc`;
  without it `libcreduction` fails with "Missing 32-bit libraries: libasc.so".
- `shared/Makefile`: the prebuilt `ark_utils.o` is linked regardless of `GTBOOSTER`, because
  `disable_ark_features()` and `ark_disable_hw_accel()` are called from `misc.c`, `rc` and `httpd`
  without any `#ifdef`.
- `rc/Makefile` + `rc/ark_stub.c`: `IS_ARK_IAM() → 0` stub, because the prebuilt `amas_lib.o`
  references that symbol while its definition lives in `ark.o`.

Controlled by the `no_security` input (default `true`), applied by a separate step, so the stock
image stays reproducible from the same workflow (`no_security=false`) for comparison. The
AiProtection tab remains in the web UI but stays empty — expected.

The `drop_asd` input (default `false`) additionally sets `ASD=n` and makes `libasc` unconditional
(`obj-y += libasc` in `router/Makefile`), so the `asd` daemon is not even compiled — done by
`scripts/drop-asd.py`. Image contents are the same either way.

## What is not here yet

- **kernel fixes** for the Brahma-B53 errata (timers, `CNTP_TVAL` bypass) — deliberately out of this
  repo for now: first the stock kernel has to build and prove it survives on real hardware;
- **proof that the image builds without Asus' closed blobs** — `blob_commit` exists precisely because
  blobs are missing on tags, while `rt-be92u-main` may already carry them;
- **the 6-hour job limit** — a full HND build does not always fit. If we hit it: cache `targets/` and
  objects between runs, or split kernel/userspace into two jobs exchanging artifacts.

## Changelog

Every change to the image, workflow, patches or scripts gets a line in [CHANGELOG.md](CHANGELOG.md)
in the same commit. A change is not done until it is there — see the "How to keep it" section at
the top of that file.
