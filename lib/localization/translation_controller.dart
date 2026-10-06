import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_api_service.dart';
import 'builtin_translations.dart';
import 'default_translation_sources.dart';

class TranslationController extends ChangeNotifier {
  TranslationController({
    Object? firestore,
    SharedPreferences? preferences,
    this.fallbackLocale = 'ru',
  }) : _preferences = preferences;

  TranslationController.forTesting({this.fallbackLocale = 'ru'})
    : _preferences = null;

  static const List<String> supportedLocales = <String>['ru', 'kk'];
  static const String _preferencesKey = 'domly_locale';

  static TranslationController? _active;

  final SharedPreferences? _preferences;
  final String fallbackLocale;

  Timer? _pollingTimer;
  Map<String, _TranslationEntry> _entries = const <String, _TranslationEntry>{};
  String _localeCode = 'ru';
  bool _isReady = false;

  bool get isReady => _isReady;
  String get localeCode => _localeCode;

  static TranslationController? get active => _active;

  Future<void> init() async {
    _active = this;
    final savedLocale = _preferences?.getString(_preferencesKey);
    final platformLocale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _localeCode = _normalizeLocale(savedLocale ?? platformLocale);
    _entries = _defaultEntries();
    _isReady = true;
    notifyListeners();

    Future<void> reload() async {
      try {
        final rows = await BackendApiService.instance.getList(
          '/translations',
          authenticated: false,
        );
        final nextEntries = _defaultEntries();
        for (final row in rows) {
          final entry = _TranslationEntry.fromBackend(row);
          final key = (row['key'] ?? '').toString().trim().isNotEmpty
              ? row['key'].toString()
              : translationKey(entry.source);
          nextEntries[key] = entry;
        }
        _entries = nextEntries;
        _isReady = true;
        notifyListeners();
      } catch (_) {
        _isReady = true;
        notifyListeners();
      }
    }

    await reload();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(reload());
    });
  }

  Future<void> setLocale(String locale) async {
    final normalized = _normalizeLocale(locale);
    if (normalized == _localeCode) {
      return;
    }
    _localeCode = normalized;
    await _preferences?.setString(_preferencesKey, normalized);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetTranslations(
    Map<String, Map<String, String>> values, {
    String locale = 'ru',
  }) {
    _localeCode = _normalizeLocale(locale);
    _entries = values.map((source, locales) {
      final normalized = normalizeSource(source);
      return MapEntry(
        translationKey(normalized),
        _TranslationEntry(source: normalized, locales: locales),
      );
    });
    _active = this;
    _isReady = true;
    notifyListeners();
  }

  String translate(String source, {Map<String, String>? params}) {
    final normalized = normalizeSource(source);
    if (normalized.isEmpty) {
      return source;
    }
    final key = translationKey(normalized);
    final entry = _entries[key];
    final translated =
        entry?.localized(_localeCode, fallbackLocale) ??
        kBuiltinTranslations[normalized]?[_localeCode] ??
        normalized;
    return _applyParams(translated, params);
  }

  static String translateSource(String source, {Map<String, String>? params}) {
    return _active?.translate(source, params: params) ??
        _applyParams(source, params);
  }

  static String localizedValue(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    final locale = _active?._localeCode ?? 'ru';
    final candidates = <String>[];
    for (final key in keys) {
      final localizedMap = data['${key}Locales'] ?? data['${key}Translations'];
      if (localizedMap is Map) {
        final exact = localizedMap[locale];
        if (exact is String && exact.trim().isNotEmpty) {
          return exact.trim();
        }
        final ru = localizedMap['ru'];
        if (ru is String && ru.trim().isNotEmpty) {
          candidates.add(ru);
        }
      }
      for (final suffix in [
        locale,
        locale.toUpperCase(),
        '_$locale',
        '${locale[0].toUpperCase()}${locale.substring(1)}',
      ]) {
        final value = data['$key$suffix'];
        if (value is String && value.trim().isNotEmpty) {
          return translateSource(value);
        }
      }
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        candidates.add(value);
      }
    }
    final source = candidates.isNotEmpty ? candidates.first : fallback;
    return translateSource(source);
  }

  static String translationKey(String source) {
    final normalized = normalizeSource(source);
    final digest = sha1.convert(utf8.encode(normalized)).toString();
    return 't_${digest.substring(0, 16)}';
  }

  static String normalizeSource(String source) {
    return source.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String localeLabel(String locale) {
    return switch (_normalizeLocale(locale)) {
      'kk' => 'Қазақша',
      _ => 'Русский',
    };
  }

  static String _normalizeLocale(String locale) {
    final normalized = locale.toLowerCase().trim();
    if (normalized.startsWith('kk')) {
      return 'kk';
    }
    return 'ru';
  }

  static String _applyParams(String source, Map<String, String>? params) {
    var result = source;
    params?.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  static Map<String, _TranslationEntry> _defaultEntries() {
    final entries = <String, _TranslationEntry>{};
    for (final rawSource in kDefaultTranslationSources) {
      final source = normalizeSource(rawSource);
      if (source.isEmpty) {
        continue;
      }
      entries[translationKey(source)] = _TranslationEntry(
        source: source,
        locales: <String, String>{
          'ru': source,
          ...?kBuiltinTranslations[source],
        },
      );
    }
    kBuiltinTranslations.forEach((rawSource, locales) {
      final source = normalizeSource(rawSource);
      entries[translationKey(source)] = _TranslationEntry(
        source: source,
        locales: <String, String>{'ru': source, ...locales},
      );
    });
    return entries;
  }

  @override
  void dispose() {
    if (_active == this) {
      _active = null;
    }
    _pollingTimer?.cancel();
    super.dispose();
  }
}

class _TranslationEntry {
  const _TranslationEntry({required this.source, required this.locales});

  final String source;
  final Map<String, String> locales;

  factory _TranslationEntry.fromBackend(Map<String, dynamic> data) {
    final rawLocales = data['locales'];
    final locales = <String, String>{};
    if (rawLocales is Map) {
      rawLocales.forEach((key, value) {
        if (value is String && value.trim().isNotEmpty) {
          locales[key.toString()] = value;
        }
      });
    }
    for (final locale in TranslationController.supportedLocales) {
      final topLevel = data[locale];
      if (topLevel is String && topLevel.trim().isNotEmpty) {
        locales[locale] = topLevel;
      }
    }
    return _TranslationEntry(
      source: (data['source'] ?? data['ru'] ?? '').toString(),
      locales: locales,
    );
  }

  String localized(String localeCode, String fallbackLocale) {
    final exact = locales[localeCode];
    if (exact != null && exact.trim().isNotEmpty) {
      return exact;
    }
    final fallback = locales[fallbackLocale];
    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback;
    }
    return source;
  }
}

extension TranslationStringX on String {
  String tr({Map<String, String>? params}) {
    return TranslationController.translateSource(this, params: params);
  }
}

extension TranslationMapX on Map<String, dynamic> {
  String trValue(List<String> keys, {String fallback = ''}) {
    return TranslationController.localizedValue(this, keys, fallback: fallback);
  }
}
