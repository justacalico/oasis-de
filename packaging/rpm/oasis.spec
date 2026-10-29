%global _enable_debug_package 0
%global debug_package %{nil}
%global _missing_build_ids_terminate_build 0
%global __provides_exclude_from /opt/oasis/lib/
%global __requires_exclude ^lib(app|dartjni|flutter_linux_gtk|screen_retriever_linux_plugin|url_launcher_linux_plugin|window_manager_plugin|jvm)\\.so

Name:           oasis
Version:        %{pkg_version}
Release:        1%{?dist}
Summary:        A calm, glassy desktop environment for Linux

License:        AGPL-3.0
URL:            https://gitlab.com/HttpAnimations/oasis-de
ExclusiveArch:  x86_64 aarch64
Requires:       dbus
Requires:       cage
BuildRequires:  patchelf

%description
Oasis is a desktop environment for people, not nerds. A floating dock,
a translucent menu bar, a quiet launcher, a control center that stays
out of your way.

%install
mkdir -p %{buildroot}/opt/oasis
cp -a %{bundle_dir}/. %{buildroot}/opt/oasis/

for so in %{buildroot}/opt/oasis/lib/*.so; do
  patchelf --set-rpath '$ORIGIN' "$so" 2>/dev/null || true
done

mkdir -p %{buildroot}%{_bindir}
ln -s /opt/oasis/oasis %{buildroot}%{_bindir}/oasis
install -Dm755 %{_sourcedir}/oasis-session %{buildroot}%{_bindir}/oasis-session

install -Dm644 %{_sourcedir}/oasis.desktop \
  %{buildroot}%{_datadir}/wayland-sessions/oasis.desktop
install -Dm644 %{_sourcedir}/gitlab.httpanimations.oasisde.desktop \
  %{buildroot}%{_datadir}/applications/gitlab.httpanimations.oasisde.desktop
install -Dm644 %{_sourcedir}/gitlab.httpanimations.oasisde.png \
  %{buildroot}%{_datadir}/icons/hicolor/1024x1024/apps/gitlab.httpanimations.oasisde.png

%files
/opt/oasis
%{_bindir}/oasis
%{_bindir}/oasis-session
%{_datadir}/wayland-sessions/oasis.desktop
%{_datadir}/applications/gitlab.httpanimations.oasisde.desktop
%{_datadir}/icons/hicolor/1024x1024/apps/gitlab.httpanimations.oasisde.png

%changelog
* Thu Oct 29 2026 Oasis <ci@oasis.local> - %{pkg_version}-1
- Initial RPM package
