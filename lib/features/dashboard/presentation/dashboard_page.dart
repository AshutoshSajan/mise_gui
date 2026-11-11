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
        description: '',
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
      children: [
        _DashboardMetricGrid(metrics: snapshot.metrics),
        const SizedBox(height: 28),
        const _MiseSelfUpdatePanel(),
        const SizedBox(height: 28),
        _RecentHistoryPanel(entries: snapshot.recentHistory),
      ],
    );
  }
}

class _DashboardMetricGrid extends StatelessWidget {
  const _DashboardMetricGrid({required this.metrics});

  final List<SummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 20.0;
        final systemMetric = _metricByLabel('Current system');
        final compactMetrics = metrics
            .where((metric) => metric.label != 'Current system')
            .toList(growable: false);

        if (systemMetric == null) {
          return _MetricWrap(
            metrics: metrics,
            spacing: spacing,
            maxWidth: constraints.maxWidth,
          );
        }

        if (constraints.maxWidth >= 1180 && compactMetrics.length >= 3) {
          final systemWidth = (constraints.maxWidth - spacing) * 0.55;
          final compactWidth = constraints.maxWidth - spacing - systemWidth;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: systemWidth,
                child: _DashboardMetricCard(metric: systemMetric),
              ),
              const SizedBox(width: spacing),
              SizedBox(
                width: compactWidth,
                child: Column(
                  children: [
                    for (var index = 0; index < compactMetrics.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == compactMetrics.length - 1
                              ? 0
                              : spacing,
                        ),
                        child: _DashboardMetricCard(
                          metric: compactMetrics[index],
                          compact: true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        final compactColumns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final compactWidth =
            (constraints.maxWidth - spacing * (compactColumns - 1)) /
            compactColumns;

        return Column(
          children: [
            _DashboardMetricCard(metric: systemMetric),
            if (compactMetrics.isNotEmpty) ...[
              const SizedBox(height: spacing),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final metric in compactMetrics)
                    SizedBox(
                      width: compactWidth,
                      child: _DashboardMetricCard(
                        metric: metric,
                        compact: true,
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  SummaryMetric? _metricByLabel(String label) {
    for (final metric in metrics) {
      if (metric.label == label) {
        return metric;
      }
    }
    return null;
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({
    required this.metrics,
    required this.spacing,
    required this.maxWidth,
  });

  final List<SummaryMetric> metrics;
  final double spacing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final twoColumns = maxWidth >= 980;
    final cardWidth = twoColumns ? (maxWidth - spacing) / 2 : maxWidth;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final metric in metrics)
          SizedBox(
            width: cardWidth,
            child: _DashboardMetricCard(metric: metric),
          ),
      ],
    );
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
    final accent = updateAvailable ? colors.warning : colors.info;

    return AppPanel(
      padding: const EdgeInsets.all(22),
      radius: 20,
      backgroundAlpha: 0.74,
      borderAlpha: 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.system_update_alt_rounded, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('mise update'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusText(info),
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _checking || _updating ? null : _checkForUpdate,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
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
                        : const Icon(Icons.upgrade_rounded),
                    label: Text(
                      _updating ? tr('Upgrading...') : tr('Upgrade mise'),
                    ),
                  ),
                ],
              ),
            ],
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
      ),
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

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _VersionChip(label: tr('Current'), value: info.currentVersion),
        _VersionChip(label: tr('Latest'), value: info.latestVersion),
        _VersionChip(label: tr('Source'), value: tr(info.installSourceLabel)),
        _VersionChip(
          label: tr('Command'),
          value: info.commandPreview,
          mono: true,
        ),
        if (!info.updateAvailable)
          _VersionChip(label: tr('Status'), value: tr('Up to date'))
        else if (info.usesPackageManager)
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.panelMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              tr(
                'Package-manager install detected; the system upgrade command will be used.',
              ),
              style: TextStyle(color: colors.textMuted, height: 1.4),
            ),
          ),
      ],
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.panelMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr(label), style: TextStyle(color: colors.textMuted)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontFamily: mono ? 'FiraCode' : null,
            ),
          ),
        ],
      ),
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

    return Column(
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
                    tr('Recent activity'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('Review results of operations run from the app.'),
                    style: TextStyle(color: colors.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            if (entries.isNotEmpty)
              TextButton.icon(
                onPressed: () => showRecentHistoryDialog(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(tr('View all')),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: colors.panel.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border.withValues(alpha: 0.38)),
            ),
            child: Text(
              tr('No recent operations yet.'),
              style: TextStyle(color: colors.textMuted),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return RecentHistoryListTile(entry: entry);
            },
          ),
      ],
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({required this.metric, this.compact = false});

  final SummaryMetric metric;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final destination = _destinationFor(metric.label);
    final accent = switch (metric.level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    const cardRadius = 20.0;
    final child = metric.label == 'Current system'
        ? _SystemMetricContent(metric: metric, accent: accent)
        : compact
        ? _CompactMetricContent(
            metric: metric,
            accent: accent,
            hasDestination: destination != null,
          )
        : _DefaultMetricContent(
            metric: metric,
            accent: accent,
            hasDestination: destination != null,
          );
    final panel = AppPanel(
      key: _keyFor(metric.label),
      padding: compact
          ? const EdgeInsets.fromLTRB(18, 18, 18, 16)
          : const EdgeInsets.all(22),
      radius: cardRadius,
      backgroundAlpha: 0.74,
      borderAlpha: 0.5,
      child: child,
    );

    if (destination == null) {
      return panel;
    }

    return Tooltip(
      message: trArgs('Open {destination}', {
        'destination': tr(destination.description),
      }),
      child: Semantics(
        button: true,
        label: trArgs('Open {metric}', {'metric': tr(metric.label)}),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(cardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(cardRadius),
            onTap: () => context.go(destination.path),
            child: panel,
          ),
        ),
      ),
    );
  }

  AppDestination? _destinationFor(String label) {
    switch (label) {
      case 'Installed tools':
        return AppDestination.tools;
      case 'Project overrides':
        return AppDestination.projects;
      default:
        return null;
    }
  }

  Key? _keyFor(String label) {
    switch (label) {
      case 'Installed tools':
        return const ValueKey('dashboard-metric-tools');
      case 'Project overrides':
        return const ValueKey('dashboard-metric-projects');
      default:
        return null;
    }
  }
}

class _CompactMetricContent extends StatelessWidget {
  const _CompactMetricContent({
    required this.metric,
    required this.accent,
    required this.hasDestination,
  });

  final SummaryMetric metric;
  final Color accent;
  final bool hasDestination;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 128),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconForMetric(metric.label),
                  color: accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr(metric.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (hasDestination)
                Icon(
                  Icons.arrow_forward_rounded,
                  color: colors.textMuted,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: accent,
              height: 1,
              fontSize: 34,
            ),
          ),
          if (metric.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              metric.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DefaultMetricContent extends StatelessWidget {
  const _DefaultMetricContent({
    required this.metric,
    required this.accent,
    required this.hasDestination,
  });

  final SummaryMetric metric;
  final Color accent;
  final bool hasDestination;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 178),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricHeader(
            label: metric.label,
            icon: _iconForMetric(metric.label),
            accent: accent,
            trailing: hasDestination
                ? Icon(
                    Icons.arrow_forward_rounded,
                    color: colors.textMuted,
                    size: 20,
                  )
                : null,
          ),
          const SizedBox(height: 26),
          Text(
            metric.value,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(color: accent, height: 1),
          ),
          if (metric.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              metric.caption,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SystemMetricContent extends StatelessWidget {
  const _SystemMetricContent({required this.metric, required this.accent});

  final SummaryMetric metric;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final details = _SystemMetricDetails.fromCaption(metric.caption);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 178),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricHeader(
            label: metric.label,
            icon: _iconForMetric(metric.label),
            accent: accent,
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              maxLines: 1,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: accent,
                height: 1,
                fontSize: 34,
              ),
            ),
          ),
          if (details.chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in details.chips)
                  _SystemInfoChip(label: chip.label, value: chip.value),
              ],
            ),
          ],
          if (details.items.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SystemInfoGrid(items: details.items),
          ],
        ],
      ),
    );
  }
}

class _MetricHeader extends StatelessWidget {
  const _MetricHeader({
    required this.label,
    required this.icon,
    required this.accent,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(tr(label), style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    );
  }
}

class _SystemInfoGrid extends StatelessWidget {
  const _SystemInfoGrid({required this.items});

  final List<_SystemInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final twoColumns = constraints.maxWidth >= 520;
        final tileWidth = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: item.fullWidth ? constraints.maxWidth : tileWidth,
                child: _SystemInfoTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _SystemInfoTile extends StatelessWidget {
  const _SystemInfoTile({required this.item});

  final _SystemInfoItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.panelMuted.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.44)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: colors.textMuted, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

class _SystemInfoChip extends StatelessWidget {
  const _SystemInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.info.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1,
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

  factory _SystemMetricDetails.fromCaption(String caption) {
    final chips = <_SystemInfoChipData>[];
    final items = <_SystemInfoItem>[];

    for (final line
        in caption
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)) {
      if (line.startsWith('Build ')) {
        chips.add(
          _SystemInfoChipData(label: 'Build', value: line.substring(6)),
        );
      } else if (line.endsWith(' arch') || line.endsWith(' 架构')) {
        final suffixLength = line.endsWith(' arch') ? 5 : 3;
        chips.add(
          _SystemInfoChipData(
            label: tr('Architecture'),
            value: line.substring(0, line.length - suffixLength),
          ),
        );
      } else if (line.startsWith('Memory ') || line.startsWith('内存 ')) {
        final prefixLength = line.startsWith('Memory ') ? 7 : 3;
        items.add(
          _SystemInfoItem(
            label: tr('Memory'),
            value: line.substring(prefixLength),
            icon: Icons.memory_rounded,
          ),
        );
      } else if (line.startsWith('Disk ') || line.startsWith('磁盘 ')) {
        final prefixLength = line.startsWith('Disk ') ? 5 : 3;
        items.add(
          _SystemInfoItem(
            label: tr('Disk'),
            value: line.substring(prefixLength),
            icon: Icons.storage_rounded,
          ),
        );
      } else {
        items.add(
          _SystemInfoItem(
            label: tr('Processor'),
            value: line,
            icon: Icons.developer_board_rounded,
            fullWidth: true,
          ),
        );
      }
    }

    return _SystemMetricDetails(chips: chips, items: items);
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
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;
}

IconData _iconForMetric(String label) {
  switch (label) {
    case 'Current system':
      return Icons.desktop_windows_rounded;
    case 'Installed tools':
      return Icons.extension_rounded;
    case 'Project overrides':
      return Icons.account_tree_rounded;
    case 'Mise version':
      return Icons.verified_rounded;
    default:
      return Icons.data_usage_rounded;
  }
}
