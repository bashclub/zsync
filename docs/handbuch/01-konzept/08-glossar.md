---
title: Glossar
audience: Anwender, Admin
outline: https://docs.bashclub.org/doc/glossar-EldhNCFEHV
outline_id: 88e2c31f-cf26-4a68-8e83-59a7f93945b8
---
**Backupserver** – der Host, auf dem `bashclub-zsync` läuft und die Replikate liegen. Er holt die Daten von der
Quelle ab.

**Bookmark** – Lesezeichen auf einen Snapshot ohne Daten. Ab 2.0 setzt zsync einen auf der Quelle, damit die
Replikation auch dann weitergeht, wenn der Snapshot dort schon gelöscht ist.
Siehe [ZFS-Grundlagen](03-zfs-grundlagen.md#bookmark).

**Config** – Datei in `/etc/bashclub/`, z. B. `pve1.conf`, mit allen Einstellungen einer Replikation: Quelle,
Target, Auswahl, Aufbewahrung, Monitoring.

**Dataset** – ein ZFS-Dateisystem oder -Volume, z. B. die Disk einer VM (`rpool/data/vm-100-disk-0`).

**Engine** – das Werkzeug, das die Snapshots von zsync anlegt: `internal` (`remote-snapshot-manager`) oder `zas`
(`zfs-auto-snapshot`). Siehe [Snapshots und Aufbewahrung](05-snapshots-und-aufbewahrung.md).

**Erstreplikation** – die erste, vollständige Übertragung eines Datasets.

**Gemeinsamer Snapshot** – ein Snapshot, den Quelle und Replikat mit derselben GUID haben. Nur von ihm aus geht eine
inkrementelle Übertragung.

**GUID** – eindeutige Nummer eines Snapshots, auf Quelle und Replikat gleich.

**Hold** – Sperre gegen das Löschen eines Snapshots. Ab 2.0 hält zsync die Snapshots, die es gerade überträgt.

**Hook** – eigenes Skript, das ab 2.0 vor oder nach einem Lauf startet (`/etc/bashclub/hooks.d/`).

**Job-Benutzer** – ab 2.0 ein eigener Benutzer je Replikation: `zsync-<name>` auf dem Backupserver,
`zsync-<backupserver>-<name>` auf der Quelle. Er hat nur die Rechte, die diese Replikation braucht.

**Kette** – die Folge der Snapshots eines Datasets. Sie ist **gerissen**, wenn Quelle und Replikat keinen gemeinsamen
Snapshot mehr haben, und **in Gefahr**, wenn die nächste Rotation auf der Quelle den letzten gemeinsamen löscht.

**Label** – Teil des Snapshot-Namens, der seine Art bezeichnet, z. B. `daily` in
`zfs-auto-snap_daily-2026-10-19-0000`. `snapshot_filter` wählt Snapshots über ihr Label aus.

**Lauf** – ein Aufruf von `bashclub-zsync` mit einer Config: Snapshots, Übertragung, Rotation, Monitoring.

**Lokaler Modus** – ab 2.0 Replikation zwischen Pools desselben Hosts ohne SSH (`source=local`).

**Pull** – der Backupserver holt die Daten ab. Gegenteil: Push, die Quelle liefert. zsync repliziert nur per Pull.

**Quelle** – der Host, dessen Datasets gesichert werden, z. B. ein Proxmox-Server.

**Replikat** – die Kopie eines Datasets auf dem Backupserver, unter dem Target, z. B.
`backup/pve1/rpool/data/vm-100-disk-0`.

**Resume** – Fortsetzen einer abgebrochenen Übertragung. Ab 2.0 mit `transfer_resume=1`.

**Rollback** – ein Dataset auf einen älteren Snapshot zurücksetzen; neuere Snapshots gehen dabei verloren. Ab 2.0 hebt
zsync die alte Kette auf dem Backupserver auf.

**Rotation** – das Löschen alter Snapshots nach den Regeln der Aufbewahrung, auf der Quelle wie auf dem Backupserver.

**Snapshot** – schreibgeschützter Stand eines Datasets zu einem Zeitpunkt.

**Spool** – Ordner des Checkmk-Agenten (`/var/lib/check_mk_agent/spool/`). Dateien darin liefert der Agent bei jeder
Abfrage mit aus.

**Tag** – die ZFS-Property, mit der Datasets auf der Quelle ausgewählt werden, Standard `bashclub:zsync`.
Siehe [Auswahl der Datasets](04-auswahl-der-datasets.md).

**Target** – das Dataset auf dem Backupserver, unter dem die Replikate einer Config liegen (`target` in der Config).

**Verwaistes Replikat** – Replikat, dessen Dataset es auf der Quelle nicht mehr gibt oder das nicht mehr ausgewählt
ist. Es wird nie automatisch gelöscht.
