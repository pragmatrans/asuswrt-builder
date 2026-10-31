# asuswrt-builder — образ і CI для збірки RT-BE92U

*[English](README.md)*

Тут живе рівно дві речі: **образ з крос-тулчейнами** і **workflow, який ним збирає прошивку**.
Дерево merlin не форкається — воно клонується в прогоні, тому наші зміни завжди зверху й видно, що саме ми наклали.

Навіщо свій образ, якщо є `gnuton/asuswrt-merlin-toolchains-docker`:

- там тулчейни під 4.1/4.19 (SDK 5.02/5.04axhnd), а для `rt-be92u-main` потрібен **gcc 13.2 / glibc 2.38 / ядро 5.15**;
- його env-скрипт `bcm-hnd-ax-4.19be.sh` під 5.15 не існує, і зсередини образу його не дописати;
- у нас тулчейн **усередині** образу, а не змонтований ззовні — інакше прогін невідтворюваний: сьогодні змонтували `brcm-arm-hnd` з master, завтра він інший.

## Що всередині

`Dockerfile` — Ubuntu 22.04, набір пакетів зі списку RMerl (його gist з девелоперським докером, який він ділив з Асусом), плюс те, що потрібне саме 5.15-дереву: `device-tree-compiler`, `cpio`, `patchelf`, `lzma`, 32-бітні бібліотеки для `hostTools/`.

Чому 22.04, а не 20.04: у дереві лежать готові x86_64-інструменти `hostTools/prebuilt/*` (`lzop`, `mksquashfs`, `mkfs.ubifs`, `ubinize`, `lzmacmd`, `addvtoken`), злінковані проти **glibc 2.34**. На 20.04 (2.31) збірка падає на `lzop` у `bootloaders/Makefile` — саме та помилка, яку видно в лозі:

```
hostTools/local_install/lzop: libc.so.6: version `GLIBC_2.34' not found
```

22.04 дає glibc 2.35. `python2` у 22.04 вже немає, але 5.15-дереву він не потрібен — є лише згадка в `u-boot-2024.04/Makefile`, не виклик.

Тулчейни беруться з публічного `RMerl/am-toolchains`, sparse-клоном (повний репо — ~1 ГБ на десяток тулчейнів, нам треба три):

| арх | каталог | навіщо |
|---|---|---|
| aarch64 | `crosstools-aarch64-gcc-13.2-linux-5.15-glibc-2.38-binutils-2.41` | ядро 5.15 (`PROFILE_KARCH=aarch64`) |
| arm | `crosstools-arm-gcc-13.2-…` | 32-бітні частини |
| arm_hf | `crosstools-arm_hf-gcc-13.2-…` | основний userspace (`PROFILE_ARCH=armhfp`) |

`env/hnd-515.sh` — те, чого не робить `make.toolchain` сам: додає `bin/` усіх трьох тулчейнів у `PATH` (виконувані файли лежать у `bin/`, не в `usr/bin/` — це видно з самого репо тулчейнів), `lib/` у `LD_LIBRARY_PATH`, і виставляє `KBUILD_BUILD_USER/HOST`, з яких ядро бере свій `uname -v`.

Префікси в скрипті не вигадані — вони з `make.toolchain`:
`aarch64-buildroot-linux-gnu` (рядок 260), `arm-buildroot-linux-gnueabi` (231), `arm-buildroot-linux-gnueabihf` (216).

## Workflow

`image.yml` — збирає образ і пушить у `ghcr.io/<owner>/asuswrt-builder:4916-gcc13.2`. Бігає тільки коли змінився `Dockerfile`, `env/**` або сам workflow.

`build.yml` — сама збірка, `workflow_dispatch` з полями:

- `ref` — гілка merlin (за замовчуванням `rt-be92u-main`; для 102.7 — `3006.102.7`, але тоді ядро 4.19 і треба env під 4.19);
- `model` — ціль `make`, нижнім регістром (`rt-be92u`);
- `build_user` / `build_host` — «прикраси», які вшиваються в `uname -v`;
- `commit_manifest` — файл зі SHA для cherry-pick (порожньо = не робити; для `rt-be92u-main` не потрібен);
- `blob_commit` — merge-коміт, з якого підтягнути `prebuilt`-блоби `RT-BE92U` (порожньо = не робити);
- `dry_run` — підготувати дерево без компіляції.

Порядок у прогоні навмисний:

1. **звільнити диск** — корінь раннера дає ~30–40 ГБ, а дерево merlin це 11 ГБ;
2. **клон у `/mnt/build`** — `/mnt` на раннері більший за корінь (той самий трюк, що в gnuton: «prevents to run out of space»);
3. cherry-pick / блоби — за потреби;
4. `CHERRY-PICKS.txt` у `www/` — щоб у веб-UI було видно, що саме зібрано;
5. `docker run` нашого образу з `-v /mnt/build:/build`, всередині `source /opt/env/hnd-515.sh`, обхід `prebuild_checks.mk` (він вимагає закритих інструментів Асуса), `make rt-be92u`;
6. перевірка артефакту й `upload-artifact`.

## Як користуватися

1. Форкнути/запушити цей репо (публічний — хвилини Actions безкоштовні).
2. Actions → `image` → Run workflow (один раз, ~10–15 хв на тулчейни й apt).
3. Actions → `build` → Run workflow → `ref`/`model` → Run.
4. Артефакт `RT-BE92U-<ref>` у прогоні, 14 днів.

## Патчі

`patches/jffs-to-tmp.patch` — логи з `/jffs` → `/tmp`. Головне там не код, а один рядок у
`src-rt/target.mak`: `PSISTLOG=y` у блоці `HND-96765_BASE` (рядок 406). Саме цей прапорець змушує
`get_syslog_fname()`/`get_logfile_path()` (`shared/misc.c`) повертати `/jffs`, і syslogd пише
`/jffs/syslog.log{,-1}`. Решта — `httpd/common.h`, `httpd/web.c`, `rc/common.c`, `rc/watchdog.c`,
`aaews/common.h`, `ssl_webs_download.sh`. Розбір і ризики: `patches/jffs-to-tmp.md`.

Крок `Apply patches` у `build.yml` накладає все, що лежить у `patches/*.patch`, **після**
cherry-pick і блобів (наші зміни — зверху), і падає голосно, якщо патч не ліг чисто.

### Варіант без `asd` і Ark

`patches/optional/no-asd-ark.patch`, чотири правки:

- `target.mak` (блок `RT-BE92U`): `GTBOOSTER=n` замість `GTBOOSTER=y` — движок Ark не збирається
  (`ark.ko`, `aqua.ko`, `ark.xdb`, `ark_service`, `arkctl`, `arklogd`, `-lark_db`).
- `router/Makefile`: `asd-install` стає заглушкою — демон `asd` і `libasd.so` **не потрапляють
  в образ**. Сам `ASD=y` лишаємо: від нього залежить `RTCONFIG_LIBASC` (`libasc.so`), яку `rc`
  лінкує через `-lasc`; без неї `libcreduction` падає з «Missing 32-bit libraries: libasc.so».
- `shared/Makefile`: `ark_utils.o` (prebuilt) лінкується незалежно від `GTBOOSTER`, бо
  `disable_ark_features()`, `ark_disable_hw_accel()` кличуть `misc.c`, `rc` і `httpd` без `#ifdef`.
- `rc/Makefile` + `rc/ark_stub.c`: заглушка `IS_ARK_IAM() → 0`, бо prebuilt `amas_lib.o`
  кличе цей символ, а визначення живе в `ark.o`.

Вмикається полем `no_security` (типово `true`) окремим кроком, тому стоковий образ можна
зібрати тим самим workflow (`no_security=false`) для порівняння. Вкладка AiProtection у веб-UI
лишиться, але буде порожньою — це очікувано.

Поле `drop_asd` (типово `false`) додатково ставить `ASD=n` і робить `libasc` безумовною
(`obj-y += libasc` у `router/Makefile`) — тоді демон `asd` взагалі не компілюється, а не
просто не встановлюється. Робить це `scripts/drop-asd.py`; на вміст образу не впливає.

## Чого тут ще немає

- **правки ядра** для ерат Brahma-B53 (таймери, `CNTP_TVAL` bypass) — свідомо поза цим репо: спершу треба зібрати стокове ядро й переконатись, що воно взагалі живе на залізі;
- **перевірки, що образ збирається без асусівських закритих блобів** — `blob_commit` існує саме тому, що на тегах їх немає, а на `rt-be92u-main` вони можуть бути вже в дереві;
- **6-годинний ліміт job'а** — повна збірка HND вкладається не завжди. Якщо впремося: кешувати `targets/`/об'єкти між прогонами або розділяти kernel/userspace на два job'и з артефактами між ними.

## Журнал змін

Кожна зміна образу, workflow, патчів чи скриптів додає рядок у [CHANGELOG.md](CHANGELOG.md) у тому
самому коміті. Зміна не вважається зробленою, поки її там немає — правила в розділі «How to keep it»
на початку файлу.
