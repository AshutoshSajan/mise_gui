import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/features/projects/application/projects_provider.dart';
import 'package:mise_gui/models/app_models.dart';

final selectedConfigProjectPathProvider = StateProvider<String?>((ref) => null);

final selectedConfigProjectProvider = Provider<ProjectRecord?>((ref) {
  final requestedPath = ref.watch(selectedConfigProjectPathProvider);
  final projects = ref
      .watch(projectsProvider)
      .maybeWhen(data: (items) => items, orElse: () => const <ProjectRecord>[]);

  if (projects.isEmpty) {
    return null;
  }

  ProjectRecord? findByPath(String path) {
    for (final project in projects) {
      if (project.path == path) {
        return project;
      }
    }
    return null;
  }

  if (requestedPath case final path?) {
    final selected = findByPath(path);
    if (selected != null) {
      return selected;
    }
  }

  final currentProject = findByPath(Directory.current.path);
  return currentProject ?? projects.first;
});

final configProvider = FutureProvider<ConfigWorkspaceData>((ref) {
  final project = ref.watch(selectedConfigProjectProvider);
  final hasTrackedProject = project != null;
  return ref
      .watch(configRepositoryProvider)
      .loadWorkspace(
        projectPath: project?.path,
        projectConfigPath: project?.configPath,
        projectName: project?.name,
        includeProjectConfig: hasTrackedProject,
      );
});
