---
title: Sicherheitsmodell
audience: Admin
outline: https://docs.bashclub.org/doc/sicherheitsmodell-vbQtnUNxxO
outline_id: 731d0006-51e8-4120-8e4d-f593ab5670c5
---
Ein Backup muss den Fall überstehen, für den es da ist: Die Quelle ist verloren, kaputt oder in fremder Hand. Daraus
folgen die Regeln, nach denen zsync gebaut ist.

## Grundsatz: Die Quelle zerstört nie das Backup
Nichts, was auf der Quelle passiert, löscht Backups auf dem Backupserver. Das gilt auch, wenn ein Angreifer die Quelle
übernommen hat:

| Was auf der Quelle passiert | Was zsync tut |
|---|---|
| Snapshots werden gelöscht | Mit fester Anzahl je Label (ab 2.0, z. B. `daily=30`) bleiben die Snapshots auf dem Backupserver. |
| Ein Dataset wird gelöscht oder nicht mehr ausgewählt | Das Replikat bleibt, Checkmk warnt (ab 2.0). |
| Rollback auf einen alten Snapshot | Ab 2.0 bleibt die alte Kette als eigenes Dataset erhalten, die Replikation läuft auf einer neuen Kette weiter. |
| Alle gemeinsamen Snapshots gelöscht (Kette gerissen) | zsync überträgt nicht neu über das alte Replikat, sondern meldet CRIT. |
| Daten werden verschlüsselt (Ransomware) | Die neuen Snapshots kommen dazu, die alten bleiben nach den Regeln der Aufbewahrung. |

Was mit solchen Replikaten passiert, entscheidet der Admin auf dem Backupserver, nicht die Quelle und nicht zsync
selbst.

## Der Admin entscheidet, zsync führt aus
Ab 2.0 meldet zsync jeden Fall, der eine Entscheidung braucht, an Checkmk und markiert ihn am Replikat.
`bashclub-zsync-maintenance` zeigt alle offenen Fälle, die Optionen und die genauen Befehle, auch was ein Löschen
mitnehmen würde. Erst nach einer Bestätigung führt es die Aktion aus und protokolliert sie mit Zeit und Benutzer.
Fälle sind:
- Replikat ohne Dataset auf der Quelle: behalten oder löschen
- Kette gerissen: altes Replikat umbenennen (behalten) oder löschen, danach überträgt der nächste Lauf neu
- alte Kette nach einem Rollback: als Archiv behalten oder löschen
- Snapshots mit dem Label in fremdem Namensschema: löschen

Alle Fälle können auch warten. Solange sie offen sind, warnt Checkmk.

## Pull: Die Quelle hat keinen Schlüssel zum Backup
Der Backupserver meldet sich an der Quelle an, nie umgekehrt (siehe [Architektur](02-architektur.md)). Auf der Quelle
liegt kein Schlüssel, der zum Backupserver führt.

Bei lokaler Replikation liegen Quelle und Replikate auf demselben Host. Wer ihn übernimmt, erreicht beide. Schutz
bietet dort ein Wechseldatenträger, der nur während des Laufs angeschlossen ist, oder zusätzlich eine entfernte
Replikation auf einen zweiten Host.

## Betrieb ohne root
Ab 2.0 braucht zsync root weder auf dem Backupserver noch auf der Quelle. Jeder Benutzer bekommt nur die ZFS-Rechte,
die er braucht (`zfs allow`).

**Auf dem Backupserver** läuft jede Replikation als eigener Benutzer (`run_as`, z. B. `zsync-pve1`):
- ZFS-Rechte nur auf ihr Target, nicht auf andere Datasets
- das Target hat `mountpoint=none`, das der Benutzer nicht ändern darf: Kein Replikat wird mit Inhalten eingehängt, die
  ein Benutzer ohne root empfangen hat
- Properties, die bestimmen, ob und wie root ein Replikat einhängt (`mountpoint`, `canmount`, `setuid`, `exec`,
  `devices`), darf er nicht setzen; ihre Werte der Quelle merkt sich das Replikat für eine Wiederherstellung

**Auf der Quelle** hat jede Replikation einen eigenen Benutzer (`zsync-<job>`, Paket `bashclub-zsync-source`):
- sein SSH-Schlüssel gilt nur von der Adresse seines Backupservers (`from=`)
- er kann keine Shell öffnen: `bashclub-zsync-remote` (`command=`) lässt nur die Befehle von zsync zu
- er darf nur die Datasets mit dem Tag seiner Config lesen
- er löscht nur Snapshots seines eigenen Labels und nutzt nur seinen eigenen Hold und Bookmark; die Snapshots anderer
  Werkzeuge und anderer Backupserver kann er nicht löschen
- abgelehnte Befehle enden mit Exit-Code 126 und stehen im Syslog: `journalctl -t bashclub-zsync-remote`

Der Verwaltungsbenutzer `zsync` auf der Quelle darf per sudo nur diese Job-Benutzer anlegen und entfernen
(`bashclub-zsync-job-user`). So braucht auch die Einrichtung keinen root-Zugang zur Quelle.

:::info
**Geändert in 2.0:** Bis 1.0.19 meldete sich der Backupserver als root an der Quelle an. Wer den Backupserver übernahm,
hatte damit root auf allen Quellen. Bestehende Configs laufen nach dem Update unverändert als root weiter.
`bashclub-zsync-setup` richtet neue Replikationen ohne root ein; bestehende lassen sich umstellen.
:::

## Zugang für eine Wiederherstellung
Ab 2.0, Paket `bashclub-zsync-restore`:
- **Pull:** Das System, das wiederhergestellt wird, liest vom Backupserver. Sein Benutzer darf nur die Replikate einer
  Config lesen (`send`, `hold`, `release`), nichts löschen, umbenennen oder empfangen.
- **Push:** Der Backupserver schreibt auf das System, mit einem Einmal-Schlüssel, der nach wenigen Tagen abläuft und
  nur vom Backupserver aus gilt. Nie mit dem Schlüssel einer Replikation.

## Was bleibt
- Der Backupserver ist das wertvollste System: Wer ihn übernimmt, hat alle Backups. Er gehört in ein eigenes Netz,
  ohne Dienste nach außen, mit eigenen Zugangsdaten.
- Eine Config ist ein Shell-Skript, das als root oder als ihr Benutzer läuft. Nur root darf `/etc/bashclub` und die
  Configs schreiben. Der Checkmk-Check (läuft als root) liest eine Config nicht, die andere schreiben dürfen.
- Mit fester Anzahl je Label kann ein Angreifer auf der Quelle ältere Snapshots durch viele neue verdrängen. Wie
  viele Snapshots ein Label behält, sollte deshalb großzügig gewählt sein; Checkmk meldet ungewöhnlich viele Snapshots
  über checkzfs.
