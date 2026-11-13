import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/shared/ui/history_entry_dialog.dart';

Future<void> showRecentHistoryDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const RecentHistoryDialog(),
  );
}

class RecentHistoryDialog extends ConsumerStatefulWidget {
  const RecentHistoryDialog({super.key});

  @override
  ConsumerState<RecentHistoryDialog> createState() =>
      _RecentHistoryDialogState();
}

class _RecentHistoryDialogState extends ConsumerState<RecentHistoryDialog> {
  late Future<List<HistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<HistoryEntry>> _loadHistory() {
    return ref.read(historyServiceProvider).fetchHistory();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.borderStrong),
        ),
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
                        tr('Recent operations'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          'Review commands run from the app and their output.',
                        ),
                        style: TextStyle(color: colors.textMuted, height: 1.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<HistoryEntry>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        tr(
                          'Failed to load recent operations. Please try again later.',
                        ),
                        style: TextStyle(color: colors.textMuted),
                      ),
                    );
                  }

                  final entries = snapshot.data ?? const <HistoryEntry>[];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        tr('No recent operations yet.'),
                        style: TextStyle(color: colors.textMuted),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return RecentHistoryListTile(entry: entry);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentHistoryListTile extends StatelessWidget {
  const RecentHistoryListTile({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final preview = entry.isFailure
        ? (entry.stderrPreview ?? entry.stdoutPreview)
        : (entry.stdoutPreview ?? entry.stderrPreview);

    return Material(
      color: colors.panelRaised.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => showHistoryEntryDialog(context, entry: entry),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _HistoryStatusMeta(entry: entry),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textMuted.withValues(alpha: 0.74),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SelectableText(
                entry.command,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.detail,
                style: TextStyle(color: colors.textMuted, height: 1.5),
              ),
              if (preview != null && preview.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.backgroundSoft.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: entry.isFailure
                          ? colors.warning
                          : colors.textMuted,
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryStatusMeta extends StatelessWidget {
  const _HistoryStatusMeta({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final statusColor = entry.isFailure ? colors.warning : colors.accent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: entry.isFailure ? 0.9 : 0.74),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          tr(entry.status.label),
          style: TextStyle(
            color: entry.isFailure ? statusColor : colors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '·',
            style: TextStyle(
              color: colors.textMuted.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          entry.timestamp,
          style: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.92),
            fontSize: 12,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}
