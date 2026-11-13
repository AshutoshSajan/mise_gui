#!/usr/bin/env dart

// Checks that dependencies are on their latest versions.
//
// Direct and dev dependencies must always be current. Transitive dependencies
// are also checked, but only packages listed in
// scripts/outdated_deps_allowlist.json may stay behind their latest version.
// Each allowlist entry must explain the upstream or Flutter SDK constraint.
//
// Usage:
//   dart run scripts/check_outdated_deps.dart
//   dart run scripts/check_outdated_deps.dart --all
//
// --all prints the reason for every allowlisted transitive dependency.
//
// Set ALLOW_OUTDATED_DEPS=1 to report outdated dependencies without failing.
// Set FLUTTER_BIN to use a specific Flutter executable.
import 'dart:convert';
import 'dart:io';

const _defaultAllowlistPath = 'scripts/outdated_deps_allowlist.json';

Future<void> main(List<String> args) async {
  final showPinnedDetails = args.contains('--all');
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

  final List<_PinnedDependency> allowlist;
  try {
    allowlist = await _loadAllowlist();
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  final allowlistByPackage = {
    for (final entry in allowlist) entry.package: entry,
  };
  final packageByName = {
    for (final package in packages)
      if (package['package'] is String) package['package'] as String: package,
  };

  final outdated = <Map<String, dynamic>>[];
  final pinned = <_PinnedDependency>[];
  final changedPins = <_PinnedDependency>[];

  for (final package in packages) {
    final kind = package['kind'] as String? ?? '';
    final name = package['package'] as String?;
    final current = _versionOf(package['current']);
    final latest = _versionOf(package['latest']);
    if (name == null ||
        current == null ||
        latest == null ||
        current == latest) {
      continue;
    }

    if (kind == 'transitive') {
      final entry = allowlistByPackage[name];
      if (entry != null) {
        if (entry.current == current && entry.latest == latest) {
          pinned.add(entry);
          continue;
        }
        changedPins.add(entry);
      }
    }

    outdated.add({
      'package': name,
      'kind': kind,
      'current': current,
      'latest': latest,
      'resolvable': _versionOf(package['resolvable']),
    });
  }

  final prunablePins = allowlist.where((entry) {
    final package = packageByName[entry.package];
    if (package == null) {
      return true;
    }
    final current = _versionOf(package['current']);
    final latest = _versionOf(package['latest']);
    return current != null && current == latest;
  }).toList();

  if (outdated.isEmpty) {
    stdout.writeln('All direct and dev dependencies are up to date.');
    if (pinned.isNotEmpty) {
      if (showPinnedDetails) {
        stdout.writeln('');
        stdout.writeln('Pinned transitive dependencies (not actionable):');
        for (final entry in pinned) {
          stdout.writeln(
            '  - ${entry.package} (${entry.current} -> ${entry.latest})',
          );
          stdout.writeln('    ${entry.reason}');
        }
      } else {
        stdout.writeln(
          '${pinned.length} transitive '
          '${pinned.length == 1 ? 'package is' : 'packages are'} pinned by '
          'the Flutter SDK or upstream; run '
          '`dart run scripts/check_outdated_deps.dart --all` for details.',
        );
      }
    }
    _printPrunablePins(prunablePins);
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

  if (changedPins.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Allowlisted dependencies changed:');
    for (final entry in changedPins) {
      stdout.writeln(
        '  - ${entry.package}: allowlist expects '
        '${entry.current} -> ${entry.latest}; review the constraint and '
        'update scripts/outdated_deps_allowlist.json.',
      );
    }
  }

  _printPrunablePins(prunablePins);

  if (allowOutdated) {
    stdout.writeln('ALLOW_OUTDATED_DEPS=1 is set; not failing.');
    return;
  }

  stderr.writeln(
    'Dependency check failed. Run `flutter pub upgrade --major-versions`, '
    'then `flutter pub get`. If a transitive dependency is pinned upstream, '
    'add a documented entry to scripts/outdated_deps_allowlist.json.',
  );
  exitCode = 1;
}

Future<List<_PinnedDependency>> _loadAllowlist() async {
  final file = _resolveAllowlistFile();
  if (!file.existsSync()) {
    throw FormatException(
      'Missing dependency allowlist: ${file.path}\n'
      'Create it or restore it from version control.',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on FormatException catch (error) {
    throw FormatException('Could not parse ${file.path}: ${error.message}');
  }

  if (decoded is! Map<String, dynamic>) {
    throw FormatException('${file.path} must contain a JSON object.');
  }

  final entries = decoded['transitive'];
  if (entries == null) {
    return const [];
  }
  if (entries is! List<dynamic>) {
    throw FormatException('${file.path}: "transitive" must be a JSON array.');
  }

  return [
    for (final entry in entries) _PinnedDependency.fromJson(file.path, entry),
  ];
}

File _resolveAllowlistFile() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File('${directory.path}/$_defaultAllowlistPath');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return File(_defaultAllowlistPath);
}

void _printPrunablePins(List<_PinnedDependency> entries) {
  if (entries.isEmpty) {
    return;
  }
  stdout.writeln('');
  stdout.writeln('Allowlist entries that can be removed:');
  for (final entry in entries) {
    stdout.writeln(
      '  - ${entry.package} is no longer behind its latest version.',
    );
  }
}

String? _versionOf(Object? value) {
  if (value is Map<String, dynamic>) {
    return value['version'] as String?;
  }
  return null;
}

class _PinnedDependency {
  const _PinnedDependency({
    required this.package,
    required this.current,
    required this.latest,
    required this.reason,
  });

  factory _PinnedDependency.fromJson(String source, Object? value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$source: each allowlist entry must be an object.');
    }
    final package = value['package'];
    final current = value['current'];
    final latest = value['latest'];
    final reason = value['reason'];
    if (package is! String ||
        package.isEmpty ||
        current is! String ||
        current.isEmpty ||
        latest is! String ||
        latest.isEmpty ||
        reason is! String ||
        reason.isEmpty) {
      throw FormatException(
        '$source: each entry needs non-empty package, current, latest, '
        'and reason strings.',
      );
    }
    return _PinnedDependency(
      package: package,
      current: current,
      latest: latest,
      reason: reason,
    );
  }

  final String package;
  final String current;
  final String latest;
  final String reason;
}
