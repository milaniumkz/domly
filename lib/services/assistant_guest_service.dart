import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_env.dart';
import 'backend_api_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';

class AssistantGuestService {
  static final instance = AssistantGuestService();
  static const _keyName = 'domly_assistant_installation_key';
  AssistantGuestService({http.Client? client, bool enablePush = true})
      : _client = client ?? http.Client(),
        _enablePush = enablePush;
  final http.Client _client;
  final bool _enablePush;
  Future<void>? _initializing;
  String? _key;
  bool _listening = false;

  Future<void> initialize() =>
      _initializing ??= _initialize().whenComplete(() => _initializing = null);
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _key = prefs.getString(_keyName);
    if (_key == null) {
      final random = Random.secure();
      _key = List.generate(
              32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString(_keyName, _key!);
    }
    await _request('/assistant/guest-session', body: {'installationKey': _key});
    if (AuthService.restoredSessionUid != null) {
      await bindToCustomer();
      return;
    }
    if (!_enablePush) return;
    try {
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          if (message.data['targetType'] == 'assistant_guest')
            NotificationService.forwardNotificationTap(message.data);
        });
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
          if (_key == null || AuthService.restoredSessionUid != null) return;
          try {
            await _request('/assistant/guest/device-token',
                body: {'token': token});
          } catch (_) {}
        });
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial?.data['targetType'] == 'assistant_guest')
          NotificationService.forwardNotificationTap(initial!.data);
      }
    } catch (_) {/* Push support must not block the guest chat. */}
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional)
        await _savePushToken();
    } catch (_) {}
  }

  Future<void> bindToCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_keyName);
    if (key == null) return;
    try {
      await BackendApiService.instance
          .postMap('/assistant/guest/bind', body: {'installationKey': key});
      await prefs.remove(_keyName);
      _key = null;
    } catch (_) {
      /* Ordinary registration must not depend on an assistant outage. */
    }
  }

  Future<void> enablePush() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied)
      throw StateError('Уведомления запрещены в настройках устройства.');
    await _savePushToken();
  }

  Future<void> _savePushToken() async {
    if (_key == null || AuthService.restoredSessionUid != null) return;
    final token = await FirebaseMessaging.instance.getToken(
        vapidKey: AppEnv.firebaseMessagingVapidKey.isEmpty
            ? null
            : AppEnv.firebaseMessagingVapidKey);
    if (token != null)
      await _request('/assistant/guest/device-token', body: {'token': token});
  }

  Future<dynamic> _request(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(
        '${AppEnv.backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');
    final headers = {
      'Content-Type': 'application/json',
      if (_key != null) 'X-Assistant-Session': _key!
    };
    final response = body == null
        ? await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15))
        : await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400)
      throw StateError((json['message'] ??
              (json['error'] is Map ? json['error']['message'] : null) ??
              'Помощник временно недоступен.')
          .toString());
    return json['data'];
  }

  Future<void> send(String text) async {
    await _request('/assistant/guest/messages', body: {'message': text});
  }

  Stream<List<Map<String, dynamic>>> messages() => Stream.multi((controller) {
        var closed = false, loading = false;
        Future<void> load() async {
          if (closed || loading) return;
          loading = true;
          try {
            final data = await _request('/assistant/guest/messages');
            if (!closed)
              controller.add((data as List)
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList());
          } catch (error) {
            if (!closed) controller.addError(error);
          } finally {
            loading = false;
          }
        }

        load();
        final timer = Timer.periodic(const Duration(seconds: 2), (_) => load());
        controller.onCancel = () {
          closed = true;
          timer.cancel();
        };
      });
}
