import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        final isMissingMise = isMiseCommandUnavailable(error);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppPanel(
              child: isMissingMise
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('mise was not detected'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'This page needs a working mise CLI to read environment information. Install it, then return and refresh.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          recommendedMiseInstallCommand(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : Text(
                      trArgs('Failed to load page: {error}', {
                        'error': error.toString(),
                      }),
                    ),
            ),
          ),
        );
      },
    );
  }
}
