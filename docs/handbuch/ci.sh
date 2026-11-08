#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# CI: Handbuch prüfen und nach Outline veröffentlichen, im Quellstand aufgerufen
#   docs/handbuch/ci.sh pull_request <basis>   nur zeigen, was nach dem Merge veröffentlicht würde
#   docs/handbuch/ci.sh release <vorher>       nach dem Veröffentlichen der Pakete (package.yml): Seiten, die sich seit
#                                              <vorher> geändert haben, ohne gültiges <vorher> alle
#   docs/handbuch/ci.sh docs <vorher>          Push nur mit Doku-Änderungen (handbuch.yml); mit Änderungen am Code
#                                              nichts, das übernimmt package.yml nach dem Release
#   docs/handbuch/ci.sh all                    alle Seiten (von Hand gestartet)
# Secret OUTLINE_API_KEY, optional OUTLINE_URL (Default https://docs.bashclub.org)
set -euo pipefail
mode=$1 ref=${2:-}
tests/handbuch.sh
since=
if [[ -n $ref ]] && git cat-file -e "$ref^{commit}" 2>/dev/null; then since=$ref; fi
if [[ $mode == pull_request ]]; then
    docs/handbuch/render.py publish ${since:+--since "$(git merge-base HEAD "$since")"} --dry-run
    exit 0
fi
if [[ $mode == docs && -n $since ]] \
    && git diff --name-only "$since" HEAD | grep -qvE '^(docs/|README(\.de)?\.md$|CONTRIBUTING\.md$)'; then
    echo "code changed as well: the handbook is published with the release (package.yml)"
    exit 0
fi
[[ $mode == all ]] && since=
# die Job-Container kennen nur code.bashclub.org (fester Eintrag), Outline liegt hinter demselben Proxy
host=$(python3 -c 'import os, urllib.parse; print(urllib.parse.urlparse(os.environ.get("OUTLINE_URL") or "https://docs.bashclub.org").hostname)')
if ! getent hosts "$host" > /dev/null; then
    addr=$(getent hosts code.bashclub.org | awk '{ print $1; exit }')
    if [[ -n $addr && -w /etc/hosts ]]; then
        echo "$addr $host" >> /etc/hosts
        echo "$host not resolvable, using $addr (address of code.bashclub.org)"
    fi
fi
docs/handbuch/render.py publish ${since:+--since "$since"}
