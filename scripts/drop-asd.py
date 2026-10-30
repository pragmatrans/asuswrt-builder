#!/usr/bin/env python3
"""ASD=n для RT-BE92U поверх no-asd-ark.patch.

Навіщо: no-asd-ark.patch лишає ASD=y (він тягне RTCONFIG_LIBASC → libasc.so, яку
rc лінкує через -lasc). Цей скрипт прибирає і сам ASD, і залежність від його
прапорця:

  1. у блоці `export RT-BE92U ...` міняє ASD=y → ASD=n;
  2. у release/src/router/Makefile робить libasc безумовним:
     `obj-$(RTCONFIG_LIBASC) += libasc` → `obj-y += libasc`.
     Без цього libcreduction падає: «Missing 32-bit libraries: libasc.so».
  3. asd-install у no-asd-ark.patch уже заглушений, тож з ASD=n демон просто
     не збирається — і в образі його теж немає.

Використання: drop-asd.py <корінь дерева merlin>
"""
import os
import re
import sys

BLOCK_START = "export RT-BE92U :="
BLOCK_CONT = "export RT-BE92U +="


def find_target_mak(root):
    release = os.path.join(root, "release")
    for name in sorted(os.listdir(release)):
        if name.startswith("src-rt-") and os.path.isdir(os.path.join(release, name)):
            p = os.path.join(release, name, "target.mak")
            if os.path.isfile(p):
                return p
    raise SystemExit("target.mak не знайдено під %s/release/src-rt-*/" % root)


def drop_asd(root):
    p = find_target_mak(root)
    lines = open(p, encoding="utf-8", errors="surrogateescape").read().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith(BLOCK_START))
    end = next(
        i
        for i in range(start + 1, len(lines))
        if lines[i].startswith("export ") and not lines[i].startswith(BLOCK_CONT)
    )
    changed = 0
    for i in range(start, end):
        if re.search(r"\bASD=y\b", lines[i]):
            lines[i] = re.sub(r"\bASD=y\b", "ASD=n", lines[i])
            changed += 1
    if not changed:
        raise SystemExit("ASD=y не знайдено в блоці RT-BE92U (%s)" % p)
    open(p, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(lines))
    print("target.mak: ASD=n у рядках блоку RT-BE92U (%d)" % changed)

    mk = os.path.join(root, "release", "src", "router", "Makefile")
    s = open(mk, encoding="utf-8", errors="surrogateescape").read()
    old = "obj-$(RTCONFIG_LIBASC) += libasc"
    new = (
        "# libasc лінкує rc через -lasc незалежно від ASD; тримаємо її безумовно,\n"
        "# інакше при ASD=n libcreduction не знаходить libasc.so.\n"
        "obj-y += libasc"
    )
    if os.environ.get("DROP_ASD_ALREADY") != "1":
        if s.count(old) != 1:
            raise SystemExit("у router/Makefile не знайдено '%s'" % old)
        open(mk, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old, new))
        print("router/Makefile: libasc тепер obj-y")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    drop_asd(sys.argv[1])
