# Патчі

Наші зміни до дерева merlin. Накладаються **останніми**, після cherry-pick і блобів.

| файл | що робить |
|---|---|
| `jffs-to-tmp.patch` | логи `/jffs` → `/tmp`, щоб не зношувати NAND (розбір — `jffs-to-tmp.md`) |
| `regulatory-db-lib-firmware.patch` | `regulatory.db` у `rom/rom/lib/firmware` |
| `busybox-httpd.patch` | busybox `httpd` у збірці |
| `optional/no-asd-ark.patch` | вирізати `ark_service` і `asd`; вмикається окремо, не за замовчуванням |

Правила й крихкість кожного — `docs/rt-be92u-notebook.md`, §2.
