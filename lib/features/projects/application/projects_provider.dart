import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/models/app_models.dart';

final projectsProvider = FutureProvider<List<ProjectRecord>>((ref) {
  ref.watch(appLocaleProvider);
  return ref.watch(projectsRepositoryProvider).loadProjects();
});

final projectCoverageProvider = FutureProvider<ProjectCoverageSnapshot>((ref) {
  ref.watch(appLocaleProvider);
  return ref.watch(projectsRepositoryProvider).loadCoverageSnapshot();
});
