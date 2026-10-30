#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bundle/lib"
printf '#!/bin/sh\n' > "$WORK/bundle/oasis"
printf 'stub' > "$WORK/bundle/lib/libapp.so"

sh "$ROOT/scripts/build-deb.sh" "$WORK/bundle" "0.0.0-test" "$WORK/out"

DEB="$(ls "$WORK"/out/oasis_*.deb | head -1)"
INFO="$(dpkg-deb --info "$DEB")"
echo "$INFO"
echo "$INFO" | grep -q 'Package: oasis'
echo "$INFO" | grep -q 'Version: 0.0.0-test'
! echo "$INFO" | grep -q 'PKG_'
dpkg-deb --contents "$DEB" | grep -q 'usr/bin/oasis$'
dpkg-deb --contents "$DEB" | grep -q 'wayland-sessions/oasis.desktop'
dpkg-deb --contents "$DEB" | grep -q 'applications/gitlab.httpanimations.oasisde.desktop'

grep -q '^Name:.*oasis' "$ROOT/packaging/rpm/oasis.spec"
grep -q '^Requires:' "$ROOT/packaging/rpm/oasis.spec"
grep -q '^%install' "$ROOT/packaging/rpm/oasis.spec"
grep -q '^%files' "$ROOT/packaging/rpm/oasis.spec"
grep -q 'opt/oasis' "$ROOT/packaging/rpm/oasis.spec"

for f in packaging/oasis-session packaging/oasis.desktop \
    packaging/debian/DEBIAN/control packaging/debian/DEBIAN/postinst \
    packaging/debian/DEBIAN/postrm; do
  [ -s "$ROOT/$f" ] || { echo "missing $f" >&2; exit 1; }
done

echo "packaging verified: $DEB"
