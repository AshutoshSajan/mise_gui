import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';

class AppPageScaffold extends StatefulWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;

  @override
  State<AppPageScaffold> createState() => _AppPageScaffoldState();
}

class _AppPageScaffoldState extends State<AppPageScaffold> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrollBehavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);

    return ScrollConfiguration(
      behavior: scrollBehavior,
      child: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: false,
        thumbColor: colors.borderStrong.withValues(alpha: isDark ? 0.55 : 0.38),
        thickness: 7,
        radius: const Radius.circular(999),
        crossAxisMargin: 8,
        mainAxisMargin: 18,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(28, 28, 38, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, colors),
              Padding(
                padding: const EdgeInsets.only(top: 22, bottom: 26),
                child: Divider(
                  height: 1,
                  color: colors.border.withValues(alpha: isDark ? 0.42 : 0.62),
                ),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppPalette colors) {
    final titleBlock = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineLarge),
          if (widget.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.description,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.actions.isEmpty) {
      return titleBlock;
    }

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: widget.actions,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleBlock, const SizedBox(height: 16), actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 32),
            Padding(padding: const EdgeInsets.only(top: 2), child: actions),
          ],
        );
      },
    );
  }
}
