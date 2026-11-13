import 'dart:async';

import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';

class _RemoteVersionLoadResult {
  const _RemoteVersionLoadResult({
    required this.versions,
    this.notice,
    this.latestStableVersion,
  });

  final List<MiseRemoteToolVersionRef> versions;
  final InlineNotice? notice;
  final String? latestStableVersion;
}

abstract class MiseCliService {
  Future<List<ToolRecord>> fetchTools();
  Future<List<EnvironmentSignal>> fetchEnvironmentSignals();
  Future<DashboardToolSummary> fetchDashboardToolSummary();
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool);
}

class LiveMiseCliService implements MiseCliService {
  const LiveMiseCliService({
    required MiseQueryService queryService,
    required MiseProcessService processService,
  }) : _queryService = queryService,
       _processService = processService;

  final MiseQueryService _queryService;
  final MiseProcessService _processService;

  @override
  Future<List<EnvironmentSignal>> fetchEnvironmentSignals() async {
    try {
      final shellEnvironment = await _processService.inspectShellEnvironment();
      final currentTools = await _queryService.fetchCurrentTools();
      final environment = await _queryService.fetchEnvironment();
      final settings = await _queryService.fetchSettings();

      final activeSummary = currentTools.isEmpty
          ? tr('No active tools resolved for the current directory.')
          : currentTools
                .map((tool) => '${tool.tool} ${tool.version}')
                .join(' / ');

      final exportedPath = environment['PATH']?.toString() ?? '';
      final pathEntries = exportedPath
          .split(':')
          .where((entry) => entry.isNotEmpty)
          .toList();
      final miseInstallEntries = pathEntries
          .where((entry) => entry.contains('/.local/share/mise/installs/'))
          .length;

      final javaHome = environment['JAVA_HOME']?.toString();
      final settingSources = _collectSettingSources(settings);

      return [
        if (shellEnvironment.source == ShellEnvironmentSource.desktopFallback)
          EnvironmentSignal(
            title: tr('Shell environment'),
            value: tr('Fallback'),
            detail:
                shellEnvironment.detail ??
                tr(
                  'Could not reliably read the login shell environment, so the desktop process environment is used. PATH and JAVA_HOME checks are more conservative, but core features still work.',
                ),
            level: HealthLevel.info,
          ),
        EnvironmentSignal(
          title: tr('Active toolchain'),
          value: trArgs(
            '{count, plural, one {# active item} other {# active items}}',
            {'count': currentTools.length},
          ),
          detail: activeSummary,
          level: currentTools.isEmpty
              ? HealthLevel.warning
              : HealthLevel.healthy,
        ),
        EnvironmentSignal(
          title: tr('PATH export'),
          value: trArgs(
            '{count, plural, one {# path entry} other {# path entries}}',
            {'count': miseInstallEntries},
          ),
          detail: miseInstallEntries == 0
              ? tr(
                  'mise env -J did not export any install directories, so command resolution may be unstable.',
                )
              : trArgs(
                  'PATH currently includes {count} mise install directories, which the UI can use to explain command sources.',
                  {'count': miseInstallEntries},
                ),
          level: miseInstallEntries == 0
              ? HealthLevel.warning
              : HealthLevel.healthy,
        ),
        EnvironmentSignal(
          title: 'JAVA_HOME',
          value: javaHome == null || javaHome.isEmpty
              ? tr('Not exported')
              : tr('Exported'),
          detail: javaHome == null || javaHome.isEmpty
              ? tr(
                  'JAVA_HOME is not exported in the current environment; Java builds may depend on extra shell configuration.',
                )
              : javaHome,
          level: javaHome == null || javaHome.isEmpty
              ? HealthLevel.warning
              : HealthLevel.healthy,
        ),
        EnvironmentSignal(
          title: tr('Config sources'),
          value: settingSources.isEmpty ? tr('Not found') : tr('Loaded'),
          detail: settingSources.isEmpty
              ? tr(
                  'No explicit configuration source was read from the settings command yet; config reading will be filled in later.',
                )
              : trArgs('Current setting sources: {sources}', {
                  'sources': settingSources.join(' / '),
                }),
          level: settingSources.isEmpty ? HealthLevel.info : HealthLevel.info,
        ),
      ];
    } catch (error) {
      if (isMiseCommandUnavailable(error)) {
        final installCommand = recommendedMiseInstallCommand();
        return [
          EnvironmentSignal(
            title: 'mise CLI',
            value: tr('Not detected'),
            detail: tr(
              'The desktop app could not find an executable mise command, so environment information is unavailable.',
            ),
            level: HealthLevel.critical,
          ),
          EnvironmentSignal(
            title: tr('First install state'),
            value: tr('Setup required'),
            detail: tr(
              'This looks like a first-run setup scenario; mock toolchain state should not be shown.',
            ),
            level: HealthLevel.warning,
          ),
          EnvironmentSignal(
            title: tr('Next step'),
            value: tr('Install mise first'),
            detail: trArgs(
              'Run `{command}` first, then reopen the app or click Refresh.',
              {'command': installCommand},
            ),
            level: HealthLevel.info,
          ),
          EnvironmentSignal(
            title: tr('Verification command'),
            value: 'mise --version',
            detail: tr(
              'After installation, confirm the CLI runs before checking PATH, shims, and project configuration.',
            ),
            level: HealthLevel.info,
          ),
        ];
      }
      return [
        EnvironmentSignal(
          title: tr('Failed to read environment signals'),
          value: tr('Unavailable'),
          detail: tr(
            'Environment information could not be read from the mise CLI this time. Please try again later.',
          ),
          level: HealthLevel.warning,
        ),
        EnvironmentSignal(
          title: tr('Suggested action'),
          value: tr('Refresh again'),
          detail: tr(
            'Try refreshing environment data first; if it still fails, inspect the error output.',
          ),
          level: HealthLevel.info,
        ),
      ];
    }
  }

  @override
  Future<DashboardToolSummary> fetchDashboardToolSummary() async {
    try {
      final installedTools = await _queryService.fetchInstalledTools();
      var activeToolCount = 0;

      for (final versions in installedTools.values) {
        if (versions.any((version) => version.active)) {
          activeToolCount += 1;
        }
      }

      return DashboardToolSummary(
        activeToolCount: activeToolCount,
        installedToolCount: installedTools.length,
        commandPreview: 'mise ls --json\nmise current',
      );
    } catch (error) {
      if (isMiseCommandUnavailable(error)) {
        return const DashboardToolSummary(
          activeToolCount: 0,
          installedToolCount: 0,
          commandPreview: 'mise --version',
        );
      }
      return const DashboardToolSummary(
        activeToolCount: 0,
        installedToolCount: 0,
        commandPreview: 'mise ls --json\nmise current',
      );
    }
  }

  @override
  Future<List<ToolRecord>> fetchTools() async {
    final installedTools = await _queryService.fetchInstalledTools();
    final tools = <ToolRecord>[];

    for (final entry in installedTools.entries) {
      final tool = entry.key;
      final versions = entry.value;
      final active = _resolveActiveVersion(versions);
      if (active == null) continue;

      tools.add(
        ToolRecord(
          id: tool,
          name: _toolName(tool),
          category: trArgs('{tool} version management', {
            'tool': _toolName(tool),
          }),
          description: _toolDescription(tool),
          activeVersion: active.version,
          requestedVersion: active.requestedVersion ?? active.version,
          source: _formatSource(active.source),
          strategy: _strategyDescription(active.source),
          latestStableVersion: tr('Pending sync'),
          latestPreviewVersion: active.version,
          installedVersions: versions
              .map(
                (version) => ToolVersionRecord(
                  version: version.version,
                  channel: version.active ? tr('Active') : tr('Installed'),
                  note: _installedNote(version),
                  commandPreview: _useCommandForSource(
                    tool,
                    version.version,
                    active.source,
                  ),
                  level: version.active
                      ? HealthLevel.healthy
                      : HealthLevel.info,
                  isInstalled: version.installed,
                  isActive: version.active,
                ),
              )
              .toList(),
          remoteVersions: const [],
          projectImpacts: _buildProjectImpacts(active),
          quickActions: _buildQuickActions(
            tool: tool,
            activeVersion: active.version,
            updateVersion: null,
            source: active.source,
          ),
          commandPreview: _buildCommandPreview(
            tool: tool,
            activeVersion: active.version,
            updateVersion: null,
            source: active.source,
          ),
          level: HealthLevel.info,
          updateVersion: null,
          remoteState: ToolRemoteState.pending,
        ),
      );
    }

    tools.sort((a, b) => a.name.compareTo(b.name));
    return tools;
  }

  @override
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    final remoteLoad = await _safeFetchRemoteVersions(
      tool.id,
      activeVersion: tool.activeVersion,
    );
    final windowsShimPath = await _processService.inspectWindowsShimPath();
    final miseExecutable = await _safeFetchMiseExecutable(tool.id);
    final shellExecutable = await _safeFetchShellExecutable(tool.id);
    final selectedRemoteVersions = _selectRemoteCandidates(
      tool: tool.id,
      activeVersion: tool.activeVersion,
      requestedVersion: tool.requestedVersion,
      versions: remoteLoad.versions,
    );
    final updateVersion = _resolveUpdateVersion(
      activeVersion: tool.activeVersion,
      remoteVersions: selectedRemoteVersions,
      outdatedEntry: remoteLoad.latestStableVersion == null
          ? null
          : <String, dynamic>{'latest': remoteLoad.latestStableVersion},
    );
    final resolvedLatestStableVersion =
        updateVersion ??
        (selectedRemoteVersions.isNotEmpty
            ? selectedRemoteVersions.first.version
            : remoteLoad.latestStableVersion ?? tool.activeVersion);
    final resolvedLatestPreviewVersion = selectedRemoteVersions.isNotEmpty
        ? selectedRemoteVersions.last.version
        : remoteLoad.latestStableVersion ?? tool.activeVersion;
    final pathConflictNotice = _buildPathConflictNotice(
      tool: tool.id,
      miseExecutable: miseExecutable,
      shellExecutable: shellExecutable,
    );
    final notices = <InlineNotice>[
      ?remoteLoad.notice,
      if (windowsShimPath.isMissing)
        _buildWindowsShimPathNotice(tool.id, windowsShimPath),
      ?pathConflictNotice,
    ];

    return tool.copyWith(
      latestStableVersion: resolvedLatestStableVersion,
      latestPreviewVersion: resolvedLatestPreviewVersion,
      remoteVersions: selectedRemoteVersions
          .map(
            (version) => ToolVersionRecord(
              version: version.version,
              channel: version.rolling
                  ? tr('Rolling version')
                  : tr('Remote version'),
              note: _remoteNote(version.version, tool.requestedVersion),
              commandPreview: version.version == updateVersion
                  ? _installAndUseCommandForSource(
                      tool.id,
                      version.version,
                      _resolveSourceRefFromLabel(tool.source),
                    )
                  : _installCommand(tool.id, version.version),
              level: version.version == updateVersion
                  ? HealthLevel.healthy
                  : HealthLevel.info,
              isRecommended: version.version == updateVersion,
            ),
          )
          .toList(),
      quickActions: _buildQuickActions(
        tool: tool.id,
        activeVersion: tool.activeVersion,
        updateVersion: updateVersion,
        source: _resolveSourceRefFromLabel(tool.source),
      ),
      commandPreview: _buildCommandPreview(
        tool: tool.id,
        activeVersion: tool.activeVersion,
        updateVersion: updateVersion,
        source: _resolveSourceRefFromLabel(tool.source),
      ),
      level: pathConflictNotice != null
          ? HealthLevel.warning
          : (updateVersion == null ? HealthLevel.info : HealthLevel.healthy),
      notices: notices,
      updateVersion: updateVersion,
      remoteState:
          remoteLoad.versions.isNotEmpty ||
              remoteLoad.latestStableVersion != null
          ? ToolRemoteState.ready
          : ToolRemoteState.unavailable,
    );
  }

  Future<_RemoteVersionLoadResult> _safeFetchRemoteVersions(
    String tool, {
    required String activeVersion,
  }) async {
    if (_prefersOutdatedLatestLookup(tool)) {
      final latestVersion = await _safeFetchOutdatedLatestVersion(
        tool,
        activeVersion: activeVersion,
      );
      return _RemoteVersionLoadResult(
        versions: _remoteVersionsFromLatest(
          tool: tool,
          activeVersion: activeVersion,
          latestVersion: latestVersion,
        ),
        latestStableVersion: latestVersion,
      );
    }

    try {
      return _RemoteVersionLoadResult(
        versions: await _queryService.fetchRemoteVersions(tool),
      );
    } catch (error) {
      final fallbackLatestVersion = await _safeFetchOutdatedLatestVersion(
        tool,
        activeVersion: activeVersion,
      );
      final fallbackVersions =
          fallbackLatestVersion != null &&
              fallbackLatestVersion != activeVersion
          ? <MiseRemoteToolVersionRef>[
              MiseRemoteToolVersionRef(
                tool: tool,
                version: fallbackLatestVersion,
                rolling: false,
              ),
            ]
          : const <MiseRemoteToolVersionRef>[];

      return _RemoteVersionLoadResult(
        versions: fallbackVersions,
        latestStableVersion: fallbackLatestVersion,
        notice: InlineNotice(
          title: trArgs('{tool} remote directory temporarily unavailable', {
            'tool': _toolName(tool),
          }),
          message: fallbackLatestVersion == null
              ? tr(
                  'Fell back to the locally installed version view; active version and source information are still reliable. Retry remote sync later.',
                )
              : tr(
                  'The direct remote list is unavailable, so mise outdated is used to find the latest stable version on the current line.',
                ),
          level: HealthLevel.warning,
          commandPreview: 'mise ls-remote --json $tool\n$error',
        ),
      );
    }
  }

  bool _prefersOutdatedLatestLookup(String tool) {
    return tool == 'python';
  }

  List<MiseRemoteToolVersionRef> _remoteVersionsFromLatest({
    required String tool,
    required String activeVersion,
    required String? latestVersion,
  }) {
    if (latestVersion == null || latestVersion == activeVersion) {
      return const <MiseRemoteToolVersionRef>[];
    }

    return <MiseRemoteToolVersionRef>[
      MiseRemoteToolVersionRef(
        tool: tool,
        version: latestVersion,
        rolling: false,
      ),
    ];
  }

  Future<String?> _safeFetchOutdatedLatestVersion(
    String tool, {
    required String activeVersion,
  }) async {
    try {
      final outdated = await _queryService.fetchOutdated();
      final entry = outdated[tool];
      if (entry is Map<String, dynamic>) {
        final latest = entry['latest']?.toString().trim();
        if (latest != null &&
            latest.isNotEmpty &&
            compareToolVersions(latest, activeVersion) > 0) {
          return latest;
        }
      }
      return activeVersion;
    } catch (_) {
      return null;
    }
  }

  Future<MiseResolvedExecutableRef?> _safeFetchMiseExecutable(
    String tool,
  ) async {
    try {
      return await _queryService.fetchExecutable(tool);
    } catch (_) {
      return null;
    }
  }

  Future<MiseResolvedExecutableRef?> _safeFetchShellExecutable(
    String tool,
  ) async {
    try {
      return await _queryService.fetchShellExecutable(tool);
    } catch (_) {
      return null;
    }
  }

  InlineNotice? _buildPathConflictNotice({
    required String tool,
    required MiseResolvedExecutableRef? miseExecutable,
    required MiseResolvedExecutableRef? shellExecutable,
  }) {
    final misePath = miseExecutable?.resolvedPath;
    final shellPath = shellExecutable?.resolvedPath;
    if (misePath == null || shellPath == null || misePath == shellPath) {
      return null;
    }

    final shellOwner = _runtimeOwnerLabel(shellPath);

    return InlineNotice(
      title: trArgs(
        '{tool} still resolves to another version manager in the current shell',
        {'tool': _toolName(tool)},
      ),
      message:
          '${trArgs('mise resolves to `{misePath}`, but the current shell executes `{shellPath}`.', {'misePath': misePath, 'shellPath': shellPath})}'
          '${shellOwner == null ? '' : ' ${trArgs('This looks like `{owner}` taking precedence over mise.', {'owner': shellOwner})}'} '
          '${tr('This is a PATH priority conflict, not an install failure.')}',
      level: HealthLevel.warning,
      commandPreview:
          'mise current $tool\n'
          'mise which $tool\n'
          'which $tool\n'
          'echo \$PATH',
    );
  }

  InlineNotice _buildWindowsShimPathNotice(
    String tool,
    WindowsShimPathStatus status,
  ) {
    return InlineNotice(
      title: tr('Windows terminal is not using mise shims yet'),
      message:
          status.detail ??
          trArgs(
            '{tool} is managed by mise but is not yet available in new cmd / PowerShell sessions. Run the command below, then reopen the terminal.',
            {'tool': _toolName(tool)},
          ),
      level: HealthLevel.warning,
      commandPreview: status.commandPreview,
    );
  }

  String? _runtimeOwnerLabel(String path) {
    if (path.contains('/.nvm/')) {
      return 'nvm';
    }
    if (path.contains('/.volta/')) {
      return 'Volta';
    }
    if (path.contains('/.asdf/')) {
      return 'asdf';
    }
    if (path.contains('/.local/share/fnm/')) {
      return 'fnm';
    }
    return null;
  }

  MiseInstalledToolVersionRef? _resolveActiveVersion(
    List<MiseInstalledToolVersionRef> versions,
  ) {
    for (final version in versions) {
      if (version.active) {
        return version;
      }
    }
    return versions.isEmpty ? null : versions.first;
  }

  List<MiseRemoteToolVersionRef> _selectRemoteCandidates({
    required String tool,
    required String activeVersion,
    required String requestedVersion,
    required List<MiseRemoteToolVersionRef> versions,
  }) {
    final normalizedRequested = requestedVersion.trim();
    final requestedMajor = _leadingMajor(normalizedRequested);
    final scopedVersions = _filterRemoteCandidateScope(
      tool: tool,
      requestedMajor: requestedMajor,
      versions: versions,
    ).toList();

    final upgradeCandidates =
        scopedVersions
            .where(
              (version) =>
                  compareToolVersions(version.version, activeVersion) > 0,
            )
            .toList()
          ..sort(
            (left, right) => compareToolVersions(left.version, right.version),
          );

    if (upgradeCandidates.isNotEmpty) {
      return _latestRemoteCandidates(upgradeCandidates);
    }

    final installableCandidates =
        scopedVersions
            .where((version) => version.version != activeVersion)
            .toList()
          ..sort(
            (left, right) => compareToolVersions(left.version, right.version),
          );

    return _latestRemoteCandidates(installableCandidates);
  }

  Iterable<MiseRemoteToolVersionRef> _filterRemoteCandidateScope({
    required String tool,
    required String? requestedMajor,
    required List<MiseRemoteToolVersionRef> versions,
  }) {
    final nonRolling = versions.where((version) => !version.rolling);

    if (tool == 'java' && requestedMajor != null) {
      return nonRolling.where(
        (version) =>
            _leadingMajor(version.version) == requestedMajor &&
            !_isJavaRuntimeOnlyVersion(version.version),
      );
    }

    if (tool == 'flutter') {
      final stableVersions = nonRolling
          .where((version) => version.version.contains('stable'))
          .toList();
      return stableVersions.isNotEmpty ? stableVersions : nonRolling;
    }

    if (requestedMajor != null) {
      return nonRolling.where(
        (version) => version.version.startsWith('$requestedMajor.'),
      );
    }

    return nonRolling;
  }

  bool _isJavaRuntimeOnlyVersion(String version) {
    final normalized = version.toLowerCase();
    return normalized.contains('-jre') || normalized.contains('+jre');
  }

  List<MiseRemoteToolVersionRef> _latestRemoteCandidates(
    List<MiseRemoteToolVersionRef> sortedVersions,
  ) {
    if (sortedVersions.isEmpty) {
      return const [];
    }

    final tail = sortedVersions.length <= 4
        ? sortedVersions
        : sortedVersions.sublist(sortedVersions.length - 4);
    return tail.reversed.toList();
  }

  String? _resolveUpdateVersion({
    required String activeVersion,
    required List<MiseRemoteToolVersionRef> remoteVersions,
    required dynamic outdatedEntry,
  }) {
    if (outdatedEntry is Map<String, dynamic>) {
      final latest = outdatedEntry['latest'] as String?;
      if (latest != null && compareToolVersions(latest, activeVersion) > 0) {
        return latest;
      }
    }

    if (remoteVersions.isEmpty) {
      return null;
    }

    return compareToolVersions(remoteVersions.first.version, activeVersion) > 0
        ? remoteVersions.first.version
        : null;
  }

  List<ToolProjectImpact> _buildProjectImpacts(
    MiseInstalledToolVersionRef active,
  ) {
    final source = active.source;
    if (source?.path == null) {
      return const [];
    }

    final path = source!.path!;
    final isGlobal = path.contains('/.config/mise/config.toml');

    return [
      ToolProjectImpact(
        projectName: isGlobal ? tr('Global config') : _basename(path),
        path: path,
        requestedVersion: active.requestedVersion ?? active.version,
        resolvedVersion: active.version,
        reason: isGlobal
            ? tr(
                'This version comes from the global configuration file and is not overridden by a project-level mise.toml.',
              )
            : tr(
                'This version is declared directly by the configuration file and applies in the current working directory.',
              ),
        level: isGlobal ? HealthLevel.info : HealthLevel.healthy,
      ),
    ];
  }

  List<ToolCommandAction> _buildQuickActions({
    required String tool,
    required String activeVersion,
    required String? updateVersion,
    required MiseSourceRef? source,
  }) {
    return [
      if (updateVersion != null)
        ToolCommandAction(
          label: tr('Upgrade to recommended version'),
          summary: trArgs('Install and switch to {version}.', {
            'version': updateVersion,
          }),
          command: _installAndUseCommandForSource(tool, updateVersion, source),
          level: HealthLevel.healthy,
        ),
      ToolCommandAction(
        label: tr('View current source'),
        summary: tr('Confirm the currently active version and source file.'),
        command: 'mise ls --json\nmise which $tool',
        level: HealthLevel.info,
      ),
      ToolCommandAction(
        label: tr('Review current version'),
        summary: trArgs(
          'Check how {version} applies in the current directory.',
          {'version': activeVersion},
        ),
        command: 'mise current $tool',
        level: HealthLevel.info,
      ),
    ];
  }

  String _buildCommandPreview({
    required String tool,
    required String activeVersion,
    required String? updateVersion,
    required MiseSourceRef? source,
  }) {
    final commands = <String>[
      'mise current $tool',
      'mise ls --json',
      if (updateVersion != null) _installCommand(tool, updateVersion),
      if (updateVersion != null)
        _useCommandForSource(tool, updateVersion, source),
      'mise which $tool',
    ];

    return commands.join('\n');
  }

  String _toolName(String tool) => switch (tool) {
    'go' => 'Go',
    'java' => 'Java',
    'python' => 'Python',
    'flutter' => 'Flutter',
    _ => tool[0].toUpperCase() + tool.substring(1),
  };

  String _toolDescription(String tool) => switch (tool) {
    'go' =>
      'Used for local backend and CLI toolchain builds, usually backed by the global default version.',
    'java' =>
      'Version and distribution combinations matter, and sources are especially useful to see in the UI.',
    'python' =>
      'Common for scripts, toolchains, and data work, where project overrides often diverge.',
    'flutter' =>
      'The core toolkit for this project; project-level pins and actual installed versions matter most.',
    _ => 'A local development tool version managed by mise.',
  };

  String _formatSource(MiseSourceRef? source) {
    if (source == null) {
      return 'Unknown';
    }

    return switch (source.type) {
      'mise.toml' =>
        (source.path?.contains('/.config/mise/') ?? false)
            ? 'Global'
            : 'Project',
      _ => source.type,
    };
  }

  MiseSourceRef? _resolveSourceRefFromLabel(String source) {
    return switch (source) {
      'Global' => const MiseSourceRef(
        type: 'mise.toml',
        path: '/.config/mise/config.toml',
      ),
      'Project' => const MiseSourceRef(
        type: 'mise.toml',
        path: '/workspace/mise.toml',
      ),
      _ => null,
    };
  }

  String _strategyDescription(MiseSourceRef? source) {
    if (source?.path == null) {
      return 'This version comes from the local installed list, but no explicit source is available yet.';
    }

    if (source!.path!.contains('/.config/mise/')) {
      return 'This version is determined by the global config.toml or global mise.toml and is inherited unless a project overrides it.';
    }

    return 'This version is determined by the project-level mise.toml and takes precedence over the global default.';
  }

  String _installedNote(MiseInstalledToolVersionRef version) {
    if (version.active) {
      return 'This is the version currently active in the working directory.';
    }
    if (version.source?.path != null) {
      return 'Installed and ready to switch; the most recent source file is ${version.source!.path}.';
    }
    return 'Installed but not currently active.';
  }

  String _remoteNote(String version, String requestedVersion) {
    return 'Remote version available; installation depends on the requested version $requestedVersion.';
  }

  String _installCommand(String tool, String version) =>
      'mise install $tool@$version';

  String _useCommand(String tool, String version) => 'mise use $tool@$version';

  String _useCommandForSource(
    String tool,
    String version,
    MiseSourceRef? source,
  ) {
    if (source?.path != null && source!.path!.contains('/.config/mise/')) {
      return 'mise use --global $tool@$version';
    }
    return _useCommand(tool, version);
  }

  String _installAndUseCommandForSource(
    String tool,
    String version,
    MiseSourceRef? source,
  ) {
    return [
      _installCommand(tool, version),
      _useCommandForSource(tool, version, source),
    ].join('\n');
  }

  String? _leadingMajor(String input) {
    final match = RegExp(r'(\d+)').firstMatch(input);
    return match?.group(1);
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  List<String> _collectSettingSources(Map<String, dynamic> settings) {
    final sources = <String>{};

    void visit(dynamic node) {
      if (node is Map<String, dynamic>) {
        final source = node['source']?.toString();
        if (source != null && source.isNotEmpty) {
          sources.add(source);
        }
        for (final value in node.values) {
          visit(value);
        }
      }
    }

    visit(settings);
    return sources.toList()..sort();
  }
}

int compareToolVersions(String left, String right) {
  final leftTokens = _VersionToken.parse(left);
  final rightTokens = _VersionToken.parse(right);
  final limit = leftTokens.length > rightTokens.length
      ? leftTokens.length
      : rightTokens.length;

  for (var index = 0; index < limit; index += 1) {
    if (index >= leftTokens.length) {
      return _remainingTokenWeight(rightTokens, index) == 0 ? 0 : -1;
    }
    if (index >= rightTokens.length) {
      return _remainingTokenWeight(leftTokens, index) == 0 ? 0 : 1;
    }

    final compared = leftTokens[index].compareTo(rightTokens[index]);
    if (compared != 0) {
      return compared;
    }
  }

  return 0;
}

int _remainingTokenWeight(List<_VersionToken> tokens, int startIndex) {
  for (var index = startIndex; index < tokens.length; index += 1) {
    final token = tokens[index];
    if (token is _NumericVersionToken && token.value == 0) {
      continue;
    }
    return 1;
  }
  return 0;
}

sealed class _VersionToken {
  const _VersionToken();

  factory _VersionToken.numeric(int value) = _NumericVersionToken;
  factory _VersionToken.text(String value) = _TextVersionToken;

  static List<_VersionToken> parse(String input) {
    final matches = RegExp(r'\d+|[A-Za-z]+').allMatches(input);
    return matches
        .map((match) {
          final value = match.group(0)!;
          final numeric = int.tryParse(value);
          if (numeric != null) {
            return _VersionToken.numeric(numeric);
          }
          return _VersionToken.text(value.toLowerCase());
        })
        .toList(growable: false);
  }

  int compareTo(_VersionToken other);
}

final class _NumericVersionToken extends _VersionToken {
  const _NumericVersionToken(this.value);

  final int value;

  @override
  int compareTo(_VersionToken other) {
    return switch (other) {
      _NumericVersionToken(:final value) => this.value.compareTo(value),
      _TextVersionToken() => -1,
    };
  }
}

final class _TextVersionToken extends _VersionToken {
  const _TextVersionToken(this.value);

  final String value;

  @override
  int compareTo(_VersionToken other) {
    return switch (other) {
      _NumericVersionToken() => 1,
      _TextVersionToken(:final value) => this.value.compareTo(value),
    };
  }
}

class MockMiseCliService implements MiseCliService {
  const MockMiseCliService();

  @override
  Future<List<EnvironmentSignal>> fetchEnvironmentSignals() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));

    return const [
      EnvironmentSignal(
        title: 'Shell 激活',
        value: '已激活',
        detail: 'zsh 已注入 mise hook，当前会话能正确解析 shim。',
        level: HealthLevel.healthy,
      ),
      EnvironmentSignal(
        title: 'PATH 顺序',
        value: '1 项提醒',
        detail: 'Homebrew bin 在部分项目 shell 中优先于 shim，建议保持 shim 靠前。',
        level: HealthLevel.warning,
      ),
      EnvironmentSignal(
        title: 'Shim 状态',
        value: '稳定',
        detail: 'node、python、java 的 shim 已命中当前激活版本。',
        level: HealthLevel.healthy,
      ),
      EnvironmentSignal(
        title: '代理与源配置',
        value: '待确认',
        detail: 'cargo 镜像与 Java 下载源还没有统一到界面配置入口。',
        level: HealthLevel.info,
      ),
    ];
  }

  @override
  Future<DashboardToolSummary> fetchDashboardToolSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));

    return const DashboardToolSummary(
      activeToolCount: 4,
      installedToolCount: 6,
      commandPreview: 'mise ls --json\nmise current',
    );
  }

  @override
  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return tool.copyWith(
      latestStableVersion: tool.activeVersion,
      latestPreviewVersion: tool.activeVersion,
      remoteState: ToolRemoteState.ready,
    );
  }

  @override
  Future<List<ToolRecord>> fetchTools() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));

    return const [
      ToolRecord(
        id: 'node',
        name: 'Node.js',
        category: 'JavaScript 运行时',
        description: '前端与全栈项目最常用的运行时，当前主要来自全局版本策略。',
        activeVersion: '20.16.0',
        requestedVersion: '20',
        source: '全局',
        strategy: '全局默认版本，项目未声明时直接继承。',
        latestStableVersion: '20.17.0',
        latestPreviewVersion: '23.0.0-rc.1',
        installedVersions: [
          ToolVersionRecord(
            version: '18.20.4',
            channel: '长期支持',
            note: '仍被老项目引用，适合作为兼容兜底。',
            commandPreview: 'mise use node@18.20.4',
            level: HealthLevel.info,
            isInstalled: true,
          ),
          ToolVersionRecord(
            version: '20.16.0',
            channel: '当前生效',
            note: '当前 shell 与多数项目的解析结果。',
            commandPreview: 'mise use --global node@20.16.0',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
          ),
          ToolVersionRecord(
            version: '22.3.0',
            channel: '当前分支',
            note: '已下载但尚未进入默认策略。',
            commandPreview: 'mise use node@22.3.0',
            level: HealthLevel.info,
            isInstalled: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: '20.17.0',
            channel: '稳定版',
            note: '建议升级目标，与现有项目兼容性最好。',
            commandPreview:
                'mise install node@20.17.0\nmise use --global node@20.17.0',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
          ToolVersionRecord(
            version: '22.4.1',
            channel: '当前分支',
            note: '适合新项目试用，但需要重新验证部分依赖。',
            commandPreview: 'mise install node@22.4.1',
            level: HealthLevel.info,
          ),
          ToolVersionRecord(
            version: '23.0.0-rc.1',
            channel: '预览版',
            note: '预览版，仅建议在隔离项目中验证。',
            commandPreview: 'mise install node@23.0.0-rc.1',
            level: HealthLevel.warning,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'mise_gui',
            path: '~/Documents/FlutterProject/mise_gui',
            requestedVersion: '20',
            resolvedVersion: '20.16.0',
            reason: '当前项目没有单独覆盖 Node，直接继承全局版本。',
            level: HealthLevel.healthy,
          ),
          ToolProjectImpact(
            projectName: 'infra-dashboard',
            path: '~/Workspaces/infra-dashboard',
            requestedVersion: '18',
            resolvedVersion: '18.20.4',
            reason: '项目锁定旧版 Node，升级全局不会影响它。',
            level: HealthLevel.info,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级到稳定版',
            summary: '安装并切换到 Node 20.17.0。',
            command:
                'mise install node@20.17.0\nmise use --global node@20.17.0',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '查看来源',
            summary: '确认当前 shell 究竟命中了哪一层版本。',
            command: 'mise current node\nmise where node',
            level: HealthLevel.info,
          ),
        ],
        commandPreview:
            'mise use --global node@20.16.0\nmise install node@20.17.0',
        level: HealthLevel.healthy,
        updateVersion: '20.17.0',
      ),
      ToolRecord(
        id: 'python',
        name: 'Python',
        category: '脚本运行时',
        description: '兼顾项目脚本和工具链依赖，当前版本被多个项目覆盖。',
        activeVersion: '3.11.9',
        requestedVersion: '3.11',
        source: '项目覆盖',
        strategy: '项目优先于全局，当前工作目录覆盖了默认 Python。',
        latestStableVersion: '3.12.5',
        latestPreviewVersion: '3.13.0b2',
        installedVersions: [
          ToolVersionRecord(
            version: '3.10.14',
            channel: '旧版本',
            note: '被老脚本链路保留，建议逐步淘汰。',
            commandPreview: 'mise use python@3.10.14',
            level: HealthLevel.warning,
            isInstalled: true,
          ),
          ToolVersionRecord(
            version: '3.11.9',
            channel: '当前生效',
            note: '当前项目命中的解释器版本。',
            commandPreview: 'mise use python@3.11.9',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
          ),
          ToolVersionRecord(
            version: '3.12.4',
            channel: '全局默认',
            note: '全局默认版本，但在当前目录被覆盖。',
            commandPreview: 'mise use --global python@3.12.4',
            level: HealthLevel.info,
            isInstalled: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: '3.11.10',
            channel: '补丁版',
            note: '最稳妥的升级路径，可先在当前项目尝试。',
            commandPreview: 'mise use python@3.11.10',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
          ToolVersionRecord(
            version: '3.12.5',
            channel: '稳定版',
            note: '适合准备切回全局统一策略时使用。',
            commandPreview: 'mise install python@3.12.5',
            level: HealthLevel.info,
          ),
          ToolVersionRecord(
            version: '3.13.0b2',
            channel: '预览版',
            note: '仅建议用于兼容性验证。',
            commandPreview: 'mise install python@3.13.0b2',
            level: HealthLevel.warning,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'api-gateway',
            path: '~/Workspaces/api-gateway',
            requestedVersion: '3.11',
            resolvedVersion: '3.11.9',
            reason: '项目明确锁定 Python 3.11，升级全局不会直接影响它。',
            level: HealthLevel.healthy,
          ),
          ToolProjectImpact(
            projectName: 'data-lab',
            path: '~/Workspaces/data-lab',
            requestedVersion: '3.12',
            resolvedVersion: '3.12.4',
            reason: '该项目依赖全局 3.12 分支，切换全局前需要先校验。',
            level: HealthLevel.warning,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级当前项目',
            summary: '仅把当前目录升级到 3.11.10。',
            command: 'mise use python@3.11.10',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '回看覆盖关系',
            summary: '确认是哪个 mise.toml 覆盖了全局 Python。',
            command: 'mise ls --current python\ncat mise.toml',
            level: HealthLevel.info,
          ),
        ],
        commandPreview: 'mise use python@3.11.9\nmise ls python',
        level: HealthLevel.warning,
        updateVersion: '3.11.10',
      ),
      ToolRecord(
        id: 'java',
        name: 'Java',
        category: 'Java 工具链',
        description: '需要展示发行版、别名和版本来源，是界面里最值得做透的工具之一。',
        activeVersion: 'temurin-21.0.3',
        requestedVersion: 'java@21',
        source: '配置别名',
        strategy: '通过别名与发行版策略把 java@21 解析到 temurin。',
        latestStableVersion: 'temurin-21.0.4',
        latestPreviewVersion: 'temurin-22.0.2',
        installedVersions: [
          ToolVersionRecord(
            version: 'zulu-17.52.17',
            channel: '旧版发行商',
            note: '历史项目仍依赖 Zulu 17，不能直接删除。',
            commandPreview: 'mise use java@zulu-17.52.17',
            level: HealthLevel.warning,
            isInstalled: true,
          ),
          ToolVersionRecord(
            version: 'temurin-21.0.3',
            channel: '当前别名',
            note: '当前别名解析到的默认 JDK。',
            commandPreview: 'mise use --global java@temurin-21.0.3',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
            isAlias: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: 'temurin-21.0.4',
            channel: '稳定版',
            note: '推荐补丁升级，能保持别名策略不变。',
            commandPreview: 'mise install java@temurin-21.0.4',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
          ToolVersionRecord(
            version: 'temurin-22.0.2',
            channel: '下一大版本',
            note: '需要评估 Maven/Gradle 项目兼容性后再升级。',
            commandPreview: 'mise install java@temurin-22.0.2',
            level: HealthLevel.info,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'legacy-jvm',
            path: '~/Archives/legacy-jvm',
            requestedVersion: '17',
            resolvedVersion: 'zulu-17.52.17',
            reason: '老项目依赖 Zulu 17，当前别名策略不会影响它。',
            level: HealthLevel.warning,
          ),
          ToolProjectImpact(
            projectName: 'infra-dashboard',
            path: '~/Workspaces/infra-dashboard',
            requestedVersion: '21',
            resolvedVersion: 'temurin-21.0.3',
            reason: '项目直接跟随别名策略，可无缝接受补丁升级。',
            level: HealthLevel.healthy,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级 Temurin',
            summary: '保留别名语义，只升级发行版的具体版本。',
            command:
                'mise install java@temurin-21.0.4\nmise use --global java@temurin-21.0.4',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '检查别名',
            summary: '查看 java@21 当前究竟解析到哪里。',
            command: 'mise alias ls java\nmise current java',
            level: HealthLevel.info,
          ),
        ],
        commandPreview:
            'mise settings set java.vendor temurin\nmise use --global java@temurin-21.0.3',
        level: HealthLevel.info,
        updateVersion: 'temurin-21.0.4',
      ),
      ToolRecord(
        id: 'bun',
        name: 'Bun',
        category: 'JavaScript 运行时',
        description: '作为更快的 JS 工具链补充，当前仅在个别项目启用。',
        activeVersion: '1.1.17',
        requestedVersion: '1',
        source: '全局',
        strategy: '默认不进入所有项目，只在明确启用的仓库中激活。',
        latestStableVersion: '1.1.19',
        latestPreviewVersion: '1.1.19',
        installedVersions: [
          ToolVersionRecord(
            version: '1.1.17',
            channel: '当前生效',
            note: '当前默认 Bun 版本，尚未广泛推广到所有项目。',
            commandPreview: 'mise use bun@1.1.17',
            level: HealthLevel.healthy,
            isInstalled: true,
            isActive: true,
          ),
        ],
        remoteVersions: [
          ToolVersionRecord(
            version: '1.1.18',
            channel: '补丁版',
            note: '轻量补丁升级，可先在单个项目验证。',
            commandPreview: 'mise install bun@1.1.18',
            level: HealthLevel.info,
          ),
          ToolVersionRecord(
            version: '1.1.19',
            channel: '稳定版',
            note: '当前建议升级目标。',
            commandPreview: 'mise install bun@1.1.19\nmise use bun@1.1.19',
            level: HealthLevel.healthy,
            isRecommended: true,
          ),
        ],
        projectImpacts: [
          ToolProjectImpact(
            projectName: 'frontend-spike',
            path: '~/Sandbox/frontend-spike',
            requestedVersion: '1.1',
            resolvedVersion: '1.1.17',
            reason: '仅实验项目使用 Bun，适合先在这里试升级。',
            level: HealthLevel.info,
          ),
        ],
        quickActions: [
          ToolCommandAction(
            label: '升级 Bun',
            summary: '把默认 Bun 升到 1.1.19。',
            command: 'mise install bun@1.1.19\nmise use bun@1.1.19',
            level: HealthLevel.healthy,
          ),
          ToolCommandAction(
            label: '查看覆盖范围',
            summary: '确认到底哪些项目在使用 Bun。',
            command: 'mise ls bun\nmise current bun',
            level: HealthLevel.info,
          ),
        ],
        commandPreview: 'mise install bun@1.1.19\nmise use bun@1.1.19',
        level: HealthLevel.healthy,
        updateVersion: '1.1.19',
      ),
    ];
  }
}
