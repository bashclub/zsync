# Handbuch bashclub-zsync: Regeln für Autoren

Das Handbuch entsteht hier im Repo und wird nach Outline veröffentlicht:
- öffentlich, ohne Login: https://docs.bashclub.org/s/bashclub-zsync
- mit Login (für Autoren beim Veröffentlichen): https://docs.bashclub.org/collection/bashclub-zsync-MKfiJIBPou

**Git ist die Quelle.** Änderungen direkt in Outline werden beim nächsten Veröffentlichen überschrieben. Jede Seite
in Outline endet mit einem Link auf ihre Datei hier.

## Aufbau
- Ein Ordner je Bereich (`01-konzept`, `02-installation`, …), die Nummer bestimmt die Reihenfolge.
- `_index.md` im Ordner ist die Seite des Bereichs in Outline, die Artikel des Ordners hängen darunter.
- Artikel heißen `NN-name.md`, die Nummer bestimmt die Reihenfolge im Bereich.
- `_collection.md` ist die Beschreibung der Collection (Startseite des Handbuchs mit der Liste der Kapitel). Ein neuer
  Bereich kommt dort dazu.

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
`render.py` bereitet eine Datei für Outline auf: Kopf entfernt, Links auf Outline-Adressen, am Ende ein Link
„Weiter“ auf den nächsten Artikel in der Reihenfolge von `render.py list` (nach dem letzten Artikel eines Bereichs der
nächste Bereich), der Hinweis auf die Quelle; davor der Ko-fi-Block (Tabelle mit einer zentrierten Spalte:
`kofi-block.png` mit Frage und Knopf, darunter der Link). Die Bilder (`kofi-block.png`, `kofi-button.png`, englisch
`kofi-button-en.png` für die README) zeichnet `kofi-button.py` im Stil des Ko-fi-Widgets, mit Text, Farbe und Frage
als Argumenten. Aufbereiten:
```bash
docs/handbuch/render.py list
docs/handbuch/render.py render docs/handbuch/01-konzept/02-architektur.md
```
Ein neuer Artikel wird zuerst angelegt und seine Adresse in `outline:` eingetragen, danach werden Links auf ihn
aufgelöst. `_collection.md` geht ohne den Hinweis am Ende in die Beschreibung der Collection. Ein neuer, verschobener
oder umbenannter Artikel ändert den Link „Weiter“ seines Vorgängers: den Vorgänger mit veröffentlichen.

Reihenfolge: Outline setzt neue Seiten an eine beliebige Stelle ihrer Ebene (meist an den Anfang). Nach dem Anlegen
deshalb **alle** Seiten des betroffenen Bereichs und den Bereich selbst an ihre Position schieben, nicht nur die neue
Seite; eine Seite in der Mitte verschiebt die folgenden. `render.py list` liefert dafür je Zeile in Spalte 5 die
Position (0-basiert, `index` von `move_document`), in Spalte 6 die eigene ID und in Spalte 7 die ID des Elternteils
(für einen Bereich die Collection, sonst die `_index.md` des Bereichs):
```bash
docs/handbuch/render.py list | awk -F'\t' '{ print $5, $6, $7, $1 }'
```
Die Positionen in aufsteigender Reihenfolge setzen (erst 0, dann 1, …). Zum Schluss mit `list_collection_documents`
gegen `render.py list` prüfen. Links auf noch nicht veröffentlichte Artikel bricht `render` ab (`--allow-missing` lässt nur den Text
stehen).

## Prüfung
`tests/handbuch.sh` läuft in der CI: Jeder Parameter mit Default in `bashclub-zsync` braucht einen Abschnitt und eine
Zeile in der Übersicht der Referenz (`06-referenz/01-konfigurationsparameter.md`), jedes Programm aus den Paketen einen
Abschnitt `` ## `name` `` in der Referenz, und jeder Artikel muss sich aufbereiten lassen. Die Referenz wird von Hand
gepflegt; die Prüfung fällt auf, wenn ein neuer Parameter oder ein neues Programm fehlt.

## Definition of Done
Ein Feature-Ticket aktualisiert die betroffenen Artikel (Konzept, Referenz, Szenario, Migration) im selben PR, mit
Versionsvermerk.
