import 'dart:ffi';
import 'dart:io';

import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/repositories/projects_repository.dart';
import 'package:mise_gui/services/history_service.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class DashboardRepository {
  const DashboardRepository({
    required this.miseCliService,
    required this.projectsRepository,
    required this.processService,
    required this.historyService,
  });

  final MiseCliService miseCliService;
  final ProjectsRepository projectsRepository;
  final MiseProcessService processService;
  final HistoryService historyService;

  Future<DashboardSnapshot> loadDashboard() async {
    final results = await Future.wait<dynamic>([
      miseCliService.fetchDashboardToolSummary(),
      projectsRepository.loadProjects(),
      _loadOperatingSystemInfo(),
      _loadMiseVersionInfo(),
      historyService.fetchHistory(),
    ]);

    final toolSummary = results[0] as DashboardToolSummary;
    final projects = results[1] as List<ProjectRecord>;
    final operatingSystemInfo = results[2] as _OperatingSystemInfo;
    final miseVersionInfo = results[3] as _MiseVersionInfo;
    final recentHistory = results[4] as List<HistoryEntry>;

    final declaredToolCount = projects.fold<int>(
      0,
      (sum, project) => sum + project.declaredToolCount,
    );
    final overrideProjectCount = projects
        .where((project) => project.hasOverrideRisk)
        .length;
    final overrideCount = projects.fold<int>(
      0,
      (sum, project) => sum + project.overrideCount,
    );

    return DashboardSnapshot(
      title: 'Environment overview',
      subtitle: '',
      metrics: [
        SummaryMetric(
          label: 'Current system',
          value: operatingSystemInfo.label,
          caption: operatingSystemInfo.caption,
          level: HealthLevel.info,
        ),
        SummaryMetric(
          label: 'Installed tools',
          value: trArgs('{count, plural, one {# tool} other {# tools}}', {
            'count': toolSummary.installedToolCount,
          }),
          caption: tr('Local tools currently managed by mise.'),
          level: toolSummary.installedToolCount > 0
              ? HealthLevel.healthy
              : HealthLevel.info,
        ),
        SummaryMetric(
          label: 'Project overrides',
          value: projects.isEmpty
              ? tr('Not configured')
              : overrideCount > 0
              ? trArgs('{count, plural, one {# project} other {# projects}}', {'count': overrideProjectCount})
              : tr('No overrides'),
          caption: projects.isEmpty
              ? tr('No project directories configured for scanning yet.')
              : overrideCount > 0
              ? trArgs(
                  'Scanned {projects} projects and found {overrides} overrides across {overrideProjects} projects.',
                  {
                    'projects': projects.length,
                    'overrides': overrideCount,
                    'overrideProjects': overrideProjectCount,
                  },
                )
              : declaredToolCount > 0
              ? trArgs('Scanned {count} projects; no global version overrides were found.', {
                  'count': projects.length,
                })
              : trArgs('Scanned {count} projects; no project-level version declarations were found.', {
                  'count': projects.length,
                }),
          level: overrideCount > 0
              ? HealthLevel.warning
              : projects.isEmpty
              ? HealthLevel.info
              : HealthLevel.healthy,
        ),
        SummaryMetric(
          label: 'Mise version',
          value: miseVersionInfo.version,
          caption: miseVersionInfo.detail,
          level: miseVersionInfo.level,
        ),
      ],
      signals: const [],
      toolSummary: toolSummary,
      recentHistory: recentHistory.take(3).toList(growable: false),
      riskHighlights: const [],
    );
  }

  String _operatingSystemLabel() {
    if (Platform.isMacOS) {
      return 'macOS';
    }
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    return Platform.operatingSystem;
  }

  Future<String?> _operatingSystemVersion() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sw_vers', const [
          '-productVersion',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }
      }

      if (Platform.isLinux) {
        final result = await Process.run('uname', const [
          '-r',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }
      }

      if (Platform.isWindows) {
        final version = Platform.operatingSystemVersion.trim();
        if (version.isNotEmpty) {
          return version;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String?> _operatingSystemBuild() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sw_vers', const [
          '-buildVersion',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _operatingSystemCaption() {
    final arch = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x64',
      _ => Abi.current().toString().split('.').last,
    };
    return '$arch arch';
  }

  Future<_OperatingSystemInfo> _loadOperatingSystemInfo() async {
    final systemName = _operatingSystemLabel();
    if (Platform.isWindows) {
      return _loadWindowsOperatingSystemInfo(systemName);
    }

    final version = await _operatingSystemVersion();
    final build = await _operatingSystemBuild();
    final label = version == null || version.isEmpty
        ? systemName
        : '$systemName $version';
    final captionParts = <String>[];

    if (build != null && build.isNotEmpty) {
      captionParts.add('Build $build');
    }
    captionParts.add(_operatingSystemCaption());
    await _appendDeviceDetails(captionParts);

    return _OperatingSystemInfo(label: label, caption: captionParts.join('\n'));
  }

  Future<_OperatingSystemInfo> _loadWindowsOperatingSystemInfo(
    String systemName,
  ) async {
    final parsed = _parseWindowsOperatingSystemVersion(
      Platform.operatingSystemVersion,
    );
    final captionParts = <String>[];

    if (parsed.build != null && parsed.build!.isNotEmpty) {
      captionParts.add('Build ${parsed.build}');
    }
    captionParts.add(_operatingSystemCaption());
    await _appendDeviceDetails(captionParts);

    final label = switch ((parsed.productName, parsed.kernelVersion)) {
      (final String productName?, _) when productName.isNotEmpty => productName,
      (_, final String kernelVersion?) when kernelVersion.isNotEmpty =>
        '$systemName $kernelVersion',
      _ => systemName,
    };

    return _OperatingSystemInfo(label: label, caption: captionParts.join('\n'));
  }

  _WindowsOperatingSystemVersion _parseWindowsOperatingSystemVersion(
    String raw,
  ) {
    final normalized = raw.trim();
    final productName = RegExp(
      r'"([^"]+)"',
    ).firstMatch(normalized)?.group(1)?.trim();
    final kernelVersion = RegExp(
      r'\b\d+\.\d+(?:\.\d+)?\b',
    ).firstMatch(normalized)?.group(0);
    final build = RegExp(
      r'build\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(normalized)?.group(1);

    return _WindowsOperatingSystemVersion(
      productName: productName,
      kernelVersion: kernelVersion,
      build: build,
    );
  }

  Future<void> _appendDeviceDetails(List<String> captionParts) async {
    final details = await Future.wait<String?>([
      _loadCpuModel(),
      _loadMemoryInfo(),
      _loadDiskInfo(),
    ]);

    final cpuModel = details[0];
    if (cpuModel != null && cpuModel.isNotEmpty) {
      captionParts.add(cpuModel);
    }

    final memoryInfo = details[1];
    if (memoryInfo != null && memoryInfo.isNotEmpty) {
      captionParts.add('Memory $memoryInfo');
    }

    final diskInfo = details[2];
    if (diskInfo != null && diskInfo.isNotEmpty) {
      captionParts.add('Disk $diskInfo');
    }
  }

  Future<String?> _loadCpuModel() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sysctl', const [
          '-n',
          'machdep.cpu.brand_string',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }

        final armResult = await Process.run(
          'sysctl',
          const ['-n', 'machdep.cpu.brand_string'],
          environment: const {'PATH': '/usr/sbin:/usr/bin:/bin:/sbin'},
          runInShell: false,
        );
        final armValue = (armResult.stdout ?? '').toString().trim();
        if (armResult.exitCode == 0 && armValue.isNotEmpty) {
          return armValue;
        }
      }

      if (Platform.isLinux) {
        final cpuInfo = await File('/proc/cpuinfo').readAsString();
        final value = parseLinuxCpuModel(cpuInfo);
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }

      if (Platform.isWindows) {
        final result = await _runWindowsPowerShell(
          'Get-CimInstance -ClassName Win32_Processor | '
          'Select-Object -First 1 -ExpandProperty Name',
        );
        final value = _firstNonEmptyLine(result?.stdout);
        if (result?.exitCode == 0 && value != null && value.isNotEmpty) {
          return value;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String?> _loadMemoryInfo() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sysctl', const [
          '-n',
          'hw.memsize',
        ], runInShell: false);
        final totalBytes = int.tryParse(
          (result.stdout ?? '').toString().trim(),
        );
        if (result.exitCode == 0 && totalBytes != null && totalBytes > 0) {
          return formatByteCount(totalBytes);
        }
      }

      if (Platform.isLinux) {
        final memInfo = await File('/proc/meminfo').readAsString();
        final totalBytes = parseLinuxMemoryBytes(memInfo);
        if (totalBytes != null && totalBytes > 0) {
          return formatByteCount(totalBytes);
        }
      }

      if (Platform.isWindows) {
        final result = await _runWindowsPowerShell(
          '(Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory',
        );
        final totalBytes = int.tryParse(
          _firstNonEmptyLine(result?.stdout) ?? '',
        );
        if (result?.exitCode == 0 && totalBytes != null && totalBytes > 0) {
          return formatByteCount(totalBytes);
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String?> _loadDiskInfo() async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('df', const [
          '-P',
          '-k',
          '/',
        ], runInShell: false);
        if (result.exitCode != 0) {
          return null;
        }
        final diskInfo = parsePosixDfKilobytes(result.stdout);
        if (diskInfo == null || diskInfo.totalBytes <= 0) {
          return null;
        }
        return trArgs('{available} free / {total} total', {
          'available': formatByteCount(diskInfo.availableBytes),
          'total': formatByteCount(diskInfo.totalBytes),
        });
      }

      if (Platform.isWindows) {
        final result = await _runWindowsPowerShell(r'''
$drive = $env:SystemDrive
if ([string]::IsNullOrWhiteSpace($drive)) { $drive = 'C:' }
$disk = Get-CimInstance -ClassName Win32_LogicalDisk |
  Where-Object { $_.DeviceID -eq $drive } |
  Select-Object -First 1
if ($null -ne $disk) {
  "FreeSpace=$($disk.FreeSpace)"
  "Size=$($disk.Size)"
}
''');
        if (result?.exitCode != 0) {
          return null;
        }
        final values = parseKeyValueOutput(result?.stdout);
        final freeBytes = int.tryParse(values['FreeSpace'] ?? '');
        final totalBytes = int.tryParse(values['Size'] ?? '');
        if (freeBytes == null || totalBytes == null || totalBytes <= 0) {
          return null;
        }
        return trArgs('{available} free / {total} total', {
          'available': formatByteCount(freeBytes),
          'total': formatByteCount(totalBytes),
        });
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<ProcessResult?> _runWindowsPowerShell(String command) async {
    for (final executable in const ['powershell.exe', 'powershell', 'pwsh']) {
      try {
        final result = await Process.run(executable, [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          command,
        ], runInShell: false);
        if (result.exitCode == 0) {
          return result;
        }
      } on ProcessException {
        continue;
      }
    }
    return null;
  }

  Future<_MiseVersionInfo> _loadMiseVersionInfo() async {
    try {
      final result = await processService.run(
        const MiseCommandRequest(
          arguments: ['--version'],
          timeout: Duration(seconds: 5),
        ),
      );
      final firstLine = result.stdout
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      final match = RegExp(r'(\d+(?:\.\d+){1,3})').firstMatch(firstLine);
      final version = match?.group(1) ?? firstLine;
      final detail = firstLine.replaceFirst(version, '').trim();

      return _MiseVersionInfo(
        version: version.isEmpty ? tr('Unknown') : version,
        detail: detail.isEmpty ? tr('mise CLI is available.') : detail,
        level: HealthLevel.info,
      );
    } catch (error) {
      if (isMiseCommandUnavailable(error)) {
        return _MiseVersionInfo(
          version: tr('Not detected'),
          detail: tr('No executable mise CLI is available on this device yet.'),
          level: HealthLevel.critical,
        );
      }
      return _MiseVersionInfo(
        version: tr('Failed to load'),
        detail: trArgs('Could not read the mise version: {error}', {'error': error}),
        level: HealthLevel.warning,
      );
    }
  }
}

class _MiseVersionInfo {
  const _MiseVersionInfo({
    required this.version,
    required this.detail,
    required this.level,
  });

  final String version;
  final String detail;
  final HealthLevel level;
}

class _OperatingSystemInfo {
  const _OperatingSystemInfo({required this.label, required this.caption});

  final String label;
  final String caption;
}

class _WindowsOperatingSystemVersion {
  const _WindowsOperatingSystemVersion({
    this.productName,
    this.kernelVersion,
    this.build,
  });

  final String? productName;
  final String? kernelVersion;
  final String? build;
}

String? parseLinuxCpuModel(String cpuInfo) {
  String? hardware;
  String? cpuModel;
  String? processor;
  for (final line in cpuInfo.split('\n')) {
    final separatorIndex = line.indexOf(':');
    if (separatorIndex == -1) {
      continue;
    }
    final key = line.substring(0, separatorIndex).trim().toLowerCase();
    final value = line.substring(separatorIndex + 1).trim();
    if (value.isEmpty) {
      continue;
    }
    if (key == 'model name') {
      return value;
    }
    if (key == 'hardware') {
      hardware ??= value;
    } else if (key == 'cpu model') {
      cpuModel ??= value;
    } else if (key == 'processor' && !RegExp(r'^\d+$').hasMatch(value)) {
      processor ??= value;
    }
  }
  return hardware ?? cpuModel ?? processor;
}

int? parseLinuxMemoryBytes(String memInfo) {
  for (final line in memInfo.split('\n')) {
    if (!line.startsWith('MemTotal:')) {
      continue;
    }
    final match = RegExp(r'(\d+)').firstMatch(line);
    final totalKb = int.tryParse(match?.group(1) ?? '');
    if (totalKb != null && totalKb > 0) {
      return totalKb * 1024;
    }
  }
  return null;
}

DiskSpaceInfo? parsePosixDfKilobytes(Object? stdout) {
  final lines = (stdout ?? '')
      .toString()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) {
    return null;
  }

  final columns = lines[1].trim().split(RegExp(r'\s+'));
  if (columns.length < 4) {
    return null;
  }

  final totalKb = int.tryParse(columns[1]);
  final availableKb = int.tryParse(columns[3]);
  if (totalKb == null || availableKb == null || totalKb <= 0) {
    return null;
  }
  return DiskSpaceInfo(
    availableBytes: availableKb * 1024,
    totalBytes: totalKb * 1024,
  );
}

Map<String, String> parseKeyValueOutput(Object? stdout) {
  final values = <String, String>{};
  for (final line in (stdout ?? '').toString().split('\n')) {
    final trimmed = line.trim();
    final separatorIndex = trimmed.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    final key = trimmed.substring(0, separatorIndex).trim();
    final value = trimmed.substring(separatorIndex + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      values[key] = value;
    }
  }
  return values;
}

String formatByteCount(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  final value = size >= 10 || size % 1 == 0
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$value ${units[unitIndex]}';
}

String? _firstNonEmptyLine(Object? stdout) {
  for (final line in (stdout ?? '').toString().split('\n')) {
    final value = line.trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

class DiskSpaceInfo {
  const DiskSpaceInfo({required this.availableBytes, required this.totalBytes});

  final int availableBytes;
  final int totalBytes;
}
