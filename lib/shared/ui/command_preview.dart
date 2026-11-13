import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';

class CommandPreview extends StatelessWidget {
  const CommandPreview({super.key, required this.title, required this.command});

  final String title;
  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.backgroundSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: SelectableText(
              command,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
                height: 1.6,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
