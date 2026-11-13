<p align="center">
  <img src="docs/brand-mark.png" alt="Mise GUI" width="96" height="96">
</p>

<h1 align="center">Mise GUI</h1>

<p align="center">
  <strong>Your mise environment, at a glance.</strong><br>
  A calm desktop console for the toolchains, versions, and projects that mise manages.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#a-closer-look">Features</a> ·
  <a href="#development">Development</a> ·
  <a href="README.zh.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/likaia/mise_gui/releases"><img src="https://img.shields.io/github/v/release/likaia/mise_gui?style=flat-square&label=release&labelColor=0F172A&color=22C55E" alt="Latest release"></a>
  <a href="https://github.com/likaia/mise_gui/releases"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-22C55E?style=flat-square&labelColor=0F172A" alt="Platforms"></a>
  <a href="https://github.com/likaia/mise_gui/releases"><img src="https://img.shields.io/github/downloads/likaia/mise_gui/total?style=flat-square&label=downloads&labelColor=0F172A&color=38BDF8" alt="Downloads"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/github/license/likaia/mise_gui?style=flat-square&label=license&labelColor=0F172A&color=38BDF8" alt="License"></a>
</p>

<br>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/dashboard-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/dashboard-light.png">
    <img src="docs/dashboard-light.png" alt="Mise GUI environment console" width="100%">
  </picture>
</p>

## The view from above

mise makes it easy to pin a toolchain per project. The hard part is seeing the
whole picture: which versions are active, which projects override the defaults,
and whether the last upgrade actually worked.

Mise GUI reads your real mise state and puts that picture on one screen. No
separate database, no sync step.

<table>
  <tr>
    <td width="33%" valign="top">
      <strong>See</strong><br><br>
      Installed and active versions, host details, and the current mise version
      in one readable ledger.
    </td>
    <td width="33%" valign="top">
      <strong>Trace</strong><br><br>
      Which projects override your global toolchain, and what happened the last
      time you ran an operation.
    </td>
    <td width="33%" valign="top">
      <strong>Act</strong><br><br>
      Switch versions, upgrade mise, and edit TOML with a command preview before
      anything runs.
    </td>
  </tr>
</table>

The interface ships in English by default and includes a built-in Simplified
Chinese switch.

## A closer look

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/feature-overview.png" alt="Environment overview" width="100%">
      <br>
      <strong>Environment console</strong><br>
      <sub>Host details, installed tools, project overrides, and the mise version in one place.</sub>
    </td>
    <td width="50%" valign="top">
      <img src="docs/feature-tools.png" alt="Tool versions" width="100%">
      <br>
      <strong>Tools</strong><br>
      <sub>Current and latest versions per tool, remote version loading, switching, upgrades, and uninstalls.</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/feature-projects.png" alt="Project overrides" width="100%">
      <br>
      <strong>Projects</strong><br>
      <sub>Multi-directory scanning that highlights only the projects overriding global defaults.</sub>
    </td>
    <td width="50%" valign="top">
      <img src="docs/feature-config.png" alt="Configuration management" width="100%">
      <br>
      <strong>Config</strong><br>
      <sub>Global and project TOML in one context, with a diff preview before saving.</sub>
    </td>
  </tr>
</table>

> **Nothing runs by surprise.** Installs and upgrades show the exact command
> first. Every result is recorded with status, duration, and exit code in
> Activity.

## Install

**1 · Install mise**, if it is not already on your machine:

| Platform | Command |
| --- | --- |
| macOS | `brew install mise` |
| Windows | `winget install jdx.mise` |
| Linux | `curl https://mise.run \| sh` |

**2 · Download Mise GUI** from
[Releases](https://github.com/likaia/mise_gui/releases). Builds are published for
macOS, Linux, and Windows.

If mise is missing, the app opens an onboarding screen with the recommended
install command instead of failing silently.

## Development

The repository pins Flutter through `mise.toml`, so the first command installs
the expected SDK:

```bash
git clone https://github.com/likaia/mise_gui.git
cd mise_gui

mise install
flutter pub get
flutter run -d linux   # or: macos / windows
```

Before opening a pull request, run the same checks as CI:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
npm run deps:check
```

`npm run deps:check` verifies that every direct and transitive dependency is on
a supported stable release. CI runs the same checks on pull requests targeting
`master`. Dependency and release rules live in [AGENTS.md](AGENTS.md).

<details>
<summary><strong>Project structure</strong></summary>

```text
lib/
  app/                  # Bootstrap, routing, theme, and application shell
  features/
    dashboard/          # Environment console and activity
    tools/              # Versions, install, upgrade, and uninstall flows
    projects/           # Scan directories and project coverage
    config/             # Global and project configuration management
  l10n/                 # English source strings and Chinese translations
  repositories/         # Page-level data aggregation
  services/             # mise CLI, config, history, update, and platform services
  shared/ui/            # Panels, states, dialogs, and preview components
assets/
  branding/             # Application marks
  fonts/                # Bundled IBM Plex Sans and JetBrains Mono faces
scripts/                # Packaging, dependency, and hook scripts
docs/                   # README screenshots and brand assets
```

</details>

<details>
<summary><strong>Design details</strong></summary>

- **Appearance** — light, dark, and follow-system modes share the same hairline
  structure, status colors, and typographic hierarchy.
- **Type** — bundled [IBM Plex Sans](https://github.com/IBM/plex) and
  [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) faces under the
  SIL Open Font License. License texts live in `assets/fonts/`.
- **Language** — English source strings with a complete Simplified Chinese
  catalog, checked by tests.
- **Stack** — Flutter · Riverpod 3 · go_router · file_selector ·
  package_info_plus.

</details>

## License

This project is licensed under the MIT License. See [LICENSE.txt](LICENSE.txt)
for details.

---

<p align="center">
  <sub>Built with Flutter. Read the <a href="README.zh.md">Chinese README</a>.</sub>
</p>
