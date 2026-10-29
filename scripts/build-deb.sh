#!/usr/bin/env sh
set -eu

BUNDLE="${1:?usage: build-deb.sh <bundle-dir> <version> <outdir>}"
VERSION="${2:?version required}"
OUT="${3:?output dir required}"

TOP="$(pwd)/debbuild"
rm -rf "$TOP"
mkdir -p "$TOP/oasis/opt/oasis" "$TOP/oasis/usr/bin" "$OUT"

cp -a "$BUNDLE"/. "$TOP/oasis/opt/oasis/"

for so in "$TOP/oasis/opt/oasis/lib/"*.so; do
  patchelf --set-rpath '$ORIGIN' "$so" 2>/dev/null || true
done

ln -s /opt/oasis/oasis "$TOP/oasis/usr/bin/oasis"
install -Dm755 packaging/oasis-session "$TOP/oasis/usr/bin/oasis-session"
install -Dm644 packaging/oasis.desktop \
  "$TOP/oasis/usr/share/wayland-sessions/oasis.desktop"
install -Dm644 de/linux/data/gitlab.httpanimations.oasisde.desktop \
  "$TOP/oasis/usr/share/applications/gitlab.httpanimations.oasisde.desktop"
install -Dm644 de/linux/data/gitlab.httpanimations.oasisde.png \
  "$TOP/oasis/usr/share/icons/hicolor/1024x1024/apps/gitlab.httpanimations.oasisde.png"

mkdir -p "$TOP/oasis/DEBIAN"
sed "s/PKG_VERSION/$VERSION/" packaging/debian/DEBIAN/control \
  > "$TOP/oasis/DEBIAN/control"
cp packaging/debian/DEBIAN/postinst packaging/debian/DEBIAN/postrm \
  "$TOP/oasis/DEBIAN/"

dpkg-deb --build "$TOP/oasis" "$OUT/oasis_${VERSION}_amd64.deb"
ls -la "$OUT"
