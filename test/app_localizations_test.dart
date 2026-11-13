import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/l10n/app_localizations.dart';
import 'package:mise_gui/l10n/translations_zh.dart';

String _unescapeDartString(String value) {
  return value
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\\', r'\');
}

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

  test('every literal tr source has a Chinese translation', () {
    final catalog = appTranslationsZh.keys.toSet();
    final literalPatterns = [
      RegExp(r"\btr(?:Args)?\(\s*'((?:\\.|[^'\\])*)'"),
      RegExp(r'\btr(?:Args)?\(\s*"((?:\\.|[^"\\])*)"'),
    ];
    final missing = <String>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.uri.pathSegments.contains('l10n')) {
        continue;
      }

      final source = entity.readAsStringSync();
      for (final pattern in literalPatterns) {
        for (final match in pattern.allMatches(source)) {
          final literal = _unescapeDartString(match.group(1)!);
          if (!catalog.contains(literal)) {
            missing.add(literal);
          }
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Add these English source strings to translations_zh.dart.',
    );
  });

  test('Chinese translations keep interpolation placeholders', () {
    final placeholderPattern = RegExp(r'\{(\w+)\}');
    final pluralPattern = RegExp(r'\{(\w+),\s*plural,');

    Set<String> placeholders(String value) =>
        placeholderPattern.allMatches(value).map((m) => m.group(1)!).toSet();

    appTranslationsZh.forEach((source, translation) {
      final plural = pluralPattern.firstMatch(source);
      if (plural != null) {
        final name = plural.group(1)!;
        final keepsCount =
            translation.contains('{$name}') ||
            translation.contains('{$name, plural');
        expect(
          keepsCount,
          isTrue,
          reason: 'Plural translation for "$source" must keep its count.',
        );
        return;
      }

      expect(
        placeholders(translation),
        placeholders(source),
        reason: 'Placeholders changed in the translation for "$source".',
      );
    });
  });
}
