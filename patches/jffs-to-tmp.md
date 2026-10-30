# Логи в /jffs у asuswrt-merlin (RT-BE92U, чип 96765) — повна картина та мінімальний патч «у /tmp»

Дерево: `RMerl/asuswrt-merlin.ng`, гілка `rt-be92u-main`, каталоги
`release/src-rt-5.04behnd.4916/` (далі *src-rt*) і `release/src/router/` (далі *router*).
Досліджено тільки читанням; патч застосовується й відкочується чисто (`git apply` + `git checkout --`).

---

## 1. Ключовий висновок: чому взагалі щось потрапляє в /jffs

Для RT-BE92U драйвер логів у /jffs — **`PSISTLOG=y`** у спільному базовому блоці моделі:

```
src-rt/target.mak:405-407
export HND-96765_BASE := HND_ROUTER=y HND_ROUTER_BE_4916=y PROFILE="96765GW" ... UBI=y UBIFS=y PSISTLOG=y CABLEDIAG=y
export RT-BE92U := $(HND-96765_BASE)
```

`PSISTLOG=y` → `RTCONFIG_PSISTLOG=y` (src-rt/Makefile:2693) → у `router/shared/misc.c`
обидві функції вибору шляху повертають **/jffs**:

- `get_logfile_path()` — `misc.c:3637-3652` (використовує `httpd/web.c:2591` для показу системного логу в UI);
- `get_syslog_fname()` — `misc.c:3654-3672` (використовує `rc/services.c:5955` — аргумент `-O` демона syslogd).

Тому головний і найважливіший письменник — **syslogd** пише `O_APPEND`-файли
`/jffs/syslog.log` + ротаційний `/jffs/syslog.log-1` (256 КБ кожен, Hard Limit за `rom/rom/jffs.json:513-531`).
Вимкнення `PSISTLOG` — це 90% записів у /jffs і **нуль правок у коді**.

Решта прапорців, які «вмикають» /jffs-логи, для RT-BE92U **не встановлені**
(`router/config_base` + блок `HND-96765_BASE`/`RT-BE92U` у target.mak):
`RTCONFIG_JFFS2`, `RTCONFIG_BRCM_NAND_JFFS2` — не встановлені (модель на UBI/UBIFS),
`SOFTWIRE46`, `HNS`, `TCPDUMP`, `AWSIOT`, `BCM_AFC`, `FRS_FEEDBACK=n`, `AHS=n`, `AICLOUD`.
Це означає, що цілий ряд /jffs-лог-коду для цієї моделі **мертвий на компіляції**:

- `rc/watchdog.c:171, 8613, 11865` та `rc/services.c:6003, 6024, 6028, 6033, 16074` —
  синхронізація `/tmp/syslog.log → /jffs/syslog.log`, огороджена
  `#if defined(RTCONFIG_JFFS2LOG) && (defined(RTCONFIG_JFFS2)||defined(RTCONFIG_BRCM_NAND_JFFS2))`
  → для BE92U не компілюється (хоча `RTCONFIG_JFFS2LOG=y` формально встановлений, src-rt/Makefile:2790);
- `rc/jffs2.c:15, 518-560` (stop/start/umount-синхронізація логів) — той самий guard;
- `rc/wan.c`, `tc_utils`, `aws-iot`, `s46comm/v6plusd/ocnvcd/dslited` (`/jffs/s46.log`), `ahs` (`/jffs/ahs/*.log`), `hns` (`/jffs/.sys/AiProtectionMonitor/`), tcpdump- pcap (`/jffs/pppoe.pcap`, `www/Makefile:973-975`) — усе вимкнено прапорцями.

Отже, фактичний перелік **активних** письменників у /jffs для RT-BE92U — таблиця нижче.

---

## 2. Таблиця: файл:рядок → що пише → чим керується → безпечний варіант у коді

| # | Файл:рядок | Що пише / копіює | Чим керується | Безпечний варіант у коді? |
|---|---|---|---|---|
| 1 | `router/shared/misc.c:3641-3652` (`get_logfile_path`), `3654-3672` (`get_syslog_fname`) | повертає префікс `/jffs` для syslog | `RTCONFIG_PSISTLOG` | **Так**: `#else → /tmp` (наявний у коді); + є runtime-fallback на /tmp, якщо /jffs недоступний |
| 2 | `router/rc/services.c:5936-5955` (`start_syslogd`) | `-O /jffs/syslog.log` → демон syslogd пише туди | через `get_syslog_fname()` (п.1) | Так — слідує п.1 автоматично |
| 3 | `router/rc/init.c:26696-26733` (`init_jffs2`-логіка) | symlink `/tmp/syslog.log → /jffs/syslog.log` | `RTCONFIG_PSISTLOG` | Так — блок зникає при вимкненому PSISTLOG |
| 4 | `router/rc/init.c:25976` | `net.unix.dgram_qlen=150` (щоб syslogd не втрачав датаграми) | `PSISTLOG \|\| JFFS2LOG` | дрібниця, зникає з прапорцем |
| 5 | `router/rc/common.c:1829-1831` (`collect_debuglog`) | `/jffs/debuglog_{klog,core,slog}.tgz` — файли пакування логів для «Feedback» (`www/Advanced_Feedback.asp:592`, `rc/rc.c:5605`) | **немає прапорця**, константи в коді | Ні — тільки правка шляхів |
| 6 | `router/httpd/common.h:44-48` | `HTTPD_DEBUG_FILE` = `/jffs/HTTPD_DEBUG.log` (debug-лог httpd, пишеться тільки за наявності тригера) | `JFFS2\|JFFSV1\|BRCM_NAND_JFFS2\|UBIFS\|JFFS_PARTITION` (для BE92U true через UBIFS) | **Так**: `#else → /tmp/HTTPD_DEBUG.log` |
| 7 | `router/httpd/common.h:62-64` | `SECURITY_LOG_FILE` = `/jffs/security_recored.log` — журнал входів/відмов (web.c:13742, 22575, 22628, 22780) | `RTCONFIG_LIBASUSLOG` (так, бо AMAS=y → LIBASUSLOG=y, src-rt/Makefile:4013) | Ні |
| 8 | `router/httpd/common.h:78-80` | `HTTPD_FB_DEBUG_FILE` = `/jffs/HTTPD_FB_DEBUG.log` — feedback-лог httpd | константа, без guard | Ні |
| 9 | `router/httpd/web.c:2779-2784` | **читання** `security_recored.log` із `/jffs` для показу в UI (`apply.c`-dump) | константа в коді | Ні — має змінюватися разом із п.7, інакше UI покаже порожній журнал |
| 10 | `router/rc/watchdog.c:9950, 9958, 9971, 9979` | `CFG_MNT_FOLDER"cfg_dbg.log"` = `/jffs/.sys/cfg_mnt/cfg_dbg.log` — діагностичний лог AiMesh/onboarding | `RTCONFIG_LIBASUSLOG` + `amas_ob.h:13` (`UBIFS=y` → /jffs/.sys) | Ні |
| 11 | `router/aaews/common.h:81` | `AAE_DBG_LOG` = `/jffs/aae.log` — debug-лог AiProtection/aae | `RTCONFIG_LIBASUSLOG` | Ні |
| 12 | `router/rom/webs_scripts/ssl_webs_download.sh:89` | `touch /jffs/KEEP_UPGRADE_DEBUG.log` — прапорець/журнал завантаження SSL/SQ | без guard, скрипт | Ні |
| 13 | `router/shared/defaults.c:4280-4283` | дефолти `ahs_bhc_log`/`ahs_dhcp_log` = `/jffs/ahs/*.log` | `RTCONFIG_AHS` (**n** для BE92U) → мертвий | — |
| 14 | `router/shared/shared.h:4953` | `AFC_LOG_FILE_PATH` `/jffs/afc_debug.log` | `BCM_AFC` (не встановлений) → мертвий | — |
| 15 | `router/rc/rc.h:407-408` | `WEBSUPG_FILE`/`WEBSUPG_1_FILE` = `/jffs/webs_upgrade.log` | `UBIFS` (так!) — але джерельних користувачів у коді немає (лише `rc.h`) | див. ризики |
| 16 | `router/rom/rom/jffs.json:505-531` | дескриптор розміщення `/jffs/syslog.log{,-1}` (Hard Limit 256 КБ) | дані для FCS/`dblog` | не є письменником; після вимкнення PSISTLOG стає нерелевантним |
| 17 | `router/httpd/web.c:3485-3495` | лог-файл `/jffs/usericon/<mac>.log` при видаленні usericon | `RTCONFIG_JFFS2USERICON` (так, через UBIFS) | дрібний, разовий |

**Окремо: prebuild-бінарники (не правляться джерелами).** Для RT-BE92U частина
підсистем постачається лише готовими об'єктами (`router/*/prebuild/RT-BE92U/`),
у яких `/jffs`-шляхи **зашиті в бінарник** (`strings`-скан підтверджено):

- `httpd/prebuild/RT-BE92U/web_hook.o` (`httpd/web_hook.c` відсутній у дереві,
  `httpd/Makefile:25-26` бере prebuild): `/jffs/HTTPD_DEBUG.log`, `/jffs/security_recored.log`,
  `/jffs/HTTPD_FB_DEBUG.log` — тобто попри правки `common.h`, web_hook.o продовжить писати в /jffs;
- `rc/prebuild/RT-BE92U/private.o`, `dsl_fb.o` (`/jffs/asd.log`, `/jffs/cfg_dbg.log`, `/jffs/ahs_*.log`,
  `/jffs/amas_ssd_dbg.log`, `/jffs/amas_wlcconnect.log`), `amas-ssd*.o`, `amas_wlcconnect.o`,
  `amas_bhctrl.o` (`/jffs/.sys/amas/*.log`), `s46comm.o`, `v6plusd/ocnvcd/dslited` (`/jffs/s46.log`);
- `asd/prebuild/RT-BE92U/asd` (`/jffs/asd.log` — ASD=y для BE92U);
- `aaews/prebuild/RT-BE92U/{aaews,mastiff}` (`/jffs/aae.log` — aaews збирається з prebuild,
  бо `aaews/*.c` у дереві немає; правка `aaews/common.h` неефективна для цієї моделі, але нешкідлива).

`dblog` і `libasuslog` prebuild — **чисті** (жодного `/jffs/*.log`; libasuslog отримує шлях як аргумент).

---

## 3. Мінімальний набір правок (у порядку зростання ризику)

### (а) Прапорці в конфігу профілю моделі — 0 правок коду, найменший ризик

Прибрати `PSISTLOG=y` з `HND-96765_BASE` (рядки 405-407 `src-rt/target.mak`).
Це вимикає таблицю пп.1-4: syslogd одразу пише `/tmp/syslog.log`,
`get_logfile_path()` повертає `/tmp` (UI показує той самий файл, консистентно),
symlink-и в `init.c` не створюються, umount-логіка `ubifs.c` не копіює нічого в /jffs.
**Це і є основа патчу.** (Джерельний `#else` уже є — жодної правки C не потрібно.)

### (б) Правки шляхів у 5 файлах джерел — точкові, низький ризик

Див. патч `jffs-to-tmp.patch` (7 хюнків): `httpd/common.h` (3 `#define`),
`httpd/web.c` (читання security_recored), `rc/common.c` (3 tgz-шляхи),
`rc/watchdog.c` (4 сайти cfg_dbg.log), `aaews/common.h` (1 `#define`),
`rom/webs_scripts/ssl_webs_download.sh` (1 `touch`).

### (в) Те, що не має прапорця або зашите в prebuild

- `debuglog_*.tgz` (пп.5), `KEEP_UPGRADE_DEBUG.log` (пп.12), `cfg_dbg.log` у watchdog (пп.10) —
  не мають прапорця, правляться напряму (вже в патчі);
- `web_hook.o`, `asd`, `aaews/mastiff`, `amas-ssd`, `private.o`, `dsl_fb.o` — **prebuild без джерел**:
  варіанти: (1) прийняти як є (усе це дрібні debug-логи та логи AiProtection,
  крім `security_recored.log`); (2) бінарний патч (`sed` зашитих рядків `/jffs/…` → `/tmp/…`
  тієї самої довжини, напр. `/tmp//…`, під час збірки); (3) не чіпати, бо /jffs-запис мінімальний.
  Рекомендую варіант (1)/(3) — з увімкненим PSISTLOG вимкнено prebuild-логи не стає менше,
  але головний навантажувач (syslogd) уже перенесено.

---

## 4. Патч

Файл: **`/opt/data/cache/scratch/merlin-find/b/jffs-to-tmp.patch`**

Застосування (перевірено на цьому дереві: `git apply` → OK, дерево відкочено):

```sh
cd /opt/data/cache/scratch/merlin
git apply --check /opt/data/cache/scratch/merlin-find/b/jffs-to-tmp.patch   # dry-run
git apply      /opt/data/cache/scratch/merlin-find/b/jffs-to-tmp.patch
# відкат:
git checkout -- release/src-rt/target.mak release/src/router/httpd/common.h \
  release/src/router/httpd/web.c release/src/router/rc/common.c \
  release/src/router/rc/watchdog.c release/src/router/aaews/common.h \
  release/src/router/rom/webs_scripts/ssl_webs_download.sh
```

Префікси в патчі — `a/release/...`, тобто застосовується з **кореня репозиторію**
(з каталогу `release/` — `patch -p2` / `git apply --directory=..`).
Примітка: `release/src-rt-5.04behnd.4916/target.mak` — це symlink на `../src-rt/target.mak`,
тому в патчі правиться реальний файл `release/src-rt/target.mak`.

Зміст (коротко):

```diff
--- a/release/src-rt/target.mak
@@ -405,2 +405,2 @@ export HND-96765_BASE := ... UBI=y UBIFS=y PSISTLOG=y CABLEDIAG=y
-		CONNDIAG=y SAMBA3="3.6.x" OOKLA=y WL_SCHED_V3=y UBI=y UBIFS=y PSISTLOG=y CABLEDIAG=y
+		CONNDIAG=y SAMBA3="3.6.x" OOKLA=y WL_SCHED_V3=y UBI=y UBIFS=y CABLEDIAG=y
--- a/release/src/router/httpd/common.h
-#define HTTPD_DEBUG_FILE   "/jffs/HTTPD_DEBUG.log"        → "/tmp/HTTPD_DEBUG.log"
-#define SECURITY_LOG_FILE  "/jffs/security_recored.log"   → "/tmp/security_recored.log"
-#define HTTPD_FB_DEBUG_FILE "/jffs/HTTPD_FB_DEBUG.log"    → "/tmp/HTTPD_FB_DEBUG.log"
--- a/release/src/router/httpd/web.c (2779-2784)
-  "/jffs/%s-1", "/jffs/%s"   → "/tmp/%s-1", "/tmp/%s"     (читання security_recored)
--- a/release/src/router/rc/common.c (1829-1831)
-#define DEBUGLOG_KLOG_PATH "/jffs/debuglog_klog.tgz"      → "/tmp/debuglog_klog.tgz"
-#define DEBUGLOG_CORE_PATH "/jffs/debuglog_core.tgz"      → "/tmp/debuglog_core.tgz"
-#define DEBUGLOG_SLOG_PATH "/jffs/debuglog_slog.tgz"      → "/tmp/debuglog_slog.tgz"
--- a/release/src/router/rc/watchdog.c (9950,9958,9971,9979)
-CFG_MNT_FOLDER"cfg_dbg.log"   → "/tmp/cfg_dbg.log"        (4 сайти)
--- a/release/src/router/aaews/common.h (81)
-#define AAE_DBG_LOG "/jffs/aae.log"                       → "/tmp/aae.log"
--- a/release/src/router/rom/webs_scripts/ssl_webs_download.sh (89)
-touch /jffs/KEEP_UPGRADE_DEBUG.log                        → /tmp/KEEP_UPGRADE_DEBUG.log
```

Повний unified-diff із контекстом — у файлі патчу (згенеровано `diff -u` з копій,
кожна заміна верифікована лічильником, `git apply --check` + повне застосування + відкат пройдені).

---

## 5. Ризики та побічні ефекти

| Зміна | Що втрачається / ламається | Оцінка |
|---|---|---|
| `PSISTLOG` вимкнено | **Логи не переживають ребут** (`/tmp` — tmpfs). Головний мінус і водночас мета. Syslog UI показує той самий `/tmp/syslog.log` — консистентно | прийнято свідомо |
| `PSISTLOG` вимкнено | `/jffs/syslog.log` більше не оновлюється; старі файли залишаться на місці (не видаляються). FCS/`jffs.json`-менеджер резерву (Hard Limit 256 КБ×2) більше не застосовний до syslog | дрібне сміття |
| `PSISTLOG` вимкнено | crashlog: для BE92U він уже у `/tmp/crashlog.log` (`init.c:26733-26740`, `mmc_export_crashlog` з prebuild `broadcom.o`: `mv %s /tmp/crashlog.log`), тобто crashlog **не залежить** від PSISTLOG і залишається як є | без змін |
| `debuglog_*.tgz` → /tmp | `collect_debuglog` (Advanced_Feedback) пакує у /tmp; завантаження feedback іде через rc/httpd послідовно в одному сеансі — /tmp достатньо. Якщо пристрій перезавантажиться між пакуванням і відправкою — архів зникне | мінімально |
| `security_recored.log` → /tmp | журнал входів більше не зберігається після ребуту; **обов'язково** правити разом із web.c:2779-2784 (в патчі зроблено), інакше UI-сторінка журналу стане порожньою. Крім того, prebuild `web_hook.o` продовжить писати у `/jffs/security_recored.log` — після патчу UI показуватиме `/tmp`-копію, а частини записів від web_hook залишаться в /jffs: **фрагментація журналу** | головний компроміс (б) |
| `HTTPD_DEBUG.log`/`HTTPD_FB_DEBUG.log` → /tmp | debug-логи httpd втрачаються після ребуту; самі логи вмикаються лише тригером (`/tmp/HTTPD_DEBUG` або `nvram HTTPD_DBG`) | дрібне |
| `cfg_dbg.log` → /tmp | діагностика AiMesh/onboarding після ребуту недоступна; крім того, `private.o`/`dsl_fb.o` (prebuild) продовжать писати у `/jffs/.sys/cfg_mnt/` — лог роз'їдеться на два місця | дрібне |
| `aae.log` → /tmp | для BE92U **неефективно** (aaews — prebuild із зашитим `/jffs/aae.log`); правка потрібна лише для моделей з джерельним aaews | нешкідливо |
| `KEEP_UPGRADE_DEBUG.log` → /tmp | прапорець діагностики оновлення; втрата після ребуту не критична | дрібне |

**Читання /jffs-логів у веб-UI:** єдиний споживач — `httpd/web.c:2779-2784`
(сторінка перегляду security_recored) та `web.c:2591` (`get_logfile_path` → слідує прапорцю сам).
`www/*.asp` жорстких `/jffs/*.log`-читань не мають (grep по www — чисто), тобто крім вищезгаданого
dump-хендлера перенесення нічого в UI не ламає.

**Що НЕ варто чіпати:** `log_path` (nvram-дефолт `/jffs`, `defaults.c:3393`) — використовується
лише мертвим для BE92U `jffs2.c:535`; `jffs.json` — дескриптор, не письменник;
`/jffs/scripts`, `/jffs/configs` — не логи.

---

## 6. Build-time кроки, що пишуть у /jffs

Перевірено `grep -rn "/jffs"` по `src-rt/{Makefile,target.mak,make.hndrt,build/*.mk,targets/**}`
і `router/{Makefile,*/Makefile,rom/Makefile}`: **логів на етапі збірки в /jffs не пишеться**.
Єдині згадки — описи розділів (`targets/arch/sysdeps/*/DEFAULT_partitions.cfg`,
`PARTITION_MNT_POINT=/jffs`) та `router/rom/rom/jffs.json` (дескриптор). Скрипт
`rom/webs_scripts/ssl_webs_download.sh:89` виконується на пристрої (оновлення SSL/SQ),
не під час збірки.

---

## 7. Підсумок

1. Найдешевший і головний крок — **прибрати `PSISTLOG=y` з `HND-96765_BASE`** в
   `src-rt/target.mak:406`: це переносить syslogd у /tmp без жодної правки C-коду.
2. П'ять дрібних правок джерел (httpd/common.h ×3, web.c ×2 рядки, rc/common.c ×3,
   rc/watchdog.c ×4 сайти, aaews/common.h, ssl_webs_download.sh) закривають усе інше,
   що компілюється з джерел для BE92U.
3. Залишається prebuild-«хвост» (`web_hook.o`, `asd`, `aaews/mastiff`, `amas-ssd`, `private.o`,
   `dsl_fb.o`) із зашитими `/jffs`-шляхами — джерельно не правиться; на навантаження /jffs
   впливає слабо (syslogd був головним).
4. Головні втрати — логи, що не переживають ребут (syslog, security_recored, debuglog-архіви,
   cfg_dbg), і фрагментація `security_recored.log` між /jffs (prebuild web_hook.o) та /tmp (web.c).
