import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/l10n/app_localizations.dart';

void main() {
  tearDown(() => AppLocalizations.sync(const Locale('en')));

  test('English is the source language', () {
    AppLocalizations.sync(const Locale('en'));

    expect(tr('Tool versions'), 'Tool versions');
    expect(tr('Environment overview'), 'Environment overview');
  });

  test('Chinese catalog translates English source strings', () {
    AppLocalizations.sync(const Locale('zh'));

    expect(tr('Tool versions'), '工具版本');
    expect(tr('Environment overview'), '环境总览');
    expect(tr('Configuration management'), '配置管理');
  });

  test('Chinese templates keep placeholders', () {
    AppLocalizations.sync(const Locale('zh'));

    expect(
      trArgs('Latest stable {version}', {'version': '1.2.3'}),
      '最新稳定版 1.2.3',
    );
  });

  test('missing entries fall back to the English source', () {
    AppLocalizations.sync(const Locale('zh'));

    expect(
      tr('A string that is not translated'),
      'A string that is not translated',
    );
  });
}
