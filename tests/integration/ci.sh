#!/bin/bash
# CI-Job auf dem Runner mit Label zfs (Test-VM): Paket aus dem ausgecheckten Stand bauen, installieren, testen.
# Aufruf im Wurzelverzeichnis des Repos: tests/integration/ci.sh
set -eu
version=$(git describe --tags --match 'v[0-9]*' --long | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+git\1.\2/')
rm -rf dist && mkdir dist
VERSION=$version nfpm pkg -f nfpm.yaml -p deb -t dist/ > /dev/null
dpkg -i dist/*.deb > /dev/null
tests/integration/run.sh
