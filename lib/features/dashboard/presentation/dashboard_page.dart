import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mise_gui/app/router/app_destination.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_self_update_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/history_entry_dialog.dart';
import 'package:mise_gui/shared/ui/recent_history_dialog.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  static const _refreshDebounce = Duration(seconds: 1);
  static const _autoRefreshInterval = Duration(seconds: 5);

  DateTime? _lastRefreshAt;
  var _refreshing = false;
  var _backgroundRefreshing = false;
  Timer? _autoRefreshTimer;
  var _pageVisible = false;
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_pageVisible == visible) {
      return;
    }
    _pageVisible = visible;
    _syncAutoRefreshTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAutoRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoRefreshTimer();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      _showFeedback(tr('Refreshing environment data, please wait.'));
      return;
    }

    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshDebounce) {
      _showFeedback(tr('Too many clicks. Try again in a second.'));
      return;
    }

    _lastRefreshAt = now;
    await _refreshDashboard(silent: false);
  }

  Future<void> _refreshDashboard({required bool silent}) async {
    if (!mounted) {
      return;
    }
    if (silent) {
      if (_refreshing || _backgroundRefreshing) {
        return;
      }
      _backgroundRefreshing = true;
    } else {
      if (_refreshing) {
        return;
      }
      setState(() => _refreshing = true);
    }

    try {
      final refreshed = ref.refresh(dashboardProvider.future);
      await refreshed;
      if (!silent) {
        _showFeedback(tr('Environment data refreshed.'));
      }
    } catch (error) {
      if (!silent) {
        _showFeedback(_formatRefreshError(error));
      }
    } finally {
      if (silent) {
        _backgroundRefreshing = false;
      } else if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  bool get _shouldAutoRefresh {
    final active =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    return _pageVisible && active;
  }

  void _syncAutoRefreshTimer() {
    if (_shouldAutoRefresh) {
      _startAutoRefreshTimer();
      return;
    }
    _stopAutoRefreshTimer();
  }

  void _startAutoRefreshTimer() {
    _autoRefreshTimer ??= Timer.periodic(_autoRefreshInterval, (_) {
      _refreshDashboard(silent: true);
    });
  }

  void _stopAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  String _formatRefreshError(Object error) {
    if (isMiseCommandUnavailable(error)) {
      return tr('Refresh failed: mise CLI not found.');
    }
    return tr('Refresh failed. Please try again later.');
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
    final snapshot = ref.watch(dashboardProvider);

    return AsyncStateView(
      value: snapshot,
      builder: (data) => AppPageScaffold(
        title: tr('Environment overview'),
        description: tr('Live state of your local mise environment.'),
        actions: [
          OutlinedButton.icon(
            onPressed: _handleRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              _refreshing
                  ? tr('Refreshing...')
                  : tr('Refresh environment data'),
            ),
          ),
        ],
        child: _DashboardOverview(snapshot: data),
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EnvironmentConsole(metrics: snapshot.metrics),
        const SizedBox(height: 30),
        const _MiseSelfUpdatePanel(),
        const SizedBox(height: 30),
        _RecentHistoryPanel(entries: snapshot.recentHistory),
      ],
    );
  }
}

class _EnvironmentConsole extends StatelessWidget {
  const _EnvironmentConsole({required this.metrics});

  final List<SummaryMetric> metrics;

  SummaryMetric? _metric(String label) {
    for (final metric in metrics) {
      if (metric.label == label) {
        return metric;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final systemMetric = _metric('Current system');
    final manifestMetrics = [
      _metric('Installed tools'),
      _metric('Project overrides'),
      _metric('Mise version'),
    ].whereType<SummaryMetric>().toList(growable: false);

    return AppPanel(
      padding: EdgeInsets.zero,
      radius: 22,
      backgroundAlpha: isDark ? 0.82 : 0.96,
      borderAlpha: isDark ? 0.62 : 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (systemMetric != null) _HostSection(metric: systemMetric),
          if (systemMetric != null && manifestMetrics.isNotEmpty)
            Divider(
              height: 1,
              thickness: 1,
              color: colors.border.withValues(alpha: isDark ? 0.38 : 0.62),
            ),
          if (manifestMetrics.isNotEmpty)
            _ManifestSection(metrics: manifestMetrics),
        ],
      ),
    );
  }
}

class _HostSection extends StatelessWidget {
  const _HostSection({required this.metric});

  final SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final details = _SystemMetricDetails.fromSystemInfo(metric.systemInfo);
    final accent = _levelColor(colors, metric.level);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ConsoleSectionLabel(label: 'Host'),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.15,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (details.chips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          for (final chip in details.chips)
                            _MetaPair(label: chip.label, value: chip.value),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (details.items.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SpecSheet(items: details.items),
          ],
        ],
      ),
    );
  }
}

class _ManifestSection extends StatelessWidget {
  const _ManifestSection({required this.metrics});

  final List<SummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ConsoleSectionLabel(label: 'Manifest'),
          const SizedBox(height: 4),
          for (final metric in metrics)
            _ManifestRow(
              key: _keyForMetric(metric.label),
              metric: metric,
              destination: _destinationForMetric(metric.label),
            ),
        ],
      ),
    );
  }
}

class _ManifestRow extends StatelessWidget {
  const _ManifestRow({
    super.key,
    required this.metric,
    required this.destination,
  });

  final SummaryMetric metric;
  final AppDestination? destination;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _levelColor(colors, metric.level);
    final leaderColor = colors.borderStrong.withValues(
      alpha: isDark ? 0.46 : 0.4,
    );

    final value = Text(
      metric.value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: colors.textPrimary,
        height: 1.2,
      ),
    );

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final dot = Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        );
        final label = Text(
          tr(metric.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        );
        final caption = metric.caption.trim().isEmpty
            ? null
            : Text(
                metric.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              );
        final arrow = destination == null
            ? const SizedBox(width: 17)
            : Icon(
                Icons.arrow_forward_rounded,
                size: 17,
                color: colors.textMuted.withValues(alpha: 0.86),
              );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  dot,
                  const SizedBox(width: 12),
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  value,
                  const SizedBox(width: 7),
                  arrow,
                ],
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 19),
                  child: caption,
                ),
              ],
            ],
          );
        }

        return Row(
          children: [
            dot,
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  if (caption != null) ...[const SizedBox(height: 3), caption],
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: CustomPaint(painter: _DottedLeaderPainter(leaderColor)),
              ),
            ),
            const SizedBox(width: 18),
            value,
            const SizedBox(width: 9),
            arrow,
          ],
        );
      },
    );

    if (destination == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: body,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(destination!.path),
        borderRadius: BorderRadius.circular(12),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: body,
        ),
      ),
    );
  }
}

class _ConsoleSectionLabel extends StatelessWidget {
  const _ConsoleSectionLabel({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Text(
          tr(label).toUpperCase(),
          style: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.9),
            fontSize: 10,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            height: 1,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            height: 1,
            color: colors.border.withValues(alpha: isDark ? 0.42 : 0.62),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class _MetaPair extends StatelessWidget {
  const _MetaPair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(label),
          style: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.88),
            fontSize: 10,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SpecSheet extends StatelessWidget {
  const _SpecSheet({required this.items});

  final List<_SystemInfoItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = colors.border.withValues(alpha: isDark ? 0.42 : 0.62);
    final fullWidthItems = items.where((item) => item.fullWidth).toList();
    final splitItems = items.where((item) => !item.fullWidth).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;

        return Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in fullWidthItems)
                _SpecCell(
                  item: item,
                  border: Border(
                    bottom: splitItems.isEmpty
                        ? BorderSide.none
                        : BorderSide(color: line),
                  ),
                ),
              if (splitItems.isNotEmpty)
                if (stacked)
                  Column(
                    children: [
                      for (var index = 0; index < splitItems.length; index++)
                        _SpecCell(
                          item: splitItems[index],
                          border: Border(
                            bottom: index == splitItems.length - 1
                                ? BorderSide.none
                                : BorderSide(color: line),
                          ),
                        ),
                    ],
                  )
                else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < splitItems.length;
                          index++
                        ) ...[
                          if (index > 0)
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: line,
                            ),
                          Expanded(
                            child: _SpecCell(
                              item: splitItems[index],
                              padding: EdgeInsets.only(
                                left: index == 0 ? 0 : 20,
                                right: index == 0 ? 20 : 0,
                                top: 14,
                                bottom: 14,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _SpecCell extends StatelessWidget {
  const _SpecCell({
    required this.item,
    this.border = const Border(),
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  final _SystemInfoItem item;
  final Border border;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      decoration: BoxDecoration(border: border),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(item.label),
            style: TextStyle(
              color: colors.textMuted.withValues(alpha: 0.88),
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedLeaderPainter extends CustomPainter {
  const _DottedLeaderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const gap = 6.0;
    const dash = 1.4;
    for (var x = 0.0; x < size.width; x += gap) {
      final end = x + dash > size.width ? size.width : x + dash;
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(end, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLeaderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

Color _levelColor(AppPalette colors, HealthLevel level) {
  return switch (level) {
    HealthLevel.healthy => colors.accent,
    HealthLevel.info => colors.info,
    HealthLevel.warning => colors.warning,
    HealthLevel.critical => colors.danger,
  };
}

AppDestination? _destinationForMetric(String label) {
  switch (label) {
    case 'Installed tools':
      return AppDestination.tools;
    case 'Project overrides':
      return AppDestination.projects;
    default:
      return null;
  }
}

Key? _keyForMetric(String label) {
  switch (label) {
    case 'Installed tools':
      return const ValueKey('dashboard-metric-tools');
    case 'Project overrides':
      return const ValueKey('dashboard-metric-projects');
    default:
      return null;
  }
}

class _MiseSelfUpdatePanel extends ConsumerStatefulWidget {
  const _MiseSelfUpdatePanel();

  @override
  ConsumerState<_MiseSelfUpdatePanel> createState() =>
      _MiseSelfUpdatePanelState();
}

class _MiseSelfUpdatePanelState extends ConsumerState<_MiseSelfUpdatePanel> {
  MiseSelfUpdateInfo? _updateInfo;
  var _checking = false;
  var _updating = false;
  final List<String> _logs = [];

  Future<void> _checkForUpdate({bool preserveLogs = false}) async {
    if (_checking || _updating) {
      return;
    }
    setState(() {
      _checking = true;
      if (!preserveLogs) {
        _logs.clear();
      }
    });

    try {
      final info = await ref
          .read(miseSelfUpdateServiceProvider)
          .checkForUpdate();
      if (!mounted) {
        return;
      }
      setState(() {
        _updateInfo = info;
      });
      _showFeedback(
        info.updateAvailable
            ? trArgs('mise {version} is available.', {
                'version': info.latestVersion,
              })
            : tr('mise is up to date.'),
      );
    } catch (error) {
      _showFeedback(
        tr('Failed to check for mise updates. Please try again later.'),
      );
      if (mounted) {
        setState(() {
          _logs
            ..clear()
            ..add(error.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _runSelfUpdate() async {
    final info = _updateInfo;
    if (info == null || _updating) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Upgrade mise')),
        content: Text(
          trArgs(
            'This will run `{command}` to upgrade mise from {current} to {latest}.\n\nDetected install source: {source}.',
            {
              'command': info.commandPreview,
              'current': info.currentVersion,
              'latest': info.latestVersion,
              'source': tr(info.installSourceLabel),
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr('Start upgrade')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _updating = true;
      _logs
        ..clear()
        ..add('\$ ${info.commandPreview}');
    });

    final stopwatch = Stopwatch()..start();
    var shouldRefreshAfterUpdate = false;
    try {
      final result = await ref
          .read(miseSelfUpdateServiceProvider)
          .selfUpdate(
            info: info,
            onOutput: (chunk) {
              if (!mounted) {
                return;
              }
              setState(() {
                _appendLogs(chunk.text);
              });
            },
          );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: info.commandPreview,
              timestamp: _formatNow(),
              detail: result.isSuccess
                  ? trArgs('Ran {command} from the app.', {
                      'command': info.commandPreview,
                    })
                  : trArgs('{command} failed.', {
                      'command': info.commandPreview,
                    }),
              level: result.isSuccess
                  ? HealthLevel.healthy
                  : HealthLevel.warning,
              status: result.isSuccess
                  ? HistoryStatus.success
                  : HistoryStatus.failure,
              exitCode: result.exitCode,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: result.stdout,
              stderr: result.stderr,
              stdoutSnippet: result.stdoutSnippet,
              stderrSnippet: result.stderrSnippet,
            ),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _appendLogs('exit ${result.exitCode}');
      });
      _showFeedback(
        result.isSuccess
            ? tr('mise upgraded successfully.')
            : tr('mise upgrade failed; details were recorded.'),
      );
      ref.invalidate(dashboardProvider);
      if (result.isSuccess) {
        shouldRefreshAfterUpdate = true;
      }
    } catch (error) {
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: info.commandPreview,
              timestamp: _formatNow(),
              detail: tr('mise self-update failed.'),
              level: HealthLevel.warning,
              status: HistoryStatus.failure,
              exitCode: -1,
              durationMs: stopwatch.elapsedMilliseconds,
              stderr: error.toString(),
              stderrSnippet: error.toString(),
            ),
          );
      if (mounted) {
        setState(() {
          _appendLogs(error.toString());
        });
        _showFeedback(tr('mise upgrade error; details were recorded.'));
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
        if (shouldRefreshAfterUpdate) {
          unawaited(_checkForUpdate(preserveLogs: true));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final info = _updateInfo;
    final updateAvailable = info?.updateAvailable ?? false;
    final accent = info == null
        ? colors.info
        : updateAvailable
        ? colors.warning
        : colors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ConsoleSectionLabel(label: 'Update'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 760;
            final summary = Row(
              children: [
                Icon(Icons.system_update_alt_rounded, color: accent, size: 19),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    tr('mise update'),
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 16),
                  ),
                ),
                if (info != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    updateAvailable ? tr('Update available') : tr('Up to date'),
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ],
            );
            final status = Text(
              _statusText(info),
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _checking || _updating ? null : _checkForUpdate,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    _checking ? tr('Checking...') : tr('Check for updates'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: updateAvailable && !_checking && !_updating
                      ? _runSelfUpdate
                      : null,
                  icon: _updating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upgrade_rounded, size: 18),
                  label: Text(
                    _updating ? tr('Upgrading...') : tr('Upgrade mise'),
                  ),
                ),
              ],
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: 6),
                  status,
                  const SizedBox(height: 12),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [summary, const SizedBox(height: 6), status],
                  ),
                ),
                const SizedBox(width: 24),
                Padding(padding: const EdgeInsets.only(top: 1), child: actions),
              ],
            );
          },
        ),
        if (info != null) ...[
          const SizedBox(height: 16),
          _MiseUpdateVersionRow(info: info),
        ],
        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MiseSelfUpdateLog(logs: _logs),
        ],
      ],
    );
  }

  String _statusText(MiseSelfUpdateInfo? info) {
    if (_updating) {
      return tr('Running the upgrade command. Keep the app open.');
    }
    if (info == null) {
      return tr(
        'Check the current mise CLI version against the latest GitHub release.',
      );
    }
    if (info.updateAvailable) {
      return trArgs(
        'Found {tag}; the upgrade will run in the GUI via {source}.',
        {'tag': info.tagName, 'source': tr(info.installSourceLabel)},
      );
    }
    return tr('mise is already up to date.');
  }

  void _appendLogs(String output) {
    final lines = output
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty);
    _logs.addAll(lines);
    if (_logs.length > 80) {
      _logs.removeRange(0, _logs.length - 80);
    }
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MiseUpdateVersionRow extends StatelessWidget {
  const _MiseUpdateVersionRow({required this.info});

  final MiseSelfUpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            _MetaPair(label: 'Current', value: info.currentVersion),
            _MetaPair(label: 'Latest', value: info.latestVersion),
            _MetaPair(label: 'Source', value: tr(info.installSourceLabel)),
            _MetaPair(label: 'Command', value: info.commandPreview),
            if (!info.updateAvailable)
              _MetaPair(label: 'Status', value: tr('Up to date')),
          ],
        ),
        if (info.updateAvailable && info.usesPackageManager) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    'Package-manager install detected; the system upgrade command will be used.',
                  ),
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MiseSelfUpdateLog extends StatelessWidget {
  const _MiseSelfUpdateLog({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.backgroundDeep.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.42 : 0.06,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: ListView.builder(
        reverse: true,
        shrinkWrap: true,
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final line = logs[logs.length - index - 1];
          return Text(
            line,
            style: TextStyle(
              color: colors.textMuted,
              fontFamily: 'FiraCode',
              fontSize: 12,
              height: 1.4,
            ),
          );
        },
      ),
    );
  }
}

class _RecentHistoryPanel extends StatelessWidget {
  const _RecentHistoryPanel({required this.entries});

  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = colors.border.withValues(alpha: isDark ? 0.4 : 0.62);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConsoleSectionLabel(
          label: 'Activity',
          trailing: entries.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => showRecentHistoryDialog(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(tr('View all')),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          tr('Review results of operations run from the app.'),
          style: TextStyle(color: colors.textMuted, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          _ActivityEmptyState(line: line)
        else
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: line)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < entries.length; index++) ...[
                  if (index > 0) Divider(height: 1, thickness: 1, color: line),
                  _ActivityRow(entry: entries[index]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final statusColor = entry.isFailure ? colors.warning : colors.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showHistoryEntryDialog(context, entry: entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr(entry.status.label).toUpperCase(),
                    style: TextStyle(
                      color: entry.isFailure
                          ? statusColor
                          : colors.textMuted.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '·',
                      style: TextStyle(
                        color: colors.textMuted.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    entry.timestamp,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.textMuted.withValues(alpha: 0.78),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontFamily: 'JetBrains Mono',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                entry.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState({required this.line});

  final Color line;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: line),
          bottom: BorderSide(color: line),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 18,
            color: colors.textMuted.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('No recent operations yet.'),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Run an install or upgrade from Tools and it will appear here.',
                  ),
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemMetricDetails {
  const _SystemMetricDetails({required this.chips, required this.items});

  final List<_SystemInfoChipData> chips;
  final List<_SystemInfoItem> items;

  factory _SystemMetricDetails.fromSystemInfo(SystemInfo? info) {
    if (info == null) {
      return const _SystemMetricDetails(chips: [], items: []);
    }

    return _SystemMetricDetails(
      chips: [
        if (info.build case final build? when build.isNotEmpty)
          _SystemInfoChipData(label: tr('Build'), value: build),
        if (info.architecture case final architecture?
            when architecture.isNotEmpty)
          _SystemInfoChipData(label: tr('Architecture'), value: architecture),
      ],
      items: [
        if (info.processor case final processor? when processor.isNotEmpty)
          _SystemInfoItem(
            label: tr('Processor'),
            value: processor,
            fullWidth: true,
          ),
        if (info.memory case final memory? when memory.isNotEmpty)
          _SystemInfoItem(label: tr('Memory'), value: memory),
        if (info.disk case final disk? when disk.isNotEmpty)
          _SystemInfoItem(label: tr('Disk'), value: disk),
      ],
    );
  }
}

class _SystemInfoChipData {
  const _SystemInfoChipData({required this.label, required this.value});

  final String label;
  final String value;
}

class _SystemInfoItem {
  const _SystemInfoItem({
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final bool fullWidth;
}
