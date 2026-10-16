#!/bin/bash
# CI-Job auf dem Runner mit Label zfs (Test-VM): Paket aus dem ausgecheckten Stand bauen, installieren, testen.
# Aufruf im Wurzelverzeichnis des Repos: tests/integration/ci.sh
set -euo pipefail
version=$(git describe --tags --match 'v[0-9]*' --long | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+git\1.\2/')
rm -rf dist && mkdir dist
for f in nfpm.yaml nfpm-source.yaml; do VERSION=$version nfpm pkg -f $f -p deb -t dist/ > /dev/null; done
dpkg -i dist/*.deb > /dev/null
# Tests ohne ZFS: command=-Wrapper und Checkmk-Check
tests/remote.sh | tail -1
tests/checkmk.sh | tail -1
tests/integration/run.sh
