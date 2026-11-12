import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';

Future<void> showHistoryEntryDialog(
  BuildContext context, {
  required HistoryEntry entry,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _HistoryEntryDialog(entry: entry),
  );
}

class _HistoryEntryDialog extends StatelessWidget {
  const _HistoryEntryDialog({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final statusColor = entry.isFailure ? colors.warning : colors.accent;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: colors.backgroundDeep.withValues(alpha: 0.16),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DialogStatusMeta(
                          label: tr(entry.status.label),
                          color: statusColor,
                          muted: !entry.isFailure,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          tr('Operation details'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.detail,
                          style: TextStyle(
                            color: colors.textMuted,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _DialogContextLine(entry: entry),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border.withValues(alpha: 0.46)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CommandBlock(entry: entry),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 760;
                        final stdout = _LogPanel(
                          title: 'Standard output',
                          content: entry.stdout?.trim().isNotEmpty == true
                              ? entry.stdout!
                              : tr('No standard output was recorded.'),
                        );
                        final stderr = _LogPanel(
                          title: entry.isFailure ? 'Error output' : 'Run log',
                          content: entry.stderr?.trim().isNotEmpty == true
                              ? entry.stderr!
                              : entry.isFailure
                              ? tr('No error output was recorded.')
                              : tr('No run log was recorded.'),
                          emphasize: entry.isFailure,
                        );

                        if (!wide) {
                          return Column(
                            children: [
                              stdout,
                              const SizedBox(height: 14),
                              stderr,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: stdout),
                            const SizedBox(width: 14),
                            Expanded(child: stderr),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogStatusMeta extends StatelessWidget {
  const _DialogStatusMeta({
    required this.label,
    required this.color,
    required this.muted,
  });

  final String label;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: muted ? 0.74 : 0.92),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          tr(label),
          style: TextStyle(
            color: muted ? colors.textMuted : color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DialogContextLine extends StatelessWidget {
  const _DialogContextLine({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final parts = <String>[entry.timestamp];
    if (entry.exitCode != null) {
      parts.add('exit ${entry.exitCode}');
    }
    if (entry.durationMs != null) {
      parts.add('${entry.durationMs}ms');
    }

    return Text(
      parts.join('  ·  '),
      style: TextStyle(
        color: colors.textMuted.withValues(alpha: 0.9),
        fontSize: 12,
        fontFamily: 'FiraCode',
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return _SurfaceBlock(
      title: 'Actual command',
      trailing: TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: entry.command));
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Actual CLI command copied.'))),
          );
        },
        icon: const Icon(Icons.content_copy_rounded, size: 16),
        label: Text(tr('Copy command')),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.backgroundSoft.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border.withValues(alpha: 0.34)),
        ),
        child: SelectableText(
          entry.command,
          style: TextStyle(
            color: colors.textPrimary,
            fontFamily: 'FiraCode',
            fontSize: 13,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({
    required this.title,
    required this.content,
    this.emphasize = false,
  });

  final String title;
  final String content;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return _SurfaceBlock(
      title: title,
      emphasize: emphasize,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 190, maxHeight: 280),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.backgroundSoft.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emphasize
                  ? colors.warning.withValues(alpha: 0.28)
                  : colors.border.withValues(alpha: 0.3),
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'FiraCode',
                fontSize: 12.5,
                height: 1.58,
                color: emphasize ? colors.warning : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SurfaceBlock extends StatelessWidget {
  const _SurfaceBlock({
    required this.title,
    required this.child,
    this.trailing,
    this.emphasize = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: emphasize
              ? colors.warning.withValues(alpha: 0.24)
              : colors.border.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(title),
                  style: TextStyle(
                    color: emphasize ? colors.warning : colors.textPrimary,
                    fontFamily: 'FiraCode',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
