import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/features/tools/application/tools_provider.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_cli_service.dart';

class _LocalizedToolService extends MockMiseCliService {
  const _LocalizedToolService();

  @override
  Future<List<ToolRecord>> fetchTools() async {
    return [
      ToolRecord(
        id: 'demo',
        name: 'Demo',
        category: tr('Not set'),
        description: '',
        activeVersion: '',
        requestedVersion: '',
        source: '',
        strategy: '',
        latestStableVersion: '',
        latestPreviewVersion: '',
        installedVersions: const [],
        remoteVersions: const [],
        projectImpacts: const [],
        quickActions: const [],
        commandPreview: '',
        level: HealthLevel.info,
      ),
    ];
  }
}

void main() {
  test(
    'tools provider refreshes localized data after a language change',
    () async {
      final container = ProviderContainer(
        overrides: [
          miseCliServiceProvider.overrideWithValue(
            const _LocalizedToolService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final english = await container.read(toolsProvider.future);
      expect(english.single.category, 'Not set');

      container.read(appLanguageProvider.notifier).state = AppLanguage.chinese;
      AppLocalizations.sync(resolveAppLocale(AppLanguage.chinese));

      final chinese = await container.read(toolsProvider.future);
      expect(chinese.single.category, '未设置');
    },
  );
}
