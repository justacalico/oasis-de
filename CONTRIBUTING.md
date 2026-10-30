# Contributing

## Setup

```sh
flutter pub get
git config core.hooksPath .githooks
```

Linux builds also need the native deps listed in the README (wayland-devel, wayland-protocols, libxkbcommon, libdrm, mesa EGL/GLES, gtk3).

## Rules that get enforced

- `flutter analyze` clean.
- `flutter test --coverage` at the repo root must pass with 100% line coverage; the `coverage/lcov.info` LF==LH gate runs in CI.
- Goldens live in `test/goldens`. Regenerate with `flutter test test/goldens_test.dart --update-goldens` and eyeball the diff.
- All user-facing text through the ARB files in `packages/oasis_ui/l10n` (en_GB, zh_Hans, ru, ga). No hardcoded strings.
- Shared UI belongs in `packages/oasis_ui`, not in apps. Refactor instead of duplicating.
- Conventional Commits (`feat:`, `fix:`, `chore:`, ...); cocogitto bumps versions and writes the changelog from them.
- No Apple/macOS names in product code or UI.

## Where things go

- Shell UI: `de/lib/shell/`. Compositor bridge: `de/lib/wayland/` + `de/linux/runner/`.
- Shared widgets/theme/l10n: `packages/oasis_ui/`.
- New bundled apps: `apps/<name>/` depending on `oasis_ui`.
- Tests for everything: `test/` at the repo root.

Open a merge request on GitLab. Keep it small and titled with a conventional-commit style subject.
