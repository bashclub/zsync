#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Baut das Paket aus dem Arbeitsstand (nfpm-Container wie in der CI), installiert es auf der Test-VM
# und führt dort die Integrationstests aus.
# Aufruf: tests/integration/remote.sh <root@host> [fall ...]
set -eu
host=$1; shift
repo=$(cd "$(dirname "$0")/../.." && pwd)
version=$(git -C "$repo" describe --tags --match 'v[0-9]*' --long | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+git\1.\2/')
git -C "$repo" diff --quiet HEAD || version="$version.dirty"
dist=$(mktemp -d); trap 'rm -rf "$dist"' EXIT
for f in nfpm.yaml nfpm-source.yaml; do
  podman run --rm -e VERSION="$version" -v "$repo:/src:ro,Z" -v "$dist:/dist:Z" -w /src docker.io/goreleaser/nfpm \
    pkg -f $f -p deb -t /dist/ > /dev/null
done
ssh "$host" 'rm -rf /root/zsync-ci && mkdir -p /root/zsync-ci'
scp -q "$dist"/*.deb "$host":/root/zsync-ci/
scp -qr "$repo/tests/integration" "$host":/root/zsync-ci/
ssh "$host" "dpkg -i /root/zsync-ci/*.deb > /dev/null && /root/zsync-ci/integration/run.sh $*"
