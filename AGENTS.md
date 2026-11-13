# AGENTS.md

Instructions for coding agents working on Mise GUI.

## Project

Mise GUI is a Flutter desktop app for inspecting and managing
[mise](https://mise.jdx.dev/) environments. The app targets Linux, Windows, and
macOS. The UI is English-first, with a built-in Simplified Chinese language
switch.

## Branch and review rules

- Work on the branch the user names. Do not create a new branch unless the user
  explicitly asks for one.
- The open English UI pull request targets `dev`. Leave it unmerged unless the
  owner explicitly asks for it to be merged.
- Do not rewrite published history, force-push `master`, or move an existing
  release tag after a GitHub release has been published without approval.
- Keep commits focused. Do not mix unrelated refactors with behavior fixes.

## Dependencies

- **Always add new stable dependencies only.** Never add beta, rc, dev, alpha,
  nightly, or other pre-release packages.
- Prefer upgrading an existing package over adding a new dependency.
- Check all dependencies with:

  ```bash
  npm run deps:check
  ```

- See the full report and the reason for every pinned transitive package with:

  ```bash
  npm run deps:outdated
  ```

  `deps:check` fails on outdated direct/dev dependencies and on any outdated
  transitive dependency that is not documented in
  `scripts/outdated_deps_allowlist.json`. Flutter SDK pins and upstream
  constraints belong in that file with a concrete reason. Never use
  `dependency_overrides` to force them. Remove allowlist entries as soon as
  upstream publishes a compatible release.

- Prefer removing a small optional dependency over allowlisting its transitive
  chain. For example, render a static logo from an existing PNG instead of
  keeping an SVG renderer just for one asset.

- Upgrade dependencies with:

  ```bash
  npm run deps:update
  flutter pub get
  ```

- Commit `pubspec.lock` together with `pubspec.yaml`.
- Do not downgrade the Flutter SDK constraint or `mise.toml` just to make a
  dependency resolve. Upgrade the toolchain or choose a compatible stable
  package instead.

## Localization

- English is the source language. Write user-facing strings in English and add
  Chinese translations to `lib/l10n/translations_zh.dart`.
- Wrap every user-visible string in `tr()` or `trArgs()`.
- When adding a translated string, add its Chinese entry and keep placeholders
  unchanged.
- Providers that build models containing translated text must watch
  `appLocaleProvider` so data is rebuilt after a language switch.
- Avoid `const` on widgets that call `tr()` unless the widget watches the
  language provider itself; otherwise the subtree will not rebuild when the
  language changes.
- Run `flutter test` after localization changes. `test/app_localizations_test.dart`
  checks catalog coverage, placeholders, and fallback behavior.

## Verification

Run these before committing:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart run scripts/check_outdated_deps.dart
```

Build the current platform before a release:

```bash
flutter build linux --release
# or
flutter build windows --release
flutter build macos --release
```

Packaging entrypoints:

```bash
npm run linux:release:tar
npm run windows:release:zip
npm run macos:release:zip
```

## Code style

- Follow the existing structure, naming, and UI patterns.
- Riverpod 3 is in use. Import `package:flutter_riverpod/legacy.dart` only for
  legacy providers such as `StateProvider`.
- `prefer_initializing_formals` is intentionally disabled because service
  constructors inject private fields through public named parameters that must
  remain usable from other libraries and tests.
- Keep services context-free; translate model/display strings at render time
  where practical.

## Git hooks

Install the repository hooks once per clone:

```bash
npm run hooks:install
```

- `pre-commit` checks dependency versions when `pubspec.yaml` is staged.
- `pre-push` checks dependency versions before every push.
- Set `SKIP_OUTDATED_DEPS_CHECK=1` only for an intentional temporary bypass.
- Set `ALLOW_OUTDATED_DEPS=1` to report outdated packages without failing.

## Release

- Bump `version` in `pubspec.yaml` before tagging.
- Release tags use the `v<version>` form, for example `v1.0.9`.
- Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds
  Linux and Windows packages and publishes them to a GitHub Release.
- GitHub Actions must be enabled for the repository before tags can trigger the
  workflow.
- macOS packages are built and notarized locally with the scripts in
  `scripts/` and uploaded manually.
