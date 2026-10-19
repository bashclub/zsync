#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Handbuch (docs/handbuch): Referenz vollständig, Artikel lassen sich für Outline aufbereiten. Ohne root, ohne ZFS.
# Aufruf im Wurzelverzeichnis des Repos: tests/handbuch.sh
repo=$(cd "$(dirname "$0")/.." && pwd)
docs=$repo/docs/handbuch
ref=$docs/06-referenz
count=0 failed=0
check() { ((count++)); if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; ((failed++)); fi; }

# jeder Parameter mit Default im Skript hat einen Abschnitt und eine Zeile in der Übersicht
params=$(sed -n '/^#### default values in config file/,/^usage()/p' "$repo/bashclub-zsync/usr/bin/bashclub-zsync" \
  | grep -oE '^[a-z_]+=' | tr -d '=')
for p in $params; do
  check "Parameter $p in der Referenz" grep -q "^### \`$p\`\$" "$ref/01-konfigurationsparameter.md"
  check "Parameter $p in der Übersicht" grep -q "^| \`$p\` |" "$ref/01-konfigurationsparameter.md"
done

# jedes Programm aus den Paketen hat einen Abschnitt in der Referenz
progs=$(grep -hoE 'dst: /usr/s?bin/[^ ]+' "$repo"/nfpm*.yaml | sed 's|.*/||' | sort -u)
for p in $progs; do
  check "Programm $p in der Referenz" grep -q "^## \`$p\`\$" "$ref"/0*.md
done

# alle Artikel: Kopf, keine Überschrift erster Ebene, Links auf vorhandene Dateien
while IFS=$'\t' read -r file _; do
  check "aufbereitbar: $file" eval '"$docs/render.py" render "$docs/$file" --allow-missing > /dev/null'
done < <("$docs/render.py" list)

# kein Text hinter einem schließenden ``` (Markdown nähme ihn als Sprache des Blocks)
check "kein Text hinter \`\`\`" eval '! grep -rnE "^\`\`\` +[^ ]" "$docs"'

echo "$((count - failed))/$count bestanden"
[ $failed -eq 0 ]
