# Changelog

All notable changes to this repository are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) — with one deviation: while
the firmware itself is built from upstream sources, the versions here describe **this builder
toolchain + workflow + patch set**, not the firmware release.

## How to keep it

A change is not done until it has a line here.

1. Every commit that touches `Dockerfile`, `env/`, `.github/workflows/`, `patches/` or `scripts/`
   adds its entry under `## [Unreleased]` in the **same commit** — the entry is part of the change,
   not a later chore.
2. One line per change, start with a verb (`added`, `fixed`, `changed`, `removed`), name the file
   or target that changed, and say **why** when the why is not obvious — the why is what saves the
   next debugging session.
3. Fixed build failures get the exact error text in backticks. That string is how the next person
   greps for it.
4. On a working image, cut a version: rename `[Unreleased]` to `[x.y.z] - YYYY-MM-DD`, add a fresh
   empty `[Unreleased]` above it, tag the commit (`git tag -a vX.Y.Z -m ...`), push tags, and create
   a GitHub Release from the matching section. Releases are what GitHub shows as "changelog";
   a tag without a release renders as nothing.

Bump rules: `MAJOR` — the produced image changes in a way that invalidates comparisons with older
builds (new SDK, new kernel); `MINOR` — new workflow input, new patch, new image variant; `PATCH` —
a fix that makes an existing build work without changing what it produces.

## [Unreleased]

### Added

- `regulatory.db` from the `wireless-regdb` package is copied into `rom/lib/firmware` before the
  build, so the image ships `/lib/firmware/regulatory.db`. Without it the 5.15 kernel logs
  `platform regulatory.0: Direct firmware load for regulatory.db failed with error -2` on every
  boot (Asus handles regulatory domains through `wl` and never shipped the file).

## [0.1.0] - 2026-10-31

First working firmware: **RT-BE92U, kernel 5.15.167, built in GitHub Actions from a self-contained
image, flashed and booted on hardware** (variant `nosec-noasd`).

### Added

- `Dockerfile` — self-contained builder image (`ubuntu:22.04`), gcc 13.2 / kernel 5.15 cross
  toolchains fetched into `/opt/toolchains`, so no host mounts are needed and a run is reproducible.
- `.github/workflows/image.yml` — builds the image and pushes it to
  `ghcr.io/pragmatrans/asuswrt-builder:4916-gcc13.2`.
- `.github/workflows/build.yml` — full firmware build: free disk → work dir → clone `RMerl` tree →
  cherry-pick manifest → import prebuilt blobs → apply patches → `make rt-be92u` → artifact.
  Inputs: `ref`, `model`, `build_user`, `build_host`, `commit_manifest`, `blob_commit`,
  `no_security`, `drop_asd`, `dry_run`.
- `env/hnd-515.sh` — environment for the 5.15 tree: `TOOLCHAIN_BASE`, three toolchain prefixes,
  `PATH` ordering, `LD_LIBRARY_PATH`, `KBUILD_BUILD_USER`/`KBUILD_BUILD_HOST`.
- `patches/jffs-to-tmp.patch` + `patches/jffs-to-tmp.md` — logs move from `/jffs` to `/tmp`
  (`PSISTLOG=n` in `target.mak` plus the seven call sites that hardcode `/jffs/*.log`), so a log
  flood no longer wears the NAND.
- `patches/optional/no-asd-ark.patch` — image variant without the security stack: `GTBOOSTER=n`,
  `asd-install` turned into a no-op, `ark_utils.o` linked regardless of the flag, and a
  `rc/ark_stub.c` stub for `IS_ARK_IAM()`.
- `scripts/drop-asd.py` + `drop_asd` workflow input — also sets `ASD=n` and makes `libasc`
  unconditional (`obj-y += libasc`), so the `asd` daemon is not even compiled.
- `README.md` (English, primary) and `README-uk.md` (Ukrainian).

### Changed

- Base image is `22.04`, not `20.04`: the prebuilt x86_64 host tools
  (`hostTools/prebuilt/*/lzop`, `addvtoken`) are linked against `GLIBC_2.34`, and `20.04` ships 2.31.
  Verified with `readelf -V`, not guessed.
- Toolchain `bin/` directories are appended to the **end** of `PATH`: the toolchain ships its own
  broken `autoreconf` (`Can't locate Autom4te/ChannelDefs.pm`), while cross compilers are found by
  prefix anyway.
- Work dir is chosen at runtime — `/mnt/build` via `sudo` when possible, `$RUNNER_TEMP/build`
  otherwise — and exported through `$GITHUB_ENV`, so no step hardcodes `/mnt`.
- Patches are applied in a separate step after cherry-pick and blobs, and fail loudly
  (`git apply --verbose`) instead of building a half-patched tree.

### Fixed

- `libtoolize: error: '/usr/share/aclocal/lt~dl.m4' does not exist` — `libtool-bin` ships only the
  binary; the m4 macros live in `libtool` and `libltdl-dev`. All three are installed now.
- `fatal: detected dubious ownership in repository at '/build/merlin'` — `/mnt` belongs to the
  runner user while the container runs as root; fixed with
  `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0=safe.directory`/`GIT_CONFIG_VALUE_0='*'` on `docker run`.
- `mkdir: cannot create directory '/mnt/build': Permission denied` — `Prepare work dir` step with
  `sudo -n mkdir/chown` and a `$RUNNER_TEMP` fallback.
- `version 'GLIBC_2.34' not found` from `hostTools/local_install/lzop` — base image moved to 22.04.
- `undefined reference to 'disable_ark_features'` — `shared/Makefile` linked the prebuilt
  `ark_utils.o` only under `RTCONFIG_GTBOOSTER`, while `misc.c`, `rc` and `httpd` call those
  functions unconditionally; now linked whenever the file exists.
- `ld: cannot find -lasc` — `rc/Makefile` links `-lasc` under `RTCONFIG_TPVPN`, but `libasc` was
  only ever built as a dependency of `asd`; `rc` now depends on it explicitly.
- `undefined reference to 'IS_ARK_IAM'` — the prebuilt `amas_lib.o` is always linked and references
  a symbol defined only in the prebuilt `ark.o`; `rc/ark_stub.c` returns 0 for builds without Ark.
- `libcreduction FATAL: Missing 32-bit libraries: libasc.so` — `RTCONFIG_LIBASC` is not a standalone
  flag, it is derived from `AHS`/`ASD` by the config generator; `libasc` is now built
  unconditionally instead of guessing flag values.

### Verified

- Image `ghcr.io/pragmatrans/asuswrt-builder:4916-gcc13.2` builds and pulls.
- Full build succeeds for `rt-be92u-main` in both variants: `-nosec` and `-nosec-noasd`.
- Flashed `-nosec-noasd` on hardware: `Linux version 5.15.167 (pragmatrans@asuswrt-builder)
  (aarch64-buildroot-linux-gnu-gcc.br_real)`, CMA pool 272 MiB, boots to userspace.
