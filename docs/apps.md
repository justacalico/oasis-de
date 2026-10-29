# Writing apps for Oasis

An Oasis app is a Flutter package in `apps/`. It depends on `oasis_ui` for look and behavior and on `oasis_settings`-style host contracts for anything the shell provides. Do not invent local widgets or colors; if a control is missing, add it to `oasis_ui` so every app gets it.

## Registering

`de/lib/shell/shell_controller.dart` builds an `OasisApp` per bundled app:

```dart
OasisApp(
  id: 'settings',
  name: l10n.appNameSettings,
  icon: OasisIcons.settings,
  iconColors: [OasisColors.accent],
  builder: (context) => const SettingsWindow(),
)
```

- `id` is stable and used for pinned state and window matching.
- `builder` returns the window contents; the shell wraps it in `OasisWindow` chrome.
- External apps instead set `exec` + `iconPath` and launch through the compositor.

## Host services

`OasisHost.of(context)` exposes what the shell offers apps:

- `appearance` - current `OasisAppearance` (theme mode + accent). Read it; never hardcode colors.
- `setLocale` / `locale` - switch and read the UI locale.
- `updates` - the shared `UpdateService`.
- `openUrl` - open links via the shell.

Use `OasisHost.maybeOf` in widgets that also run standalone (tests, web demo).

## Text

All user-facing strings go through `packages/oasis_ui/l10n` ARB files (en_GB base, zh_Hans, ru, ga). Never hardcode strings in app UI.

## Testing

Golden and widget tests live in the repo-root `test/` suite. Reuse `test/helpers/test_app.dart`, which loads the bundled fonts and wraps widgets in an `OasisHost`.
