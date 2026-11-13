import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/models/app_models.dart';

final toolsProvider = FutureProvider<List<ToolRecord>>((ref) {
  ref.watch(appLocaleProvider);
  return ref.watch(toolsRepositoryProvider).loadTools();
});

final toolDetailProvider = FutureProvider.family<ToolRecord, String>((
  ref,
  toolId,
) async {
  final tools = await ref.watch(toolsProvider.future);
  final baseTool = tools.firstWhere((tool) => tool.id == toolId);
  return ref.watch(toolsRepositoryProvider).hydrateToolRemoteState(baseTool);
});
