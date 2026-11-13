import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/router/app_destination.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/shared/ui/app_backdrop.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appLanguageProvider);
    final destination = AppDestination.values[navigationShell.currentIndex];
    final colors = AppTheme.colorsOf(context);
    final miseAvailableValue = ref.watch(miseAvailableProvider);
    final isMissingMise = miseAvailableValue.maybeWhen(
      data: (value) => !value,
      orElse: () => false,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final expandedSidebar = constraints.maxWidth >= 1280;
        final immersiveMacDesktop =
            !compact &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.macOS;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: compact
              ? AppBar(
                  title: _WindowChromeDoubleTapRegion(
                    child: Text(
                      tr(isMissingMise ? 'Install mise' : destination.label),
                    ),
                  ),
                  actions: const [
                    Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: Center(child: _TopMetaRow(compact: true)),
                    ),
                  ],
                )
              : null,
          drawer: compact
              ? Drawer(
                  backgroundColor: colors.panel,
                  child: SafeArea(
                    child: _Sidebar(
                      currentIndex: navigationShell.currentIndex,
                      expanded: true,
                      locked: isMissingMise,
                      onSelect: (index) {
                        if (isMissingMise) {
                          return;
                        }
                        Navigator.of(context).pop();
                        navigationShell.goBranch(index);
                      },
                    ),
                  ),
                )
              : null,
          body: Stack(
            children: [
              const AppBackdrop(),
              SafeArea(
                top: !immersiveMacDesktop,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    compact ? 16 : (immersiveMacDesktop ? 10 : 24),
                    compact ? 16 : 24,
                    compact ? 16 : 24,
                  ),
                  child: compact
                      ? _ContentPanel(
                          child: miseAvailableValue.when(
                            data: (available) => available
                                ? navigationShell
                                : const _MissingMiseExperience(),
                            loading: () => const _ShellLoadingView(),
                            error: (error, stackTrace) => navigationShell,
                          ),
                        )
                      : Column(
                          children: [
                            if (immersiveMacDesktop)
                              const _DesktopChromeBar()
                            else
                              const _TopBar(),
                            SizedBox(height: immersiveMacDesktop ? 14 : 20),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Sidebar(
                                    currentIndex: navigationShell.currentIndex,
                                    expanded: expandedSidebar,
                                    locked: isMissingMise,
                                    onSelect: isMissingMise
                                        ? (_) {}
                                        : navigationShell.goBranch,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: _ContentPanel(
                                      child: miseAvailableValue.when(
                                        data: (available) => available
                                            ? navigationShell
                                            : const _MissingMiseExperience(),
                                        loading: () =>
                                            const _ShellLoadingView(),
                                        error: (error, stackTrace) =>
                                            navigationShell,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopChromeBar extends StatelessWidget {
  const _DesktopChromeBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Stack(
        children: [
          Positioned.fill(left: 92, child: _WindowChromeDoubleTapRegion()),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(left: 92),
              child: _TopMetaRow(compact: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.currentIndex,
    required this.expanded,
    required this.locked,
    required this.onSelect,
  });

  final int currentIndex;
  final bool expanded;
  final bool locked;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final appVersion = ref.watch(appVersionInfoProvider);
    final sidebarWidth = expanded ? 280.0 : 112.0;
    final sidebarPadding = expanded ? 18.0 : 12.0;
    final brandPadding = expanded ? 16.0 : 10.0;
    final compactBrandSize = expanded ? 92.0 : 54.0;

    return SizedBox(
      width: sidebarWidth,
      child: AppPanel(
        padding: EdgeInsets.all(sidebarPadding),
        radius: 24,
        backgroundAlpha: 0.8,
        borderAlpha: 0.62,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: expanded
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: expanded
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(brandPadding),
                          decoration: BoxDecoration(
                            gradient: expanded
                                ? LinearGradient(
                                    colors: [
                                      colors.panelRaised.withValues(
                                        alpha: 0.24,
                                      ),
                                      colors.accent.withValues(alpha: 0.06),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colors.border.withValues(
                                alpha: expanded ? 0.38 : 0,
                              ),
                            ),
                          ),
                          child: expanded
                              ? Row(
                                  children: [
                                    const _BrandBadge(size: 58),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Mise GUI',
                                            style: TextStyle(
                                              fontFamily: 'FiraCode',
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            tr('Local environments, unified'),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: colors.textMuted,
                                              fontSize: 12,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: _BrandBadge(size: compactBrandSize),
                                ),
                        ),
                        if (locked) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colors.warning.withValues(alpha: 0.26),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 16,
                                  color: colors.warning,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tr(
                                      'Install mise first to unlock the sidebar.',
                                    ),
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (expanded) ...[
                          const SizedBox(height: 22),
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 8),
                            child: Text(
                              tr('Navigation'),
                              style: TextStyle(
                                color: colors.textMuted.withValues(alpha: 0.8),
                                fontSize: 10,
                                fontFamily: 'FiraCode',
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                        ] else
                          const SizedBox(height: 20),
                        for (final destination in AppDestination.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SidebarDestination(
                              destination: destination,
                              expanded: expanded,
                              selected:
                                  !locked && currentIndex == destination.index,
                              locked: locked,
                              onTap: () => onSelect(destination.index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SidebarFooter(
                  expanded: expanded,
                  compactWidth: constraints.maxWidth,
                  versionLabel: appVersion.maybeWhen(
                    data: (value) => value.shortLabel,
                    orElse: () => 'v1.0.0',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.expanded,
    required this.compactWidth,
    required this.versionLabel,
  });

  final bool expanded;
  final double compactWidth;
  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final style = TextStyle(
      color: colors.textMuted.withValues(alpha: 0.82),
      fontSize: 11,
      fontFamily: 'FiraCode',
      fontWeight: FontWeight.w600,
    );

    if (expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          trArgs('Version {versionLabel}', {'versionLabel': versionLabel}),
          style: style,
        ),
      );
    }

    return Center(
      child: SizedBox(
        width: compactWidth,
        child: Text(
          versionLabel,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.destination,
    required this.expanded,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final AppDestination destination;
  final bool expanded;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = selected ? destination.selectedIcon : destination.icon;
    final colors = AppTheme.colorsOf(context);

    return Tooltip(
      message: tr(destination.label),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.14)
            : locked
            ? colors.panelMuted.withValues(alpha: 0.34)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: locked ? Colors.transparent : colors.hover,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 8,
              vertical: 14,
            ),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: expanded ? 42 : 40,
                  height: expanded ? 42 : 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.accent.withValues(alpha: 0.18)
                        : locked
                        ? colors.panel.withValues(alpha: 0.62)
                        : colors.panelRaised.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected
                          ? colors.accent.withValues(alpha: 0.45)
                          : locked
                          ? colors.borderStrong.withValues(alpha: 0.26)
                          : colors.border.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? colors.accent
                        : locked
                        ? colors.textMuted
                        : colors.textPrimary,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(destination.label),
                          style: TextStyle(
                            color: locked
                                ? colors.textMuted
                                : colors.textPrimary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr(destination.description),
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locked)
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: colors.textMuted,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: isDark ? 0.24 : 0.52),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.18 : 0.7),
        ),
      ),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Stack(
        children: [
          Positioned.fill(child: _WindowChromeDoubleTapRegion()),
          Align(
            alignment: Alignment.centerRight,
            child: _TopMetaRow(compact: false),
          ),
        ],
      ),
    );
  }
}

class _WindowChromeDoubleTapRegion extends ConsumerWidget {
  const _WindowChromeDoubleTapRegion({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        unawaited(ref.read(desktopWindowServiceProvider).toggleMaximize());
      },
      child: child,
    );
  }
}

class _TopMetaRow extends ConsumerWidget {
  const _TopMetaRow({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = compact ? 8.0 : 12.0;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: const [_ToolbarGlassGroup()],
    );
  }
}

class _ToolbarGlassGroup extends ConsumerWidget {
  const _ToolbarGlassGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appLanguageProvider);
    final themePreference = ref.watch(themePreferenceProvider);

    return _ToolbarGlassPanel(
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LanguageMenu(),
          const SizedBox(width: 6),
          SegmentedButton<AppThemePreference>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment<AppThemePreference>(
                value: AppThemePreference.system,
                icon: const Icon(Icons.brightness_auto_rounded),
                label: Text(tr('System')),
              ),
              ButtonSegment<AppThemePreference>(
                value: AppThemePreference.light,
                icon: const Icon(Icons.light_mode_rounded),
                label: Text(tr('Light')),
              ),
              ButtonSegment<AppThemePreference>(
                value: AppThemePreference.dark,
                icon: const Icon(Icons.dark_mode_rounded),
                label: Text(tr('Dark')),
              ),
            ],
            selected: {themePreference},
            onSelectionChanged: (selection) {
              final nextPreference = selection.first;
              ref.read(themePreferenceProvider.notifier).state = nextPreference;
            },
          ),
        ],
      ),
    );
  }
}

class _LanguageMenu extends ConsumerWidget {
  const _LanguageMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final colors = AppTheme.colorsOf(context);
    final useChinese = AppLocalizations.current.isChinese;

    return PopupMenuButton<AppLanguage>(
      tooltip: tr('Language'),
      initialValue: language,
      onSelected: (value) {
        ref.read(appLanguageProvider.notifier).state = value;
      },
      itemBuilder: (context) => [
        for (final option in AppLanguage.values)
          PopupMenuItem<AppLanguage>(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == AppLanguage.system
                      ? Icons.settings_suggest_rounded
                      : Icons.translate_rounded,
                  size: 18,
                  color: option == language ? colors.accent : colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appLanguageLabel(option),
                    style: TextStyle(
                      fontWeight: option == language
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (option == language)
                  Icon(Icons.check_rounded, size: 18, color: colors.accent),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.translate_rounded, size: 18, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(
              useChinese ? '中文' : 'EN',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarGlassPanel extends StatelessWidget {
  const _ToolbarGlassPanel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.panelRaised.withValues(alpha: isDark ? 0.58 : 0.76),
                colors.backgroundSoft.withValues(alpha: isDark ? 0.48 : 0.62),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.borderStrong.withValues(
                alpha: isDark ? 0.34 : 0.22,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.backgroundDeep.withValues(
                  alpha: isDark ? 0.16 : 0.06,
                ),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/mise_gui_logo_1024.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
    );
  }
}

class _ShellLoadingView extends StatelessWidget {
  const _ShellLoadingView();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 18),
          Text(
            tr('Checking if mise is available'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            tr('Hang tight while we confirm this device can run the mise CLI.'),
            style: TextStyle(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MissingMiseExperience extends ConsumerStatefulWidget {
  const _MissingMiseExperience();

  @override
  ConsumerState<_MissingMiseExperience> createState() =>
      _MissingMiseExperienceState();
}

class _MissingMiseExperienceState
    extends ConsumerState<_MissingMiseExperience> {
  static const _retryDebounce = Duration(seconds: 1);

  DateTime? _lastRetryAt;
  var _retrying = false;

  Future<void> _handleRetry() async {
    if (_retrying) {
      _showFeedback(tr('Checking again, please wait.'));
      return;
    }

    final now = DateTime.now();
    if (_lastRetryAt != null &&
        now.difference(_lastRetryAt!) < _retryDebounce) {
      _showFeedback(tr('Too many clicks. Try again in a second.'));
      return;
    }

    _lastRetryAt = now;
    setState(() => _retrying = true);

    try {
      final available = await ref.refresh(miseAvailableProvider.future);
      _showFeedback(
        tr(available ? 'mise CLI detected.' : 'mise CLI not detected yet.'),
      );
    } catch (_) {
      _showFeedback(tr('Re-check failed. Please try again later.'));
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final colors = AppTheme.colorsOf(context);
    final installCommand = recommendedMiseInstallCommand();
    final platformLabel = _currentPlatformLabel();

    return LayoutBuilder(
      builder: (context, viewport) {
        final targetHeight = viewport.maxHeight.isFinite
            ? (viewport.maxHeight - 56).clamp(720.0, 1600.0)
            : 760.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 34, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: targetHeight),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.panelRaised.withValues(alpha: 0.98),
                    colors.backgroundSoft.withValues(alpha: 0.92),
                    colors.accent.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: colors.borderStrong),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 1040;
                  final showFooterBand =
                      viewport.maxHeight >= 820 && constraints.maxWidth >= 760;
                  final hero = _MissingHeroText(platformLabel: platformLabel);
                  final commandCard = _InstallCommandCard(
                    installCommand: installCommand,
                    onCopy: () async {
                      await Clipboard.setData(
                        ClipboardData(text: installCommand),
                      );
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr('Install command copied to clipboard.'),
                          ),
                        ),
                      );
                    },
                    onRetry: _handleRetry,
                    retrying: _retrying,
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        hero,
                        const SizedBox(height: 24),
                        commandCard,
                        if (showFooterBand) ...[
                          const SizedBox(height: 24),
                          _MissingMiseFooterBand(),
                        ],
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: hero),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 34),
                              child: commandCard,
                            ),
                          ),
                        ],
                      ),
                      if (showFooterBand) ...[
                        const SizedBox(height: 28),
                        const _MissingMiseFooterBand(),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MissingHeroText extends StatelessWidget {
  const _MissingHeroText({required this.platformLabel});

  final String platformLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('mise is not installed on this computer'),
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 14),
        Text(
          tr(
            'Mise GUI needs a working mise CLI to read tool versions, project overrides, and global config. Install it and the features on the right will unlock.',
          ),
          style: TextStyle(color: colors.textMuted, fontSize: 16, height: 1.65),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.panel.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Icon(Icons.terminal_rounded, color: colors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trArgs('Recommended install for {platformLabel}', {
                            'platformLabel': platformLabel,
                          }),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            'Install, then click "Check again" on the right to enter the app.',
                          ),
                          style: TextStyle(
                            color: colors.textMuted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _StepRow(
                index: '01',
                title: 'Run the install command',
                description:
                    'Use the command on the right to install mise on this system.',
              ),
              const SizedBox(height: 12),
              _StepRow(
                index: '02',
                title: 'Verify the CLI works',
                description:
                    'After installing, run `mise --version` to verify the command works.',
              ),
              const SizedBox(height: 12),
              _StepRow(
                index: '03',
                title: 'Return to the app and check again',
                description:
                    'After installing, click "Check again" to restore the sidebar and full pages.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstallCommandCard extends StatelessWidget {
  const _InstallCommandCard({
    required this.installCommand,
    required this.onCopy,
    required this.onRetry,
    required this.retrying,
  });

  final String installCommand;
  final VoidCallback onCopy;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Install command'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        'Copy and run it in a terminal. No further setup is needed on this page.',
                      ),
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: colors.backgroundDeep.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.54
                    : 0.82,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.borderStrong),
            ),
            child: SelectableText(
              installCommand,
              style: TextStyle(
                fontFamily: 'FiraCode',
                fontSize: 14,
                height: 1.55,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tr('After installing, run `mise --version` once more.'),
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.content_copy_rounded),
                label: Text(tr('Copy install command')),
              ),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(tr(retrying ? 'Checking...' : 'Check again')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingMiseFooterBand extends StatelessWidget {
  const _MissingMiseFooterBand();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Available as soon as mise is installed'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Environment overview, tool versions, and global config connect automatically.',
            ),
            style: TextStyle(color: colors.textMuted, height: 1.55),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 280,
                child: _FooterFeatureTile(
                  icon: Icons.space_dashboard_rounded,
                  title: 'Environment overview',
                  description:
                      'Active tools, PATH exports, and an overall health score appear immediately.',
                ),
              ),
              SizedBox(
                width: 280,
                child: _FooterFeatureTile(
                  icon: Icons.handyman_rounded,
                  title: 'Tool versions',
                  description:
                      'Installed versions, active versions, and sources are detected automatically.',
                ),
              ),
              SizedBox(
                width: 320,
                child: _FooterFeatureTile(
                  icon: Icons.tune_rounded,
                  title: 'Global config',
                  description:
                      'Default versions and config file contents are read automatically.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterFeatureTile extends StatelessWidget {
  const _FooterFeatureTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSoft.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.info.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: colors.info, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(title), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  tr(description),
                  style: TextStyle(color: colors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.title,
    required this.description,
  });

  final String index;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.accent.withValues(alpha: 0.24)),
          ),
          alignment: Alignment.center,
          child: Text(
            index,
            style: TextStyle(
              color: colors.accent,
              fontFamily: 'FiraCode',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(title), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                tr(description),
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _currentPlatformLabel() {
  if (Platform.isMacOS) {
    return 'macOS';
  }
  if (Platform.isWindows) {
    return 'Windows';
  }
  if (Platform.isLinux) {
    return 'Linux';
  }
  return tr('Current system');
}
