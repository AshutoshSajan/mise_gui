#!/usr/bin/env dart

// Checks that all direct and dev dependencies are on their latest versions.
//
// Usage:
//   dart run scripts/check_outdated_deps.dart
//   dart run scripts/check_outdated_deps.dart --all
//
// Set ALLOW_OUTDATED_DEPS=1 to report outdated dependencies without failing.
// Set FLUTTER_BIN to use a specific Flutter executable.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final includeTransitive = args.contains('--all');
  final allowOutdated = Platform.environment['ALLOW_OUTDATED_DEPS'] == '1';
  final flutter = Platform.environment['FLUTTER_BIN'] ?? 'flutter';

  final result = await Process.run(flutter, [
    'pub',
    'outdated',
    '--json',
  ], runInShell: Platform.isWindows);

  if (result.exitCode != 0) {
    stderr.writeln(
      'Failed to check dependency versions with `$flutter pub outdated`.',
    );
    final error = result.stderr.toString().trim();
    if (error.isNotEmpty) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }

  final output = result.stdout.toString();
  final jsonStart = output.indexOf('{');
  if (jsonStart == -1) {
    stderr.writeln('Could not parse `$flutter pub outdated --json` output.');
    exitCode = 1;
    return;
  }

  final Map<String, dynamic> report;
  try {
    report = jsonDecode(output.substring(jsonStart)) as Map<String, dynamic>;
  } on FormatException catch (error) {
    stderr.writeln(
      'Could not parse `$flutter pub outdated --json` output: $error',
    );
    exitCode = 1;
    return;
  }

  final packages =
      (report['packages'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
      const <Map<String, dynamic>>[];

  final outdated = <Map<String, dynamic>>[];
  for (final package in packages) {
    final kind = package['kind'] as String? ?? '';
    if (!includeTransitive && kind == 'transitive') {
      continue;
    }

    final current = _versionOf(package['current']);
    final latest = _versionOf(package['latest']);
    if (current == null || latest == null || current == latest) {
      continue;
    }

    outdated.add({
      'package': package['package'],
      'kind': kind,
      'current': current,
      'latest': latest,
      'resolvable': _versionOf(package['resolvable']),
    });
  }

  if (outdated.isEmpty) {
    final scope = includeTransitive
        ? 'All dependencies'
        : 'All direct dependencies';
    stdout.writeln('$scope are up to date.');
    return;
  }

  stdout.writeln('Outdated dependencies:');
  for (final package in outdated) {
    final resolvable = package['resolvable'];
    final hint = resolvable != null && resolvable == package['latest']
        ? ' (constraint allows it)'
        : '';
    stdout.writeln(
      '  - ${package['package']} (${package['kind']}): '
      '${package['current']} -> ${package['latest']}$hint',
    );
  }

  if (allowOutdated) {
    stdout.writeln('ALLOW_OUTDATED_DEPS=1 is set; not failing.');
    return;
  }

  stderr.writeln(
    'Dependency check failed. Run `flutter pub upgrade --major-versions`, '
    'then `flutter pub get`.',
  );
  exitCode = 1;
}

String? _versionOf(Object? value) {
  if (value is Map<String, dynamic>) {
    return value['version'] as String?;
  }
  return null;
}
