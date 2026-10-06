import 'package:flutter/foundation.dart';

class DebugSession {
  static String? get uid {
    if (!kIsWeb || !kDebugMode) {
      return null;
    }
    final value =
        Uri.base.queryParameters['debug_uid']?.trim() ?? _fragmentDebugUid();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static bool get enabled => uid != null;

  static String? get route {
    if (!kIsWeb || !kDebugMode) {
      return null;
    }
    final value = Uri.base.queryParameters['debug_route']?.trim() ??
        _fragmentRoute() ??
        _fragmentValue('debug_route');
    if (value == null || value.isEmpty) {
      return null;
    }
    return value.startsWith('/') ? value : '/$value';
  }

  static String? _fragmentRoute() {
    final fragment = Uri.base.fragment.trim();
    if (fragment.isEmpty || !fragment.startsWith('/')) {
      return null;
    }
    final queryIndex = fragment.indexOf('?');
    if (queryIndex == -1) {
      return fragment;
    }
    return fragment.substring(0, queryIndex).trim();
  }

  static String? _fragmentDebugUid() {
    return _fragmentValue('debug_uid');
  }

  static String? value(String key) {
    if (!kIsWeb || !kDebugMode) {
      return null;
    }
    final direct = Uri.base.queryParameters[key]?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final fragment = _fragmentValue(key);
    if (fragment != null && fragment.isNotEmpty) {
      return fragment;
    }
    return null;
  }

  static String? _fragmentValue(String key) {
    final fragment = Uri.base.fragment;
    if (fragment.isEmpty) {
      return null;
    }
    final queryIndex = fragment.indexOf('?');
    if (queryIndex == -1 || queryIndex == fragment.length - 1) {
      return null;
    }
    final query = fragment.substring(queryIndex + 1);
    return Uri.splitQueryString(query)[key]?.trim();
  }
}
