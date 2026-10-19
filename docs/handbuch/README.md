# Handbuch bashclub-zsync: Regeln für Autoren

Das Handbuch entsteht hier im Repo und wird nach Outline veröffentlicht:
https://docs.bashclub.org/collection/bashclub-zsync-MKfiJIBPou

**Git ist die Quelle.** Änderungen direkt in Outline werden beim nächsten Veröffentlichen überschrieben. Jede Seite
in Outline endet mit einem Link auf ihre Datei hier.

## Aufbau
- Ein Ordner je Bereich (`01-konzept`, `02-installation`, …), die Nummer bestimmt die Reihenfolge.
- `_index.md` im Ordner ist die Seite des Bereichs in Outline, die Artikel des Ordners hängen darunter.
- Artikel heißen `NN-name.md`, die Nummer bestimmt die Reihenfolge im Bereich.

Jede Datei beginnt mit einem Kopf:
```
---
title: Architektur und Ablauf eines Laufs
audience: Admin
outline:
---
```
- `title`: Titel in Outline. Der Text beginnt ohne Überschrift erster Ebene (`#`), Outline zeigt den Titel selbst.
- `audience`: `Anwender`, `Admin` oder `Anwender, Admin`.
- `outline`, `outline_id`: Adresse und ID der Seite in Outline, beim ersten Veröffentlichen eingetragen.

## Versionen
Das Handbuch beschreibt 2.0 und alles danach. Eine Historie zu 1.0 gibt es nicht.

- **Neue Funktionen** nennen die Version, mit der sie kamen, im ersten Satz des Abschnitts: „Ab 2.0 …“.
  Was es schon in 1.0 gab, bekommt keinen Vermerk.
- **Geänderter Betrieb** gegenüber einer früheren Version steht in einer Hinweisbox, mit dem alten und dem neuen
  Verhalten und was der Admin tun muss (oder dass er nichts tun muss):
  ```
  :::info
  **Geändert in 2.0:** Bis 1.0.19 … Ab 2.0 … Bestehende Configs …
  :::
  ```
  Für 1.0 nur dort, wo sich der Betrieb ändert; Änderungen ohne Folgen für den Betrieb stehen im CHANGELOG.
- **Spätere Versionen** ergänzen den Text, statt ihn zu ersetzen: „Ab 2.1 …“ bzw. „Geändert in 2.1: …“. Wer eine
  ältere Version betreibt, muss erkennen, was für ihn gilt.
- **Legacy-Default und neuer Default** werden unterschieden, wo sie verschieden sind: was eine bestehende Config
  ohne den Parameter tut und was `bashclub-zsync-setup` für neue Configs schreibt.

## Befehle
- **Copy & Paste-fest:** keine Platzhalter wie `<pool>` und kein „ersetze X“. Werte, die das System liefert,
  ermittelt der Befehl selbst (z. B. `$(. /etc/os-release && echo "$VERSION_CODENAME")`, Werte aus der Config per
  `( . "$conf"; … )`). Wo der Admin einen Wert wählen muss, steht er als Variable in der ersten Zeile des Blocks.
- Codeblöcke mit Sprache (`bash`), ein Befehl pro Zeile, Ausgaben getrennt davon.
- Befehle, die etwas löschen, zuerst als Probelauf (`-n`, `--dry-run`).
- Snippets werden vor dem Veröffentlichen in einem Container oder auf der Test-VM ausgeführt.

## Sprache und Stil
- Deutsch zuerst; die englische Collection folgt, wenn die deutschen Artikel stehen.
- Kurze Sätze, eine Aussage pro Satz, Fachbegriffe beim ersten Auftreten erklären (siehe Glossar).
- Programme, Parameter, Dateien und Properties in `Code`.

## Links
- Auf andere Artikel relativ verlinken: `[Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md)`, auch mit Anker
  (`…md#abschnitt`). Beim Veröffentlichen werden daraus die Adressen in Outline.
- Auf Tickets mit voller Adresse, nur wenn sie dem Leser weiterhelfen.

## Veröffentlichen
`render.py` bereitet eine Datei für Outline auf (Kopf entfernt, Links auf Outline-Adressen, Hinweis auf die Quelle
am Ende):
```bash
docs/handbuch/render.py list
docs/handbuch/render.py render docs/handbuch/01-konzept/02-architektur.md
```
Ein neuer Artikel wird zuerst angelegt und seine Adresse in `outline:` eingetragen, danach werden Links auf ihn
aufgelöst. Links auf noch nicht veröffentlichte Artikel bricht `render` ab (`--allow-missing` lässt nur den Text
stehen).

## Prüfung
`tests/handbuch.sh` läuft in der CI: Jeder Parameter mit Default in `bashclub-zsync` braucht einen Abschnitt und eine
Zeile in der Übersicht der Referenz (`06-referenz/01-konfigurationsparameter.md`), jedes Programm aus den Paketen einen
Abschnitt `` ## `name` `` in der Referenz, und jeder Artikel muss sich aufbereiten lassen. Die Referenz wird von Hand
gepflegt; die Prüfung fällt auf, wenn ein neuer Parameter oder ein neues Programm fehlt.

## Definition of Done
Ein Feature-Ticket aktualisiert die betroffenen Artikel (Konzept, Referenz, Szenario, Migration) im selben PR, mit
Versionsvermerk.
