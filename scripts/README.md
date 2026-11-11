# Scripts

这个目录下是桌面端打包脚本。根目录已经加了 `package.json`，可以直接通过 `npm run` 调用，不需要记具体脚本文件名。

## 常用命令

```bash
npm run help
npm run deps:check
npm run deps:update
npm run hooks:install
npm run macos:dmg:background
npm run macos:dmg:background:2x
npm run macos:debug:dmg
npm run macos:release:app
npm run macos:release:dmg
npm run macos:release:zip
npm run macos:release:zip:unsigned
npm run macos:release:version
npm run windows:release:zip
npm run linux:release:tar
npm run linux:release:zip
```

Windows 包必须在 Windows 机器上构建，Linux 包必须在 Linux 机器上构建。Flutter 桌面端不支持在 macOS 上直接交叉编译 Windows/Linux release 包。GitHub Actions 目前只自动构建 Windows 和 Linux，macOS 端按本地脚本手动打包后再上传。

Windows 打包机需要安装 Visual Studio 的 `Desktop development with C++` 工作负载。Linux 打包机需要安装 Flutter Linux 桌面工具链依赖，例如 `clang`、`cmake`、`ninja-build`、`pkg-config`、`libgtk-3-dev`。

## 依赖检查与 git hooks

`npm run deps:check` 会运行 `scripts/check_outdated_deps.dart`，检查直接依赖和开发依赖是否都已是最新版本。CI 的 quality job 也会执行同一项检查。

需要升级依赖时执行：

```bash
npm run deps:update
flutter pub get
```

仓库自带 `.githooks/pre-commit` 和 `.githooks/pre-push`：

- `pre-commit`：暂存区包含 `pubspec.yaml` 时检查依赖版本
- `pre-push`：推送前检查依赖版本

启用 hooks：

```bash
npm run hooks:install
```

临时跳过 pre-push 检查可以设置 `SKIP_OUTDATED_DEPS_CHECK=1`。如果只想记录问题而不让检查失败，可以设置 `ALLOW_OUTDATED_DEPS=1`。

## 跳过公证

如果你只想本地快速出包验证，不走 Apple notarization，可以用这些命令：

```bash
npm run macos:release:app:skip-notarization
npm run macos:release:dmg:skip-notarization
npm run macos:release:zip:skip-notarization
```

## 每个脚本做什么

- `deps:check`
  运行 `scripts/check_outdated_deps.dart`，检查直接依赖和开发依赖是否都是最新版本
- `deps:update`
  执行 `flutter pub upgrade --major-versions`，把可升级的依赖更新到最新主版本
- `hooks:install`
  运行 `scripts/setup_git_hooks.sh`，把当前仓库的 `core.hooksPath` 指向 `.githooks`
- `macos:dmg:background`
  生成 DMG 背景图，默认输出到 `packaging/macos/dmg-background.png` 和 `packaging/macos/dmg-background@2x.png`
- `macos:debug:dmg`
  构建 debug 版 macOS app，并打成调试用 DMG
- `macos:release:app`
  构建 release 版 `.app`，签名、公证、staple 后输出到 `dist/macos/`
- `macos:release:dmg`
  构建 release 版 `.dmg`，签名、公证、staple 后输出到 `dist/macos/`
- `macos:release:zip`
  构建 release 版 `.zip`，先提交 zip 做公证，再对 app staple，最后重新打成最终 zip
- `macos:release:zip:unsigned`
  构建未签名、未公证的 release 版 `.zip`，用于 GitHub Actions 这类没有 Developer ID 证书的 CI 环境
- `windows:release:zip`
  在 Windows 上执行 `flutter build windows --release`，收集 `.exe`、`.dll`、`data/` 和可找到的 Visual C++ runtime DLL，输出可分发 `.zip`
- `linux:release:tar`
  在 Linux 上执行 `flutter build linux --release`，把 Flutter 生成的 bundle 输出为 `.tar.gz`
- `linux:release:zip`
  在 Linux 上执行 `flutter build linux --release`，把 Flutter 生成的 bundle 输出为 `.zip`
- `release_macos_version.sh`
  从最新 `vX.Y.Z` tag 推导下一个版本，更新 `pubspec.yaml` 的 `version: X.Y.Z+N`，执行 macOS release app 打包，然后提交、打 tag 并推送。可用 `--version`、`--build-number`、`--remote` 覆盖默认值。

## 可用环境变量

这些变量可以在执行前临时传入：

```bash
SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="mise-gui-notary" \
npm run macos:release:dmg
```

- `SIGNING_IDENTITY`
  覆盖默认签名证书。不传时会自动选择第一个可用的 `Developer ID Application`
- `NOTARY_PROFILE`
  覆盖 `xcrun notarytool` 使用的 keychain profile，默认是 `mise-gui-notary`
- `SKIP_NOTARIZATION`
  只在对应的 `:skip-notarization` npm script 里预先设置为 `1`
- `SKIP_CODESIGN`
  传 `1` 时 macOS zip 跳过 codesign、公证和 staple
- `USE_MISE`
  Windows/Linux 打包脚本默认优先使用 `mise exec -- flutter ...`。传 `USE_MISE=0` 时改用当前 `PATH` 里的 `flutter`
- `SKIP_FLUTTER_BUILD`
  只调试打包流程时可传 `SKIP_FLUTTER_BUILD=1`，脚本会复用现有 `build/` 产物

## 输出目录

默认产物都放在：

```bash
dist/macos/
dist/windows/
dist/linux/
```
