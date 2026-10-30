#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${1:?usage: build-rpm.sh <bundle-dir> <version> <outdir>}"
VERSION="${2:?version required}"
OUT="${3:?output dir required}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

command -v rpmbuild >/dev/null || { echo "rpmbuild not found" >&2; exit 1; }
command -v patchelf >/dev/null || { echo "patchelf not found" >&2; exit 1; }

TOP="$ROOT/rpmbuild"
rm -rf "$TOP"
mkdir -p "$TOP/BUILD" "$TOP/RPMS" "$TOP/SOURCES" "$TOP/SPECS" "$TOP/SRPMS" "$OUT"

cp "$ROOT/packaging/oasis-session" "$ROOT/packaging/oasis.desktop" \
  "$ROOT/de/linux/data/gitlab.httpanimations.oasisde.desktop" \
  "$ROOT/de/linux/data/gitlab.httpanimations.oasisde.png" "$TOP/SOURCES/"
cp "$ROOT/packaging/rpm/oasis.spec" "$TOP/SPECS/oasis.spec"

rpmbuild -bb --nodeps "$TOP/SPECS/oasis.spec" \
  --define "_topdir $TOP" \
  --define "pkg_version $VERSION" \
  --define "bundle_dir $(cd "$BUNDLE" && pwd)"

find "$TOP/RPMS" -name '*.rpm' -exec cp -t "$OUT" {} +
ls -la "$OUT"
