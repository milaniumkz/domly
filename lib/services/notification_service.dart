import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app/app_env.dart';
import 'backend_api_service.dart';

class NotificationService {
  NotificationService({required this.userId, this.adminSurface = false});

  final String userId;
  final bool adminSurface;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get notificationTaps =>
      _tapController.stream;

  static const int _androidFlagInsistent = 4;
  static const _orderAlarmSound = RawResourceAndroidNotificationSound(
    'domly_order_alarm',
  );
  static final _orderAlarmVibrationPattern = Int64List.fromList(const <int>[
    0,
    900,
    180,
    900,
    180,
    900,
    180,
    1200,
  ]);

  Future<void> _storeInboxMessage(RemoteMessage message) async {
    // Inbox entries are created by the backend. Firebase remains only the
    // transport for push delivery.
  }

  Future<void> init() async {
    if (kIsWeb) {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: AppEnv.firebaseMessagingVapidKey.isEmpty
            ? null
            : AppEnv.firebaseMessagingVapidKey,
      );
      if (token != null) {
        await _saveBackendDeviceToken(platform: 'web', token: token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((nextToken) async {
        await _saveBackendDeviceToken(platform: 'web', token: nextToken);
      });
      FirebaseMessaging.onMessage.listen(_storeInboxMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _emitNotificationTap(message.data);
      });
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _emitNotificationTap(initialMessage.data);
      }
      return;
    }

    await FirebaseMessaging.instance.requestPermission();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
        android: androidInit, iOS: DarwinInitializationSettings());
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.trim().isEmpty) {
          return;
        }
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _emitNotificationTap(
              decoded.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
        } catch (_) {}
      },
    );
    await _configureAndroidChannels();

    final token = await FirebaseMessaging.instance.getToken();
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    if (token != null) {
      await _saveBackendDeviceToken(platform: platform, token: token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((nextToken) async {
      await _saveBackendDeviceToken(platform: platform, token: nextToken);
    });

    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      if (notification == null) {
        return;
      }

      await _storeInboxMessage(message);

      final type = (message.data['type'] ?? '').toString();
      final isUrgentOrderOffer = type == 'new_order_offer';
      final isScheduledOrderOffer = type == 'scheduled_order_offer';
      final isOrderOffer = isUrgentOrderOffer || isScheduledOrderOffer;
      final channelId = isUrgentOrderOffer
          ? 'domly_order_offer_alarm_v2'
          : isScheduledOrderOffer
              ? 'domly_schedule_offer_alarm_v2'
              : 'domly_main';
      final channelName = isUrgentOrderOffer
          ? 'Order Offers Alarm'
          : isScheduledOrderOffer
              ? 'Scheduled Offers Alarm'
              : 'Domly Notifications';

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.max,
        priority: isOrderOffer ? Priority.max : Priority.high,
        category: isOrderOffer ? AndroidNotificationCategory.alarm : null,
        fullScreenIntent: isOrderOffer,
        ongoing: isOrderOffer,
        autoCancel: !isOrderOffer,
        onlyAlertOnce: false,
        playSound: true,
        enableVibration: true,
        sound: isOrderOffer ? _orderAlarmSound : null,
        vibrationPattern: isOrderOffer ? _orderAlarmVibrationPattern : null,
        additionalFlags: isOrderOffer
            ? Int32List.fromList(const <int>[_androidFlagInsistent])
            : null,
        audioAttributesUsage: isOrderOffer
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      );
      final details = NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(message.data),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _emitNotificationTap(message.data);
    });
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _emitNotificationTap(initialMessage.data);
    }
  }

  static void _emitNotificationTap(Map<String, dynamic> data) {
    if (data.isEmpty || _tapController.isClosed) {
      return;
    }
    _tapController.add(Map<String, dynamic>.from(data));
  }

  Future<void> _saveBackendDeviceToken({
    required String platform,
    required String token,
  }) async {
    try {
      await BackendApiService.instance.saveDeviceToken(
        platform: platform,
        token: token,
        role: adminSurface ? 'admin' : 'user',
      );
    } catch (_) {
      // Push token registration must not block app startup.
    }
  }

  Future<void> _configureAndroidChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final androidPlatform =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlatform?.createNotificationChannel(
      const AndroidNotificationChannel(
        'domly_main',
        'Domly Notifications',
        importance: Importance.high,
      ),
    );
    await androidPlatform?.createNotificationChannel(
      const AndroidNotificationChannel(
        'domly_order_offer',
        'Order Offers',
        description: 'Срочные предложения новых заказов',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await androidPlatform?.createNotificationChannel(
      const AndroidNotificationChannel(
        'domly_schedule_offer',
        'Scheduled Offers',
        description: 'Подтверждение заказов на завтра и будущие даты',
        importance: Importance.high,
        playSound: true,
      ),
    );
    await androidPlatform?.createNotificationChannel(
      const AndroidNotificationChannel(
        'domly_order_offer_alarm_v2',
        'Order Offers Alarm',
        description: 'Навязчивый звук новых заказов для уборщицы',
        importance: Importance.max,
        playSound: true,
        sound: _orderAlarmSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
      ),
    );
    await androidPlatform?.createNotificationChannel(
      const AndroidNotificationChannel(
        'domly_schedule_offer_alarm_v2',
        'Scheduled Offers Alarm',
        description: 'Навязчивый звук предложений заказов по расписанию',
        importance: Importance.max,
        playSound: true,
        sound: _orderAlarmSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
      ),
    );
  }
}
