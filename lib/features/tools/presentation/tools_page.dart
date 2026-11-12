import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/features/tools/application/tools_provider.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_action_service.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';
import 'package:mise_gui/shared/ui/action_preview_dialog.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/history_entry_dialog.dart';
import 'package:mise_gui/shared/ui/inline_notice_bar.dart';

List<String> selectVersionSuggestions(List<MiseRemoteToolVersionRef> versions) {
  final stableVersions = versions
      .where(
        (version) =>
            !version.rolling &&
            !(version.tool == 'java' &&
                _isJavaRuntimeOnlySuggestion(version.version)),
      )
      .toList();
  final source = stableVersions.isNotEmpty ? stableVersions : versions;
  if (source.isEmpty) {
    return const [];
  }

  final latestByMajor = <String, String>{};
  for (final version in source) {
    final value = version.version.trim();
    if (value.isEmpty) {
      continue;
    }

    final majorKey = _majorVersionKey(value);
    final current = latestByMajor[majorKey];
    if (current == null || compareToolVersions(value, current) > 0) {
      latestByMajor[majorKey] = value;
    }
  }

  final selected = latestByMajor.values.toList()
    ..sort((left, right) => compareToolVersions(right, left));
  return selected.take(5).toList(growable: false);
}

String _majorVersionKey(String input) {
  final match = RegExp(r'(\d+)').firstMatch(input);
  return match?.group(1) ?? input;
}

bool _isJavaRuntimeOnlySuggestion(String version) {
  final normalized = version.toLowerCase();
  return normalized.contains('-jre') || normalized.contains('+jre');
}

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  String? _selectedToolId;
  final Set<String> _requestedToolIds = <String>{};
  final Set<String> _loadingToolIds = <String>{};
  final Set<String> _failedToolIds = <String>{};
  final Map<String, ToolRecord> _hydratedTools = <String, ToolRecord>{};
  var _refreshing = false;

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadToolDetail(
    String toolId, {
    bool forceRefresh = false,
  }) async {
    if (_loadingToolIds.contains(toolId)) {
      return;
    }

    setState(() {
      _requestedToolIds.add(toolId);
      _loadingToolIds.add(toolId);
      _failedToolIds.remove(toolId);
    });

    try {
      final detail = forceRefresh
          ? await ref.refresh(toolDetailProvider(toolId).future)
          : await ref.read(toolDetailProvider(toolId).future);
      if (!mounted) {
        return;
      }
      setState(() {
        _hydratedTools[toolId] = detail;
        _failedToolIds.remove(toolId);
      });
    } catch (error) {
      _showFeedback(
        tr('Failed to load version details. Please try again later.'),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _failedToolIds.add(toolId);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingToolIds.remove(toolId);
        });
      }
    }
  }

  Future<void> _refreshTools() async {
    if (_refreshing) {
      _showFeedback(tr('Tool data is refreshing. Please wait.'));
      return;
    }

    setState(() {
      _refreshing = true;
      _hydratedTools.clear();
      _requestedToolIds.clear();
      _loadingToolIds.clear();
      _failedToolIds.clear();
    });

    try {
      final _ = await ref.refresh(toolsProvider.future);
      final selectedToolId = _selectedToolId;
      if (selectedToolId != null) {
        await _loadToolDetail(selectedToolId, forceRefresh: true);
      }
      _showFeedback(tr('Tool status refreshed.'));
    } catch (_) {
      _showFeedback(
        tr('Failed to refresh tool status. Please try again later.'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final toolsValue = ref.watch(toolsProvider);

    return AsyncStateView(
      value: toolsValue,
      builder: (tools) {
        final displayTools = tools
            .map((tool) => _hydratedTools[tool.id] ?? tool)
            .toList(growable: false);

        return AppPageScaffold(
          title: tr('Tool versions'),
          description: tr(
            'Review the current version of each tool and upgrade or uninstall when needed.',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refreshTools,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _refreshing ? tr('Refreshing...') : tr('Refresh status'),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openInstallToolFlow(context),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text(tr('Install tool')),
            ),
          ],
          child: _ToolList(
            tools: displayTools,
            selectedToolId: _selectedToolId,
            hydratedTools: _hydratedTools,
            loadingToolIds: _loadingToolIds,
            requestedToolIds: _requestedToolIds,
            failedToolIds: _failedToolIds,
            onSelected: _selectTool,
            onRetryDetail: _retryToolDetail,
            onOpenPreview: _openToolActionPreview,
          ),
        );
      },
    );
  }

  void _selectTool(String id) {
    if (_selectedToolId == id) {
      setState(() {
        _selectedToolId = null;
      });
      return;
    }

    setState(() {
      _selectedToolId = id;
      _requestedToolIds.add(id);
    });

    if (!_loadingToolIds.contains(id) &&
        !_hydratedTools.containsKey(id) &&
        !_failedToolIds.contains(id)) {
      unawaited(_loadToolDetail(id));
    }
  }

  void _retryToolDetail(String id) {
    unawaited(_loadToolDetail(id, forceRefresh: true));
  }

  Future<void> _openInstallToolFlow(BuildContext context) async {
    final request = await showDialog<_InstallToolRequest>(
      context: context,
      builder: (dialogContext) => const _InstallToolDialog(),
    );
    if (request == null || !mounted || !context.mounted) {
      return;
    }

    final installCommand = 'mise install ${request.tool}@${request.version}';
    final useCommand = 'mise use --global ${request.tool}@${request.version}';

    await _openToolActionPreview(
      context,
      ActionPreviewDialogData(
        title: trArgs('Install {tool}@{version}', {
          'tool': request.tool,
          'version': request.version,
        }),
        summary: tr(
          'Installs this version first, then sets it as the global default.',
        ),
        command: '$installCommand\n$useCommand',
        level: HealthLevel.info,
        affectedFiles: [
          _globalConfigPath(),
          tr('mise cache / installed versions'),
        ],
        impactScope: [
          tr('Changes the global default tool version.'),
          tr(
            'Refreshes the Tools and Overview pages when the install finishes.',
          ),
        ],
        riskNotes: [
          tr('Installing requires network access and may take a while.'),
          tr(
            'If the version is invalid, the install fails and the result is recorded in recent operations.',
          ),
        ],
        confirmLabel: tr('Confirm install'),
      ),
    );
  }

  Future<void> _openToolActionPreview(
    BuildContext context,
    ActionPreviewDialogData data,
  ) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showActionPreviewDialog(context, data: data);
    if (!confirmed) {
      if (data.requiresConfirmation) {
        await ref
            .read(historyServiceProvider)
            .appendEntry(
              HistoryEntry(
                command: data.command,
                timestamp: _formatNow(),
                detail: trArgs('User canceled {title}.', {'title': data.title}),
                level: HealthLevel.info,
                status: HistoryStatus.canceled,
              ),
            );
      }
      return;
    }

    if (!mounted || !context.mounted || !data.requiresConfirmation) {
      return;
    }

    final progressState = ValueNotifier<_ActionProgressState>(
      _ActionProgressState.initial(title: data.title, command: data.command),
    );
    _showRunningDialog(context, progressState: progressState);
    HistoryEntry? failureEntryToShow;
    String? snackMessage;
    try {
      final result = await ref
          .read(miseActionServiceProvider)
          .runScript(
            data.command,
            onProgress: (event) {
              progressState.value = progressState.value.apply(event);
            },
          );
      if (!mounted || !context.mounted) {
        return;
      }

      final success = result.isSuccess;
      final diagnosis = success
          ? null
          : diagnoseMiseCommandFailure(
              command: data.command,
              stdout: result.stdout,
              stderr: result.stderr,
            );
      final historyEntry = HistoryEntry(
        command: data.command,
        timestamp: _formatNow(),
        detail: success
            ? trArgs('Ran {title} from the app.', {'title': data.title})
            : _appendLockfileCleanupDetail(
                diagnosis?.detail ??
                    trArgs(
                      '{title} failed. The actual CLI command and error output were preserved.',
                      {'title': data.title},
                    ),
                result.lockfileCleanupReport.detail,
              ),
        level: success ? data.level : HealthLevel.warning,
        status: success ? HistoryStatus.success : HistoryStatus.failure,
        exitCode: result.exitCode,
        durationMs: result.duration.inMilliseconds,
        stdout: result.stdout,
        stderr: result.stderr,
        stdoutSnippet: result.stdoutSnippet,
        stderrSnippet: result.stderrSnippet,
      );
      await ref.read(historyServiceProvider).appendEntry(historyEntry);

      if (success) {
        final affectedToolIds = _extractAffectedToolIds(data.command);
        if (mounted) {
          setState(() {
            if (affectedToolIds.isEmpty) {
              _hydratedTools.clear();
              _requestedToolIds.clear();
              _loadingToolIds.clear();
              _failedToolIds.clear();
            } else {
              for (final toolId in affectedToolIds) {
                _hydratedTools.remove(toolId);
                _requestedToolIds.remove(toolId);
                _loadingToolIds.remove(toolId);
                _failedToolIds.remove(toolId);
              }
            }
          });
        }

        ref.invalidate(toolsProvider);
        await ref.read(toolsProvider.future);
        ref.invalidate(dashboardProvider);

        if (!mounted) {
          return;
        }

        for (final toolId in affectedToolIds) {
          if (toolId == _selectedToolId) {
            unawaited(_loadToolDetail(toolId, forceRefresh: true));
          }
        }
      } else {
        ref.invalidate(dashboardProvider);
      }

      snackMessage = _actionSnackMessage(
        title: data.title,
        success: success,
        diagnosis: diagnosis,
        cleanedLockfiles: result.lockfileCleanupReport.removedPaths.isNotEmpty,
      );
      if (!success) {
        failureEntryToShow = historyEntry;
      }
    } catch (error) {
      final historyEntry = HistoryEntry(
        command: data.command,
        timestamp: _formatNow(),
        detail: trArgs(
          '{title} raised an error. The app intercepted it and preserved the error details.',
          {'title': data.title},
        ),
        level: HealthLevel.warning,
        status: HistoryStatus.failure,
        exitCode: -1,
        stderr: error.toString(),
        stderrSnippet: error.toString(),
      );
      await ref.read(historyServiceProvider).appendEntry(historyEntry);
      snackMessage = trArgs(
        '{title} raised an error. Error details were opened.',
        {'title': data.title},
      );
      failureEntryToShow = historyEntry;
    } finally {
      if (rootNavigator.mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      progressState.dispose();
    }

    if (!mounted || !context.mounted) {
      return;
    }

    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(snackMessage)));

    if (failureEntryToShow != null) {
      await showHistoryEntryDialog(context, entry: failureEntryToShow);
    }
  }

  void _showRunningDialog(
    BuildContext context, {
    required ValueNotifier<_ActionProgressState> progressState,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _ActionProgressDialog(progressState: progressState),
      ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _appendLockfileCleanupDetail(String detail, String? cleanupDetail) {
    final value = cleanupDetail?.trim();
    if (value == null || value.isEmpty) {
      return detail;
    }
    return '$detail\n\n$value';
  }

  String _actionSnackMessage({
    required String title,
    required bool success,
    required MiseFailureDiagnosis? diagnosis,
    required bool cleanedLockfiles,
  }) {
    if (success) {
      return trArgs('{title} completed.', {'title': title});
    }
    if (cleanedLockfiles) {
      return trArgs('{title} failed. Leftover lock files were cleaned up.', {
        'title': title,
      });
    }
    if (diagnosis == null) {
      return trArgs('{title} failed. Error details were opened.', {
        'title': title,
      });
    }
    return trArgs('{title} failed: {summary}', {
      'title': title,
      'summary': diagnosis.summary,
    });
  }

  String _globalConfigPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '~/.config/mise/config.toml';
    }
    return '$home/.config/mise/config.toml';
  }

  Set<String> _extractAffectedToolIds(String command) {
    final toolIds = <String>{};
    final matcher = RegExp(
      r'mise\s+install\s+([a-zA-Z0-9._-]+)|mise\s+uninstall\s+(?:--all\s+)?([a-zA-Z0-9._-]+)|mise\s+use\s+(?:--global\s+)?(?:--remove\s+)?([a-zA-Z0-9._-]+)',
      caseSensitive: false,
    );

    for (final match in matcher.allMatches(command)) {
      final toolId = (match.group(1) ?? match.group(2) ?? match.group(3))
          ?.trim();
      if (toolId != null && toolId.isNotEmpty) {
        toolIds.add(toolId);
      }
    }

    return toolIds;
  }
}

class _ActionProgressState {
  const _ActionProgressState({
    required this.title,
    required this.totalCommands,
    required this.completedCommands,
    required this.currentCommandIndex,
    required this.currentCommand,
    required this.status,
    required this.logs,
  });

  final String title;
  final int totalCommands;
  final int completedCommands;
  final int currentCommandIndex;
  final String currentCommand;
  final String status;
  final List<String> logs;

  factory _ActionProgressState.initial({
    required String title,
    required String command,
  }) {
    final commands = _parseProgressCommands(command);
    return _ActionProgressState(
      title: title,
      totalCommands: commands.length,
      completedCommands: 0,
      currentCommandIndex: 0,
      currentCommand: commands.isEmpty ? command.trim() : commands.first,
      status: tr('Preparing to run'),
      logs: const [],
    );
  }

  double? get progressValue {
    if (totalCommands == 0) {
      return null;
    }
    final runningOffset = currentCommandIndex > completedCommands ? 0.35 : 0;
    final value = (completedCommands + runningOffset) / totalCommands;
    return value.clamp(0, 1).toDouble();
  }

  String get stepLabel {
    if (totalCommands == 0) {
      return tr('Preparing');
    }
    final index = currentCommandIndex == 0 ? 1 : currentCommandIndex;
    return '$index/$totalCommands';
  }

  _ActionProgressState apply(MiseActionProgressEvent event) {
    return switch (event.type) {
      MiseActionProgressEventType.commandStarted => _copyWith(
        currentCommandIndex: event.commandIndex,
        currentCommand: event.command,
        status: trArgs('Running {current}/{total}', {
          'current': event.commandIndex,
          'total': event.totalCommands,
        }),
        logs: _appendLogLines(logs, '\$ ${event.command}'),
      ),
      MiseActionProgressEventType.output => _copyWith(
        currentCommandIndex: event.commandIndex,
        currentCommand: event.command,
        status: trArgs('Running {current}/{total}', {
          'current': event.commandIndex,
          'total': event.totalCommands,
        }),
        logs: _appendLogLines(logs, event.output ?? ''),
      ),
      MiseActionProgressEventType.commandFinished => _copyWith(
        completedCommands: event.exitCode == 0
            ? event.commandIndex
            : completedCommands,
        currentCommandIndex: event.commandIndex,
        currentCommand: event.command,
        status: event.exitCode == 0
            ? trArgs('Completed {current}/{total}', {
                'current': event.commandIndex,
                'total': event.totalCommands,
              })
            : tr('Run failed. Collecting results.'),
        logs: _appendLogLines(logs, 'exit ${event.exitCode ?? -1}'),
      ),
      MiseActionProgressEventType.lockfileCleanup => _copyWith(
        status: tr('Handled error state'),
        logs: _appendLogLines(logs, event.lockfileCleanupReport?.detail ?? ''),
      ),
    };
  }

  _ActionProgressState _copyWith({
    int? completedCommands,
    int? currentCommandIndex,
    String? currentCommand,
    String? status,
    List<String>? logs,
  }) {
    return _ActionProgressState(
      title: title,
      totalCommands: totalCommands,
      completedCommands: completedCommands ?? this.completedCommands,
      currentCommandIndex: currentCommandIndex ?? this.currentCommandIndex,
      currentCommand: currentCommand ?? this.currentCommand,
      status: status ?? this.status,
      logs: logs ?? this.logs,
    );
  }

  static List<String> _parseProgressCommands(String command) {
    return const LineSplitter()
        .convert(command)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }

  static List<String> _appendLogLines(List<String> current, String output) {
    final normalized = output.replaceAll('\r', '\n');
    final nextLines = normalized
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
    if (nextLines.isEmpty) {
      return current;
    }

    final next = <String>[...current, ...nextLines];
    if (next.length <= 80) {
      return next;
    }
    return next.sublist(next.length - 80);
  }
}

class _ActionProgressDialog extends StatelessWidget {
  const _ActionProgressDialog({required this.progressState});

  final ValueNotifier<_ActionProgressState> progressState;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: ValueListenableBuilder<_ActionProgressState>(
        valueListenable: progressState,
        builder: (context, state, _) {
          return Semantics(
            liveRegion: true,
            label: '${state.title} ${state.status}',
            child: Container(
              width: 620,
              constraints: const BoxConstraints(maxHeight: 560),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.borderStrong),
                boxShadow: [
                  BoxShadow(
                    color: colors.backgroundDeep.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.3),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              state.status,
                              style: TextStyle(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        state.stepLabel,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: state.progressValue,
                      backgroundColor: colors.panelMuted,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CurrentCommandView(command: state.currentCommand),
                  const SizedBox(height: 14),
                  Flexible(child: _ActionLogView(logs: state.logs)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CurrentCommandView extends StatelessWidget {
  const _CurrentCommandView({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.panelMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        command,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ActionLogView extends StatelessWidget {
  const _ActionLogView({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      height: 260,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.backgroundDeep.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.42 : 0.06,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: logs.isEmpty
          ? Align(
              alignment: Alignment.topLeft,
              child: Text(
                tr('Waiting for mise output...'),
                style: TextStyle(color: colors.textMuted),
              ),
            )
          : ListView.builder(
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final line = logs[logs.length - index - 1];
                return Text(
                  line,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.42,
                  ),
                );
              },
            ),
    );
  }
}

class _ToolWorkspaceLoading extends StatelessWidget {
  const _ToolWorkspaceLoading({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(color: colors.textMuted, height: 1.55),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolWorkspaceError extends StatelessWidget {
  const _ToolWorkspaceError({required this.toolName, required this.onRetry});

  final String toolName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.warning.withValues(alpha: 0.24)),
            ),
            child: Icon(Icons.refresh_rounded, color: colors.warning, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trArgs('Could not load details for {tool}', {
                    'tool': toolName,
                  }),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Remote version sync may be temporarily unavailable, or the current network cannot reach the mise data source.',
                  ),
                  style: TextStyle(color: colors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          OutlinedButton.icon(
            key: ValueKey('retry-tool-detail-$toolName'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(tr('Retry')),
          ),
        ],
      ),
    );
  }
}

class _InstallToolRequest {
  const _InstallToolRequest({required this.tool, required this.version});

  final String tool;
  final String version;
}

class _InstallToolDialog extends ConsumerStatefulWidget {
  const _InstallToolDialog();

  @override
  ConsumerState<_InstallToolDialog> createState() => _InstallToolDialogState();
}

class _InstallToolDialogState extends ConsumerState<_InstallToolDialog> {
  final TextEditingController _toolController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final FocusNode _versionFocusNode = FocusNode();
  Timer? _lookupDebounce;
  var _loadingVersions = false;
  List<String> _versionSuggestions = const [];
  String? _lookupMessage;
  int _lookupToken = 0;

  @override
  void initState() {
    super.initState();
    _toolController.addListener(_scheduleVersionLookup);
    _versionFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _toolController.removeListener(_scheduleVersionLookup);
    _toolController.dispose();
    _versionController.dispose();
    _versionFocusNode.dispose();
    super.dispose();
  }

  void _scheduleVersionLookup() {
    final tool = _toolController.text.trim();
    final scheduledToken = ++_lookupToken;

    _lookupDebounce?.cancel();
    if (mounted) {
      setState(() {
        _versionSuggestions = const [];
        _lookupMessage = tool.isEmpty ? null : tr('Loading remote versions...');
        _loadingVersions = tool.isNotEmpty;
      });
    }
    _lookupDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadRemoteVersions(scheduledToken),
    );
  }

  Future<void> _loadRemoteVersions(int token) async {
    final tool = _toolController.text.trim();

    if (tool.isEmpty) {
      if (mounted && token == _lookupToken) {
        setState(() {
          _loadingVersions = false;
          _versionSuggestions = const [];
          _lookupMessage = null;
        });
      }
      return;
    }

    setState(() {
      _loadingVersions = true;
      _lookupMessage = null;
    });

    try {
      final versions = await ref
          .read(miseQueryServiceProvider)
          .fetchRemoteVersions(tool);
      if (!mounted || token != _lookupToken) {
        return;
      }
      final selected = selectVersionSuggestions(versions);

      setState(() {
        _loadingVersions = false;
        _versionSuggestions = selected;
        _lookupMessage = selected.isEmpty
            ? tr(
                'No selectable versions found. You can still enter one manually.',
              )
            : null;
      });
    } catch (error) {
      if (!mounted || token != _lookupToken) {
        return;
      }
      setState(() {
        _loadingVersions = false;
        _versionSuggestions = const [];
        _lookupMessage = tr(
          'Could not load remote versions. You can still enter a version manually.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: colors.backgroundDeep.withValues(alpha: 0.14),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Install a new tool'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Enter the tool name and version. You will review the command before it runs.',
              ),
              style: TextStyle(color: colors.textMuted, height: 1.55),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _toolController,
              decoration: InputDecoration(
                labelText: tr('Tool'),
                hintText: tr('e.g. node / python / go / php'),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _versionController,
              focusNode: _versionFocusNode,
              decoration: InputDecoration(
                labelText: tr('Version'),
                hintText: tr('e.g. 20 or 20.19.0 / 3.12 or 3.12.9 / latest'),
              ),
            ),
            if (_versionFocusNode.hasFocus &&
                (_loadingVersions ||
                    _versionSuggestions.isNotEmpty ||
                    _lookupMessage != null)) ...[
              const SizedBox(height: 10),
              _VersionSuggestionList(
                loading: _loadingVersions,
                versions: _versionSuggestions,
                message: _lookupMessage,
                selectedVersion: _versionController.text.trim(),
                onSelected: (version) {
                  _versionController.text = version;
                  _versionController.selection = TextSelection.collapsed(
                    offset: version.length,
                  );
                  _versionFocusNode.unfocus();
                  setState(() {});
                },
              ),
            ],
            const SizedBox(height: 18),
            Text(
              tr('The installed version becomes the global default.'),
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(tr('Continue to preview')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final tool = _toolController.text.trim();
    final version = _versionController.text.trim();
    if (tool.isEmpty || version.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Enter both a tool name and a version.'))),
      );
      return;
    }

    Navigator.of(
      context,
    ).pop(_InstallToolRequest(tool: tool, version: version));
  }
}

class _VersionSuggestionList extends StatelessWidget {
  const _VersionSuggestionList({
    required this.loading,
    required this.versions,
    required this.message,
    required this.selectedVersion,
    required this.onSelected,
  });

  final bool loading;
  final List<String> versions;
  final String? message;
  final String selectedVersion;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          : versions.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  child: Text(
                    tr(
                      'Available remote versions (latest release of each major line)',
                    ),
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var index = 0; index < versions.length; index++)
                  _VersionSuggestionRow(
                    version: versions[index],
                    selected: versions[index] == selectedVersion,
                    isFirst: index == 0,
                    onTap: () => onSelected(versions[index]),
                  ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                message ??
                    tr(
                      'No selectable versions found. You can still enter one manually.',
                    ),
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ),
    );
  }
}

class _VersionSuggestionRow extends StatelessWidget {
  const _VersionSuggestionRow({
    required this.version,
    required this.selected,
    required this.isFirst,
    required this.onTap,
  });

  final String version;
  final bool selected;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? colors.info.withValues(alpha: 0.12)
            : colors.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTapDown: (_) => onTap(),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: colors.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    version,
                    style: const TextStyle(
                      fontFamily: 'FiraCode',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isFirst)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tr('Latest'),
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_rounded, size: 18, color: colors.info),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolList extends StatelessWidget {
  const _ToolList({
    required this.tools,
    required this.selectedToolId,
    required this.hydratedTools,
    required this.loadingToolIds,
    required this.requestedToolIds,
    required this.failedToolIds,
    required this.onSelected,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final List<ToolRecord> tools;
  final String? selectedToolId;
  final Map<String, ToolRecord> hydratedTools;
  final Set<String> loadingToolIds;
  final Set<String> requestedToolIds;
  final Set<String> failedToolIds;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Installed'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            tr(
              'Review the current version of each tool and load upgrade information on demand.',
            ),
            style: TextStyle(color: colors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          for (final tool in tools)
            KeyedSubtree(
              key: ValueKey('tool-accordion-${tool.id}'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ToolAccordionItem(
                  tool: tool,
                  hydratedTool: hydratedTools[tool.id],
                  expanded: tool.id == selectedToolId,
                  detailLoading: loadingToolIds.contains(tool.id),
                  detailRequested: requestedToolIds.contains(tool.id),
                  detailFailed: failedToolIds.contains(tool.id),
                  onTap: () => onSelected(tool.id),
                  onRetryDetail: () => onRetryDetail(tool.id),
                  onOpenPreview: onOpenPreview,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolAccordionItem extends StatelessWidget {
  const _ToolAccordionItem({
    required this.tool,
    required this.hydratedTool,
    required this.expanded,
    required this.detailLoading,
    required this.detailRequested,
    required this.detailFailed,
    required this.onTap,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final ToolRecord? hydratedTool;
  final bool expanded;
  final bool detailLoading;
  final bool detailRequested;
  final bool detailFailed;
  final VoidCallback onTap;
  final VoidCallback onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final detail = _resolveDetail();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToolListItem(
          tool: tool,
          selected: expanded,
          detailLoading: detailLoading,
          detailRequested: detailRequested,
          detailFailed: detailFailed,
          onTap: onTap,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: detail,
        ),
      ],
    );
  }

  Widget _resolveDetail() {
    if (!expanded) {
      return const SizedBox.shrink(key: ValueKey('collapsed-detail'));
    }

    if (detailLoading && hydratedTool == null) {
      return _AccordionDetailShell(
        key: ValueKey('loading-detail-${tool.id}'),
        child: _ToolWorkspaceLoading(
          title: trArgs('Loading details for {tool}', {'tool': tool.name}),
          message: tr(
            'Remote versions and details will appear here when they are available.',
          ),
        ),
      );
    }

    final detailTool = hydratedTool;
    if (detailTool == null) {
      if (detailFailed) {
        return _AccordionDetailShell(
          key: ValueKey('failed-detail-${tool.id}'),
          child: _ToolWorkspaceError(
            toolName: tool.name,
            onRetry: onRetryDetail,
          ),
        );
      }
      return const SizedBox.shrink(key: ValueKey('empty-detail'));
    }

    return _AccordionDetailShell(
      key: ValueKey('ready-detail-${tool.id}-${detailTool.activeVersion}'),
      child: _ToolWorkspace(
        tool: detailTool,
        onRetryDetail: onRetryDetail,
        onOpenPreview: onOpenPreview,
      ),
    );
  }
}

class _AccordionDetailShell extends StatelessWidget {
  const _AccordionDetailShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      child: child,
    );
  }
}

class _ToolListItem extends StatelessWidget {
  const _ToolListItem({
    required this.tool,
    required this.selected,
    required this.detailLoading,
    required this.detailRequested,
    required this.detailFailed,
    required this.onTap,
  });

  final ToolRecord tool;
  final bool selected;
  final bool detailLoading;
  final bool detailRequested;
  final bool detailFailed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveVersion = tool.installedVersions.any(
      (version) => version.isActive,
    );
    final latestValue = switch ((
      detailLoading,
      detailRequested,
      detailFailed,
      tool.remoteState,
    )) {
      (true, _, _, _) => tr('Loading...'),
      (false, _, true, _) => tr('Load failed'),
      (false, false, _, _) => tr('Click to view'),
      (false, true, _, ToolRemoteState.unavailable) => tr('Not loaded'),
      _ => tool.latestStableVersion,
    };

    return Material(
      color: selected
          ? colors.info.withValues(alpha: 0.10)
          : isDark
          ? colors.panelRaised.withValues(alpha: 0.84)
          : colors.panelMuted.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: selected
              ? colors.info.withValues(alpha: 0.35)
              : colors.border.withValues(alpha: isDark ? 0.0 : 0.7),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tr(tool.category),
                style: TextStyle(color: colors.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniFact(
                    label: hasActiveVersion ? tr('Current') : tr('Installed'),
                    value: tool.activeVersion,
                  ),
                  _MiniFact(label: tr('Latest'), value: latestValue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolWorkspace extends StatelessWidget {
  const _ToolWorkspace({
    required this.tool,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final VoidCallback onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ToolHeroPanel(
          tool: tool,
          onRetryDetail: onRetryDetail,
          onOpenPreview: onOpenPreview,
        ),
        const SizedBox(height: 18),
        _VersionInventoryPanel(
          title: tr('Local versions'),
          subtitle: tr('Installed locally and ready to switch.'),
          toolId: tool.id,
          toolName: tool.name,
          inventoryType: _VersionInventoryType.installed,
          versions: tool.installedVersions,
          emptyState: _PanelEmptyStateData(
            icon: Icons.inventory_2_outlined,
            title: tr('No local versions yet'),
            message: tr(
              'Install at least one version to see the full local version list here.',
            ),
            level: HealthLevel.info,
          ),
          onOpenPreview: onOpenPreview,
        ),
        const SizedBox(height: 18),
        _VersionInventoryPanel(
          title: tr('Remote versions'),
          subtitle: tr('Remote versions available to install or upgrade.'),
          toolId: tool.id,
          toolName: tool.name,
          inventoryType: _VersionInventoryType.remote,
          versions: tool.remoteVersions,
          emptyState: _PanelEmptyStateData(
            icon: Icons.cloud_off_rounded,
            title: tr('No remote versions loaded yet'),
            message: tr(
              'Retry the sync later, or keep switching between the local versions above.',
            ),
            level: HealthLevel.warning,
          ),
          onOpenPreview: onOpenPreview,
        ),
      ],
    );
  }
}

class _ToolHeroPanel extends StatelessWidget {
  const _ToolHeroPanel({
    required this.tool,
    required this.onRetryDetail,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final VoidCallback onRetryDetail;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final recommendedVersion = _recommendedVersion(tool);
    final latestLabel = switch (tool.remoteState) {
      ToolRemoteState.pending => tr('Loading'),
      ToolRemoteState.unavailable => tr('Not loaded'),
      ToolRemoteState.ready => tool.latestStableVersion,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      trArgs('Current {version}', {
                        'version': tool.activeVersion,
                      }),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: 'FiraCode',
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trArgs('Latest stable {version}', {
                        'version': latestLabel,
                      }),
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 13,
                        fontFamily: 'FiraCode',
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (tool.hasUpdate && recommendedVersion != null)
                    FilledButton.icon(
                      onPressed: () => onOpenPreview(
                        context,
                        ActionPreviewDialogData(
                          title: trArgs('Upgrade {tool} to {version}', {
                            'tool': tool.name,
                            'version': recommendedVersion.version,
                          }),
                          summary: tr(
                            'Installs the new version first, then switches to it.',
                          ),
                          command: recommendedVersion.commandPreview,
                          level: HealthLevel.healthy,
                          affectedFiles: _affectedFilesForToolCommand(
                            recommendedVersion.commandPreview,
                          ),
                          impactScope: [
                            tr('Adds a local installed version.'),
                            tr(
                              'The default active version switches to the new version.',
                            ),
                          ],
                          riskNotes: [
                            tr(
                              'Upgrading requires network access and may take a while.',
                            ),
                          ],
                          confirmLabel: tr('Confirm upgrade'),
                        ),
                      ),
                      icon: const Icon(Icons.upgrade_rounded),
                      label: Text(
                        trArgs('Upgrade to {version}', {
                          'version': recommendedVersion.version,
                        }),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => onOpenPreview(
                      context,
                      ActionPreviewDialogData(
                        title: trArgs('Uninstall {tool}', {'tool': tool.name}),
                        summary: tr(
                          'Removes the tool from global config first, then deletes every installed version of the tool on this machine.',
                        ),
                        command:
                            'mise use --global --remove ${tool.id}\n'
                            'mise uninstall --all ${tool.id}',
                        level: HealthLevel.warning,
                        affectedFiles: _affectedFilesForToolCommand(
                          'mise use --global --remove ${tool.id}\n'
                          'mise uninstall --all ${tool.id}',
                        ),
                        impactScope: [
                          tr(
                            'The tool is no longer declared in global config.',
                          ),
                          tr(
                            'All locally installed versions of this tool are removed.',
                          ),
                          tr(
                            'Commands may still fail if other configs depend on this tool.',
                          ),
                        ],
                        riskNotes: [
                          tr(
                            'Confirm no other config depends on this tool before uninstalling.',
                          ),
                        ],
                        confirmLabel: tr('Confirm uninstall'),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(tr('Uninstall tool')),
                  ),
                ],
              ),
            ],
          ),
          if (tool.notices.isNotEmpty) ...[
            const SizedBox(height: 18),
            Column(
              children: [
                for (final notice in tool.notices) ...[
                  InlineNoticeBar(
                    notice: notice,
                    actionLabel: _canRetryRemoteNotice(notice)
                        ? tr('Retry')
                        : null,
                    actionIcon: _canRetryRemoteNotice(notice)
                        ? Icons.refresh_rounded
                        : null,
                    onAction: _canRetryRemoteNotice(notice)
                        ? onRetryDetail
                        : null,
                  ),
                  if (notice != tool.notices.last) const SizedBox(height: 12),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _canRetryRemoteNotice(InlineNotice notice) {
    return tool.remoteState == ToolRemoteState.unavailable &&
        notice.title.toLowerCase().contains(
          'remote directory temporarily unavailable',
        );
  }

  ToolVersionRecord? _recommendedVersion(ToolRecord tool) {
    for (final version in tool.remoteVersions) {
      if (version.isRecommended) {
        return version;
      }
    }
    return null;
  }
}

enum _VersionInventoryType { installed, remote }

class _VersionInventoryPanel extends StatelessWidget {
  const _VersionInventoryPanel({
    required this.title,
    required this.subtitle,
    required this.toolId,
    required this.toolName,
    required this.inventoryType,
    required this.versions,
    this.emptyState,
    required this.onOpenPreview,
  });

  final String title;
  final String subtitle;
  final String toolId;
  final String toolName;
  final _VersionInventoryType inventoryType;
  final List<ToolVersionRecord> versions;
  final _PanelEmptyStateData? emptyState;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolSectionHeader(
            title: title,
            subtitle: subtitle,
            badgeLabel: versions.length > 1
                ? trArgs(
                    '{count, plural, one {# version} other {# versions}}',
                    {'count': versions.length},
                  )
                : null,
          ),
          const SizedBox(height: 18),
          if (versions.isEmpty)
            _PanelEmptyStateCard(
              data:
                  emptyState ??
                  _PanelEmptyStateData(
                    icon: Icons.info_outline_rounded,
                    title: tr('No data to display'),
                    message: tr(
                      'Sync again later, or continue with the current local versions.',
                    ),
                    level: HealthLevel.info,
                  ),
              onOpenPreview: onOpenPreview,
            )
          else
            Column(
              children: [
                for (var index = 0; index < versions.length; index++) ...[
                  _VersionCard(
                    toolId: toolId,
                    toolName: toolName,
                    version: versions[index],
                    inventoryType: inventoryType,
                    onOpenPreview: onOpenPreview,
                  ),
                  if (index != versions.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.border.withValues(alpha: 0.46),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.toolId,
    required this.toolName,
    required this.version,
    required this.inventoryType,
    required this.onOpenPreview,
  });

  final String toolId;
  final String toolName;
  final ToolVersionRecord version;
  final _VersionInventoryType inventoryType;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final statusLabel = _statusLabel();
    final statusLevel = _statusLevel();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final actionRow = _VersionActions(
          toolId: toolId,
          toolName: toolName,
          version: version,
          inventoryType: inventoryType,
          onOpenPreview: onOpenPreview,
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              version.version,
              style: TextStyle(
                color: colors.textPrimary,
                fontFamily: 'FiraCode',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (statusLabel != null) ...[
              const SizedBox(height: 6),
              _VersionStateLabel(label: statusLabel, level: statusLevel),
            ],
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              info,
              const SizedBox(height: 12),
              actionRow,
              const SizedBox(height: 14),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              actionRow,
            ],
          ),
        );
      },
    );
  }

  String? _statusLabel() {
    if (version.isActive) {
      return tr('In use');
    }
    if (version.isRecommended) {
      return tr('Upgrade recommended');
    }
    if (version.isAlias) {
      return tr('Alias mapping');
    }
    return null;
  }

  HealthLevel _statusLevel() {
    if (version.isActive) {
      return HealthLevel.healthy;
    }
    if (version.isRecommended) {
      return HealthLevel.info;
    }
    return version.level;
  }
}

class _VersionActions extends StatelessWidget {
  const _VersionActions({
    required this.toolId,
    required this.toolName,
    required this.version,
    required this.inventoryType,
    required this.onOpenPreview,
  });

  final String toolId;
  final String toolName;
  final ToolVersionRecord version;
  final _VersionInventoryType inventoryType;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!version.isActive && version.isInstalled)
          TextButton(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: trArgs('Switch to {version}', {
                  'version': version.version,
                }),
                summary: tr(
                  'This version is already installed locally. Confirming will switch to it.',
                ),
                command: version.commandPreview,
                level: version.level,
                affectedFiles: _affectedFilesForToolCommand(
                  version.commandPreview,
                ),
                impactScope: [
                  tr('The default active version for this tool changes.'),
                  tr('Resolved versions for related projects may update.'),
                ],
                riskNotes: [
                  tr('Check for project-level overrides before switching.'),
                ],
                confirmLabel: tr('Confirm switch'),
              ),
            ),
            child: Text(tr('Switch')),
          )
        else if (!version.isInstalled)
          TextButton(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: trArgs('Install {version}', {
                  'version': version.version,
                }),
                summary: tr(
                  'This version is not installed locally. Confirming will start the install.',
                ),
                command: version.commandPreview,
                level: version.level,
                affectedFiles: _affectedFilesForToolCommand(
                  version.commandPreview,
                ),
                impactScope: [
                  tr('Adds a local installed version record.'),
                  tr(
                    'The active version source may change if it is activated next.',
                  ),
                ],
                riskNotes: [
                  tr(
                    'Installing accesses the network and updates the local cache.',
                  ),
                ],
                confirmLabel: version.isRecommended
                    ? tr('Confirm upgrade')
                    : tr('Confirm install'),
              ),
            ),
            child: Text(version.isRecommended ? tr('Upgrade') : tr('Install')),
          ),
        if (inventoryType == _VersionInventoryType.installed &&
            version.isInstalled)
          TextButton.icon(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: trArgs('Uninstall {tool} {version}', {
                  'tool': toolName,
                  'version': version.version,
                }),
                summary: version.isActive
                    ? tr(
                        'This version is currently in use. Uninstalling only removes the local install and does not change global or project config.',
                      )
                    : tr(
                        'Removes this locally installed version without changing global or project config.',
                      ),
                command: 'mise uninstall $toolId@${version.version}',
                level: HealthLevel.warning,
                affectedFiles: _affectedFilesForToolCommand(
                  'mise uninstall $toolId@${version.version}',
                ),
                impactScope: [
                  tr('Removes only this specific local install.'),
                  tr(
                    'Global and project configs are not changed automatically.',
                  ),
                ],
                riskNotes: version.isActive
                    ? [
                        tr(
                          'If the active version is removed and config still references it, later commands may report it as missing.',
                        ),
                        tr(
                          'Switch to another version or be ready to reinstall before uninstalling.',
                        ),
                      ]
                    : [
                        tr(
                          'If another project config still references this version, you may need to reinstall it after entering that project.',
                        ),
                      ],
                confirmLabel: tr('Confirm uninstall version'),
              ),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(tr('Uninstall')),
          ),
      ],
    );
  }
}

class _VersionStateLabel extends StatelessWidget {
  const _VersionStateLabel({required this.label, required this.level});

  final String label;
  final HealthLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final color = switch (level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ToolSectionHeader extends StatelessWidget {
  const _ToolSectionHeader({
    required this.title,
    required this.subtitle,
    this.badgeLabel,
  });

  final String title;
  final String subtitle;
  final String? badgeLabel;

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
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            if (badgeLabel != null) ...[
              const SizedBox(width: 12),
              _SectionCountLabel(label: badgeLabel!),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 1,
          width: double.infinity,
          color: colors.border.withValues(alpha: 0.8),
        ),
      ],
    );
  }
}

class _SectionCountLabel extends StatelessWidget {
  const _SectionCountLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Text(
      label,
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PanelEmptyStateData {
  const _PanelEmptyStateData({
    required this.icon,
    required this.title,
    required this.message,
    required this.level,
  });

  final IconData icon;
  final String title;
  final String message;
  final HealthLevel level;
}

class _PanelEmptyStateCard extends StatelessWidget {
  const _PanelEmptyStateCard({required this.data, this.onOpenPreview});

  final _PanelEmptyStateData data;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )?
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: switch (data.level) {
                    HealthLevel.healthy => colors.accent.withValues(
                      alpha: 0.14,
                    ),
                    HealthLevel.info => colors.info.withValues(alpha: 0.14),
                    HealthLevel.warning => colors.warning.withValues(
                      alpha: 0.14,
                    ),
                    HealthLevel.critical => colors.danger.withValues(
                      alpha: 0.14,
                    ),
                  },
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  data.icon,
                  color: switch (data.level) {
                    HealthLevel.healthy => colors.accent,
                    HealthLevel.info => colors.info,
                    HealthLevel.warning => colors.warning,
                    HealthLevel.critical => colors.danger,
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.message,
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontFamily: 'FiraCode',
        ),
      ),
    );
  }
}

List<String> _affectedFilesForToolCommand(String command) {
  final normalized = command.toLowerCase();
  final files = <String>[];
  final home = Platform.environment['HOME'];

  if (normalized.contains('mise use --global ')) {
    if (home != null && home.isNotEmpty) {
      files.add('$home/.config/mise/config.toml');
    } else {
      files.add('~/.config/mise/config.toml');
    }
  } else if (normalized.contains('mise use ')) {
    files.add('${Directory.current.path}/mise.toml');
  }

  if (normalized.contains('mise install ')) {
    files.add(tr('mise cache / installed versions'));
  }

  if (normalized.contains('mise uninstall ')) {
    files.add(tr('mise cache / installed versions'));
  }

  return files;
}
