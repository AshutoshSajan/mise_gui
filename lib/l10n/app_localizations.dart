import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mise_gui/l10n/translations_zh.dart';

/// Language preference selected by the user.
///
/// English is the primary language. [system] resolves to Chinese when the
/// operating system locale is Chinese and English otherwise.
enum AppLanguage { system, english, chinese }

Locale resolveAppLocale(AppLanguage language) {
  return switch (language) {
    AppLanguage.english => const Locale('en'),
    AppLanguage.chinese => const Locale('zh'),
    AppLanguage.system => _systemLocale(),
  };
}

Locale _systemLocale() {
  final locale = PlatformDispatcher.instance.locale;
  return locale.languageCode.toLowerCase() == 'zh'
      ? const Locale('zh')
      : const Locale('en');
}

String appLanguageLabel(AppLanguage language) {
  return switch (language) {
    AppLanguage.system => tr('Follow system'),
    AppLanguage.english => 'English',
    AppLanguage.chinese => '中文',
  };
}

/// Lightweight localization layer.
///
/// English is the source language: every user-facing string is written in
/// English and translated to Chinese through [appTranslationsZh]. This keeps
/// translations usable from services and models that have no [BuildContext],
/// while widgets can still access the active instance through
/// [AppLocalizations.of].
class AppLocalizations {
  const AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// The localization instance used by context-free code such as services.
  ///
  /// It is synchronized from [MaterialApp] on every build, so changing the
  /// locale rebuilds the widget tree with the matching catalog.
  static AppLocalizations current = const AppLocalizations(Locale('en'));

  final Locale locale;

  bool get isChinese => locale.languageCode.toLowerCase() == 'zh';

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        current;
  }

  static void sync(Locale locale) {
    current = AppLocalizations(locale);
  }

  /// Translates an English source string into the active language.
  String tr(String source) {
    if (!isChinese) {
      return source;
    }
    return appTranslationsZh[source] ?? source;
  }

  /// Translates a template and substitutes `{name}` placeholders.
  ///
  /// Source templates may use ICU-style plural blocks:
  /// `{count, plural, one {tool} other {tools}}`.
  String trArgs(String template, Map<String, Object?> args) {
    var result = tr(template);
    result = result.replaceAllMapped(_pluralPattern, (match) {
      final name = match.group(1)!;
      final value = args[name];
      final count = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '') ?? 0;
      final branch = count == 1 ? match.group(2)! : match.group(3)!;
      return branch.replaceAll('#', count.toString());
    });
    return result.replaceAllMapped(_placeholderPattern, (match) {
      final name = match.group(1)!;
      if (!args.containsKey(name)) {
        return match.group(0)!;
      }
      return args[name]?.toString() ?? '';
    });
  }

  /// Shorthand for a plain string.
  static String t(String source) => current.tr(source);

  /// Shorthand for a template with placeholders.
  static String ta(String template, Map<String, Object?> args) =>
      current.trArgs(template, args);

  static final RegExp _pluralPattern = RegExp(
    r'\{(\w+),\s*plural,\s*one\s*\{([^{}]*)\}\s*other\s*\{([^{}]*)\}\s*\}',
  );

  static final RegExp _placeholderPattern = RegExp(r'\{(\w+)\}');
}

/// Global translation helper for widgets, services, and models.
String tr(String source) => AppLocalizations.current.tr(source);

/// Global template translation helper with `{name}` placeholders.
String trArgs(String template, Map<String, Object?> args) =>
    AppLocalizations.current.trArgs(template, args);

/// Whether the active locale is English.
bool get isEnglishLocale => !AppLocalizations.current.isChinese;

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String tr(String source) => l10n.tr(source);

  String trArgs(String template, Map<String, Object?> args) =>
      l10n.trArgs(template, args);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    return code == 'en' || code == 'zh';
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
