#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${1:?usage: build-deb.sh <bundle-dir> <version> <outdir>}"
VERSION="${2:?version required}"
OUT="${3:?output dir required}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

command -v dpkg-deb >/dev/null || { echo "dpkg-deb not found" >&2; exit 1; }
command -v patchelf >/dev/null || { echo "patchelf not found" >&2; exit 1; }

TOP="$ROOT/debbuild"
rm -rf "$TOP"
mkdir -p "$TOP/oasis/opt/oasis" "$TOP/oasis/usr/bin" "$OUT"

cp -a "$BUNDLE"/. "$TOP/oasis/opt/oasis/"

for so in "$TOP/oasis/opt/oasis/lib/"*.so; do
  [ -e "$so" ] || continue
  patchelf --set-rpath '$ORIGIN' "$so"
done

ln -s /opt/oasis/oasis "$TOP/oasis/usr/bin/oasis"
install -Dm755 "$ROOT/packaging/oasis-session" "$TOP/oasis/usr/bin/oasis-session"
install -Dm644 "$ROOT/packaging/oasis.desktop" \
  "$TOP/oasis/usr/share/wayland-sessions/oasis.desktop"
install -Dm644 "$ROOT/de/linux/data/gitlab.httpanimations.oasisde.desktop" \
  "$TOP/oasis/usr/share/applications/gitlab.httpanimations.oasisde.desktop"
install -Dm644 "$ROOT/de/linux/data/gitlab.httpanimations.oasisde.png" \
  "$TOP/oasis/usr/share/icons/hicolor/1024x1024/apps/gitlab.httpanimations.oasisde.png"

mkdir -p "$TOP/oasis/DEBIAN"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
sed "s/PKG_VERSION/$VERSION/; s/PKG_ARCH/$ARCH/" "$ROOT/packaging/debian/DEBIAN/control" \
  > "$TOP/oasis/DEBIAN/control"
cp "$ROOT/packaging/debian/DEBIAN/postinst" "$ROOT/packaging/debian/DEBIAN/postrm" \
  "$TOP/oasis/DEBIAN/"

dpkg-deb --root-owner-group --build "$TOP/oasis" "$OUT/oasis_${VERSION}_${ARCH}.deb"
ls -la "$OUT"
