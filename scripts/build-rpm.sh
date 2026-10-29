#!/usr/bin/env sh
set -eu

BUNDLE="${1:?usage: build-rpm.sh <bundle-dir> <version> <outdir>}"
VERSION="${2:?version required}"
OUT="${3:?output dir required}"

TOP="$(pwd)/rpmbuild"
mkdir -p "$TOP/BUILD" "$TOP/RPMS" "$TOP/SOURCES" "$TOP/SPECS" "$TOP/SRPMS" "$OUT"

cp packaging/oasis-session packaging/oasis.desktop \
  de/linux/data/gitlab.httpanimations.oasisde.desktop \
  de/linux/data/gitlab.httpanimations.oasisde.png "$TOP/SOURCES/"
cp packaging/rpm/oasis.spec "$TOP/SPECS/oasis.spec"

rpmbuild -bb "$TOP/SPECS/oasis.spec" \
  --define "_topdir $TOP" \
  --define "pkg_version $VERSION" \
  --define "bundle_dir $(cd "$BUNDLE" && pwd)"

find "$TOP/RPMS" -name '*.rpm' -exec cp -t "$OUT" {} +
ls -la "$OUT"
