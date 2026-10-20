import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app/app_env.dart';
import 'session_store.dart';

/// Bounded, best-effort device reports. Never records input contents or secrets.
class ClientTelemetry {
  static bool _handlersInstalled = false;
  static void installErrorHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    final frameworkHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      emit('client.error', label: details.exception.runtimeType.toString());
      frameworkHandler?.call(details);
    };
    final platformHandler = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      emit('client.error', label: error.runtimeType.toString());
      return platformHandler?.call(error, stack) ?? false;
    };
  }

  static final String session = _id();
  static String operation = _id();
  static String screen = '';
  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _timer;
  static bool _busy = false;
  static final Random _random = Random.secure();
  static String _id() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  static Map<String, String> get headers => {
        'X-Domly-Session': session,
        'X-Domly-Operation': operation,
        'X-Domly-Platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'X-Domly-Version': const String.fromEnvironment('DOMLY_APP_VERSION',
            defaultValue: 'version-not-reported'),
      };
  static void opened(String? route) {
    if (route == null || !route.startsWith('/') || route.contains('?')) return;
    screen = route;
    emit('screen.open');
  }

  static void begin(String label) {
    operation = _id();
    emit('ui.action.started', label: label);
  }

  static void emit(String action, {String? label, Map<String, dynamic>? gps}) {
    if (SessionStore.sessionMutationInProgress) return;
    final epoch = SessionStore.telemetryEpoch;
    final event = <String, dynamic>{
      'action': action,
      'screen': screen,
      'label': label?.substring(0, min(label.length, 100)),
      'session': session,
      'operation': operation,
      'time': DateTime.now().toUtc().toIso8601String(),
      if (gps != null) 'gps': gps
    };
    unawaited(_enqueue(event, epoch));
  }

  static Future<void> _enqueue(Map<String, dynamic> event, int epoch) async {
    try {
      final store = SessionStore(surface: SessionStore.activeSurface);
      final user = await store.backendSession();
      if (user == null ||
          SessionStore.sessionMutationInProgress ||
          epoch != SessionStore.telemetryEpoch) return;
      if (_queue.length >= 100) _queue.removeAt(0);
      _queue.add({...event, '_actorId': user.userId, '_epoch': epoch});
      _timer ??= Timer(const Duration(seconds: 2), () {
        _timer = null;
        unawaited(_flush());
      });
    } catch (_) {
      // Device diagnostics must never interrupt the application.
    }
  }

  static Future<void> _flush() async {
    if (_busy || _queue.isEmpty) return;
    _busy = true;
    try {
      if (SessionStore.sessionMutationInProgress) return;
      final epoch = SessionStore.telemetryEpoch;
      final active = await SessionStore().backendSession();
      if (SessionStore.sessionMutationInProgress ||
          epoch != SessionStore.telemetryEpoch) return;
      final token = active?.accessToken;
      if (token == null || token.isEmpty) {
        _queue.clear();
        return;
      }
      _queue.removeWhere(
          (e) => e['_actorId'] != active?.userId || e['_epoch'] != epoch);
      final batch = _queue
          .take(20)
          .map((e) => Map<String, dynamic>.from(e)
            ..remove('_actorId')
            ..remove('_epoch')
            ..['actorId'] = active!.userId)
          .toList();
      if (batch.isEmpty) return;
      _queue.removeRange(0, batch.length);
      final url = AppEnv.backendBaseUrl.replaceFirst(RegExp(r'/+$'), '');
      await http
          .post(Uri.parse('$url/telemetry/client-events'),
              headers: {
                ...headers,
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json'
              },
              body: jsonEncode({'events': batch}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // An offline client is not evidence that a business operation failed.
    } finally {
      _busy = false;
      if (_queue.isNotEmpty)
        _timer ??= Timer(const Duration(seconds: 3), () {
          _timer = null;
          unawaited(_flush());
        });
    }
  }
}
