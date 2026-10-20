---
title: Häufige Fragen
audience: Anwender, Admin
outline: https://docs.bashclub.org/doc/haufige-fragen-xm1g70gTDd
outline_id: 558fa8b0-23d7-46b2-9bee-72d4a4dfd920
---
## Warum holt der Backupserver ab, statt dass die Quelle schickt?
Damit die Quelle keinen Zugang zum Backup hat. Wer die Quelle übernimmt, etwa mit Ransomware, findet dort keinen
Schlüssel, mit dem er die Backups lesen oder löschen könnte. Bei Push läge dieser Schlüssel auf der Quelle. Der
Backupserver selbst ist ab 2.0 auf der Quelle eingeschränkt: Sein Benutzer darf nur die Befehle von zsync ausführen, nur
die ausgewählten Datasets lesen und nur von seiner Adresse aus. Mehr in [Architektur](../01-konzept/02-architektur.md)
und [Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md).

## Ist das Replikat ein Spiegel der Quelle?
Nur so weit, wie es eingestellt ist. Ein reiner Spiegel übernähme jede Änderung, auch die schlechten: gelöschte
Snapshots, ein Rollback, eine verschlüsselte Platte. zsync folgt beim Löschen von Snapshots der Quelle, wenn
`snapshot_filter` Labels ohne Zahl hat; einen Rollback oder ein gelöschtes Dataset übernimmt es nie. zsync überträgt jeden Snapshot einzeln (`zfs send -i`), nicht den ganzen Stand der Quelle (`zfs send -R`), und löscht
auf dem Backupserver nach eigenen Regeln (`snapshot_filter`). `zfs receive -F` setzt dabei nur das Replikat auf seinen
eigenen neuesten Snapshot zurück, bevor der nächste ankommt; Snapshots, die es auf der Quelle nicht mehr gibt, löscht es
nicht. Mit einer festen Anzahl je Label (`daily=30`, ab 2.0) bleiben die Snapshots auf dem Backupserver, egal was die
Quelle löscht. Siehe [Snapshots und Aufbewahrung](../01-konzept/05-snapshots-und-aufbewahrung.md).

## Was passiert bei einem Rollback auf der Quelle?
Ab 2.0 setzt zsync die Replikation auf einer neuen Kette fort und behält die alte als
`<replikat>.zsync-branch-<datum>`. Checkmk warnt, bis der Admin mit `bashclub-zsync-maintenance` entscheidet: behalten
(Archiv) oder löschen. War der Rollback nicht gewollt, enthält die alte Kette die Stände vor dem Rollback; siehe
[Ransomware und Angriffe](../05-restore/07-ransomware.md). Bis 1.0.19 brach die Replikation des Datasets bei jedem Lauf
ab.

Soll die Quelle nach einem versehentlichen Rollback die neueren Stände zurückbekommen, ohne dass eine neue Kette
entsteht: [Nach einem Rollback wieder anfügen](../05-restore/05-reattach.md).

## Was passiert, wenn auf der Quelle eine VM gelöscht wird?
Nichts am Backup. Das Replikat bleibt mit allen Snapshots; nach einem Tag meldet Checkmk es als Replikat ohne Quelle.
Mit `bashclub-zsync-maintenance` behalten oder löschen.

## Wie viel Platz brauche ich auf dem Backupserver?
Etwa so viel, wie die Datasets auf der Quelle belegen (die Kompression bleibt erhalten), plus die Änderungen, die die
Snapshots festhalten. Wie viel das ist, hängt von der Änderungsrate und der Aufbewahrung ab; ein guter Anhalt ist, was
die Snapshots auf der Quelle heute belegen (`zfs list -o name,used,usedbysnapshots`), hochgerechnet auf die längere
Aufbewahrung des Backupservers. Dazu kommen alte Ketten und Replikate ohne Quelle, bis jemand entscheidet. Siehe
[Platz planen](../04-betrieb/05-platz.md).

## Kann ich eine Datei aus dem Backup holen, ohne alles zurückzuspielen?
Ja, ab 2.0 mit `bashclub-zsync-restore mount`: Es hängt einen Snapshot schreibgeschützt ein, bei VM-Disks auch die
Partitionen. Siehe [Einzelne Dateien zurückholen](../05-restore/01-einzelne-dateien.md).

## Sind verschlüsselte Datasets auf dem Backupserver lesbar?
Nein. zsync überträgt raw (`zfs send -w`); die Daten bleiben verschlüsselt, der Schlüssel verlässt die Quelle nie. Für
eine Wiederherstellung reicht das: Das Replikat geht verschlüsselt zurück, auf dem Ziel wird der Schlüssel geladen. Zum
Einhängen auf dem Backupserver muss der Schlüssel dort geladen werden. Siehe
[Verschlüsselte Datasets](../03-szenarien/08-verschluesselung.md).

## Muss zsync als root laufen?
Ab 2.0 nicht, weder auf dem Backupserver noch auf der Quelle. Neue Replikationen aus `bashclub-zsync-setup` laufen als
eigene Benutzer mit Rechten nur auf ihr Target; bestehende lassen sich umstellen. Siehe
[Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md).

## Brauche ich checkzfs?
Ab 2.0 nicht mehr. Die Services je Dataset erzeugt zsync auch selbst (`monitor_engine=internal`, Default neuer
Configs), mit denselben Namen und Schwellwerten. Bestehende Configs bleiben bei checkzfs, solange es installiert ist.
Siehe [Monitoring-Konzept](../01-konzept/07-monitoring-konzept.md).

## Wie unterscheidet sich zsync von syncoid, zrepl oder Proxmox Backup Server?
Alle haben ihren Platz; die Unterschiede in Kürze:

| | zsync | syncoid (sanoid) | zrepl | Proxmox Backup Server |
|---|---|---|---|---|
| Prinzip | ZFS-Replikation | ZFS-Replikation | ZFS-Replikation | Backup in einen eigenen, deduplizierten Speicher |
| Richtung | Pull vom Backupserver | Push oder Pull, ein Befehl je Aufruf | Push oder Pull, als Dienst | Client sichert zum Server |
| Auswahl | ZFS-Property auf der Quelle | Datasets im Aufruf | Filter in der Config | VMs und Container in Proxmox |
| Löschen am Ziel | eigene Regeln je Label, nie automatisch nach Rollback oder Löschen auf der Quelle | über sanoid am Ziel oder optional nach der Quelle | eigene Regeln je Seite | Prune-Regeln je Datastore |
| Überwachung | Checkmk-Services | Checks von sanoid für Nagios | Prometheus | eigene Oberfläche und Benachrichtigung |
| braucht ZFS auf der Quelle | ja | ja | ja | nein |

zsync ist für Proxmox mit ZFS gebaut und ergänzt eher einen Proxmox Backup Server, als ihn zu ersetzen: Die Replikate
sind sofort benutzbare ZFS-Datasets mit allen Snapshots, auch alle 15 Minuten, und lassen sich mit `zfs send`
zurückspielen. Ein Proxmox Backup Server sichert unabhängig vom Speicher der Quelle und hält Sicherungen lange und
platzsparend.
