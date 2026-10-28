This is Oasis, a Flutter desktop environment shell for Linux.

Monorepo layout:
- `packages/oasis_ui` — shared theme engine and component library. All apps use it; no app invents its own widgets.
- `de` — the desktop shell itself (menu bar, dock, launcher, control center, window chrome).
- `apps/` — bundled DE apps (currently `settings`). New apps go here and depend on `oasis_ui` and `oasis_settings` for host contracts.
- `landing` — Flutter web landing page and download page.
- `test/` — root test suite covering every package plus goldens for every screen.

Rules:
- Keep 100% line coverage. Run `flutter test --coverage` at the repo root and inspect `coverage/lcov.info` before finishing.
- Goldens live in `test/goldens`. Regenerate with `flutter test test/goldens_test.dart --update-goldens`. Bundled fonts are loaded by `test/helpers/test_app.dart`.
- All user-facing text goes through the ARB files in `packages/oasis_ui/l10n`. Never hardcode strings. Locales: en_GB base, zh_Hans, ru, ga.
- Refactor rather than duplicating code. Small focused files, no god files.
- Aim for an A+ codebase. If something should be refactored, refactor it.
- Commits use Conventional Commits (`feat:`, `fix:`, `chore:`...) so cocogitto can bump versions and write the changelog. Run `git config core.hooksPath .githooks` once.
- Do not use Apple or macOS names anywhere in product code or UI.
