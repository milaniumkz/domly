import '../utils/promotion_data.dart';
import '../utils/banner_data.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../utils/backend_compat.dart';
import '../utils/admin_cleaner_data.dart';
import '../utils/cleaner_order_data.dart';
import 'package:flutter/foundation.dart';

import '../app/debug_session.dart';
import '../app/debug_storage.dart';
import '../app/launch_config.dart';
import '../localization/default_translation_sources.dart';
import '../localization/builtin_translations.dart';
import '../localization/translation_controller.dart';
import 'app_config_service.dart';
import 'auth_service.dart';
import 'session_store.dart';
import 'backend_api_service.dart';
import '../utils/package_catalog_utils.dart';

class FirestoreDataService {
  FirestoreDataService._();

  static final FirestoreDataService instance = FirestoreDataService._();
  dynamic get _db =>
      throw StateError('Firestore отключён: данные идут через backend.');
  List<Map<String, dynamic>>? _debugCustomerSubscriptionsState;
  List<Map<String, dynamic>>? _debugCustomerOrdersState;
  List<Map<String, dynamic>>? _debugCustomerScheduleSlotsState;
  Map<String, dynamic>? _debugCustomerProfileState;
  List<Map<String, dynamic>>? _debugCleanerOrdersState;
  List<Map<String, dynamic>>? _debugCleanerScheduleSlotsState;
  List<Map<String, dynamic>>? _debugComplaintsState;
  List<Map<String, dynamic>>? _debugReviewsState;
  List<Map<String, dynamic>>? _debugNotificationsState;
  Map<String, List<Map<String, dynamic>>>? _debugChatMessagesState;
  final StreamController<void> _debugStateChanges =
      StreamController<void>.broadcast(sync: true);
  final List<Map<String, dynamic>> _debugPhotoReportsState =
      <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _debugCleanerChecklistState =
      <String, Map<String, dynamic>>{};
  String? get _uidOrNull =>
      DebugSession.uid ??
      AuthService.temporarySessionUid ??
      AuthService.restoredSessionUid;
  String get _uid =>
      _uidOrNull ?? (throw StateError('Требуется вход в аккаунт.'));
  String get currentUserId => _uid;
  bool get _useDebugFixtures => kIsWeb && DebugSession.enabled;
  bool get _isDebugCustomer =>
      _useDebugFixtures && _uidOrNull == 'customer_demo';
  bool get _isDebugCleaner => _useDebugFixtures && _uidOrNull == 'cleaner_demo';
  bool get _isDebugAdmin => _useDebugFixtures && _uidOrNull == 'admin_demo';
  bool get _isTemporaryCustomerSession =>
      !DebugSession.enabled &&
      AuthService.hasTemporarySession &&
      ((_uidOrNull ?? '').startsWith('temp_customer_'));
  bool get _isTemporaryCleanerSession =>
      !DebugSession.enabled &&
      AuthService.hasTemporarySession &&
      ((_uidOrNull ?? '').startsWith('temp_cleaner_'));
  bool get _canUseLocalCustomerOrderFallback =>
      !_useDebugFixtures && !_isDebugAdmin && !_isDebugCleaner;
  bool get isDebugCustomer => _isDebugCustomer;
  bool get _useWebOneShotStreams => false;

  Stream<T> _debugSnapshotStream<T>(T Function() reader) {
    return Stream<T>.multi((controller) {
      void emit() {
        if (!controller.isClosed) {
          controller.add(reader());
        }
      }

      emit();
      final sub = _debugStateChanges.stream.listen((_) => emit());
      controller.onCancel = sub.cancel;
    });
  }

  void _notifyDebugStateChanged() {
    _persistDebugState();
    if (!_debugStateChanges.isClosed) {
      _debugStateChanges.add(null);
    }
  }

  String get _debugStoragePrefix => 'domly_debug_${_uidOrNull ?? 'guest'}';

  String _debugStorageKey(String suffix) => '${_debugStoragePrefix}_$suffix';

  List<Map<String, dynamic>>? _loadDebugList(String suffix) {
    final raw = debugStorageRead(_debugStorageKey(suffix));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _loadDebugMap(String suffix) {
    final raw = debugStorageRead(_debugStorageKey(suffix));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  void _persistDebugState() {
    if (!_useDebugFixtures) {
      return;
    }
    if (_debugCustomerSubscriptionsState != null) {
      debugStorageWrite(
        _debugStorageKey('customer_subscriptions'),
        jsonEncode(_jsonSafe(_debugCustomerSubscriptionsState)),
      );
    }
    if (_debugCustomerOrdersState != null) {
      debugStorageWrite(
        _debugStorageKey('customer_orders'),
        jsonEncode(_jsonSafe(_debugCustomerOrdersState)),
      );
    }
    if (_debugCustomerProfileState != null) {
      debugStorageWrite(
        _debugStorageKey('customer_profile'),
        jsonEncode(_jsonSafe(_debugCustomerProfileState)),
      );
    }
    if (_debugCustomerScheduleSlotsState != null) {
      debugStorageWrite(
        _debugStorageKey('customer_slots'),
        jsonEncode(_jsonSafe(_debugCustomerScheduleSlotsState)),
      );
    }
    if (_debugCleanerOrdersState != null) {
      debugStorageWrite(
        _debugStorageKey('cleaner_orders'),
        jsonEncode(_jsonSafe(_debugCleanerOrdersState)),
      );
    }
    if (_debugCleanerScheduleSlotsState != null) {
      debugStorageWrite(
        _debugStorageKey('cleaner_slots'),
        jsonEncode(_jsonSafe(_debugCleanerScheduleSlotsState)),
      );
    }
    if (_debugComplaintsState != null) {
      debugStorageWrite(
        _debugStorageKey('complaints'),
        jsonEncode(_jsonSafe(_debugComplaintsState)),
      );
    }
    if (_debugReviewsState != null) {
      debugStorageWrite(
        _debugStorageKey('reviews'),
        jsonEncode(_jsonSafe(_debugReviewsState)),
      );
    }
    if (_debugNotificationsState != null) {
      debugStorageWrite(
        _debugStorageKey('notifications'),
        jsonEncode(_jsonSafe(_debugNotificationsState)),
      );
    }
    if (_debugChatMessagesState != null) {
      debugStorageWrite(
        _debugStorageKey('chat_messages'),
        jsonEncode(_jsonSafe(_debugChatMessagesState)),
      );
    }
    if (_debugPhotoReportsState.isNotEmpty) {
      debugStorageWrite(
        _debugStorageKey('photo_reports'),
        jsonEncode(_jsonSafe(_debugPhotoReportsState)),
      );
    }
    if (_debugCleanerChecklistState.isNotEmpty) {
      debugStorageWrite(
        _debugStorageKey('cleaner_checklists'),
        jsonEncode(_jsonSafe(_debugCleanerChecklistState)),
      );
    }
  }

  dynamic _jsonSafe(dynamic value) {
    if (value is Timestamp) {
      return {'_seconds': value.seconds, '_nanoseconds': value.nanoseconds};
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is List) {
      return value.map(_jsonSafe).toList();
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonSafe(item)),
      );
    }
    return value;
  }

  Stream<Map<String, dynamic>?> _docStreamOnce(dynamic ref) {
    if (!_useWebOneShotStreams) {
      return ref.snapshots().map((doc) => doc.data());
    }
    return Stream.fromFuture(ref.get().then((doc) => doc.data()));
  }

  Stream<T> _resilientStream<T>(
    Stream<T> source, {
    required T Function() fallback,
  }) {
    final broadcastSource = source.asBroadcastStream();
    return Stream<T>.multi((controller) {
      final sub = broadcastSource.listen(
        controller.add,
        onError: (_) {
          if (!controller.isClosed) {
            controller.add(fallback());
          }
        },
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Stream<Map<String, dynamic>?> _resilientDocStream(
    dynamic ref, {
    required Map<String, dynamic>? Function() fallback,
  }) {
    return Stream<Map<String, dynamic>?>.multi((controller) {
      final sub = _docStreamOnce(ref).listen(
        controller.add,
        onError: (_) {
          if (!controller.isClosed) {
            controller.add(fallback());
          }
        },
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Stream<List<Map<String, dynamic>>> _queryStreamOnce(dynamic query) {
    if (!_useWebOneShotStreams) {
      return query.snapshots().map(
            (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
          );
    }
    return Stream.fromFuture(
      query.get().then(
            (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
          ),
    );
  }

  Stream<List<Map<String, dynamic>>> _queryPollingStream(
    dynamic query, {
    Duration interval = const Duration(seconds: 2),
  }) {
    if (!_useWebOneShotStreams) {
      return query.snapshots().map(
            (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
          );
    }
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      Timer? timer;
      var loading = false;

      Future<void> load() async {
        if (loading || controller.isClosed) {
          return;
        }
        loading = true;
        try {
          final snap = await query.get();
          if (!controller.isClosed) {
            controller.add(
              snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
            );
          }
        } catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        } finally {
          loading = false;
        }
      }

      unawaited(load());
      timer = Timer.periodic(interval, (_) => unawaited(load()));
      controller.onCancel = () {
        timer?.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> _resilientQueryStream(
    dynamic query, {
    required List<Map<String, dynamic>> Function() fallback,
  }) {
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      final sub = _queryStreamOnce(query).listen(
        controller.add,
        onError: (_) {
          if (!controller.isClosed) {
            controller.add(fallback());
          }
        },
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Stream<R> _combineLatestLists<A, B, R>(
    Stream<List<A>> left,
    Stream<List<B>> right,
    R Function(List<A> left, List<B> right) combiner,
  ) {
    late final StreamController<R> controller;
    StreamSubscription<List<A>>? leftSub;
    StreamSubscription<List<B>>? rightSub;
    List<A>? latestLeft;
    List<B>? latestRight;

    void emitIfReady() {
      final leftValue = latestLeft;
      final rightValue = latestRight;
      if (leftValue != null && rightValue != null && !controller.isClosed) {
        controller.add(combiner(leftValue, rightValue));
      }
    }

    controller = StreamController<R>(
      onListen: () {
        leftSub = left.listen((value) {
          latestLeft = value;
          emitIfReady();
        }, onError: controller.addError);
        rightSub = right.listen((value) {
          latestRight = value;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await leftSub?.cancel();
        await rightSub?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<T> _backendPollingStream<T>(Future<T> Function() loader,
      {Duration interval = const Duration(seconds: 20)}) {
    return Stream<T>.multi((controller) {
      Timer? timer;
      var closed = false;
      var loading = false;
      var reload = false;
      Future<void> emit() async {
        if (closed) return;
        if (loading) {
          reload = true;
          return;
        }
        loading = true;
        try {
          final value = await loader();
          if (!closed) controller.add(value);
        } catch (_) {
          if (!closed) {
            controller.addError('Сервис временно недоступен.');
          }
        } finally {
          loading = false;
          if (reload && !closed) {
            reload = false;
            emit();
          }
        }
      }

      emit();
      timer = Timer.periodic(interval, (_) => emit());
      BackendApiService.instance.dataRevision.addListener(emit);
      controller.onCancel = () {
        closed = true;
        timer?.cancel();
        BackendApiService.instance.dataRevision.removeListener(emit);
      };
    });
  }

  Stream<Map<String, dynamic>?> customerProfileStream() {
    if (_isDebugCustomer) {
      return _debugSharedCustomerProfileStream();
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerProfile);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(null);
    }
    return _backendPollingStream(_loadBackendCustomerProfile);
  }

  Future<Map<String, dynamic>?> _loadBackendCustomerProfile() async {
    final user = await BackendApiService.instance.me();
    final addresses = await BackendApiService.instance.getList('/addresses');
    final addressItems = addresses.map(_mapBackendAddress).toList();
    final primaryAddress = addressItems.isEmpty ? null : addressItems.first;
    final fullName = (user['full_name'] ?? user['fullName'] ?? '').toString();
    return {
      'id': user['id'],
      'referralCode': user['referralCode'],
      'referredByCode': user['referredByCode'],
      'referralQualifiedCount': user['referralQualifiedCount'],
      'referralDiscountPercent': user['referralDiscountPercent'],
      'numericId': user['numeric_id'],
      'name': fullName.isEmpty ? 'Пользователь' : fullName,
      'fullName': fullName,
      'phone': user['phone'],
      'email': user['email'],
      'language': user['language'] ?? 'ru',
      'rating': _num(user['rating']),
      'bonusBalance': _num(user['bonus_balance']).round(),
      'bonuses': _num(user['bonus_balance']).round(),
      'status': user['status'],
      'createdAt': user['created_at'],
      'updatedAt': user['updated_at'],
      'addresses': addressItems,
      if (primaryAddress != null) ...primaryAddress,
    };
  }

  Future<String?> _backendPrimaryAddressId() async {
    final addresses = await BackendApiService.instance.getList('/addresses');
    if (addresses.isEmpty) return null;
    return (addresses.first['id'] ?? '').toString();
  }

  Map<String, dynamic> _mapBackendAddress(Map<String, dynamic> item) {
    final parts = [item['settlement'], item['street'], item['house']]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .map((part) => part.toString().trim())
        .toList();
    final address = parts.join(', ');
    return {
      'id': item['id'],
      'addressId': item['id'],
      'city': item['city'],
      'settlement': item['settlement'],
      'street': item['street'],
      'house': item['house'],
      'address': address,
      'addressLine': address,
      'apartment': item['apartment'],
      'entrance': item['entrance'],
      'floor': item['floor'],
      'intercom': item['intercom'],
      'accessComment': item['access_comment'],
      'area': _num(item['area']),
      'verifiedArea': _num(item['verified_area']),
      'areaVerified': item['verified_area'] != null,
      'areaStatus': item['verified_area'] != null ? 'VERIFIED' : 'UNVERIFIED',
      'latitude': _numOrNull(item['latitude']),
      'longitude': _numOrNull(item['longitude']),
      'isPrimary': item['is_primary'] != false,
    };
  }

  Map<String, dynamic> _mapBackendCatalogPackage(Map<String, dynamic> item) {
    final cleaningCount = _num(item['cleaning_count']).toInt();
    final months = _num(item['months']).toInt();
    final basePrice = _num(item['base_price']).round();
    final metadata = item['features'] is Map
        ? Map<String, dynamic>.from(item['features'] as Map)
        : <String, dynamic>{};
    return {
      ...item,
      ...metadata,
      'features':
          item['features'] is List ? item['features'] : metadata['items'] ?? [],
      'id': item['id'],
      'name': item['name_ru'] ?? item['name'] ?? 'Пакет',
      'nameLocales': {
        'ru': item['name_ru'] ?? item['name'],
        'kk': item['name_kk'] ?? item['name_ru'] ?? item['name'],
      },
      'description': item['description_ru'] ?? '',
      'descriptionLocales': {
        'ru': item['description_ru'] ?? '',
        'kk': item['description_kk'] ?? item['description_ru'] ?? '',
      },
      'price': _num(item['price_per_m2']) > 0
          ? _num(item['price_per_m2']).round()
          : basePrice,
      'basePrice': basePrice,
      'pricePerM2': _num(item['price_per_m2']).round(),
      'cleaningsPerMonth': cleaningCount,
      'includedVisits': cleaningCount,
      'billingPeriodMonths': months <= 0 ? 1 : months,
      'months': months <= 0 ? 1 : months,
      'sortOrder': _num(item['sort_order'] ?? metadata['sortOrder']).toInt(),
      'isActive': item['active'] != false,
      'createdAt': item['created_at'],
      'updatedAt': item['updated_at'],
    };
  }

  Map<String, dynamic> _mapBackendCustomerPackage(Map<String, dynamic> item) {
    final total = _num(item['total_cleanings']).toInt();
    final available = _num(item['available_cleanings']).toInt();
    final used = (total - available).clamp(0, total);
    final packageName = item['name_ru'] ?? item['package_name_ru'] ?? 'Пакет';
    return {
      'id': item['id'],
      'subscriptionId': item['id'],
      'packageId': item['package_id'],
      'addressId': item['address_id'],
      'package': packageName,
      'packageName': packageName,
      'name': packageName,
      'status': item['status'],
      'paymentStatus':
          item['status'] == 'pending_payment' ? 'pending_invoice' : 'paid',
      'remainingCleanings': available,
      'availableCleanings': available,
      'includedVisits': total,
      'totalCleanings': total,
      'usedCleanings': used,
      'scheduledVisits': used,
      'months': _num(item['months']).toInt(),
      'billingPeriodMonths': _num(item['months']).toInt(),
      'validFrom': item['started_at'] ?? item['created_at'],
      'validUntil': item['expires_at'],
      'createdAt': item['created_at'],
      'updatedAt': item['updated_at'],
    };
  }

  Map<String, dynamic> _mapBackendOrder(Map<String, dynamic> item) {
    final date = (item['scheduled_date'] ?? '').toString();
    final start = (item['start_time'] ?? '').toString();
    final end = (item['end_time'] ?? '').toString();
    final time = end.isEmpty ? start : '$start - $end';
    final address = [
      item['settlement'],
      item['street'],
      item['house'],
      item['apartment'] == null ? null : 'кв. ${item['apartment']}',
    ]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .join(', ');
    return {
      'id': item['id'],
      'orderId': item['id'],
      'addonsDetailed': item['addons'] ?? const [],
      'number': item['numeric_id'],
      'status': item['status'],
      'orderStatus': item['status'],
      'startRequiresCustomerConfirmation':
          item['start_requires_customer_confirmation'] == true,
      'cleaningStartConfirmed': item['cleaning_start_confirmed'] == true,
      'cleaningStartRejected': item['cleaning_start_rejected'] == true,
      'startedAt': item['started_at'],
      'completedAt': item['completed_at'],
      'paymentStatus':
          item['status'] == 'pending_payment' ? 'pending_invoice' : 'paid',
      'customerId': item['customer_id'],
      'cleanerId': item['cleaner_id'],
      'customerName': item['customer_name'],
      'customerPhone': item['customer_phone'],
      'cleanerName': item['cleaner_name'],
      'cleanerPhone': item['cleaner_phone'],
      'date': date,
      'scheduledDateKey': date,
      'time': time,
      'startTime': start,
      'endTime': end,
      'scheduledFor': date,
      'package': item['package_name_ru'] ?? item['packageName'],
      'packageName': item['package_name_ru'] ?? item['packageName'],
      'address': address,
      'city': item['city'],
      'area': _num(item['area']).round(),
      'price': _num(item['total_amount']).round(),
      'amount': _num(item['total_amount']).round(),
      'payableAmount': _num(item['payable_amount']).round(),
      'bonusSpent': _num(item['bonus_spent']).round(),
      'addonAmount': _num(item['addon_amount']).round(),
      'totalDurationMinutes': _num(item['estimated_duration_minutes']).toInt(),
      'createdAt': item['created_at'],
      'updatedAt': item['updated_at'],
    };
  }

  Map<String, dynamic> _mapBackendPayment(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      ...item,
      'customerId': item['customer_id'],
      'customerName': item['customer_name'],
      'customerPhone': item['customer_phone'],
      'address': [
        item['city'],
        item['settlement'],
        item['street'],
        item['house'],
        if (item['apartment'] != null) 'кв. ${item['apartment']}'
      ]
          .where((value) => value != null && value.toString().trim().isNotEmpty)
          .join(', '),
      'areaVerified': item['verified_area'] != null,
      'paymentId': item['id'],
      'orderId': item['order_id'],
      'customerPackageId': item['customer_package_id'],
      'type': (item['payload'] is Map ? item['payload']['kind'] : null) ??
          (item['customer_package_id'] != null
              ? 'package_purchase'
              : 'order_payment'),
      'status': item['status'],
      'paymentStatus': item['status'],
      'provider': item['provider'],
      'amount': _num(item['amount']).round(),
      'bonusAmount': _num(item['bonus_amount']).round(),
      'kaspiPhone': item['invoice_phone'],
      'packageName': item['package_name_ru'],
      'orderNumber': item['order_number'],
      'createdAt': item['created_at'],
      'updatedAt': item['updated_at'],
      'paidAt': item['paid_at'],
    };
  }

  Map<String, dynamic> _mapBackendNotification(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'userId': item['user_id'],
      'role': item['role'],
      'type': item['target_type'],
      'targetType': item['target_type'],
      'targetId': item['target_id'],
      'title': item['title_ru'] ?? item['title'],
      'body': item['body_ru'] ?? item['body'],
      'titleLocales': {
        'ru': item['title_ru'] ?? item['title'],
        'kk': item['title_kk'] ?? item['title_ru'] ?? item['title'],
      },
      'bodyLocales': {
        'ru': item['body_ru'] ?? item['body'],
        'kk': item['body_kk'] ?? item['body_ru'] ?? item['body'],
      },
      'read': item['read_at'] != null,
      'readAt': item['read_at'],
      'createdAt': item['created_at'],
    };
  }

  Map<String, dynamic> _mapBackendBonusTransaction(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'userId': item['user_id'],
      'orderId': item['order_id'],
      'paymentId': item['payment_id'],
      'type': item['type'],
      'amount': _num(item['amount']).round(),
      'balanceAfter': _num(item['balance_after']).round(),
      'title': item['reason_ru'] ?? 'Бонусы',
      'reason': item['reason_ru'] ?? '',
      'reasonLocales': {
        'ru': item['reason_ru'] ?? '',
        'kk': item['reason_kk'] ?? item['reason_ru'] ?? '',
      },
      'createdAt': item['created_at'],
    };
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  num? _numOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  Stream<Map<String, dynamic>?> cleanerProfileStream() {
    if (_isDebugCleaner) {
      return _debugSharedCleanerProfileStream();
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryCleanerProfile);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(null);
    }
    return _backendPollingStream(_loadBackendCleanerProfile);
  }

  Future<Map<String, dynamic>?> _loadBackendCleanerProfile() async {
    final data = await BackendApiService.instance.getMap('/cleaner/profile');
    final profile = Map<String, dynamic>.from(
      (data['profile'] as Map?) ?? const <String, dynamic>{},
    );
    final documents = (data['documents'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final zones = (data['zones'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final fullName =
        (profile['full_name'] ?? profile['fullName'] ?? '').toString();
    return {
      'id': profile['id'] ?? profile['user_id'],
      'uid': profile['id'] ?? profile['user_id'],
      'name': fullName.isEmpty ? 'Уборщица' : fullName,
      'fullName': fullName,
      'phone': profile['phone'],
      'email': profile['email'],
      'city': profile['city'],
      'status': profile['status'],
      'rating': _num(profile['rating']),
      'verificationStatus':
          profile['verification_status'] ?? profile['verificationStatus'],
      'registrationStatus':
          profile['registration_status'] ?? profile['registrationStatus'],
      'monthlyAreaLimit': _num(profile['monthly_area_limit']).round(),
      'dailyWorkLimitMinutes': _num(
        profile['daily_work_limit_minutes'],
      ).round(),
      'soundEnabled': profile['sound_enabled'],
      'soundVolume': _num(profile['sound_volume']).round(),
      'soundKey': profile['sound_key'],
      'registeredAt': profile['registered_at'] ?? profile['created_at'],
      'createdAt': profile['registered_at'] ?? profile['created_at'],
      'verifiedAt': profile['verified_at'],
      'workStartDate': profile['work_start_date'],
      'documents': documents,
      'zones': zones,
      'serviceAreaIds': zones.map((zone) => zone['id'].toString()).toList(),
      'serviceAreas':
          zones.map((zone) => (zone['name_ru'] ?? '').toString()).toList(),
      'districts': zones
          .map((zone) => (zone['name_ru'] ?? zone['name'] ?? '').toString())
          .where((item) => item.isNotEmpty)
          .toList(),
    };
  }

  Stream<List<Map<String, dynamic>>> cleanersDirectoryStream() {
    if (_isDebugAdmin) {
      return _debugSharedAdminCleanersStream();
    }
    return _backendPollingStream(
      () async => (await BackendApiService.instance.getList('/admin/cleaners'))
          .map(mapAdminCleaner)
          .toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _loadServiceZones() async {
    final rows = <Map<String, dynamic>>[];
    final admin = SessionStore.activeSurface == SessionSurface.admin;
    while (true) {
      final page = await BackendApiService.instance.getList(
        admin ? '/admin/zones' : '/geo/zones',
        query: {'limit': '200', 'offset': '${rows.length}'},
        authenticated: admin,
      );
      rows.addAll(page);
      if (page.length < 200) return rows;
    }
  }

  Stream<List<Map<String, dynamic>>> clustersStream() {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(_debugClusters);
    }
    if (_useDebugFixtures) {
      return _debugSharedClustersStream();
    }
    return _backendPollingStream(
      () async => (await _loadServiceZones())
          .map((row) => <String, dynamic>{
                ...row,
                'title': row['name_ru'],
                'titleKk': row['name_kk'],
                'status': row['active'] == true ? 'active' : 'inactive',
                'createdAt': row['created_at'],
              })
          .toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> housesStream({bool admin = false}) {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryHouses);
    }
    if (_useDebugFixtures) {
      return _debugSharedHousesStream();
    }
    return _backendPollingStream(
      () async {
        final houses = <Map<String, dynamic>>[];
        while (true) {
          final page = await BackendApiService.instance.getList(
            admin ? '/admin/houses' : '/geo/connected-houses',
            query: {'limit': '200', 'offset': '${houses.length}'},
          );
          houses.addAll(page);
          if (page.length < 200) break;
        }
        return houses
            .map((row) => <String, dynamic>{
                  ...row,
                  'address':
                      '${row['street_ru'] ?? ''}, ${row['house'] ?? ''}, ${row['city'] ?? ''}',
                  'street': row['street_ru'],
                  'residentialComplex': row['residential_complex_ru'],
                  'zoneId': row['zone_id'],
                  'lat': row['latitude'],
                  'lng': row['longitude'],
                  'status': row['active'] == true ? 'ACTIVE' : 'INACTIVE',
                  'createdAt': row['created_at'],
                })
            .toList();
      },
    );
  }

  Stream<List<Map<String, dynamic>>> adminWaitlistStream() {
    if (_isDebugAdmin) {
      return _debugSharedWaitlistStream();
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/addressRequests'),
    );
  }

  Stream<List<Map<String, dynamic>>> adminPrelaunchBookingsStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(
        () =>
            _loadDebugList('order_requests') ?? const <Map<String, dynamic>>[],
      ).map((rows) => rows.where(_isPrelaunchBooking).toList());
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/preorders'),
    );
  }

  bool _isPrelaunchBooking(Map<String, dynamic> item) =>
      (item['type'] ?? '').toString() == 'prelaunch_prebooking';

  Future<void> markPrelaunchBookingWorked(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) {
      throw FlutterError('Не найдена предварительная запись.');
    }
    final update = {
      'status': 'prelaunch_worked',
      'orderStatus': 'prelaunch_worked',
      'workedAt': _isDebugAdmin
          ? DateTime.now().toIso8601String()
          : FieldValue.serverTimestamp(),
      'updatedAt': _isDebugAdmin
          ? DateTime.now().toIso8601String()
          : FieldValue.serverTimestamp(),
    };
    if (_isDebugAdmin) {
      final rows = _loadDebugList('order_requests') ?? <Map<String, dynamic>>[];
      final index = rows.indexWhere((item) => (item['id'] ?? '') == id);
      if (index == -1) {
        throw FlutterError('Предварительная запись не найдена.');
      }
      rows[index] = {...rows[index], ...update};
      debugStorageWrite(
        _debugStorageKey('order_requests'),
        jsonEncode(_jsonSafe(rows)),
      );
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.patchMap(
      '/admin/preorders/$id',
      body: {'status': 'worked'},
    );
  }

  Stream<List<Map<String, dynamic>>> customerPrelaunchBookingsStream() {
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    if (_isTemporaryCustomerSession || _isDebugCustomer) {
      return _debugSnapshotStream(
        () =>
            (_loadDebugList('order_requests') ?? const <Map<String, dynamic>>[])
                .where(
                  (item) =>
                      _isPrelaunchBooking(item) &&
                      (item['customerId'] ?? '').toString() == uid,
                )
                .toList(),
      );
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/preorders'),
    );
  }

  Future<Map<String, Map<String, dynamic>>> adminCustomersByIds(
    Iterable<String> customerIds,
  ) async {
    final ids = customerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const <String, Map<String, dynamic>>{};
    }
    if (_isDebugAdmin) {
      final customers = await adminCustomersStream().first;
      return {
        for (final customer in customers)
          if (ids.contains((customer['id'] ?? '').toString()))
            (customer['id'] ?? '').toString(): customer,
      };
    }
    final result = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      try {
        final details = await BackendApiService.instance.getMap('/users/$id');
        final user = Map<String, dynamic>.from(
          (details['user'] as Map?) ?? const <String, dynamic>{},
        );
        if (user.isNotEmpty) {
          result[id] = user;
        }
      } catch (_) {}
    }
    return result;
  }

  Future<Map<String, Map<String, dynamic>>> adminCleanersByIds(
    Iterable<String> cleanerIds,
  ) async {
    final ids = cleanerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const <String, Map<String, dynamic>>{};
    }
    if (_isDebugAdmin) {
      final cleaners = await _debugSharedAdminCleanersStream().first;
      return {
        for (final cleaner in cleaners)
          if (ids.contains((cleaner['id'] ?? '').toString()))
            (cleaner['id'] ?? '').toString(): cleaner,
      };
    }
    final result = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      try {
        final details = await BackendApiService.instance.getMap(
          '/admin/cleaners/$id/details',
        );
        final cleaner = Map<String, dynamic>.from(
          (details['cleaner'] as Map?) ?? const <String, dynamic>{},
        );
        if (cleaner.isNotEmpty) {
          result[id] = cleaner;
        }
      } catch (_) {}
    }
    return result;
  }

  Stream<List<Map<String, dynamic>>> adminCustomersStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(
        () => [
          {
            'id': 'customer_demo',
            ..._debugCustomerProfile(),
            'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 4)),
            ),
            'lastLoginAt': Timestamp.now(),
          },
        ],
      );
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/users'),
    ).map((items) {
      items.sort((a, b) {
        final leftMs = _timestampMillis(
          a['createdAt'] ?? a['registeredAt'] ?? a['updatedAt'],
        );
        final rightMs = _timestampMillis(
          b['createdAt'] ?? b['registeredAt'] ?? b['updatedAt'],
        );
        return rightMs.compareTo(leftMs);
      });
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> adminReferralStatsStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminReferralStats);
    }
    return _backendPollingStream(
        () => BackendApiService.instance.getList('/admin/referrals'));
  }

  Future<List<Map<String, dynamic>>> getAvailableHouses() async {
    if (_isTemporaryCustomerSession) {
      final profile = _temporaryCustomerProfile();
      final waitlist = _temporaryHouseWaitlist();
      final housesById = <String, Map<String, dynamic>>{};

      try {
        final liveHouses = await BackendApiService.instance.getList(
          '/geo/connected-houses',
          authenticated: false,
        );
        for (final house in liveHouses) {
          final id = (house['id'] ?? '').toString();
          if (id.isNotEmpty) housesById[id] = house;
        }
      } catch (_) {}

      for (final item in waitlist) {
        final houseId = (item['houseId'] ?? '').toString().trim();
        if (houseId.isEmpty) {
          continue;
        }
        housesById[houseId] = {
          'id': houseId,
          'title': item['residentialComplex'] ?? item['address'] ?? houseId,
          'residentialComplex':
              item['residentialComplex'] ?? item['address'] ?? houseId,
          'address': item['address'] ?? item['residentialComplex'] ?? houseId,
          'status': 'IN_PROGRESS',
          'threshold': 20,
          'current_users': waitlist
              .where((entry) => (entry['houseId'] ?? '').toString() == houseId)
              .length,
          if (item['lat'] != null) 'lat': item['lat'],
          if (item['lng'] != null) 'lng': item['lng'],
        };
      }

      final profileHouseId = (profile['houseId'] ?? '').toString().trim();
      if (profileHouseId.isNotEmpty) {
        housesById[profileHouseId] = {
          'id': profileHouseId,
          'title': profile['residentialComplex'] ??
              profile['address'] ??
              profileHouseId,
          'residentialComplex': profile['residentialComplex'] ??
              profile['address'] ??
              profileHouseId,
          'address': profile['address'] ??
              profile['residentialComplex'] ??
              profileHouseId,
          'status': profile['houseStatus'] ?? 'IN_PROGRESS',
          'threshold': 20,
          'current_users': housesById[profileHouseId]?['current_users'] ?? 1,
          if (profile['addressLat'] != null) 'lat': profile['addressLat'],
          if (profile['addressLng'] != null) 'lng': profile['addressLng'],
        };
      }

      final items = housesById.values.toList();
      items.sort((a, b) {
        final aText =
            '${a['residentialComplex'] ?? ''} ${a['address'] ?? ''} ${a['title'] ?? ''}'
                .trim();
        final bText =
            '${b['residentialComplex'] ?? ''} ${b['address'] ?? ''} ${b['title'] ?? ''}'
                .trim();
        return aText.compareTo(bText);
      });
      return items;
    }
    if (_useDebugFixtures) {
      final remote = await _db.collection('debug_bridge_houses').get();
      final items = _mergeDebugHouses(
        remote.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList(),
      );
      items.sort((a, b) {
        final aText =
            '${a['residentialComplex'] ?? ''} ${a['address'] ?? ''} ${a['title'] ?? ''}'
                .trim();
        final bText =
            '${b['residentialComplex'] ?? ''} ${b['address'] ?? ''} ${b['title'] ?? ''}'
                .trim();
        return aText.compareTo(bText);
      });
      return items;
    }
    final items = await BackendApiService.instance.getList(
      '/geo/connected-houses',
      authenticated: false,
    );
    items.sort((a, b) {
      final aText =
          '${a['residentialComplex'] ?? ''} ${a['address'] ?? ''} ${a['title'] ?? ''}'
              .trim();
      final bText =
          '${b['residentialComplex'] ?? ''} ${b['address'] ?? ''} ${b['title'] ?? ''}'
              .trim();
      return aText.compareTo(bText);
    });
    return items;
  }

  Future<Map<String, dynamic>?> resolveHouseForAddress({
    required String residentialComplex,
    String addressLine = '',
    String placeId = '',
    double? lat,
    double? lng,
  }) async {
    final queryText = _normalizeAddressText(
      '$residentialComplex $addressLine $placeId',
    );
    final queryLooseText = _normalizeAddressLooseText(queryText);
    if (queryText.isEmpty && (lat == null || lng == null)) {
      return null;
    }

    final items = await getAvailableHouses();
    Map<String, dynamic>? best;
    var bestScore = 0;
    final queryTokens = _addressTokens(queryText);
    final queryLooseTokens = _addressTokens(queryLooseText);
    for (final data in items) {
      var score = 0;
      final houseText = _normalizeAddressText(
        '${data['id'] ?? ''} ${data['address'] ?? ''} ${data['residentialComplex'] ?? ''} ${data['title'] ?? ''} ${_addressAliasesText(data)}',
      );
      final houseLooseText = _normalizeAddressLooseText(houseText);
      final houseTokens = _addressTokens(houseText);
      final houseId = _normalizeAddressText((data['id'] ?? '').toString());
      if (queryText.isNotEmpty && houseText.isNotEmpty) {
        if (placeId.isNotEmpty && houseId == _normalizeAddressText(placeId)) {
          score += 160;
        } else if (houseText == queryText) {
          score += 120;
        } else if (houseText.contains(queryText) ||
            queryText.contains(houseText)) {
          score += 90;
        } else {
          final matchedTokens =
              queryTokens.where((token) => houseText.contains(token)).length;
          final requiredTokensMatched = queryTokens.length <= 1 ||
              matchedTokens >= math.min(queryTokens.length, 2);
          score += matchedTokens * 20;
          if (requiredTokensMatched && matchedTokens == queryTokens.length) {
            score += 30;
          }
          if (queryTokens.length > 1 &&
              queryTokens.every((token) => houseText.contains(token))) {
            score += 45;
          }
        }
        if (queryLooseText.isNotEmpty) {
          if (houseLooseText == queryLooseText) {
            score += 110;
          } else if (houseLooseText.contains(queryLooseText) ||
              queryLooseText.contains(houseLooseText)) {
            score += 80;
          } else {
            final matchedLooseTokens = queryLooseTokens
                .where((token) => houseLooseText.contains(token))
                .length;
            score += matchedLooseTokens * 18;
            if (queryLooseTokens.length > 1 &&
                queryLooseTokens.every(
                  (token) => houseLooseText.contains(token),
                )) {
              score += 40;
            }
          }
          score += _fuzzyAddressScore(queryLooseTokens, houseTokens);
        }
      }

      final houseLat = (data['lat'] as num?)?.toDouble();
      final houseLng = (data['lng'] as num?)?.toDouble();
      if (lat != null && lng != null && houseLat != null && houseLng != null) {
        final distance = _distanceMeters(lat, lng, houseLat, houseLng);
        final radius = ((data['radiusMeters'] as num?)?.toDouble() ?? 500)
            .clamp(150, 1500);
        if (distance <= radius) {
          score += 100;
        } else if (distance <= radius * 2) {
          score += 35;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = data;
      }
    }

    return bestScore >= 35 ? best : null;
  }

  String _normalizeAddressText(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('ә', 'а')
        .replaceAll('ғ', 'г')
        .replaceAll('қ', 'к')
        .replaceAll('ң', 'н')
        .replaceAll('ө', 'о')
        .replaceAll('ұ', 'у')
        .replaceAll('ү', 'у')
        .replaceAll('һ', 'х')
        .replaceAll('і', 'и')
        .replaceAll('жилой комплекс', 'жк')
        .replaceAll(RegExp(r'\b(улица|ул|проспект|пр|переулок|пер)\b'), ' ')
        .replaceAll(
          RegExp(r'\b(кошеси|көшесі|коше|көше|дангылы|даңғылы)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeAddressLooseText(String value) {
    return _normalizeAddressText(value).replaceAll('ы', 'и');
  }

  Set<String> _addressTokens(String value) => _normalizeAddressLooseText(
        value,
      ).split(' ').where((token) => token.length > 1).toSet();

  bool _isNumberToken(String token) =>
      RegExp(r'^\d+[a-zа-я]?$').hasMatch(token);

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        );
      }
      previous = current;
    }
    return previous.last;
  }

  bool _tokenLooksLikePart(String query, String target, int maxDistance) {
    if ((query.length - target.length).abs() <= maxDistance &&
        _levenshteinDistance(query, target) <= maxDistance) {
      return true;
    }
    if (query.length < 3 || target.length <= query.length) {
      return false;
    }
    for (var index = 0; index <= target.length - query.length; index += 1) {
      final part = target.substring(index, index + query.length);
      if (_levenshteinDistance(query, part) <= maxDistance) {
        return true;
      }
    }
    return false;
  }

  int _fuzzyAddressScore(Set<String> queryTokens, Set<String> houseTokens) {
    final queryNumbers = queryTokens.where(_isNumberToken).toSet();
    final houseNumbers = houseTokens.where(_isNumberToken).toSet();
    final numberMatched =
        queryNumbers.isNotEmpty && queryNumbers.any(houseNumbers.contains);
    var fuzzyStreetMatches = 0;
    for (final query in queryTokens.where((token) => !_isNumberToken(token))) {
      for (final house in houseTokens.where(
        (token) => !_isNumberToken(token),
      )) {
        final maxDistance = query.length <= 4 || house.length <= 4 ? 1 : 2;
        if (_tokenLooksLikePart(query, house, maxDistance)) {
          fuzzyStreetMatches += 1;
          break;
        }
      }
    }
    if (numberMatched && fuzzyStreetMatches > 0) {
      return 55 + fuzzyStreetMatches * 20;
    }
    return fuzzyStreetMatches * 12;
  }

  String _addressAliasesText(Map<String, dynamic> data) {
    final aliases = data['aliases'];
    if (aliases is Iterable) {
      return aliases.map((item) => item.toString()).join(' ');
    }
    return [
      data['addressRu'],
      data['addressKk'],
      data['titleRu'],
      data['titleKk'],
      data['searchKeywords'],
      data['keywords'],
    ].where((item) => item != null).join(' ');
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  Future<List<Map<String, dynamic>>> adminCities() => BackendApiService.instance
      .getList('/admin/cities', query: {'limit': '200'});

  Stream<List<Map<String, dynamic>>> serviceZonesStream() {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(_debugServiceZones);
    }
    if (_isDebugAdmin) {
      return _debugSharedServiceZonesStream();
    }
    if (_useDebugFixtures) {
      return _debugSnapshotStream(_debugServiceZones);
    }
    return _backendPollingStream(
      () async => (await _loadServiceZones())
          .map((row) => <String, dynamic>{
                ...row,
                'title': row['name_ru'],
                'titleKk': row['name_kk'],
                'status': row['active'] == true ? 'active' : 'inactive',
                'createdAt': row['created_at'],
              })
          .toList(),
    );
  }

  Stream<Map<String, dynamic>?> houseStream(String houseId) {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(() {
        for (final item in _temporaryHouses()) {
          if ((item['id'] ?? '').toString() == houseId) {
            return item;
          }
        }
        return null;
      });
    }
    if (_useDebugFixtures) {
      return _debugSharedHousesStream().map((items) {
        for (final item in items) {
          if ((item['id'] ?? '').toString() == houseId) {
            return item;
          }
        }
        return null;
      });
    }
    return _backendPollingStream(() async {
      final houses = await BackendApiService.instance.getList(
        '/geo/connected-houses',
        authenticated: false,
      );
      for (final item in houses) {
        if ((item['id'] ?? '').toString() == houseId) {
          return item;
        }
      }
      return null;
    });
  }

  Stream<List<Map<String, dynamic>>> houseWaitlistStream(String houseId) {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(
        () => _temporaryHouseWaitlist()
            .where((item) => (item['houseId'] ?? '').toString() == houseId)
            .toList(),
      );
    }
    if (_useDebugFixtures) {
      return _debugSharedWaitlistStream(houseId: houseId);
    }
    return _backendPollingStream(() =>
        BackendApiService.instance.getList('/geo/houses/$houseId/waitlist'));
  }

  Stream<List<Map<String, dynamic>>> scheduleSlotsByClusterStream(
    String clusterName,
  ) {
    if (_isDebugAdmin) {
      return Stream.multi((controller) {
        List<Map<String, dynamic>> remote = const <Map<String, dynamic>>[];

        void emit() {
          final merged = _mergeDebugCleanerSlots(remote);
          final normalizedCluster = clusterName.trim().toLowerCase();
          final filtered = merged.where((item) {
            final itemCluster = (item['clusterName'] ??
                    item['residentialComplex'] ??
                    item['address'] ??
                    '')
                .toString()
                .trim()
                .toLowerCase();
            return itemCluster == normalizedCluster;
          }).toList();
          controller.add(filtered);
        }

        final remoteSub = _db
            .collection('debug_bridge_cleaner_slots')
            .snapshots()
            .listen((snap) {
          remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          emit();
        });
        final stateSub = _debugStateChanges.stream.listen((_) => emit());

        emit();
        controller.onCancel = () async {
          await remoteSub.cancel();
          await stateSub.cancel();
        };
      });
    }
    return _backendPollingStream(() async {
      final orders = await BackendApiService.instance.getList('/admin/orders');
      final normalizedCluster = clusterName.trim().toLowerCase();
      return orders.where((item) {
        final itemCluster = (item['clusterName'] ??
                item['residentialComplex'] ??
                item['address'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
        return itemCluster == normalizedCluster;
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> customerPackagesStream() {
    if (_isDebugCustomer) {
      return _db.collection('debug_bridge_customer_packages').snapshots().map((
        snap,
      ) {
        final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        final merged = <String, Map<String, dynamic>>{};
        for (final item in [..._debugAdminPackages(), ...remote]) {
          final id = (item['id'] ?? '').toString();
          if (id.isEmpty) {
            continue;
          }
          merged[id] = {
            ...merged[id] ?? const <String, dynamic>{},
            ...item,
            'id': id,
          };
        }
        final items =
            merged.values.where((item) => item['isActive'] != false).toList();
        items.sort((a, b) {
          final aOrder =
              PackageCatalogUtils.numValue(a['sortOrder'])?.toInt() ?? 999;
          final bOrder =
              PackageCatalogUtils.numValue(b['sortOrder'])?.toInt() ?? 999;
          if (aOrder != bOrder) {
            return aOrder.compareTo(bOrder);
          }
          return (a['name'] ?? '').toString().compareTo(
                (b['name'] ?? '').toString(),
              );
        });
        return items;
      });
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(() {
        final items = _debugAdminPackages()
            .where((item) => item['isActive'] != false)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        items.sort((a, b) {
          final aOrder =
              PackageCatalogUtils.numValue(a['sortOrder'])?.toInt() ?? 999;
          final bOrder =
              PackageCatalogUtils.numValue(b['sortOrder'])?.toInt() ?? 999;
          if (aOrder != bOrder) {
            return aOrder.compareTo(bOrder);
          }
          return (a['name'] ?? '').toString().compareTo(
                (b['name'] ?? '').toString(),
              );
        });
        return items;
      });
    }
    return _backendPollingStream(() async {
      final items = (await BackendApiService.instance.getList(
        '/catalog/packages',
      ))
          .map(_mapBackendCatalogPackage)
          .toList();
      items.sort((a, b) {
        final aOrder =
            PackageCatalogUtils.numValue(a['sortOrder'])?.toInt() ?? 999;
        final bOrder =
            PackageCatalogUtils.numValue(b['sortOrder'])?.toInt() ?? 999;
        if (aOrder != bOrder) {
          return aOrder.compareTo(bOrder);
        }
        return (a['name'] ?? '').toString().compareTo(
              (b['name'] ?? '').toString(),
            );
      });
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> customerOrdersStream() {
    if (_isDebugCustomer) {
      return _debugSharedCustomerOrdersStream();
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerOrders);
    }
    final mergedOrdersStream = _backendPollingStream(() async {
      final orders = (await BackendApiService.instance.getList(
        '/orders',
      ))
          .map(_mapBackendOrder)
          .toList();
      orders.sort(
        (a, b) => _timestampMillis(
          b['createdAt'] ?? b['updatedAt'],
        ).compareTo(_timestampMillis(a['createdAt'] ?? a['updatedAt'])),
      );
      return orders;
    }, interval: const Duration(seconds: 2));
    return _combineLatestLists(
      mergedOrdersStream,
      customerPrelaunchBookingsStream(),
      (orders, prelaunchBookings) => [
        ...orders,
        ...prelaunchBookings
            .where(_isActiveCustomerPrelaunchBooking)
            .map(_customerPrelaunchBookingOrderView),
      ],
    );
  }

  bool _isActiveCustomerPrelaunchBooking(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString().toLowerCase();
    final orderStatus = (item['orderStatus'] ?? '').toString().toLowerCase();
    const closed = {
      'canceled',
      'cancelled',
      'completed',
      'paid',
      'prelaunch_worked',
      'prelaunch_started',
    };
    return !closed.contains(status) && !closed.contains(orderStatus);
  }

  Map<String, dynamic> _customerPrelaunchBookingOrderView(
    Map<String, dynamic> item,
  ) {
    final desiredDate =
        (item['desiredDate'] ?? item['form']?['desiredDate'] ?? '').toString();
    final preferredTime =
        (item['preferredTime'] ?? item['form']?['preferredTime'] ?? '')
            .toString();
    return {
      ...item,
      'id': item['id'] ?? item['requestId'],
      'orderId': item['id'] ?? item['requestId'],
      'type': 'prelaunch_prebooking',
      'package': 'Предварительная запись',
      'status': item['status'] ?? 'prelaunch_waiting',
      'orderStatus': item['orderStatus'] ?? 'prelaunch_waiting',
      'paymentStatus': item['paymentStatus'] ?? 'not_required_until_launch',
      'date': desiredDate.isNotEmpty ? desiredDate : item['date'],
      'time': preferredTime.isNotEmpty ? preferredTime : 'Время будет уточнено',
      'address': 'Предварительная запись',
      'price': 0,
    };
  }

  Stream<List<Map<String, dynamic>>> adminOrdersStream() {
    if (_isDebugAdmin) {
      return _debugSharedOrdersStream().map(
        (items) => items.map(_debugAdminOrderView).toList(),
      );
    }
    return _backendPollingStream(() async {
      final live = await BackendApiService.instance.getList('/admin/orders');
      const bridge = <Map<String, dynamic>>[];
      final merged = <String, Map<String, dynamic>>{};
      for (final item in [...bridge, ...live]) {
        final id = (item['id'] ?? item['orderId'] ?? '').toString().trim();
        if (id.isEmpty) {
          continue;
        }
        final existing = merged[id] ?? const <String, dynamic>{};
        merged[id] = {
          ...existing,
          ...item,
          'id': id,
          'orderId': item['orderId'] ?? id,
        };
      }
      final items =
          _dedupeAdminOrderItems(merged.values.where(_shouldShowInAdminOrders))
            ..sort(
              (a, b) => _timestampMillis(
                b['createdAt'] ?? b['date'] ?? b['updatedAt'],
              ).compareTo(
                _timestampMillis(
                  a['createdAt'] ?? a['date'] ?? a['updatedAt'],
                ),
              ),
            );
      return items;
    }, interval: const Duration(seconds: 2));
  }

  bool _shouldShowInAdminOrders(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString().toLowerCase();
    if (type == 'prelaunch_prebooking') {
      return false;
    }
    if (type != 'prelaunch_order') {
      return true;
    }
    final status =
        (item['orderStatus'] ?? item['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (item['paymentStatus'] ?? '')
        .toString()
        .toLowerCase()
        .replaceAll('-', '_');
    return status != 'prelaunch_waiting' &&
        status != 'prelaunch_started' &&
        paymentStatus == 'paid';
  }

  List<Map<String, dynamic>> _dedupeAdminOrderItems(
    Iterable<Map<String, dynamic>> items,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final id = (item['id'] ?? item['orderId'] ?? '').toString().trim();
      if (id.isEmpty) {
        continue;
      }
      byId[id] = _mergeAdminOrderDuplicate(byId[id], item);
    }

    final byVisit = <String, Map<String, dynamic>>{};
    var fallbackIndex = 0;
    for (final item in byId.values) {
      final key = _adminOrderVisitKey(item) ?? 'id:${fallbackIndex++}';
      byVisit[key] = _mergeAdminOrderDuplicate(byVisit[key], item);
    }
    return byVisit.values.toList();
  }

  String? _adminOrderVisitKey(Map<String, dynamic> item) {
    final customerId =
        (item['customerId'] ?? item['userId'] ?? '').toString().trim();
    final dateKey = _adminOrderDateKey(item);
    final timeKey = _adminOrderTimeKey(item);
    if (customerId.isEmpty || dateKey.isEmpty || timeKey.isEmpty) {
      return null;
    }
    return '$customerId|$dateKey|$timeKey';
  }

  String _adminOrderDateKey(Map<String, dynamic> item) {
    final explicit = (item['scheduledDateKey'] ??
            item['visitDateKey'] ??
            item['dateKey'] ??
            '')
        .toString()
        .trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(explicit)) {
      return explicit;
    }
    final date = _valueToDate(
      item['scheduledFor'] ??
          item['scheduledDate'] ??
          item['visitDate'] ??
          item['date'],
    );
    if (date == null) {
      return '';
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _adminOrderTimeKey(Map<String, dynamic> item) {
    final raw = (item['time'] ??
            item['scheduledTime'] ??
            item['orderTime'] ??
            item['timeRange'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    if (raw.isEmpty || raw == '—' || raw.contains('ожидает')) {
      return '';
    }
    final times = RegExp(r'\d{1,2}:\d{2}').allMatches(raw).toList();
    if (times.length >= 2) {
      return '${times[0].group(0)}-${times[1].group(0)}';
    }
    return raw.contains('выбор') ? '' : raw;
  }

  Map<String, dynamic> _mergeAdminOrderDuplicate(
    Map<String, dynamic>? current,
    Map<String, dynamic> next,
  ) {
    if (current == null) {
      return next;
    }
    final preferred =
        _adminOrderDuplicateScore(next) >= _adminOrderDuplicateScore(current)
            ? next
            : current;
    final fallback = identical(preferred, next) ? current : next;
    return {
      ...fallback,
      ...preferred,
      'addons': _preferAdminList(preferred['addons'], fallback['addons']),
      'addonsDetailed': _preferAdminList(
        preferred['addonsDetailed'],
        fallback['addonsDetailed'],
      ),
      'separatePaymentAddons': _preferAdminList(
        preferred['separatePaymentAddons'],
        fallback['separatePaymentAddons'],
      ),
    };
  }

  int _adminOrderDuplicateScore(Map<String, dynamic> item) {
    var score = 0;
    if (_adminList(item['addonsDetailed']).isNotEmpty ||
        _adminList(item['addons']).isNotEmpty) {
      score += 20;
    }
    if ((item['scheduledDateKey'] ?? '').toString().trim().isNotEmpty) {
      score += 8;
    }
    if ((item['subscriptionId'] ?? '').toString().trim().isNotEmpty) {
      score += 4;
    }
    if ((item['assignmentStatus'] ?? '').toString().trim().isNotEmpty) {
      score += 2;
    }
    if (_timestampMillis(item['updatedAt'] ?? item['createdAt']) > 0) {
      score += 1;
    }
    return score;
  }

  List<dynamic> _preferAdminList(Object? primary, Object? fallback) {
    final left = _adminList(primary);
    return left.isNotEmpty ? left : _adminList(fallback);
  }

  List<dynamic> _adminList(Object? value) =>
      value is List ? value : const <dynamic>[];

  Stream<List<Map<String, dynamic>>> adminCleanerDailyScheduleStream() {
    if (_isDebugAdmin) {
      return _debugSharedOrdersStream().map((items) {
        return _buildAdminCleanerDailySchedule(items);
      });
    }
    return adminAssignmentItemsStream().map(_buildAdminCleanerDailySchedule);
  }

  List<Map<String, dynamic>> _buildAdminCleanerDailySchedule(
    List<Map<String, dynamic>> items,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final item in items) {
      if (!_isActiveAdminAssignment(item)) {
        continue;
      }
      final cleanerId = (item['cleanerId'] ?? '').toString().trim();
      final dateKey = _adminAssignmentDateKey(item);
      if (cleanerId.isEmpty || dateKey.isEmpty) {
        continue;
      }
      final area = (item['area'] as num?)?.toDouble() ??
          (item['apartmentArea'] as num?)?.toDouble() ??
          0;
      final minutes = (item['totalDurationMinutes'] as num?)?.toInt() ??
          (item['estimatedDurationMinutes'] as num?)?.toInt() ??
          0;
      final entry = grouped.putIfAbsent('$cleanerId:$dateKey', () {
        return {
          'id': '${cleanerId}_$dateKey',
          'cleanerId': cleanerId,
          'dateKey': dateKey,
          'orders': <String>[],
          'totalSqm': 0.0,
          'totalMinutes': 0,
          'totalTravelMinutes': 0,
          'isFull': false,
        };
      });
      (entry['orders'] as List<String>).add((item['id'] ?? '').toString());
      entry['totalSqm'] = ((entry['totalSqm'] as num?)?.toDouble() ?? 0) + area;
      entry['totalMinutes'] =
          ((entry['totalMinutes'] as num?)?.toInt() ?? 0) + minutes;
    }
    for (final entry in grouped.values) {
      entry['isFull'] = ((entry['totalSqm'] as num?)?.toDouble() ?? 0) >= 220;
    }
    return grouped.values.toList();
  }

  bool _isActiveAdminAssignment(Map<String, dynamic> item) {
    final status =
        (item['orderStatus'] ?? item['status'] ?? '').toString().toLowerCase();
    return const {
      'assigned',
      'confirmed',
      'start_pending',
      'in_progress',
    }.contains(status);
  }

  String _adminAssignmentDateKey(Map<String, dynamic> item) {
    final explicit =
        (item['scheduledDateKey'] ?? item['dateKey'] ?? '').toString().trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(explicit)) {
      return explicit;
    }
    for (final value in [
      item['scheduledFor'],
      item['scheduledDate'],
      item['date'],
    ]) {
      final date = _valueToDate(value);
      if (date != null) {
        return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    }
    return '';
  }

  DateTime? _valueToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  Stream<List<Map<String, dynamic>>> adminScheduleSlotsStream() {
    if (_isDebugAdmin) {
      return _debugSharedCustomerScheduleSlotsStream();
    }
    return adminOrdersStream();
  }

  Stream<List<Map<String, dynamic>>> adminAssignmentItemsStream() {
    return _combineLatestLists(
      adminOrdersStream(),
      adminScheduleSlotsStream(),
      (orders, slots) => [
        ...orders,
        ...slots.map(
          (slot) => {
            ...slot,
            'id': slot['id'] ?? slot['slotId'],
            'orderStatus': slot['status'],
            'scopeType': 'schedule_slot',
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> adminPaymentsStream() {
    return _backendPollingStream(
      () async => (await BackendApiService.instance.getList('/admin/payments'))
          .map(_mapBackendPayment)
          .toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> adminChecklistsStream() {
    if (_isDebugAdmin) {
      return _debugSharedCleanerChecklistsStream();
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/checklistReports'),
    );
  }

  Stream<List<Map<String, dynamic>>> adminPayoutsStream() {
    if (_isDebugAdmin) {
      return _debugSharedCleanerPayoutsStream();
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/payouts'),
    );
  }

  Stream<List<Map<String, dynamic>>> adminVideoContentStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminVideoContent);
    }
    return _backendPollingStream(
        () => BackendApiService.instance.getList('/admin/videos'));
  }

  Stream<List<Map<String, dynamic>>> adminInfoContentStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminInfoContent);
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/contentPages'),
    );
  }

  Stream<List<Map<String, dynamic>>> adminCustomerPackagesStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminPackages);
    }
    return _backendPollingStream(
      () async => (await BackendApiService.instance.getList('/admin/packages'))
          .map(_mapBackendCatalogPackage)
          .toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> adminNotificationsStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(() => const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
        () => BackendApiService.instance.getList('/admin/notifications'),
        interval: const Duration(seconds: 2));
  }

  Stream<Map<String, dynamic>> adminPoliciesStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminPolicies);
    }
    return _backendPollingStream(() async {
      final rows = await BackendApiService.instance.getList('/admin/settings');
      return {
        for (final row in rows)
          if ((row['key'] ?? '').toString().isNotEmpty)
            row['key'].toString(): row['value'],
      };
    });
  }

  Stream<List<Map<String, dynamic>>> adminPromoBannersStream() {
    if (_isDebugAdmin) return _debugSnapshotStream(_debugAdminPromoBanners);
    return _backendPollingStream(() async {
      final items = await BackendApiService.instance.getList('/admin/banners');
      return items.map(mapBackendBanner).toList();
    });
  }

  Future<void> saveAdminPromoBanner(Map<String, dynamic> banner) async {
    if (_isDebugAdmin) {
      final items = List<Map<String, dynamic>>.from(_debugAdminPromoBanners());
      final index = items.indexWhere((item) => item['id'] == banner['id']);
      if (index < 0) { items.add(banner); } else { items[index] = banner; }
      await saveAdminPromoBanners(items);
      return;
    }
    await saveAdminPromoBanners([banner]);
  }

  Future<void> deleteAdminPromoBanner(String id) async {
    if (_isDebugAdmin) {
      await saveAdminPromoBanners(_debugAdminPromoBanners().where((item) => item['id'] != id).toList());
      return;
    }
    await BackendApiService.instance.delete('/admin/banners/$id');
  }

  Stream<List<Map<String, dynamic>>> adminPromotionsStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminPromotions);
    }
    return _backendPollingStream(() async {
      final items = await BackendApiService.instance.getList(
        '/admin/promotions',
      );
      final mapped = items.map(mapBackendPromotion).toList();
      mapped.sort((a, b) {
        final aActive = a['isActive'] == false ? 1 : 0;
        final bActive = b['isActive'] == false ? 1 : 0;
        if (aActive != bActive) {
          return aActive.compareTo(bActive);
        }
        return (a['title'] ?? a['id']).toString().compareTo(
              (b['title'] ?? b['id']).toString(),
            );
      });
      return mapped;
    });
  }

  Stream<List<Map<String, dynamic>>> adminAddonGroupsStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminAddonGroups);
    }
    return _backendPollingStream(() async {
      final groups = await BackendApiService.instance
          .getList('/admin/addonGroups', query: {'limit': '200'});
      final addons = await BackendApiService.instance
          .getList('/admin/addons', query: {'limit': '200'});
      return groups
          .map((group) => <String, dynamic>{
                ...group,
                'key': group['id'],
                'label': group['title_ru'],
                'labelKk': group['title_kk'],
                'sortOrder': group['sort_order'],
                'isActive': group['active'],
                'items': addons
                    .where((item) => item['group_id'] == group['id'])
                    .map((item) => <String, dynamic>{
                          ...item,
                          'key': item['id'],
                          'label': item['title_ru'],
                          'labelKk': item['title_kk'],
                          'description': item['description_ru'],
                          'fullInfo': item['description_ru'],
                          'note': item['hint_ru'],
                          'price': _num(item['price']).round(),
                          'durationMinutes': item['duration_minutes'],
                          'pricingType': item['pricing_type'],
                          'supportsQuantity':
                              item['pricing_type'] != 'fixed_per_order',
                          'separatePayment': item['paid_separately'],
                          'sortOrder': item['sort_order'],
                          'isActive': item['active'],
                        })
                    .toList(),
              })
          .toList();
    });
  }

  Stream<List<Map<String, dynamic>>> adminChecklistTemplatesStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminChecklistTemplates);
    }
    return AppConfigService.instance.cleanerChecklistTemplatesStream();
  }

  Stream<List<Map<String, dynamic>>> adminTranslationEntriesStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminTranslations);
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/admin/translations'),
    );
  }

  Stream<List<Map<String, dynamic>>> adminSavedViewsStream() {
    if (_isDebugAdmin) {
      return _debugSnapshotStream(_debugAdminSavedViews);
    }
    return _backendPollingStream(() async {
      final rows = await BackendApiService.instance.getList('/admin/settings');
      return rows
          .where((row) =>
              (row['key'] ?? '').toString().startsWith('admin_saved_view_') &&
              row['value'] is Map &&
              row['value']['deleted'] != true)
          .map((row) => Map<String, dynamic>.from(row['value'] as Map))
          .toList();
    });
  }

  Stream<List<Map<String, dynamic>>> areaMismatchReportsStream() {
    if (_isDebugAdmin) {
      return _debugAreaMismatchReportsBridgeStream();
    }
    return _backendPollingStream(
      () async => (await BackendApiService.instance.getList('/admin/quality'))
          .map((row) => <String, dynamic>{
                ...row,
                'userId': row['customer_id'],
                'customerId': row['customer_id'],
                'orderId': row['order_id'],
                'actualArea': row['requested_area'],
                'initialArea': row['verified_area'] ?? row['area'] ?? 0,
                'createdAt': row['created_at'],
                'updatedAt': row['updated_at'],
                'type': row['document_file_id'] == null
                    ? 'quality_area_check'
                    : 'area_mismatch',
                'status':
                    row['status'] == 'approved' ? 'resolved' : row['status'],
                'reviewStatus': row['status'],
                'customerName': row['customer_name'],
                'customerPhone': row['customer_phone'],
              })
          .toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> qualityControlAreaChecksStream() {
    return areaMismatchReportsStream().map((items) {
      final checks = items
          .where(
            (item) => (item['type'] ?? '').toString() == 'quality_area_check',
          )
          .toList();
      checks.sort(
        (a, b) => _timestampMillis(
          b['createdAt'] ?? b['updatedAt'],
        ).compareTo(_timestampMillis(a['createdAt'] ?? a['updatedAt'])),
      );
      return checks;
    });
  }

  Stream<List<Map<String, dynamic>>> customerPaymentsStream({String? userId}) {
    final uid = userId ?? _uidOrNull;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final items = (await BackendApiService.instance.getList(
        '/payments/my',
      ))
          .map(_mapBackendPayment)
          .toList();
      items.sort(
        (a, b) => _timestampMillis(
          b['createdAt'] ?? b['updatedAt'],
        ).compareTo(_timestampMillis(a['createdAt'] ?? a['updatedAt'])),
      );
      return items;
    });
  }

  List<Map<String, dynamic>> adminDebugOrdersFallback() {
    if (!_isDebugAdmin) {
      return const <Map<String, dynamic>>[];
    }
    return _debugAdminOrders();
  }

  Stream<List<Map<String, dynamic>>> customerScheduleSlotsStream() {
    if (_isDebugCustomer) {
      return _debugSharedCustomerScheduleSlotsStream();
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerScheduleSlots);
    }
    if (_uidOrNull == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final orders = (await BackendApiService.instance.getList(
        '/orders',
      ))
          .map(_mapBackendOrder)
          .toList();
      return orders
          .where((item) => _isActiveScheduleSlot(item))
          .map(
            (item) => {
              ...item,
              'sourceOrderId': item['id'],
              'customerOrderId': item['id'],
              'subscriptionId': item['customerPackageId'],
              'scheduledDateKey': item['scheduledDateKey'],
            },
          )
          .toList();
    }, interval: const Duration(seconds: 2));
  }

  Stream<List<Map<String, dynamic>>> customerSubscriptionsStream() {
    if (_isDebugCustomer) {
      return _debugSharedCustomerSubscriptionsStream();
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerSubscriptions);
    }
    return _backendPollingStream(() async {
      final items = (await BackendApiService.instance.getList(
        '/packages/my',
      ))
          .map(_mapBackendCustomerPackage)
          .toList();
      items.sort(
        (a, b) => _timestampMillis(
          b['createdAt'] ?? b['updatedAt'],
        ).compareTo(_timestampMillis(a['createdAt'] ?? a['updatedAt'])),
      );
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> customerAddonRequestsStream() {
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/addon-requests'),
    ).map((items) {
      items.sort((a, b) {
        final aMs = _timestampMillis(a['createdAt'] ?? a['updatedAt']);
        final bMs = _timestampMillis(b['createdAt'] ?? b['updatedAt']);
        return bMs.compareTo(aMs);
      });
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> cleanerAddonRequestsStream() {
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/addon-requests'),
    ).map((items) {
      items.sort((a, b) {
        final aMs = _timestampMillis(a['createdAt'] ?? a['updatedAt']);
        final bMs = _timestampMillis(b['createdAt'] ?? b['updatedAt']);
        return bMs.compareTo(aMs);
      });
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> cleanerPaidAddonRequestsForSlotStream(
    String orderId,
  ) {
    final uid = _uidOrNull;
    final normalizedOrderId = orderId.trim();
    if (uid == null || normalizedOrderId.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
      () => BackendApiService.instance.getList('/addon-requests'),
    ).map((items) {
      final paidStatuses = {'paid', 'payment_confirmed', 'completed'};
      final result = items.where((item) {
        final status = (item['status'] ?? '').toString().toLowerCase().trim();
        if (!paidStatuses.contains(status)) {
          return false;
        }
        final ids = [
          item['slotId'],
          item['scheduleSlotId'],
          item['sourceOrderId'],
          item['customerOrderId'],
          item['orderId'],
          item['order_id'],
        ].map((value) => (value ?? '').toString().trim()).toSet();
        return ids.contains(normalizedOrderId);
      }).toList()
        ..sort((a, b) {
          final aMs = _timestampMillis(a['paidAt'] ?? a['updatedAt']);
          final bMs = _timestampMillis(b['paidAt'] ?? b['updatedAt']);
          return aMs.compareTo(bMs);
        });
      return result;
    });
  }

  Stream<Map<String, dynamic>?> chatMetaStream(String orderId) {
    if (_isDebugCustomer || _isDebugCleaner) {
      return Stream.multi((controller) {
        var canAccess = false;

        void emit() {
          controller.add(
            canAccess
                ? {
                    'id': orderId,
                    'participants': [
                      if (_isDebugCustomer) 'customer_demo' else 'cleaner_demo',
                      if (_isDebugCustomer) 'cleaner_demo' else 'customer_demo',
                    ],
                  }
                : null,
          );
        }

        final accessSub = _debugCanAccessOrderStream(orderId).listen((value) {
          canAccess = value;
          emit();
        });

        emit();
        controller.onCancel = () async {
          await accessSub.cancel();
        };
      });
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return Stream.multi((controller) {
        var canAccess = false;

        void emit() {
          controller.add(
            canAccess
                ? {
                    'id': orderId,
                    'participants': [
                      _uidOrNull ?? '',
                      if (_isTemporaryCustomerSession)
                        'temp_cleaner_chat'
                      else
                        'temp_customer_chat',
                    ],
                  }
                : null,
          );
        }

        final accessSub = _temporaryCanAccessOrderStream(orderId).listen((
          value,
        ) {
          canAccess = value;
          emit();
        });

        emit();
        controller.onCancel = () async {
          await accessSub.cancel();
        };
      });
    }
    return _backendPollingStream(() async {
      final chat = await _backendChatForOrder(orderId, create: false);
      if (chat == null) return null;
      return _mapBackendChatSummary(chat);
    });
  }

  Stream<Map<String, dynamic>?> chatSummaryStream(String orderId) {
    if (_isDebugCustomer || _isDebugCleaner) {
      return _debugSharedChatSummariesStream().map((items) {
        for (final item in items) {
          if ((item['orderId'] ?? '').toString() == orderId) {
            return item;
          }
        }
        return null;
      });
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _temporaryChatSummariesStream().map((items) {
        for (final item in items) {
          if ((item['orderId'] ?? '').toString() == orderId) {
            return item;
          }
        }
        return null;
      });
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(null);
    }
    return userChatSummariesStream().map((items) {
      for (final item in items) {
        final ids = [
          item['orderId'],
          item['targetOrderId'],
          item['sourceOrderId'],
          item['scopeId'],
          item['slotId'],
          item['scheduleSlotId'],
        ].map((value) => (value ?? '').toString().trim()).toSet();
        if (ids.contains(orderId.trim())) {
          return item;
        }
      }
      return null;
    });
  }

  Stream<List<Map<String, dynamic>>> userChatSummariesStream() {
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    if (_isDebugCustomer || _isDebugCleaner) {
      return _debugSharedChatSummariesStream();
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _temporaryChatSummariesStream();
    }
    return _backendPollingStream(() async {
      final items = await BackendApiService.instance.getList('/chats');
      final mapped = items.map(_mapBackendChatSummary).toList();
      mapped.sort((a, b) {
        final aMs = _timestampMillis(a['updatedAt'] ?? a['lastMessageAt']);
        final bMs = _timestampMillis(b['updatedAt'] ?? b['lastMessageAt']);
        return bMs.compareTo(aMs);
      });
      return mapped;
    }).map((items) {
      items.sort((a, b) {
        final aMs = _timestampMillis(a['updatedAt'] ?? a['lastMessageAt']);
        final bMs = _timestampMillis(b['updatedAt'] ?? b['lastMessageAt']);
        return bMs.compareTo(aMs);
      });
      return items;
    });
  }

  Stream<int> userUnreadActivityCountStream() {
    final notificationsStream = userNotificationsStream();
    final chatsStream = userChatSummariesStream();
    return Stream.multi((controller) {
      List<Map<String, dynamic>> notifications = const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> chats = const <Map<String, dynamic>>[];

      void emit() {
        final unreadNotifications =
            notifications.where((item) => item['read'] != true).length;
        final unreadChats = chats.fold<int>(0, (total, item) {
          final value = item['unreadCount'];
          if (value is num) {
            return total + value.toInt();
          }
          return total + (int.tryParse(value?.toString() ?? '') ?? 0);
        });
        controller.add(unreadNotifications + unreadChats);
      }

      final notificationsSub = notificationsStream.listen((items) {
        notifications = items;
        emit();
      }, onError: controller.addError);
      final chatsSub = chatsStream.listen((items) {
        chats = items;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await notificationsSub.cancel();
        await chatsSub.cancel();
      };
    });
  }

  Stream<bool> _debugCanAccessOrderStream(String orderId) {
    if (_isDebugCustomer) {
      return _debugSharedCustomerOrdersStream().map(
        (items) => items.any(
          (item) => (item['id'] ?? item['orderId'] ?? '').toString() == orderId,
        ),
      );
    }
    if (_isDebugCleaner) {
      return _debugSharedCleanerOrdersStream().map(
        (items) => items.any(
          (item) =>
              (item['customerOrderId'] ?? item['orderId'] ?? item['id'] ?? '')
                  .toString() ==
              orderId,
        ),
      );
    }
    return Stream.value(false);
  }

  Future<bool> _debugCanAccessOrder(String orderId) async {
    return await _debugCanAccessOrderStream(orderId).first;
  }

  Stream<bool> _temporaryCanAccessOrderStream(String orderId) {
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerOrders).map(
        (items) => items.any(
          (item) => (item['id'] ?? item['orderId'] ?? '').toString() == orderId,
        ),
      );
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryCleanerOrders).map(
        (items) => items.any(
          (item) =>
              (item['customerOrderId'] ?? item['orderId'] ?? item['id'] ?? '')
                  .toString() ==
              orderId,
        ),
      );
    }
    return Stream.value(false);
  }

  Future<bool> _temporaryCanAccessOrder(String orderId) async {
    return await _temporaryCanAccessOrderStream(orderId).first;
  }

  Future<bool> _debugOwnsSubscription(String subscriptionId) async {
    if (!_isDebugCustomer) {
      return false;
    }
    final subscriptions = await _debugMergedCustomerSubscriptions();
    return subscriptions.any(
      (item) => (item['id'] ?? '').toString() == subscriptionId,
    );
  }

  Stream<Map<String, dynamic>?> cleanerVerificationStream() {
    if (_isDebugCleaner) {
      return _debugSharedCleanerVerificationStream();
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryCleanerVerification);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(null);
    }
    return _backendPollingStream(() async {
      final profile = await BackendApiService.instance.getMap(
        '/cleaner/profile',
      );
      return Map<String, dynamic>.from((profile['profile'] as Map?) ?? profile);
    });
  }

  Stream<List<Map<String, dynamic>>> allCleanerVerificationsStream() {
    if (_isDebugAdmin) {
      return _debugSharedCleanerVerificationsStream();
    }
    return _backendPollingStream(
      () async => (await BackendApiService.instance.getList('/admin/cleaners'))
          .map((row) => {
                ...mapAdminCleaner(row),
                'status': row['verification_status'] ?? 'pending'
              })
          .toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> cleanerOrdersStream() {
    if (_isDebugCleaner) {
      return _debugSharedCleanerOrdersStream();
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryCleanerOrders);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
            () => BackendApiService.instance.getList('/cleaner/orders'),
            interval: const Duration(seconds: 2))
        .asyncMap(_enrichCleanerAssignments);
  }

  Stream<List<Map<String, dynamic>>> cleanerOrderOffersStream() {
    if (_isDebugCleaner) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
            () => BackendApiService.instance.getList('/cleaner/offers'),
            interval: const Duration(seconds: 2))
        .asyncMap(_enrichCleanerOffers);
  }

  Stream<List<Map<String, dynamic>>> cleanerShiftsStream() {
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(() {
        final slots = _temporaryCleanerScheduleSlots();
        return slots.map((slot) {
          final scheduledFor = slot['scheduledFor'] ?? slot['date'];
          return <String, dynamic>{
            'id': (slot['id'] ??
                    slot['sourceOrderId'] ??
                    slot['customerOrderId'] ??
                    '')
                .toString(),
            'cleanerId':
                _uidOrNull ?? AuthService.temporarySessionUid ?? 'temp_cleaner',
            'date': scheduledFor,
            'scheduledFor': scheduledFor,
            'time': (slot['time'] ?? '').toString(),
            'status': (slot['status'] ?? 'assigned').toString(),
            'clusterName': slot['clusterName'] ?? slot['residentialComplex'],
            'address': slot['address'],
            'createdAt': slot['createdAt'] ?? Timestamp.now(),
          };
        }).toList();
      });
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return cleanerScheduleSlotsStream();
  }

  Stream<List<Map<String, dynamic>>> cleanerScheduleSlotsStream() {
    if (_isDebugCleaner) {
      return _debugSharedCleanerSlotsStream();
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryCleanerScheduleSlots);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(
            () => BackendApiService.instance.getList('/cleaner/orders'),
            interval: const Duration(seconds: 2))
        .asyncMap(_enrichCleanerAssignments);
  }

  Future<List<Map<String, dynamic>>> _enrichCleanerAssignments(
    List<Map<String, dynamic>> items,
  ) async {
    return items.map((item) {
      final merged = mapCleanerWorkItem(item);
      final address = (merged['address'] ?? '').toString().trim();
      final residentialComplex =
          (merged['residentialComplex'] ?? '').toString().trim();
      merged['address'] = address.isNotEmpty
          ? address
          : (residentialComplex.isNotEmpty
              ? residentialComplex
              : 'Адрес будет уточнен');
      merged['addons'] = merged['addons'] is List ? merged['addons'] : const [];
      merged['addonsDetailed'] = merged['addonsDetailed'] is List
          ? merged['addonsDetailed']
          : const [];
      merged['addonCount'] =
          merged['addonCount'] ?? ((merged['addonsDetailed'] as List).length);
      merged['addonTotalPrice'] = merged['addonTotalPrice'] ?? 0;
      merged['addonsSeparatePaymentTotal'] =
          merged['addonsSeparatePaymentTotal'] ?? 0;
      merged['separatePaymentAddons'] = merged['separatePaymentAddons'] is List
          ? merged['separatePaymentAddons']
          : const [];
      if ((merged['client'] ?? '').toString().trim().isEmpty &&
          (merged['customerName'] ?? '').toString().trim().isNotEmpty) {
        merged['client'] = merged['customerName'];
      }
      return merged;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _enrichCleanerOffers(
    List<Map<String, dynamic>> items,
  ) async {
    final now = DateTime.now();
    final result = items.map((item) {
      final normalized = mapCleanerWorkItem(item, offer: true);
      final expiresAt = _toDateTime(normalized['expiresAt']);
      final remainingSeconds =
          expiresAt.difference(now).inSeconds.clamp(0, 365 * 24 * 3600);
      Object? listValue(Object? value) => value is List ? value : const [];
      return <String, dynamic>{
        ...normalized,
        'address':
            normalized['address'] ?? normalized['residentialComplex'] ?? '',
        'residentialComplex': normalized['residentialComplex'],
        'package': normalized['package'],
        'addons': listValue(normalized['addons']),
        'addonsDetailed': listValue(normalized['addonsDetailed']),
        'separatePaymentAddons': listValue(normalized['separatePaymentAddons']),
        'area': normalized['area'] ?? normalized['areaSqm'] ?? 0,
        'price': normalized['price'] ?? 0,
        'estimatedDurationMinutes': normalized['totalDurationMinutes'] ??
            normalized['estimatedDurationMinutes'],
        'travelMinutes': normalized['travelMinutes'] ?? 0,
        'remainingSeconds': remainingSeconds,
      };
    }).toList()
      ..sort(
        (a, b) => _toDateTime(
          a['expiresAt'],
        ).compareTo(_toDateTime(b['expiresAt'])),
      );
    return result;
  }

  Stream<List<Map<String, dynamic>>> cleanerPayoutsStream() {
    if (_isDebugCleaner) {
      return _debugSharedCleanerPayoutsStream();
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_temporaryCleanerPayouts);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final items = await BackendApiService.instance.getList('/payouts');
      items.sort((a, b) {
        return _timestampMillis(
          b['created_at'],
        ).compareTo(_timestampMillis(a['created_at']));
      });
      return items
          .map(
            (item) => {
              'id': item['id'],
              'cleanerId': item['cleaner_id'],
              'amount': _num(item['amount']).round(),
              'status': item['status'],
              'payoutType': item['payout_type'],
              'kaspiPhone': item['kaspi_phone'],
              'createdAt': item['created_at'],
              'updatedAt': item['updated_at'],
            },
          )
          .toList();
    });
  }

  Stream<Map<String, dynamic>?> _debugSharedCleanerVerificationStream() {
    return _db
        .collection('debug_bridge_cleaner_verifications')
        .doc(_uidOrNull ?? 'cleaner_demo')
        .snapshots()
        .map((doc) {
      final remote = doc.data();
      final local = _debugCleanerVerification();
      if (remote == null) {
        return local;
      }
      return {...local, ...remote, 'cleanerId': doc.id};
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCleanerVerificationsStream() {
    return _db.collection('debug_bridge_cleaner_verifications').snapshots().map(
      (snap) {
        final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        final merged = <String, Map<String, dynamic>>{
          'cleaner_demo': {
            'id': 'cleaner_demo',
            'cleanerId': 'cleaner_demo',
            ..._debugCleanerVerification(),
          },
        };
        for (final item in remote) {
          final id = (item['cleanerId'] ?? item['id'] ?? '').toString();
          if (id.isEmpty) {
            continue;
          }
          merged[id] = {
            ...merged[id] ?? const <String, dynamic>{},
            ...item,
            'id': id,
            'cleanerId': id,
          };
        }
        final items = merged.values.toList();
        items.sort((a, b) {
          final aMs = _timestampMillis(a['updatedAt'] ?? a['reviewedAt']);
          final bMs = _timestampMillis(b['updatedAt'] ?? b['reviewedAt']);
          return bMs.compareTo(aMs);
        });
        return items;
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCleanerPayoutsStream() {
    return _db.collection('debug_bridge_payouts').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final local = _debugCleanerPayouts();
      final merged = <String, Map<String, dynamic>>{};
      for (final item in [...local, ...remote]) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
        };
      }
      final items = merged.values
          .where(
            (item) =>
                !_isDebugCleaner ||
                (item['cleanerId'] ?? '').toString() ==
                    (_uidOrNull ?? 'cleaner_demo'),
          )
          .toList();
      items.sort((a, b) {
        final aMillis = _timestampMillis(a['createdAt']);
        final bMillis = _timestampMillis(b['createdAt']);
        return bMillis.compareTo(aMillis);
      });
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> clientVideosStream() {
    if (_isDebugCustomer) {
      return _debugSharedVideoContentStream('client');
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_debugClientVideos);
    }
    return Stream.fromFuture(_loadVideosForAudience('client'));
  }

  List<Map<String, dynamic>> fallbackVideosForAudience(String audienceType) {
    return _debugVideosForAudience(audienceType);
  }

  Map<String, dynamic>? fallbackVideoById(String videoId) {
    for (final video in _debugAdminVideoContent()) {
      if (video['id'] == videoId) {
        return video;
      }
    }
    return null;
  }

  Stream<List<Map<String, dynamic>>> cleanerVideosStream() {
    if (_isDebugCleaner) {
      return _debugSharedVideoContentStream('cleaner');
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(_debugCleanerVideos);
    }
    return Stream.fromFuture(_loadVideosForAudience('cleaner'));
  }

  Future<List<Map<String, dynamic>>> _loadVideosForAudience(
    String audienceType,
  ) async {
    return BackendApiService.instance.getList('/training/videos',
        query: {'audience': audienceType}, authenticated: false);
  }

  bool _isClientAudience(Map<String, dynamic> item) {
    final normalized = _normalizeVideoAudience(item['audienceType']);
    return normalized == 'both' || normalized == 'client';
  }

  bool _isCleanerAudience(Map<String, dynamic> item) {
    final normalized = _normalizeVideoAudience(item['audienceType']);
    return normalized == 'both' || normalized == 'cleaner';
  }

  String _normalizeVideoAudience(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case '':
      case 'all':
      case 'both':
      case 'обе роли':
      case 'все':
        return 'both';
      case 'client':
      case 'clients':
      case 'customer':
      case 'customers':
      case 'клиент':
      case 'клиенты':
        return 'client';
      case 'cleaner':
      case 'cleaners':
      case 'уборщица':
      case 'уборщицы':
        return 'cleaner';
      default:
        return value;
    }
  }

  Stream<List<Map<String, dynamic>>> userVideoViewsStream() {
    if (_useDebugFixtures) {
      return _debugSnapshotStream(_debugVideoViews);
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(_debugVideoViews);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final items = await BackendApiService.instance.getList(
        '/training/video-views',
      );
      return items
          .map(
            (item) => {
              'id': item['video_id'],
              'videoId': item['video_id'],
              'audienceType': item['audience_type'],
              'completed': item['completed'] == true,
              'lastProgressSeconds': _num(
                item['last_progress_seconds'],
              ).toInt(),
              'viewedAt': item['viewed_at'],
              'updatedAt': item['updated_at'],
            },
          )
          .toList();
    });
  }

  Stream<Map<String, dynamic>?> videoStream(String videoId) {
    if (_useDebugFixtures) {
      return _debugSharedVideoByIdStream(videoId);
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(() => fallbackVideoById(videoId));
    }
    return Stream.fromFuture(_loadVideoById(videoId));
  }

  Future<Map<String, dynamic>?> _loadVideoById(String videoId) async {
    return BackendApiService.instance
        .getMap('/training/videos/$videoId', authenticated: false);
  }

  List<Map<String, dynamic>> _debugVideosForAudience(String audienceType) {
    final items = _debugAdminVideoContent()
        .where(
          (item) =>
              item['isActive'] != false &&
              (audienceType == 'cleaner'
                  ? _isCleanerAudience(item)
                  : _isClientAudience(item)),
        )
        .toList();
    items.sort((a, b) => _sortByPublishedAtDesc(a, b));
    return items;
  }

  Stream<List<Map<String, dynamic>>> _debugSharedVideoContentStream(
    String audienceType,
  ) {
    return _db.collection('debug_bridge_video_content').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = _mergeDebugVideoContent(remote);
      final filtered = merged
          .where(
            (item) =>
                item['isActive'] != false &&
                (audienceType == 'cleaner'
                    ? _isCleanerAudience(item)
                    : _isClientAudience(item)),
          )
          .toList();
      filtered.sort((a, b) => _sortByPublishedAtDesc(a, b));
      return filtered;
    });
  }

  Stream<Map<String, dynamic>?> _debugSharedVideoByIdStream(String videoId) {
    return _db.collection('debug_bridge_video_content').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = _mergeDebugVideoContent(remote);
      for (final video in merged) {
        if ((video['id'] ?? '').toString() == videoId) {
          return video;
        }
      }
      return null;
    });
  }

  List<Map<String, dynamic>> _mergeDebugVideoContent(
    List<Map<String, dynamic>> remote,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final video in [
      ..._debugClientVideos(),
      ..._debugCleanerVideos(),
      ...remote,
    ]) {
      final id = (video['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...video,
        'id': id,
      };
    }
    return merged.values.toList();
  }

  Stream<List<Map<String, dynamic>>> cleanerStatusHistoryStream() {
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(() {
        final profile = _temporaryCleanerProfile();
        final status = (profile['verificationStatus'] ??
                profile['status'] ??
                profile['cleanerStatus'] ??
                'pending')
            .toString();
        return <Map<String, dynamic>>[
          {
            'id': 'temp_cleaner_status_${_uidOrNull ?? 'cleaner'}',
            'cleanerId':
                _uidOrNull ?? AuthService.temporarySessionUid ?? 'temp_cleaner',
            'status': status,
            'title': 'Временная сессия',
            'description':
                'История статуса формируется локально до подключения live backend.',
            'createdAt': Timestamp.now(),
          },
        ];
      });
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final profile = await BackendApiService.instance.getMap(
        '/cleaner/profile',
      );
      return [
        {
          'id': 'cleaner_status_${profile['id'] ?? uid}',
          'cleanerId': profile['id'] ?? uid,
          'status': profile['verification_status'] ??
              profile['registration_status'] ??
              profile['status'],
          'title': 'Статус профиля',
          'description': 'Статус уборщицы синхронизирован с сервером.',
          'createdAt': profile['updated_at'] ?? profile['created_at'],
        },
      ];
    });
  }

  Stream<Map<String, dynamic>?> pricingStream() {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return Stream.value(const <String, dynamic>{
        'id': 'default',
        'currency': 'KZT',
        'minArea': 40,
        'baseHourlyRate': 1800,
        'standardCleaningPerSqm': 65,
        'deepCleaningPerSqm': 90,
      });
    }
    return _backendPollingStream(() async {
      final bootstrap = await BackendApiService.instance.getMap(
        '/app/bootstrap',
        authenticated: false,
      );
      final settings =
          Map<String, dynamic>.from((bootstrap['settings'] as Map?) ?? {});
      return {
        'id': 'default',
        'currency': 'KZT',
        'minArea': settings['minArea'] ?? 0,
        'baseHourlyRate': settings['baseHourlyRate'] ?? 0,
        'standardCleaningPerSqm': settings['minutesPerM2'],
        'deepCleaningPerSqm': settings['deepCleaningPerSqm'],
        ...settings,
      };
    });
  }

  Stream<Map<String, dynamic>?> customerSettingsStream() {
    if (_isDebugCustomer) {
      return _debugSnapshotStream(_debugCustomerSettings);
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerSettings);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(null);
    }
    return _backendPollingStream(() async {
      try {
        final settings = await BackendApiService.instance.getMap(
          '/me/settings',
        );
        return {..._defaultCustomerSettings(), ...settings};
      } catch (_) {
        return _defaultCustomerSettings();
      }
    });
  }

  Stream<List<Map<String, dynamic>>> userNotificationsStream() {
    if (_useDebugFixtures) {
      return _debugSnapshotStream(_debugNotifications);
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return _debugSnapshotStream(_debugNotifications);
    }
    final recipientId = _uidOrNull;
    if (recipientId == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final items = (await BackendApiService.instance.getList(
        '/notifications',
      ))
          .map(_mapBackendNotification)
          .toList();
      if (_uidOrNull != recipientId) return <Map<String, dynamic>>[];
      items.removeWhere((item) =>
          item['userId'] != null && item['userId'].toString() != recipientId);
      items.sort((a, b) {
        final aRead = a['read'] == true;
        final bRead = b['read'] == true;
        if (aRead != bRead) return aRead ? 1 : -1;
        return _timestampMillis(
          b['createdAt'],
        ).compareTo(_timestampMillis(a['createdAt']));
      });
      return items;
    }, interval: const Duration(seconds: 2));
  }

  Stream<List<Map<String, dynamic>>> customerBonusTransactionsStream() {
    if (_uidOrNull == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final items = (await BackendApiService.instance.getList(
        '/bonus/history',
      ))
          .map(_mapBackendBonusTransaction)
          .toList();
      items.sort(
        (a, b) => _timestampMillis(
          b['createdAt'],
        ).compareTo(_timestampMillis(a['createdAt'])),
      );
      return items;
    });
  }

  Future<void> _recordCustomerBonusTransaction({
    required String userId,
    required int amount,
    required String title,
    required String reason,
    String type = 'bonus_credit',
    String? orderId,
  }) async {
    if (userId.trim().isEmpty || amount == 0) {
      return;
    }
    await BackendApiService.instance.postMap(
      '/bonus/transactions',
      body: {
        'userId': userId,
        'amount': amount,
        'title': title,
        'reasonRu': reason,
        'type': type,
        if (orderId != null && orderId.trim().isNotEmpty) 'orderId': orderId,
      },
    );
  }

  Future<void> _createUserNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    if (userId.trim().isEmpty) {
      return;
    }
    await BackendApiService.instance.postMap(
      '/notifications',
      body: {
        'userId': userId,
        'type': type,
        'titleRu': title,
        'bodyRu': body,
        'targetType': type,
        'payload': payload,
      },
    );
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (_useDebugFixtures ||
        _isTemporaryCustomerSession ||
        _isTemporaryCleanerSession) {
      final notifications = _debugNotifications()
          .map(
            (item) => (item['id'] ?? '').toString() == notificationId
                ? {...item, 'read': true, 'readAt': Timestamp.now()}
                : item,
          )
          .toList();
      _debugNotificationsState = notifications;
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/notifications/$notificationId/read',
    );
  }

  Future<void> markAllNotificationsRead() async {
    if (_useDebugFixtures ||
        _isTemporaryCustomerSession ||
        _isTemporaryCleanerSession) {
      final notifications = _debugNotifications()
          .map(
            (item) => {
              ...item,
              'read': true,
              'readAt': item['readAt'] ?? Timestamp.now(),
            },
          )
          .toList();
      _debugNotificationsState = notifications;
      _notifyDebugStateChanged();
      return;
    }
    if (_uidOrNull == null) {
      return;
    }
    await BackendApiService.instance.postMap('/notifications/read-all');
  }

  Stream<Map<String, dynamic>?> customPackageDraftStream() {
    if (_isDebugCustomer || _isTemporaryCustomerSession) {
      return _debugSnapshotStream(() {
        final raw = debugStorageRead(_debugStorageKey('custom_package_draft'));
        if (raw == null || raw.trim().isEmpty) {
          return null;
        }
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
        return null;
      });
    }
    return _debugSnapshotStream(() {
      final raw = debugStorageRead(_debugStorageKey('custom_package_draft'));
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return null;
    });
  }

  Stream<Map<String, dynamic>?> referralStatsStream() {
    if (_isDebugCustomer) {
      return _debugSnapshotStream(_debugReferralStats);
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(_temporaryCustomerReferralStats);
    }
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(null);
    }
    return Stream.fromFuture(getReferralStats(userId: uid));
  }

  Future<void> updateCustomerSettings(Map<String, dynamic> data) async {
    if (_isDebugCustomer) {
      final updated = {..._debugCustomerSettings(), ...data};
      debugStorageWrite(
        _debugStorageKey('customer_settings'),
        jsonEncode(_jsonSafe(updated)),
      );
      _notifyDebugStateChanged();
      return;
    }
    if (_isTemporaryCustomerSession) {
      final updated = {..._temporaryCustomerSettings(), ...data};
      debugStorageWrite(
        _debugStorageKey('customer_settings'),
        jsonEncode(_jsonSafe(updated)),
      );
      if (!_debugStateChanges.isClosed) {
        _debugStateChanges.add(null);
      }
      return;
    }
    await BackendApiService.instance.patchMap('/me/settings', body: data);
  }

  Future<void> updateCustomerProfile(Map<String, dynamic> data) async {
    final normalizedData = <String, dynamic>{...data};
    final rawHouseStatus = normalizedData['houseStatus']?.toString().trim();
    if (rawHouseStatus != null && rawHouseStatus.isNotEmpty) {
      normalizedData['houseStatus'] = rawHouseStatus.toUpperCase();
    }
    if (normalizedData['addresses'] is List) {
      normalizedData['addresses'] = (normalizedData['addresses'] as List).map((
        item,
      ) {
        if (item is! Map) {
          return item;
        }
        final next = Map<String, dynamic>.from(item);
        final addressHouseStatus = next['houseStatus']?.toString().trim();
        if (addressHouseStatus != null && addressHouseStatus.isNotEmpty) {
          next['houseStatus'] = addressHouseStatus.toUpperCase();
        }
        return next;
      }).toList();
    }
    if (_isDebugCustomer) {
      final merged = <String, dynamic>{
        ..._debugCustomerProfile(),
        ...normalizedData,
      };
      _debugCustomerProfileState = merged;
      try {
        await _db
            .collection('debug_bridge_customer_profiles')
            .doc(_uidOrNull ?? 'customer_demo')
            .set({
          ...normalizedData,
          'updatedAt': Timestamp.now(),
          'sourceDebugUid': _uidOrNull ?? 'customer_demo',
        }, SetOptions(merge: true));
      } catch (_) {}
      _notifyDebugStateChanged();
      return;
    }
    if (_isTemporaryCustomerSession) {
      final merged = <String, dynamic>{
        ..._temporaryCustomerProfile(),
        ...normalizedData,
      };
      _debugCustomerProfileState = merged;
      debugStorageWrite(
        _debugStorageKey('customer_profile'),
        jsonEncode(_jsonSafe(merged)),
      );
      if (!_debugStateChanges.isClosed) {
        _debugStateChanges.add(null);
      }
      return;
    }
    await _updateCustomerProfileBackend(normalizedData);
  }

  Future<void> _updateCustomerProfileBackend(Map<String, dynamic> data) async {
    final fullName =
        (data['fullName'] ?? data['name'] ?? data['fio'] ?? '').toString();
    await BackendApiService.instance.patchMap(
      '/me',
      body: {
        if (fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
        if (data['email'] != null) 'email': data['email'],
        if (data['language'] != null) 'language': data['language'],
      },
    );

    final rawAddresses = data['addresses'];
    final address = rawAddresses is List && rawAddresses.isNotEmpty
        ? Map<String, dynamic>.from(rawAddresses.first as Map)
        : data;
    final streetLine = (address['street'] ??
            address['address'] ??
            address['addressLine'] ??
            '')
        .toString()
        .trim();
    final parsedHouse = RegExp(
      r'(\d+[А-Яа-яA-Za-z/-]*)\s*$',
    ).firstMatch(streetLine)?.group(1);
    final parsedStreet = parsedHouse == null
        ? streetLine
        : streetLine
            .substring(0, streetLine.length - parsedHouse.length)
            .trim();
    final hasAddress = streetLine.isNotEmpty ||
        address['city'] != null ||
        address['area'] != null ||
        data['area'] != null;
    if (!hasAddress) return;

    final existing = await BackendApiService.instance.getList('/addresses');
    final primary = existing.isEmpty ? null : existing.first;
    final payload = <String, dynamic>{
      'city': address['city'] ?? data['city'] ?? 'Астана',
      'settlement': address['settlement'],
      'street': address['street'] ?? parsedStreet,
      'house': address['house'] ?? parsedHouse,
      'apartment': address['apartment'] ?? data['apartment'],
      'entrance': address['entrance'] ?? data['entrance'],
      'floor': address['floor'] ?? data['floor'],
      'intercom': address['intercom'] ?? data['intercom'],
      'accessComment': address['accessComment'] ?? data['accessComment'],
      'area': address['area'] ?? data['area'] ?? data['apartmentArea'],
      'latitude': address['latitude'] ?? data['latitude'],
      'longitude': address['longitude'] ?? data['longitude'],
    }..removeWhere((_, value) => value == null || value.toString().isEmpty);

    if (payload['street'] == null || payload['house'] == null) {
      throw FlutterError('Укажите улицу и номер дома.');
    }

    if (primary == null) {
      await BackendApiService.instance.postMap('/addresses', body: payload);
    } else {
      await BackendApiService.instance.patchMap(
        '/addresses/${primary['id']}',
        body: payload,
      );
    }
  }

  bool _canFallbackCustomerProfileUpdate(String code) {
    return code == 'unavailable' ||
        code == 'deadline-exceeded' ||
        code == 'internal' ||
        code == 'unknown' ||
        code == 'unimplemented';
  }

  Future<void> _updateCustomerProfileDirect(Map<String, dynamic> data) async {
    await _updateCustomerProfileBackend(data);
  }

  Future<void> updateSubscription(
    String subscriptionId,
    Map<String, dynamic> data,
  ) async {
    if (_isDebugCustomer || _isTemporaryCustomerSession) {
      final items = _isTemporaryCustomerSession
          ? _temporaryCustomerSubscriptions()
          : _debugCustomerSubscriptions();
      final index = items.indexWhere(
        (item) => (item['id'] ?? '').toString() == subscriptionId,
      );
      final current =
          index == -1 ? <String, dynamic>{'id': subscriptionId} : items[index];
      final updated = <String, dynamic>{
        ...current,
        ...data,
        'id': subscriptionId,
        'updatedAt': data['updatedAt'] ?? Timestamp.now(),
      };
      if (index == -1) {
        items.insert(0, updated);
      } else {
        items[index] = updated;
      }
      _debugCustomerSubscriptionsState =
          items.map((item) => Map<String, dynamic>.from(item)).toList();
      debugStorageWrite(
        _debugStorageKey('customer_subscriptions'),
        jsonEncode(_jsonSafe(_debugCustomerSubscriptionsState)),
      );
      if (_isDebugCustomer) {
        try {
          await _db
              .collection('debug_bridge_customer_subscriptions')
              .doc(subscriptionId)
              .set({
            ...data,
            'id': subscriptionId,
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
            'updatedAt': Timestamp.now(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.patchMap(
      '/packages/my/$subscriptionId',
      body: data,
    );
  }

  Future<void> updateCleanerProfile(Map<String, dynamic> data) async {
    if (_isDebugCleaner) {
      final normalizedVerificationStatus =
          data['verificationStatus']?.toString().trim();
      if (normalizedVerificationStatus != null &&
          normalizedVerificationStatus.isNotEmpty) {
        data = {
          ...data,
          'verificationStatus': normalizedVerificationStatus.toLowerCase(),
        };
      }
      try {
        await _db
            .collection('debug_bridge_cleaners')
            .doc(_uidOrNull ?? 'cleaner_demo')
            .set({
          ...data,
          'updatedAt': Timestamp.now(),
          'sourceDebugUid': _uidOrNull ?? 'cleaner_demo',
        }, SetOptions(merge: true));
      } catch (_) {}
      _notifyDebugStateChanged();
      return;
    }
    if (_isTemporaryCleanerSession) {
      final normalizedVerificationStatus =
          data['verificationStatus']?.toString().trim();
      if (normalizedVerificationStatus != null &&
          normalizedVerificationStatus.isNotEmpty) {
        data = {
          ...data,
          'verificationStatus': normalizedVerificationStatus.toLowerCase(),
        };
      }
      final merged = <String, dynamic>{..._temporaryCleanerProfile(), ...data};
      debugStorageWrite(
        _debugStorageKey('cleaner_profile'),
        jsonEncode(_jsonSafe(merged)),
      );
      if (!_debugStateChanges.isClosed) {
        _debugStateChanges.add(null);
      }
      return;
    }
    await BackendApiService.instance.patchMap(
      '/cleaner/profile',
      body: {
        if (data['name'] != null) 'fullName': data['name'],
        if (data['fullName'] != null) 'fullName': data['fullName'],
        if (data['email'] != null) 'email': data['email'],
        if (data['city'] != null) 'city': data['city'],
        if (data['monthlyAreaLimit'] != null)
          'monthlyAreaLimit': data['monthlyAreaLimit'],
        if (data['dailyWorkLimitMinutes'] != null)
          'dailyWorkLimitMinutes': data['dailyWorkLimitMinutes'],
        if (data['soundEnabled'] != null) 'soundEnabled': data['soundEnabled'],
        if (data['soundVolume'] != null) 'soundVolume': data['soundVolume'],
        if (data['soundKey'] != null) 'soundKey': data['soundKey'],
        if (data['serviceAreaIds'] != null) 'zoneIds': data['serviceAreaIds'],
      },
    );
  }

  Future<void> _updateCleanerProfileDirect(Map<String, dynamic> data) async {
    await updateCleanerProfile(data);
  }

  Future<void> createSubscriptionRequest({
    required int price,
    required int rooms,
    required int bathrooms,
    required int area,
    required int frequency,
    int billingPeriodMonths = 1,
    required bool windows,
    required bool ironing,
    required bool balcony,
  }) async {
    if (_isTemporaryCustomerSession) {
      final requests =
          _loadDebugList('order_requests') ?? <Map<String, dynamic>>[];
      requests.insert(0, {
        'id': 'temp_order_request_${DateTime.now().millisecondsSinceEpoch}',
        'customerId': _uidOrNull ?? 'temp_customer',
        'status': 'created',
        'date': DateTime.now().toIso8601String(),
        'price': price,
        'package': 'Индивидуальный',
        'orderStatus': 'pending_payment',
        'paymentStatus': 'initiated',
        'currency': 'KZT',
        'localFallback': true,
        'form': {
          'rooms': rooms,
          'bathrooms': bathrooms,
          'area': area,
          'frequency': frequency,
          'billingPeriodMonths': billingPeriodMonths,
          'windows': windows,
          'ironing': ironing,
          'balcony': balcony,
        },
      });
      debugStorageWrite(
        _debugStorageKey('order_requests'),
        jsonEncode(_jsonSafe(requests)),
      );
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/order-requests',
      body: {
        'price': price,
        'package': 'Индивидуальный',
        'currency': 'KZT',
        'area': area,
        'form': {
          'rooms': rooms,
          'bathrooms': bathrooms,
          'area': area,
          'frequency': frequency,
          'billingPeriodMonths': billingPeriodMonths,
          'windows': windows,
          'ironing': ironing,
          'balcony': balcony,
        },
      },
    );
  }

  Future<void> createPrelaunchBookingRequest({
    required String name,
    required String phone,
    required int area,
    required DateTime desiredDate,
    required String preferredTime,
  }) async {
    final normalizedName = name.trim();
    final normalizedPhone = phone.trim();
    final normalizedTime = preferredTime.trim();
    final desiredDateText = _dateOnlyText(desiredDate);

    final payload = <String, dynamic>{
      'customerId': _uidOrNull ?? 'anonymous',
      'type': 'prelaunch_prebooking',
      'source': 'prelaunch_button',
      'status': 'prelaunch_waiting',
      'orderStatus': 'prelaunch_waiting',
      'paymentStatus': 'not_required_until_launch',
      'price': 0,
      'currency': 'KZT',
      'package': 'Предварительная запись',
      'customerName': normalizedName,
      'customerPhone': normalizedPhone,
      'area': area,
      'desiredDate': desiredDateText,
      'preferredTime': normalizedTime,
      'launchDate': _isTemporaryCustomerSession
          ? desiredDateText
          : Timestamp.fromDate(
              DateTime(desiredDate.year, desiredDate.month, desiredDate.day),
            ),
      'form': {
        'name': normalizedName,
        'phone': normalizedPhone,
        'area': area,
        'desiredDate': desiredDateText,
        'preferredTime': normalizedTime,
      },
    };

    if (_isTemporaryCustomerSession) {
      final requests =
          _loadDebugList('order_requests') ?? <Map<String, dynamic>>[];
      requests.insert(0, {
        'id': 'temp_prebooking_${DateTime.now().millisecondsSinceEpoch}',
        ...payload,
        'createdAt': DateTime.now().toIso8601String(),
        'date': DateTime.now().toIso8601String(),
        'localFallback': true,
      });
      debugStorageWrite(
        _debugStorageKey('order_requests'),
        jsonEncode(_jsonSafe(requests)),
      );
      _notifyDebugStateChanged();
      return;
    }

    await BackendApiService.instance.postMap(
      '/preorders',
      body: {
        'desiredDate': desiredDateText,
        'desiredTime': normalizedTime,
        'area': area,
        'customerName': normalizedName,
        'customerPhone': normalizedPhone,
      },
    );
  }

  Future<int> startPrelaunchBookings({
    required DateTime startDate,
    required String startTime,
  }) async {
    final normalizedTime = startTime.trim();
    if (normalizedTime.isEmpty) {
      throw FlutterError('Укажите время старта.');
    }
    final startDateText = _dateOnlyText(startDate);

    final result = await BackendApiService.instance.postMap(
      '/admin/preorders/start',
      body: {'startDate': startDateText, 'startTime': normalizedTime},
    );
    return (result['notified'] as num?)?.toInt() ?? 0;
  }

  String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _dateOnlyText(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  Map<String, dynamic> _debugCustomerProfile() {
    _debugCustomerProfileState ??= (() {
      final raw = debugStorageRead(_debugStorageKey('customer_profile'));
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
      return <String, dynamic>{
        'name': 'Асет',
        'phone': '+7 708 636 21 53',
        'planName': '4 раза в месяц',
        'planPrice': 25000,
        'nextPaymentDate': '30.04.2026',
        'cleaningsCount': 12,
        'nextCleaningIn': '2 дня',
        'ordersCount': 12,
        'monthsWithUs': 3,
        'rating': 4.9,
        'bonusPoints': 7200,
        'tier': 'GOLD',
        'next_tier_threshold': 120000,
        'monthly_spent': 89000,
        'remaining_amount': 31000,
        'tier_progress': 0.74,
        'tier_discount_percent': 10,
        'houseId': 'emerald_1',
        'houseStatus': 'IN_PROGRESS',
        'referralCode': 'ASET2026',
        'referralQualifiedCount': 3,
        'referralDiscountPercent': 6,
        'menu': [
          {'title': 'Мой адрес', 'subtitle': 'ЖК Триумф, кв. 45'},
          {
            'title': 'Оплата',
            'subtitle': 'Счёт выставляется менеджером через KASPI.KZ',
          },
          {'title': 'Любимые уборщицы', 'subtitle': '3 человека'},
        ],
      };
    })();
    return _debugCustomerProfileState!;
  }

  String? _temporarySessionPhone(String prefix) {
    final uid = AuthService.temporarySessionUid;
    if (uid == null || !uid.startsWith(prefix)) {
      return null;
    }
    final phone = uid.substring(prefix.length).trim();
    return phone.isEmpty ? null : phone;
  }

  Map<String, dynamic> _temporaryCustomerProfile() {
    if (_debugCustomerProfileState != null) {
      return Map<String, dynamic>.from(_debugCustomerProfileState!);
    }
    final persisted = _loadDebugMap('customer_profile');
    if (persisted != null) {
      _debugCustomerProfileState = Map<String, dynamic>.from(persisted);
      return Map<String, dynamic>.from(_debugCustomerProfileState!);
    }
    final phone = _temporarySessionPhone('temp_customer_') ?? '';
    final profile = <String, dynamic>{
      'uid': _uidOrNull,
      'name': 'Пользователь',
      'phone': phone.isEmpty ? '' : '+$phone',
      'bonusPoints': 0,
      'tier': 'NEWBIE',
      'referralQualifiedCount': 0,
      'referralDiscountPercent': 0,
      'ordersCount': _temporaryCustomerOrders().length,
      'cleaningsCount': 0,
      'houseStatus': 'INACTIVE',
      'addresses': const <Map<String, dynamic>>[],
      'tempAuth': true,
      'authMode': 'local_otp_fallback',
    };
    _debugCustomerProfileState = profile;
    return Map<String, dynamic>.from(profile);
  }

  Map<String, dynamic> _temporaryCleanerProfile() {
    final persisted = _loadDebugMap('cleaner_profile');
    final phone = _temporarySessionPhone('temp_cleaner_') ?? '';
    final base = <String, dynamic>{
      'uid': _uidOrNull,
      'fullName': 'Уборщица',
      'phone': phone.isEmpty ? '' : '+$phone',
      'verificationStatus': 'pending',
      'status': 'active',
      'rating': 0,
      'jobsCount': 0,
      'todayEarnings': 0,
      'walletBalance': 0,
      'tempAuth': true,
      'authMode': 'local_otp_fallback',
    };
    final computed = _buildDebugCleanerProfile(
      slotsOverride: _temporaryCleanerScheduleSlots(),
      ordersOverride: _temporaryCleanerOrders(),
      payoutsOverride: _temporaryCleanerPayouts(),
    );
    return <String, dynamic>{
      ...base,
      ...persisted ?? const <String, dynamic>{},
      ...computed,
      'uid': _uidOrNull,
      'phone': (persisted?['phone'] ?? base['phone'] ?? '').toString(),
      'verificationStatus': ((persisted?['verificationStatus'] ??
                  _temporaryCleanerVerification()['status'] ??
                  'pending'))
              .toString()
              .trim()
              .toLowerCase()
              .isEmpty
          ? 'pending'
          : ((persisted?['verificationStatus'] ??
                  _temporaryCleanerVerification()['status'] ??
                  'pending'))
              .toString()
              .trim()
              .toLowerCase(),
      'tempAuth': true,
      'authMode': 'local_otp_fallback',
    };
  }

  Map<String, dynamic> _fallbackCleanerProfile(String uid) {
    final computed = _buildDebugCleanerProfile(
      slotsOverride: _temporaryCleanerScheduleSlots(),
      ordersOverride: _temporaryCleanerOrders(),
      payoutsOverride: _temporaryCleanerPayouts(),
    );
    final resolvedName =
        (computed['name'] ?? computed['fullName'] ?? 'Исполнитель').toString();
    final resolvedFullName =
        (computed['fullName'] ?? computed['name'] ?? 'Исполнитель').toString();
    return <String, dynamic>{
      'uid': uid,
      'name': resolvedName,
      'fullName': resolvedFullName,
      'phone': '',
      'status': 'active',
      'verificationStatus': 'pending',
      'rating': 0,
      'jobsCount': 0,
      'todayEarnings': 0,
      'walletBalance': 0,
      'currentWalletBalance': 0,
      'availableWithdrawalAmount': 0,
      'totalWithdrawn': 0,
      'monthlyEarnings': '0 ₸',
      ...computed,
    };
  }

  Map<String, dynamic> _temporaryCustomerReferralStats() {
    final profile = _temporaryCustomerProfile();
    final bonus = (profile['bonusPoints'] as num?)?.toInt() ?? 0;
    final qualified = (profile['referralQualifiedCount'] as num?)?.toInt() ?? 0;
    final discount = (profile['referralDiscountPercent'] as num?)?.toInt() ?? 0;
    return <String, dynamic>{
      'bonus': bonus,
      'paid': qualified,
      'registered': qualified,
      'invited': qualified,
      'monthlyActivated': qualified,
      'referralDiscountPercent': discount,
      'nextReferralDiscountThreshold': 5,
      'nextReferralDiscountPercent': discount >= 10 ? discount : 10,
      'remainingForNextDiscount': math.max(0, 5 - qualified),
    };
  }

  Map<String, dynamic> _temporaryCustomerSettings() {
    return _loadDebugMap('customer_settings') ?? _defaultCustomerSettings();
  }

  List<Map<String, dynamic>> _temporaryCustomerSubscriptions() {
    if (_debugCustomerSubscriptionsState != null) {
      return List<Map<String, dynamic>>.from(_debugCustomerSubscriptionsState!);
    }
    final persisted = _loadDebugList('customer_subscriptions');
    if (persisted != null) {
      _debugCustomerSubscriptionsState = List<Map<String, dynamic>>.from(
        persisted,
      );
      return List<Map<String, dynamic>>.from(_debugCustomerSubscriptionsState!);
    }
    final profile = _temporaryCustomerProfile();
    final planName = (profile['planName'] ?? '').toString().trim();
    if (planName.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final includedVisits = (profile['includedVisits'] as num?)?.toInt() ??
        (profile['cleaningsCount'] as num?)?.toInt() ??
        4;
    final usedVisits = (profile['usedVisits'] as num?)?.toInt() ??
        math.max(0, includedVisits - 1);
    final scheduledVisits = (profile['scheduledVisits'] as num?)?.toInt() ?? 0;
    final items = <Map<String, dynamic>>[
      {
        'id':
            (profile['subscriptionId'] ?? 'temp_subscription_main').toString(),
        'status': 'active',
        'package': planName,
        'frequencyLabel': planName,
        'price': (profile['planPrice'] as num?)?.toInt() ?? 0,
        'nextPaymentDate': (profile['nextPaymentDate'] ?? '').toString(),
        'billingPeriodMonths': 1,
        'cleaningsPerMonth': includedVisits,
        'includedVisits': includedVisits,
        'usedVisits': usedVisits,
        'scheduledVisits': scheduledVisits,
        'remainingCleanings': math.max(
          0,
          includedVisits - usedVisits - scheduledVisits,
        ),
        'area': (profile['area'] as num?)?.toInt() ?? 100,
        'scheduleSelectionRequired':
            (profile['scheduleSelectionRequired'] ?? false) == true,
        'updatedAt': profile['updatedAt'] ?? Timestamp.now(),
      },
    ];
    _debugCustomerSubscriptionsState = items;
    return List<Map<String, dynamic>>.from(items);
  }

  List<Map<String, dynamic>> _temporaryCustomerScheduleSlots() {
    if (_debugCustomerScheduleSlotsState != null) {
      return List<Map<String, dynamic>>.from(_debugCustomerScheduleSlotsState!);
    }
    final persisted = _loadDebugList('customer_slots');
    if (persisted != null) {
      _debugCustomerScheduleSlotsState = List<Map<String, dynamic>>.from(
        persisted,
      );
      return List<Map<String, dynamic>>.from(_debugCustomerScheduleSlotsState!);
    }
    _debugCustomerScheduleSlotsState = <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(_debugCustomerScheduleSlotsState!);
  }

  Map<String, dynamic> _temporaryCleanerVerification() {
    return _loadDebugMap('cleaner_verification') ??
        <String, dynamic>{
          'cleanerId': _uidOrNull,
          'status': 'pending',
          'verificationStatus': 'pending',
          'rejectionReason': '',
        };
  }

  List<Map<String, dynamic>> _temporaryCleanerOrders() {
    return _loadDebugList('cleaner_orders') ?? const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _temporaryCleanerScheduleSlots() {
    return _loadDebugList('cleaner_slots') ?? const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _temporaryCleanerPayouts() {
    return _loadDebugList('cleaner_payouts') ?? const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _temporaryHouseWaitlist() {
    return _loadDebugList('house_waitlist') ?? const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _temporaryHouses() {
    final profile = _temporaryCustomerProfile();
    final waitlist = _temporaryHouseWaitlist();
    final housesById = <String, Map<String, dynamic>>{};

    for (final item in waitlist) {
      final houseId = (item['houseId'] ?? '').toString().trim();
      if (houseId.isEmpty) {
        continue;
      }
      final currentUsers = waitlist
          .where((entry) => (entry['houseId'] ?? '').toString() == houseId)
          .length;
      housesById[houseId] = {
        'id': houseId,
        'title': item['residentialComplex'] ?? item['address'] ?? houseId,
        'residentialComplex':
            item['residentialComplex'] ?? item['address'] ?? houseId,
        'address': item['address'] ?? item['residentialComplex'] ?? houseId,
        'status': 'IN_PROGRESS',
        'threshold': 20,
        'current_users': currentUsers,
        'total_users': currentUsers,
        if (item['lat'] != null) 'lat': item['lat'],
        if (item['lng'] != null) 'lng': item['lng'],
      };
    }

    final profileHouseId = (profile['houseId'] ?? '').toString().trim();
    if (profileHouseId.isNotEmpty) {
      housesById[profileHouseId] = {
        'id': profileHouseId,
        'title': profile['residentialComplex'] ??
            profile['address'] ??
            profileHouseId,
        'residentialComplex': profile['residentialComplex'] ??
            profile['address'] ??
            profileHouseId,
        'address': profile['address'] ??
            profile['residentialComplex'] ??
            profileHouseId,
        'status': profile['houseStatus'] ?? 'IN_PROGRESS',
        'threshold': 20,
        'current_users': housesById[profileHouseId]?['current_users'] ?? 1,
        'total_users': housesById[profileHouseId]?['total_users'] ?? 1,
        if (profile['addressLat'] != null) 'lat': profile['addressLat'],
        if (profile['addressLng'] != null) 'lng': profile['addressLng'],
      };
    }

    final items = housesById.values.toList();
    items.sort((a, b) {
      final aText =
          '${a['residentialComplex'] ?? ''} ${a['address'] ?? ''} ${a['title'] ?? ''}'
              .trim();
      final bText =
          '${b['residentialComplex'] ?? ''} ${b['address'] ?? ''} ${b['title'] ?? ''}'
              .trim();
      return aText.compareTo(bText);
    });
    return items;
  }

  Stream<Map<String, dynamic>?> _debugSharedCustomerProfileStream() {
    final customerId = _uidOrNull ?? 'customer_demo';
    return Stream.multi((controller) {
      Map<String, dynamic>? remoteProfile;
      List<Map<String, dynamic>> sharedHouses = const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> sharedSubscriptions =
          _debugCustomerSubscriptions();
      List<Map<String, dynamic>> sharedOrders = _debugCustomerOrders();

      void emit() {
        final local = _debugCustomerProfile();
        final merged = <String, dynamic>{
          ...local,
          ...remoteProfile ?? const {},
        };
        final activeSubscription = sharedSubscriptions
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (item) =>
                  (item?['status'] ?? '').toString().toLowerCase() == 'active',
              orElse: () => null,
            );
        if (activeSubscription != null) {
          merged['planName'] = activeSubscription['frequencyLabel'] ??
              activeSubscription['package'] ??
              merged['planName'];
          merged['planPrice'] =
              activeSubscription['price'] ?? merged['planPrice'];
          merged['nextPaymentDate'] = activeSubscription['nextPaymentDate'] ??
              merged['nextPaymentDate'];
          merged['cleaningsCount'] = activeSubscription['includedVisits'] ??
              activeSubscription['cleaningsPerMonth'] ??
              merged['cleaningsCount'];
        }
        merged['ordersCount'] = sharedOrders.where((item) {
          final status = (item['status'] ?? '').toString().toLowerCase();
          return status != 'cancelled' && status != 'canceled';
        }).length;
        final houseId = (merged['houseId'] ?? '').toString();
        if (houseId.isNotEmpty) {
          final house = sharedHouses.cast<Map<String, dynamic>?>().firstWhere(
                (item) => (item?['id'] ?? '').toString() == houseId,
                orElse: () => null,
              );
          if (house != null) {
            merged['houseStatus'] = house['status'] ??
                house['houseStatus'] ??
                merged['houseStatus'];
            merged['houseTitle'] = house['title'] ?? merged['houseTitle'];
            merged['houseAddress'] = house['address'] ?? merged['houseAddress'];
            merged['houseResidentialComplex'] = house['residentialComplex'] ??
                merged['houseResidentialComplex'];
          }
        }
        _debugCustomerProfileState = merged;
        controller.add(merged);
      }

      final profileSub = _db
          .collection('debug_bridge_customer_profiles')
          .doc(customerId)
          .snapshots()
          .listen((doc) {
        remoteProfile = doc.data();
        emit();
      });
      final housesSub = _debugSharedHousesStream().listen((items) {
        sharedHouses = items;
        emit();
      });
      final subscriptionsSub = _debugSharedCustomerSubscriptionsStream().listen(
        (items) {
          sharedSubscriptions = items;
          emit();
        },
      );
      final ordersSub = _debugSharedOrdersStream().listen((items) {
        sharedOrders = items
            .where(
              (item) =>
                  (item['customerId'] ?? customerId).toString() == customerId,
            )
            .toList();
        emit();
      });

      emit();
      controller.onCancel = () async {
        await profileSub.cancel();
        await housesSub.cancel();
        await subscriptionsSub.cancel();
        await ordersSub.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> _debugAreaMismatchReportsBridgeStream() {
    return _db.collection('debug_bridge_area_reports').snapshots().map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
            ..sort((a, b) {
              final aMs = _timestampMillis(a['createdAt']);
              final bMs = _timestampMillis(b['createdAt']);
              return bMs.compareTo(aMs);
            }),
        );
  }

  List<Map<String, dynamic>> _debugCustomerSubscriptions() {
    return _debugCustomerSubscriptionsState ??=
        _loadDebugList('customer_subscriptions') ??
            [
              {
                'id': 'sub_demo',
                'status': 'active',
                'package': '4 раза в месяц',
                'frequencyLabel': '4 раза в месяц',
                'price': 25000,
                'nextPaymentDate': '30.04.2026',
                'billingPeriodMonths': 1,
                'cleaningsPerMonth': 4,
                'includedVisits': 4,
                'usedVisits': 3,
                'scheduledVisits': 0,
                'remainingCleanings': 1,
                'area': 100,
                'frozenUntil': null,
              },
            ];
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCustomerSubscriptionsStream() {
    final customerId = _uidOrNull ?? 'customer_demo';
    return _db
        .collection('debug_bridge_customer_subscriptions')
        .snapshots()
        .map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = <String, Map<String, dynamic>>{};
      final localItems = _debugCustomerSubscriptions();
      final localIds = localItems
          .map((item) => (item['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      final remoteItems = remote.where((item) {
        final itemCustomerId = (item['customerId'] ?? customerId).toString();
        final id = (item['id'] ?? '').toString();
        return itemCustomerId == customerId || localIds.contains(id);
      });
      for (final item in [...localItems, ...remoteItems]) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
        };
      }
      final items = merged.values.toList();
      items.sort((a, b) {
        final aActive =
            (a['status'] ?? '').toString().toLowerCase() == 'active' ? 1 : 0;
        final bActive =
            (b['status'] ?? '').toString().toLowerCase() == 'active' ? 1 : 0;
        if (aActive != bActive) {
          return bActive.compareTo(aActive);
        }
        final aMs = _timestampMillis(a['createdAt'] ?? a['updatedAt']);
        final bMs = _timestampMillis(b['createdAt'] ?? b['updatedAt']);
        return bMs.compareTo(aMs);
      });
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCustomerOrdersStream() {
    final customerId = _uidOrNull ?? 'customer_demo';
    return _debugSharedOrdersStream().map((items) {
      final localOrderIds = _debugCustomerOrders()
          .map((item) => (item['id'] ?? item['orderId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      return items.where((item) {
        final itemCustomerId = (item['customerId'] ?? customerId).toString();
        final orderId = (item['id'] ?? item['orderId'] ?? '').toString();
        return itemCustomerId == customerId || localOrderIds.contains(orderId);
      }).toList();
    });
  }

  Future<List<Map<String, dynamic>>> _debugMergedCustomerSubscriptions() async {
    final remoteSnap =
        await _db.collection('debug_bridge_customer_subscriptions').get();
    final remote =
        remoteSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final merged = <String, Map<String, dynamic>>{};
    for (final item in [..._debugCustomerSubscriptions(), ...remote]) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...item,
        'id': id,
      };
    }
    return merged.values.toList();
  }

  List<Map<String, dynamic>> _debugCustomerOrders() {
    return _debugCustomerOrdersState ??=
        _loadDebugList('customer_orders') ?? _seedDebugCustomerOrders();
  }

  List<Map<String, dynamic>> _debugAdminOrders() {
    final sourceOrders = _debugCustomerOrders();
    final baseOrders =
        sourceOrders.isEmpty ? _seedDebugCustomerOrders() : sourceOrders;
    return baseOrders.map(_debugAdminOrderView).toList();
  }

  Map<String, dynamic> _debugAdminOrderView(Map<String, dynamic> item) {
    final status = (item['orderStatus'] ?? item['status'] ?? '').toString();
    final normalizedStatus = status.isEmpty ? 'confirmed' : status;
    return {
      ...item,
      'id': (item['id'] ?? '').toString(),
      'orderStatus': normalizedStatus,
      'customerName': item['customerName'] ?? 'Асет',
      'customerId': item['customerId'] ?? 'customer_demo',
      'customerPhone': item['customerPhone'] ?? '+7 708 636 21 53',
      'cleanerId': item['cleanerId'] ?? 'Мария',
      'cleanerName': item['cleanerName'] ?? 'Мария',
      'clusterName':
          item['clusterName'] ?? item['residentialComplex'] ?? 'ЖК Триумф',
    };
  }

  Stream<List<Map<String, dynamic>>> _debugSharedOrdersStream() {
    return _db.collection('debug_bridge_orders').snapshots().map(
          (snap) => _mergeDebugOrders(
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
          ),
        );
  }

  List<Map<String, dynamic>> _mergeDebugOrders(
    List<Map<String, dynamic>> remote,
  ) {
    final local = List<Map<String, dynamic>>.from(_debugCustomerOrders());
    final merged = <String, Map<String, dynamic>>{};
    for (final item in [...local, ...remote]) {
      final id = (item['id'] ?? item['orderId'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      final existing = merged[id];
      if (existing == null) {
        merged[id] = {...item, 'id': id, 'orderId': item['orderId'] ?? id};
        continue;
      }
      merged[id] = {
        ...existing,
        ...item,
        'id': id,
        'orderId': item['orderId'] ?? existing['orderId'] ?? id,
      };
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final aMs = _timestampMillis(a['scheduledFor'] ?? a['createdAt']);
      final bMs = _timestampMillis(b['scheduledFor'] ?? b['createdAt']);
      return bMs.compareTo(aMs);
    });
    return items;
  }

  List<Map<String, dynamic>> _debugAdminPaymentsFromOrders(
    List<Map<String, dynamic>> orders,
  ) {
    final now = DateTime.now();
    final items = <Map<String, dynamic>>[];
    for (final order in orders) {
      final orderId = (order['id'] ?? order['orderId'] ?? '').toString();
      if (orderId.isEmpty) {
        continue;
      }
      final subscriptionId = (order['subscriptionId'] ?? '').toString();
      final rawPaymentStatus =
          (order['paymentStatus'] ?? order['status'] ?? '').toString();
      final paymentStatus = switch (rawPaymentStatus) {
        'pending_payment' => 'pending_invoice',
        'pending_assignment' => 'invoice_requested',
        '' => (orderId == 'cust_order_done_1' ? 'paid' : 'invoice_requested'),
        _ => rawPaymentStatus,
      };
      if (!{
        'pending_invoice',
        'invoice_requested',
        'paid',
        'rejected',
        'initiated',
      }.contains(paymentStatus)) {
        continue;
      }
      if (paymentStatus == 'paid' && subscriptionId.isNotEmpty) {
        continue;
      }
      final createdAt = order['createdAt'] ??
          Timestamp.fromDate(
            DateTime(now.year, now.month, now.day - 1, 10, 30),
          );
      items.add({
        'id': 'debug_payment_$orderId',
        'orderId': orderId,
        'status': paymentStatus,
        'amount': (order['price'] as num?)?.toInt() ?? 25000,
        'currency': (order['currency'] ?? 'KZT').toString(),
        'kaspiPhone': (order['kaspiPhone'] ?? '+77086362153').toString(),
        'customerId': (order['customerId'] ?? 'customer_demo').toString(),
        'customerName': (order['customerName'] ?? 'Асет').toString(),
        'customerPhone':
            (order['customerPhone'] ?? '+7 708 636 21 53').toString(),
        'packageName': (order['package'] ?? '4 раза в месяц').toString(),
        'frequencyLabel':
            (order['frequencyLabel'] ?? order['package'] ?? '4 раза в месяц')
                .toString(),
        'addons': order['addons'] ?? const [],
        'addonsDetailed': order['addonsDetailed'] ?? const [],
        'addonCount': order['addonCount'] ?? 0,
        'addonTotalPrice': order['addonTotalPrice'] ?? 0,
        'addonsSeparatePaymentTotal': order['addonsSeparatePaymentTotal'] ?? 0,
        'separatePaymentAddons': order['separatePaymentAddons'] ?? const [],
        'address': (order['address'] ?? 'ЖК Триумф, кв. 45').toString(),
        if (paymentStatus == 'invoice_requested' ||
            paymentStatus == 'pending_invoice' ||
            paymentStatus == 'initiated')
          'invoiceRequestedAt': order['updatedAt'] ?? createdAt,
        'createdAt': createdAt,
      });
    }
    items.sort((a, b) {
      final aMs = _timestampMillis(a['createdAt']);
      final bMs = _timestampMillis(b['createdAt']);
      return bMs.compareTo(aMs);
    });
    return items;
  }

  List<Map<String, dynamic>> _mergeAdminPaymentFeeds(
    List<Map<String, dynamic>> livePayments,
    List<Map<String, dynamic>> fallbackPayments,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final item in livePayments) {
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = Map<String, dynamic>.from(item);
    }
    for (final item in fallbackPayments) {
      final orderId = (item['orderId'] ?? '').toString().trim();
      final fallbackId = (item['id'] ?? '').toString().trim();
      if (fallbackId.isEmpty) {
        continue;
      }
      final hasLivePaymentForOrder = merged.values.any((payment) {
        return (payment['orderId'] ?? '').toString().trim() == orderId &&
            orderId.isNotEmpty;
      });
      if (hasLivePaymentForOrder) {
        continue;
      }
      merged[fallbackId] = Map<String, dynamic>.from(item);
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final aMs = _timestampMillis(
        a['invoiceRequestedAt'] ?? a['createdAt'] ?? a['updatedAt'],
      );
      final bMs = _timestampMillis(
        b['invoiceRequestedAt'] ?? b['createdAt'] ?? b['updatedAt'],
      );
      return bMs.compareTo(aMs);
    });
    return items;
  }

  List<Map<String, dynamic>> _debugAdminCleaners() {
    final cleanerProfile = _debugCleanerProfile();
    return <Map<String, dynamic>>[
      {
        'id': 'cleaner_demo',
        'name': (cleanerProfile['name'] ?? 'Мария').toString(),
        'phone': (cleanerProfile['phone'] ?? '+7 701 234 56 78').toString(),
        'clusterName': 'ЖК Изумрудный кластер',
        'verificationStatus':
            (cleanerProfile['verificationStatus'] ?? 'approved').toString(),
        'rating': (cleanerProfile['rating'] as num?)?.toDouble() ?? 4.9,
        'jobsCount': (cleanerProfile['jobsCount'] as num?)?.toInt() ?? 0,
        'monthlyEarnings':
            (cleanerProfile['monthlyEarnings'] as num?)?.toInt() ?? 0,
        'status': 'active',
      },
      {
        'id': 'cleaner_candidate_demo',
        'name': 'Айгерим',
        'phone': '+7 702 111 22 33',
        'clusterName': 'ЖК Триумф',
        'verificationStatus': 'pending',
        'rating': 4.7,
        'jobsCount': 12,
        'monthlyEarnings': 275000,
        'status': 'pending',
      },
    ];
  }

  List<Map<String, dynamic>> _debugClusters() {
    return <Map<String, dynamic>>[
      {
        'id': 'cluster_emerald',
        'name': 'ЖК Изумрудный кластер',
        'residentialComplex': 'ЖК Изумрудный',
        'lat': 51.1099,
        'lng': 71.4038,
        'radiusMeters': 300,
        'cleanersCount': 1,
      },
      {
        'id': 'cluster_triumph',
        'name': 'ЖК Триумф',
        'residentialComplex': 'ЖК Триумф',
        'lat': 51.1276,
        'lng': 71.4275,
        'radiusMeters': 300,
        'cleanersCount': 1,
      },
    ];
  }

  List<Map<String, dynamic>> _debugAdminChecklists() {
    final stored = _debugCleanerChecklistState.entries
        .map((entry) => {'id': entry.key, ...entry.value})
        .toList();
    if (stored.isNotEmpty) {
      return stored;
    }
    return <Map<String, dynamic>>[
      {
        'id': 'cust_order_active_1',
        'orderId': 'cust_order_active_1',
        'cleanerId': 'cleaner_demo',
        'completedTasks': <String>[
          'Протерты поверхности',
          'Пылесос',
          'Санузел',
        ],
        'addons': <String>['Мытье окон'],
        'note': 'Ключ оставлен у консьержа.',
        'completedAt': Timestamp.now(),
      },
    ];
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCleanerChecklistsStream() {
    return _db.collection('debug_bridge_cleaner_checklists').snapshots().map((
      snap,
    ) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = <String, Map<String, dynamic>>{};
      for (final item in [..._debugAdminChecklists(), ...remote]) {
        final id = (item['id'] ?? item['orderId'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
          'orderId': (item['orderId'] ?? id).toString(),
        };
      }
      final items = merged.values.toList();
      items.sort((a, b) {
        final aMs = _timestampMillis(a['completedAt']);
        final bMs = _timestampMillis(b['completedAt']);
        return bMs.compareTo(aMs);
      });
      return items;
    });
  }

  List<Map<String, dynamic>> _seedDebugCustomerOrders() {
    final now = DateTime.now();
    return [
      {
        'id': 'cust_order_active_1',
        'status': 'confirmed',
        'paymentStatus': 'paid',
        'scheduledFor': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day + 1, 10, 0),
        ),
        'date': DateTime(
          now.year,
          now.month,
          now.day + 1,
          10,
          0,
        ).toIso8601String(),
        'time': '10:00 - 13:00',
        'package': '4 раза в месяц',
        'price': 25000,
        'residentialComplex': 'ЖК Триумф',
        'address': 'ЖК Триумф, кв. 45',
        'cleanerName': 'Мария',
        'cleanerPhone': '+7 701 234 56 78',
        'kaspiPhone': '+77086362153',
        'createdAt': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 1),
        ),
      },
      {
        'id': 'cust_order_done_1',
        'status': 'completed',
        'paymentStatus': 'paid',
        'scheduledFor': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 6),
        ),
        'date': DateTime(now.year, now.month, now.day - 6).toIso8601String(),
        'time': '10:00 - 13:00',
        'package': '4 раза в месяц',
        'price': 25000,
        'residentialComplex': 'ЖК Триумф',
        'address': 'ЖК Триумф, кв. 45',
        'cleanerName': 'Мария',
        'cleanerPhone': '+7 701 234 56 78',
        'createdAt': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 7),
        ),
        'paidAt': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 6),
        ),
        'rating': 5,
        'comment': 'Все было аккуратно и вовремя.',
      },
    ];
  }

  List<Map<String, dynamic>> _debugCustomerScheduleSlots() {
    return _debugCustomerScheduleSlotsState ??=
        _loadDebugList('customer_slots') ??
            (() {
              final now = DateTime.now();
              return [
                {
                  'id': 'cust_slot_1',
                  'sourceOrderId': 'cust_order_active_1',
                  'subscriptionId': 'sub_demo',
                  'status': 'assigned',
                  'scheduledFor': Timestamp.fromDate(
                    DateTime(now.year, now.month, now.day + 1, 10, 0),
                  ),
                  'time': '10:00 - 13:00',
                  'package': '4 раза в месяц',
                  'residentialComplex': 'ЖК Триумф',
                  'address': 'ЖК Триумф, кв. 45',
                  'cleanerName': 'Мария',
                  'cleanerPhone': '+7 701 234 56 78',
                  'totalDurationMinutes': 180,
                  'price': 6250,
                  'area': 100,
                },
              ];
            })();
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCustomerScheduleSlotsStream() {
    final customerId = _uidOrNull ?? 'customer_demo';
    return Stream.multi((controller) {
      List<Map<String, dynamic>> sharedOrders = _debugCustomerOrders();
      List<Map<String, dynamic>> remoteSlots = const <Map<String, dynamic>>[];

      void emit() {
        final allowedOrderIds = <String>{
          ..._debugCustomerScheduleSlots()
              .map(
                (item) =>
                    (item['sourceOrderId'] ?? item['customerOrderId'] ?? '')
                        .toString(),
              )
              .where((id) => id.isNotEmpty),
          ...sharedOrders
              .map((item) => (item['id'] ?? item['orderId'] ?? '').toString())
              .where((id) => id.isNotEmpty),
        };
        final filteredRemote = remoteSlots.where((item) {
          final itemCustomerId = (item['customerId'] ?? '').toString();
          final orderId = (item['customerOrderId'] ??
                  item['sourceOrderId'] ??
                  item['orderId'] ??
                  item['id'] ??
                  '')
              .toString();
          return itemCustomerId == customerId ||
              allowedOrderIds.contains(orderId);
        }).toList();
        controller.add(_mergeDebugCustomerScheduleSlots(filteredRemote));
      }

      final ordersSub = _debugSharedCustomerOrdersStream().listen((items) {
        sharedOrders = items;
        emit();
      });
      final slotsSub = _db
          .collection('debug_bridge_cleaner_slots')
          .snapshots()
          .listen((snap) {
        remoteSlots = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        emit();
      });

      emit();
      controller.onCancel = () async {
        await ordersSub.cancel();
        await slotsSub.cancel();
      };
    });
  }

  List<Map<String, dynamic>> _mergeDebugCustomerScheduleSlots(
    List<Map<String, dynamic>> remote,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    final remoteByOrderId = <String, Map<String, dynamic>>{};
    for (final item in remote) {
      final orderId = (item['customerOrderId'] ??
              item['sourceOrderId'] ??
              item['orderId'] ??
              item['id'] ??
              '')
          .toString();
      if (orderId.isNotEmpty) {
        remoteByOrderId[orderId] = item;
      }
    }
    for (final item in _debugCustomerScheduleSlots()) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      final orderId =
          (item['sourceOrderId'] ?? item['customerOrderId'] ?? '').toString();
      final remoteMatch = remoteByOrderId[orderId];
      merged[id] = {
        ...item,
        if (remoteMatch != null) ...remoteMatch,
        'id': id,
        if (orderId.isNotEmpty) 'sourceOrderId': orderId,
      };
    }
    for (final entry in remoteByOrderId.entries) {
      final orderId = entry.key;
      final remoteMatch = entry.value;
      final alreadyMerged = merged.values.any((item) {
        final existingOrderId =
            (item['sourceOrderId'] ?? item['customerOrderId'] ?? '').toString();
        return existingOrderId == orderId;
      });
      if (alreadyMerged) {
        continue;
      }
      final fallbackId = (remoteMatch['id'] ?? 'cust_slot_$orderId').toString();
      merged[fallbackId] = {
        'id': fallbackId,
        'sourceOrderId': orderId,
        'customerOrderId': orderId,
        'subscriptionId': (remoteMatch['subscriptionId'] ?? '').toString(),
        'status': remoteMatch['status'] ?? 'assigned',
        'scheduledFor': remoteMatch['scheduledFor'] ?? remoteMatch['date'],
        'date': remoteMatch['date'] ?? remoteMatch['scheduledFor'],
        'time': (remoteMatch['time'] ?? '10:00 - 13:00').toString(),
        'package': remoteMatch['package'],
        'residentialComplex': remoteMatch['residentialComplex'],
        'address': remoteMatch['address'],
        'cleanerId': remoteMatch['cleanerId'],
        'cleanerName': remoteMatch['cleanerName'],
        'cleanerPhone': remoteMatch['cleanerPhone'],
        'customerId': remoteMatch['customerId'] ?? 'customer_demo',
        'totalDurationMinutes': remoteMatch['totalDurationMinutes'] ??
            remoteMatch['estimatedDurationMinutes'],
        'estimatedDurationMinutes': remoteMatch['estimatedDurationMinutes'] ??
            remoteMatch['totalDurationMinutes'],
        'price': remoteMatch['price'] ?? 0,
        'area': remoteMatch['area'] ?? 0,
        if (remoteMatch['photoUrls'] != null)
          'photoUrls': remoteMatch['photoUrls'],
        if (remoteMatch['completedAt'] != null)
          'completedAt': remoteMatch['completedAt'],
        if (remoteMatch['updatedAt'] != null)
          'updatedAt': remoteMatch['updatedAt'],
      };
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final left = _toDateTime(a['scheduledFor'] ?? a['date']);
      final right = _toDateTime(b['scheduledFor'] ?? b['date']);
      return left.compareTo(right);
    });
    return items;
  }

  Map<String, List<Map<String, dynamic>>> _debugChatMessagesMap() {
    return _debugChatMessagesState ??= (() {
      final loaded = debugStorageRead(_debugStorageKey('chat_messages'));
      if (loaded == null || loaded.isEmpty) {
        return <String, List<Map<String, dynamic>>>{};
      }
      try {
        final decoded = jsonDecode(loaded);
        if (decoded is! Map) {
          return <String, List<Map<String, dynamic>>>{};
        }
        return decoded.map((key, value) {
          final items = (value is List ? value : const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          return MapEntry(key.toString(), items);
        });
      } catch (_) {
        return <String, List<Map<String, dynamic>>>{};
      }
    })();
  }

  List<Map<String, dynamic>> _debugChatMessages(String orderId) {
    final messagesMap = _debugChatMessagesMap();
    return messagesMap.putIfAbsent(orderId, () {
      final otherId = _isDebugCustomer ? 'cleaner_demo' : 'customer_demo';
      final otherRole = _isDebugCustomer ? 'cleaner' : 'customer';
      final now = DateTime.now();
      return [
        {
          'id': 'debug_chat_seed_${orderId}_1',
          'senderId': otherId,
          'senderRole': otherRole,
          'text': 'Здравствуйте! Если будут вопросы по заказу, напишите сюда.',
          'type': 'system',
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(minutes: 30)),
          ),
          'readBy': [_uidOrNull ?? ''],
        },
      ];
    });
  }

  List<Map<String, dynamic>> _temporaryChatMessages(String orderId) {
    final messagesMap = _debugChatMessagesMap();
    return messagesMap.putIfAbsent(orderId, () {
      final otherId = _isTemporaryCustomerSession
          ? 'temp_cleaner_chat'
          : 'temp_customer_chat';
      final otherRole = _isTemporaryCustomerSession ? 'cleaner' : 'customer';
      final now = DateTime.now();
      return [
        {
          'id': 'temp_chat_seed_${orderId}_1',
          'senderId': otherId,
          'senderRole': otherRole,
          'text': 'Здравствуйте! Если будут вопросы по заказу, напишите сюда.',
          'type': 'system',
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(minutes: 30)),
          ),
          'readBy': [_uidOrNull ?? ''],
        },
      ];
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedChatMessagesStream(
    String orderId,
  ) {
    return _db
        .collection('debug_bridge_chat_messages')
        .where('orderId', isEqualTo: orderId)
        .snapshots()
        .map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = _mergeDebugChatMessages(orderId, remote);
      merged.sort(
        (a, b) => _timestampMillis(
          a['createdAt'],
        ).compareTo(_timestampMillis(b['createdAt'])),
      );
      return merged;
    });
  }

  List<Map<String, dynamic>> _mergeDebugChatMessages(
    String orderId,
    List<Map<String, dynamic>> remote,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final message in [..._debugChatMessages(orderId), ...remote]) {
      final id = (message['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...message,
        'id': id,
        'orderId': orderId,
      };
    }
    return merged.values.toList();
  }

  Stream<List<Map<String, dynamic>>> _debugSharedChatSummariesStream() {
    final currentUserId = _uidOrNull;
    return Stream.multi((controller) {
      List<Map<String, dynamic>> ownedOrders = const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> allMessages = const <Map<String, dynamic>>[];

      List<Map<String, dynamic>> buildItems() {
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final message in allMessages) {
          final orderId = (message['orderId'] ?? '').toString();
          if (orderId.isEmpty) {
            continue;
          }
          grouped
              .putIfAbsent(orderId, () => <Map<String, dynamic>>[])
              .add(message);
        }
        final orderIds = ownedOrders
            .map(
              (item) => (item['customerOrderId'] ??
                      item['orderId'] ??
                      item['id'] ??
                      '')
                  .toString(),
            )
            .where((id) => id.isNotEmpty)
            .toSet();
        final items = orderIds.map((orderId) {
          final messages = _mergeDebugChatMessages(
            orderId,
            grouped[orderId] ?? const <Map<String, dynamic>>[],
          )..sort(
              (a, b) => _timestampMillis(
                a['createdAt'],
              ).compareTo(_timestampMillis(b['createdAt'])),
            );
          final lastMessage = messages.isEmpty ? null : messages.last;
          final unreadCount = currentUserId == null
              ? 0
              : messages.where((message) {
                  if ((message['senderId'] ?? '').toString() == currentUserId) {
                    return false;
                  }
                  final readBy = ((message['readBy'] ?? const []) as List)
                      .map((item) => item.toString())
                      .toSet();
                  return !readBy.contains(currentUserId);
                }).length;
          return {
            'id': '${currentUserId ?? 'debug'}_$orderId',
            'orderId': orderId,
            'userId': currentUserId,
            'participantName': _debugChatParticipantName(orderId),
            'lastMessage': (lastMessage?['text'] ?? '').toString(),
            'lastMessageAt': lastMessage?['createdAt'] ?? Timestamp.now(),
            'unreadCount': unreadCount,
            'updatedAt': lastMessage?['createdAt'] ?? Timestamp.now(),
          };
        }).toList();
        items.sort((a, b) {
          final aMs = _timestampMillis(a['updatedAt'] ?? a['lastMessageAt']);
          final bMs = _timestampMillis(b['updatedAt'] ?? b['lastMessageAt']);
          return bMs.compareTo(aMs);
        });
        return items;
      }

      void emit() => controller.add(buildItems());

      final messagesSub = _db
          .collection('debug_bridge_chat_messages')
          .snapshots()
          .listen((snap) {
        allMessages = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        emit();
      });

      StreamSubscription<List<Map<String, dynamic>>> ownedSub;
      if (_isDebugCustomer) {
        ownedSub = _debugSharedCustomerOrdersStream().listen((items) {
          ownedOrders = items;
          emit();
        });
      } else {
        ownedSub = _debugSharedCleanerOrdersStream().listen((items) {
          ownedOrders = items;
          emit();
        });
      }

      emit();
      controller.onCancel = () async {
        await messagesSub.cancel();
        await ownedSub.cancel();
      };
    });
  }

  String _temporaryChatParticipantName(String orderId) {
    if (_isTemporaryCustomerSession) {
      final customerOrder =
          _temporaryCustomerOrders().cast<Map<String, dynamic>?>().firstWhere(
                (order) => (order?['id'] ?? order?['orderId']) == orderId,
                orElse: () => null,
              );
      final cleanerName =
          (customerOrder?['cleanerName'] ?? '').toString().trim();
      return cleanerName.isNotEmpty ? cleanerName : 'Менеджер DOMLY';
    }
    if (_isTemporaryCleanerSession) {
      final slot = _temporaryCleanerScheduleSlots()
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (item) =>
                (item?['customerOrderId'] ??
                    item?['sourceOrderId'] ??
                    item?['id']) ==
                orderId,
            orElse: () => null,
          );
      final customerName =
          (slot?['customerName'] ?? slot?['client'] ?? '').toString().trim();
      return customerName.isNotEmpty ? customerName : 'Клиент';
    }
    return 'DOMLY';
  }

  Stream<List<Map<String, dynamic>>> _temporaryChatSummariesStream() {
    final currentUserId = _uidOrNull;
    if (currentUserId == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return Stream.multi((controller) {
      void emit() {
        final ownedOrders = _isTemporaryCustomerSession
            ? _temporaryCustomerOrders()
            : _temporaryCleanerOrders();
        final orderIds = ownedOrders
            .map(
              (item) => (item['customerOrderId'] ??
                      item['orderId'] ??
                      item['id'] ??
                      '')
                  .toString(),
            )
            .where((id) => id.isNotEmpty)
            .toSet();
        final items = orderIds.map((orderId) {
          final messages = _temporaryChatMessages(orderId)
            ..sort(
              (a, b) => _timestampMillis(
                a['createdAt'],
              ).compareTo(_timestampMillis(b['createdAt'])),
            );
          final lastMessage = messages.isEmpty ? null : messages.last;
          final unreadCount = messages.where((message) {
            if ((message['senderId'] ?? '').toString() == currentUserId) {
              return false;
            }
            final readBy = ((message['readBy'] ?? const []) as List)
                .map((item) => item.toString())
                .toSet();
            return !readBy.contains(currentUserId);
          }).length;
          return {
            'id': '${currentUserId}_$orderId',
            'orderId': orderId,
            'userId': currentUserId,
            'participantName': _temporaryChatParticipantName(orderId),
            'lastMessage': (lastMessage?['text'] ?? '').toString(),
            'lastMessageAt': lastMessage?['createdAt'] ?? Timestamp.now(),
            'unreadCount': unreadCount,
            'updatedAt': lastMessage?['createdAt'] ?? Timestamp.now(),
          };
        }).toList();
        items.sort((a, b) {
          final aMs = _timestampMillis(a['updatedAt'] ?? a['lastMessageAt']);
          final bMs = _timestampMillis(b['updatedAt'] ?? b['lastMessageAt']);
          return bMs.compareTo(aMs);
        });
        controller.add(items);
      }

      final sub = _debugStateChanges.stream.listen((_) => emit());
      emit();
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  String _debugChatParticipantName(String orderId) {
    if (_isDebugCustomer) {
      final customerOrder =
          _debugCustomerOrders().cast<Map<String, dynamic>?>().firstWhere(
                (order) => (order?['id'] ?? order?['orderId']) == orderId,
                orElse: () => null,
              );
      final cleanerName =
          (customerOrder?['cleanerName'] ?? '').toString().trim();
      if (cleanerName.isNotEmpty) {
        return cleanerName;
      }
    }
    if (_isDebugCleaner) {
      final slot =
          _debugCleanerScheduleSlots().cast<Map<String, dynamic>?>().firstWhere(
                (item) =>
                    (item?['customerOrderId'] ??
                        item?['sourceOrderId'] ??
                        item?['id']) ==
                    orderId,
                orElse: () => null,
              );
      final slotCustomerName =
          (slot?['customerName'] ?? slot?['client'] ?? '').toString().trim();
      if (slotCustomerName.isNotEmpty) {
        return slotCustomerName;
      }
      final cleanerOrder = _debugCleanerOrders()
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (item) =>
                (item?['customerOrderId'] ?? item?['orderId'] ?? item?['id']) ==
                orderId,
            orElse: () => null,
          );
      final orderCustomerName =
          (cleanerOrder?['customerName'] ?? cleanerOrder?['client'] ?? '')
              .toString()
              .trim();
      if (orderCustomerName.isNotEmpty) {
        return orderCustomerName;
      }
    }
    return '';
  }

  Map<String, dynamic> _debugCustomerSettings() {
    final persisted = _loadDebugMap('customer_settings');
    if (persisted != null) {
      return {..._defaultCustomerSettings(), ...persisted};
    }
    return _defaultCustomerSettings();
  }

  Map<String, dynamic> _defaultCustomerSettings() {
    return {
      'notifications': true,
      'emailNotifications': true,
      'darkMode': false,
      'animations': true,
      'language': 'Русский',
    };
  }

  List<Map<String, dynamic>> _debugNotifications() {
    final persisted = _loadDebugList('notifications');
    final now = DateTime.now();
    return _debugNotificationsState ??= persisted ??
        (_isDebugCleaner
            ? <Map<String, dynamic>>[
                {
                  'id': 'cleaner_notification_assigned_1',
                  'userId': 'cleaner_demo',
                  'type': 'cleaner_assigned',
                  'title': 'Новая уборка назначена',
                  'body': 'Заказ на сегодня добавлен в ваши активные задачи.',
                  'payload': {'orderId': 'cust_order_active_1'},
                  'read': false,
                  'createdAt': Timestamp.fromDate(
                    now.subtract(const Duration(hours: 2)),
                  ),
                },
                {
                  'id': 'cleaner_notification_training_1',
                  'userId': 'cleaner_demo',
                  'type': 'video_training',
                  'title': 'Доступно новое обучение',
                  'body': 'Откройте короткое видео по стандарту уборки кухни.',
                  'payload': {'videoId': 'cleaner_training_kitchen'},
                  'read': true,
                  'readAt': Timestamp.fromDate(
                    now.subtract(const Duration(days: 1)),
                  ),
                  'createdAt': Timestamp.fromDate(
                    now.subtract(const Duration(days: 1, hours: 3)),
                  ),
                },
              ]
            : <Map<String, dynamic>>[
                {
                  'id': 'customer_notification_payment_1',
                  'userId': 'customer_demo',
                  'type': 'payment_confirmed',
                  'title': 'Оплата подтверждена',
                  'body':
                      'Подписка активна, можно выбрать дату и время уборки.',
                  'payload': {'orderId': 'cust_order_active_1'},
                  'read': false,
                  'createdAt': Timestamp.fromDate(
                    now.subtract(const Duration(hours: 3)),
                  ),
                },
                {
                  'id': 'customer_notification_bonus_1',
                  'userId': 'customer_demo',
                  'type': 'referral_bonus',
                  'title': 'Начислены бонусы',
                  'body': 'За приглашенного друга начислено 2000 бонусов.',
                  'payload': const <String, dynamic>{},
                  'read': true,
                  'readAt': Timestamp.fromDate(
                    now.subtract(const Duration(days: 1)),
                  ),
                  'createdAt': Timestamp.fromDate(
                    now.subtract(const Duration(days: 1, hours: 2)),
                  ),
                },
              ]);
  }

  Map<String, dynamic> _debugAvailableDates(DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final today = DateTime.now();
    var cursor = monthStart;
    final minDate = LaunchConfig.nextBookingDate(today);
    if (cursor.isBefore(minDate)) {
      cursor = minDate;
    }
    final items = <Map<String, dynamic>>[];
    while (!cursor.isAfter(monthEnd) && items.length < 8) {
      if (cursor.weekday != DateTime.sunday) {
        items.add({
          'date':
              '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}',
          'availableSlotsCount': 3,
        });
      }
      cursor = cursor.add(const Duration(days: 2));
    }
    return {'ok': true, 'dates': items};
  }

  Map<String, dynamic> _debugAvailableSlots(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final isFriday = normalized.weekday == DateTime.friday;
    final slots = <Map<String, dynamic>>[
      {
        'time': '10:00 - 13:00',
        'availableCleaners': 2,
        'estimatedHours': 3,
        'totalDurationMinutes': 180,
      },
      {
        'time': '13:00 - 16:00',
        'availableCleaners': 1,
        'estimatedHours': 3,
        'totalDurationMinutes': 180,
      },
    ];
    if (!isFriday) {
      slots.add({
        'time': '16:00 - 19:00',
        'availableCleaners': 2,
        'estimatedHours': 3,
        'totalDurationMinutes': 180,
      });
    }
    return {
      'ok': true,
      'date':
          '${normalized.year.toString().padLeft(4, '0')}-${normalized.month.toString().padLeft(2, '0')}-${normalized.day.toString().padLeft(2, '0')}',
      'estimatedHours': 3,
      'slots': slots,
    };
  }

  Map<String, dynamic> _debugReferralStats() {
    final profile = _debugCustomerProfile();
    final qualified = (profile['referralQualifiedCount'] as num?)?.toInt() ?? 0;
    final discountPercent =
        (profile['referralDiscountPercent'] as num?)?.toInt() ?? 0;
    final bonus = (profile['bonusPoints'] as num?)?.toInt() ?? 0;
    final nextThreshold = qualified < 5
        ? 5
        : qualified < 10
            ? 10
            : qualified < 20
                ? 20
                : qualified;
    final nextDiscountPercent = discountPercent < 3
        ? 3
        : discountPercent < 7
            ? 7
            : discountPercent < 10
                ? 10
                : discountPercent;
    return {
      'invited': 8,
      'registered': 5,
      'paid': 3,
      'bonus': bonus,
      'monthlyActivated': qualified,
      'referralDiscountPercent': discountPercent,
      'nextReferralDiscountThreshold': nextThreshold,
      'nextReferralDiscountPercent': nextDiscountPercent,
      'remainingForNextDiscount': (nextThreshold - qualified).clamp(
        0,
        nextThreshold,
      ),
      'referrals': [
        {
          'name': 'Анна Иванова',
          'phone': '+7 701 111 22 33',
          'status': 'paid',
          'paid': true,
          'registered': true,
        },
        {
          'name': 'Марина Садыкова',
          'phone': '+7 702 333 44 55',
          'status': 'registered',
          'paid': false,
          'registered': true,
        },
      ],
    };
  }

  Map<String, dynamic> _debugCleanerProfile() {
    return _buildDebugCleanerProfile();
  }

  Map<String, dynamic> _buildDebugCleanerProfile({
    List<Map<String, dynamic>>? slotsOverride,
    List<Map<String, dynamic>>? ordersOverride,
    List<Map<String, dynamic>>? payoutsOverride,
  }) {
    final now = DateTime.now();
    final slots = slotsOverride ?? _debugCleanerScheduleSlots();
    final sourceOrders = ordersOverride ?? _debugCleanerOrders();
    final completedOrders = sourceOrders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      return status == 'completed';
    }).toList();
    final payouts = payoutsOverride ?? _debugCleanerPayouts();
    bool isSameDay(DateTime left, DateTime right) =>
        left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    final activeSlots = slots.where((slot) {
      final status = (slot['status'] ?? '').toString().toLowerCase();
      return status != 'cancelled' &&
          status != 'canceled' &&
          status != 'completed';
    }).toList();
    int cleanerIncomeOf(Map<String, dynamic> item) =>
        ((item['cleanerIncome'] ?? item['price'] ?? 0) as num?)?.toInt() ?? 0;
    final todayEarnings = activeSlots
        .where(
          (slot) =>
              isSameDay(_toDateTime(slot['scheduledFor'] ?? slot['date']), now),
        )
        .fold<int>(0, (total, slot) => total + cleanerIncomeOf(slot));
    int earningsForPeriod(
      List<Map<String, dynamic>> items,
      DateTime periodStart,
      DateTime periodEnd, {
      required Object? Function(Map<String, dynamic>) dateOf,
    }) {
      return items.where((item) {
        final scheduledFor = _toDateTime(dateOf(item));
        return !scheduledFor.isBefore(periodStart) &&
            scheduledFor.isBefore(periodEnd);
      }).fold<int>(0, (total, item) => total + cleanerIncomeOf(item));
    }

    int ordersForPeriod(
      List<Map<String, dynamic>> items,
      DateTime periodStart,
      DateTime periodEnd, {
      required Object? Function(Map<String, dynamic>) dateOf,
    }) {
      return items.where((item) {
        final scheduledFor = _toDateTime(dateOf(item));
        return !scheduledFor.isBefore(periodStart) &&
            scheduledFor.isBefore(periodEnd);
      }).length;
    }

    final activeWeekEarnings = earningsForPeriod(
      activeSlots,
      startOfWeek,
      endOfWeek,
      dateOf: (item) => item['scheduledFor'] ?? item['date'],
    );
    final completedWeekEarnings = earningsForPeriod(
      completedOrders,
      startOfWeek,
      endOfWeek,
      dateOf: (item) => item['scheduledFor'] ?? item['createdAt'],
    );
    final weeklyEarnings = activeWeekEarnings + completedWeekEarnings;
    final activeMonthEarnings = earningsForPeriod(
      activeSlots,
      startOfMonth,
      endOfMonth,
      dateOf: (item) => item['scheduledFor'] ?? item['date'],
    );
    final completedMonthEarnings = earningsForPeriod(
      completedOrders,
      startOfMonth,
      endOfMonth,
      dateOf: (item) => item['scheduledFor'] ?? item['createdAt'],
    );
    final monthlyEarnings = activeMonthEarnings + completedMonthEarnings;
    final weekOrders = ordersForPeriod(
          activeSlots,
          startOfWeek,
          endOfWeek,
          dateOf: (item) => item['scheduledFor'] ?? item['date'],
        ) +
        ordersForPeriod(
          completedOrders,
          startOfWeek,
          endOfWeek,
          dateOf: (item) => item['scheduledFor'] ?? item['createdAt'],
        );
    final totalEarned = activeSlots.fold<int>(
          0,
          (total, slot) => total + cleanerIncomeOf(slot),
        ) +
        completedOrders.fold<int>(
          0,
          (total, order) => total + cleanerIncomeOf(order),
        );
    final completedWithdrawn = payouts.where((payout) {
      final status = (payout['status'] ?? '').toString().toLowerCase();
      return status == 'completed' ||
          status == 'paid' ||
          status == 'approved' ||
          status == 'settled' ||
          status == 'success' ||
          status == 'succeeded';
    }).fold<int>(
      0,
      (total, payout) => total + ((payout['amount'] as num?)?.toInt() ?? 0),
    );
    final pendingWithdrawal = payouts
        .where(
          (payout) =>
              (payout['status'] ?? '').toString().toLowerCase() == 'pending',
        )
        .fold<int>(
          0,
          (total, payout) => total + ((payout['amount'] as num?)?.toInt() ?? 0),
        );
    final currentWalletBalance = math.max(totalEarned - completedWithdrawn, 0);
    final availableWithdrawalAmount = math.max(
      currentWalletBalance - pendingWithdrawal,
      0,
    );
    final totalCleanedArea = activeSlots.fold<int>(
          0,
          (total, slot) => total + ((slot['area'] as num?)?.toInt() ?? 0),
        ) +
        completedOrders.fold<int>(
          0,
          (total, order) => total + ((order['area'] as num?)?.toInt() ?? 0),
        );
    final jobsCount = activeSlots.length + completedOrders.length;
    final dailyIncome = todayEarnings > 0 ? todayEarnings : 13500;
    final currentWeekCleanedArea = activeSlots.where((slot) {
          final scheduledFor = _toDateTime(
            slot['scheduledFor'] ?? slot['date'],
          );
          return !scheduledFor.isBefore(startOfWeek) &&
              scheduledFor.isBefore(endOfWeek);
        }).fold<int>(
          0,
          (total, slot) => total + ((slot['area'] as num?)?.toInt() ?? 0),
        ) +
        completedOrders.where((order) {
          final scheduledFor = _toDateTime(
            order['scheduledFor'] ?? order['createdAt'],
          );
          return !scheduledFor.isBefore(startOfWeek) &&
              scheduledFor.isBefore(endOfWeek);
        }).fold<int>(
          0,
          (total, order) => total + ((order['area'] as num?)?.toInt() ?? 0),
        );
    const currentWeekAddonSales = 18000;
    final cleanerStatusLabel = jobsCount >= 50
        ? 'Топ'
        : jobsCount >= 20
            ? 'Специалист'
            : 'Новичок';
    final nextCleanerStatus = jobsCount >= 50
        ? ''
        : jobsCount >= 20
            ? 'Топ'
            : 'Специалист';
    final remainingForNextStatus = jobsCount >= 50
        ? 0
        : jobsCount >= 20
            ? 50 - jobsCount
            : 20 - jobsCount;
    final cleanerStatusProgress = jobsCount >= 50
        ? 1.0
        : jobsCount >= 20
            ? ((jobsCount - 20) / 30).clamp(0.0, 1.0)
            : (jobsCount / 20).clamp(0.0, 1.0);
    final cleanerStatusProgressText = jobsCount >= 50
        ? 'Максимальный уровень достигнут.'
        : 'До следующего статуса осталось $remainingForNextStatus уборки';
    final nextCareerBonusAmount = nextCleanerStatus == 'Специалист'
        ? 100000
        : nextCleanerStatus == 'Топ'
            ? 200000
            : 0;
    final remainingAreaToNextStatus = nextCleanerStatus == 'Специалист'
        ? math.max(12000 - totalCleanedArea, 0)
        : nextCleanerStatus == 'Топ'
            ? math.max(30000 - totalCleanedArea, 0)
            : 0;
    const unlockedBonusAmount = 3000;
    const lockedBonusAmount = 5000;
    const totalBonusAwarded = 8000;
    return {
      'name': 'Мария',
      'fullName': 'Мария Садыкова',
      'phone': '+7 701 234 56 78',
      'email': 'maria.cleaner@domly.kz',
      'homeAddress': 'ЖК Изумрудный, подъезд 2, кв. 12',
      'emergencyContactPhone': '+7 707 555 44 11',
      'emergencyContactRelation': 'Сестра',
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 45))),
      'verificationStatus': 'approved',
      'approvedAt': Timestamp.fromDate(now.subtract(const Duration(days: 44))),
      'level': cleanerStatusLabel,
      'rating': 4.9,
      'jobsCount': jobsCount,
      'experienceMonths': 6,
      'monthlyEarnings': monthlyEarnings,
      'todayEarnings': todayEarnings,
      'weeklyEarnings': weeklyEarnings,
      'weekOrders': weekOrders,
      'dailyIncome': dailyIncome,
      'totalCleanedArea': totalCleanedArea,
      'currentWeekCleanedArea': currentWeekCleanedArea,
      'currentWeekAddonSales': currentWeekAddonSales,
      'totalEarned': totalEarned,
      'currentWalletBalance': currentWalletBalance,
      'totalWithdrawn': completedWithdrawn,
      'availableWithdrawalAmount': availableWithdrawalAmount,
      'availableFullCashoutAmount': availableWithdrawalAmount,
      'availableWeeklyCashoutAmount': math.min(
        (availableWithdrawalAmount * 0.3).round(),
        availableWithdrawalAmount,
      ),
      'unlockedBonusAmount': unlockedBonusAmount,
      'lockedBonusAmount': lockedBonusAmount,
      'totalBonusAwarded': totalBonusAwarded,
      'cleanerStatusLabel': cleanerStatusLabel,
      'nextCleanerStatus': nextCleanerStatus,
      'nextCareerBonusAmount': nextCareerBonusAmount,
      'remainingAreaToNextStatus': remainingAreaToNextStatus,
      'cleanerStatusProgressText': cleanerStatusProgressText,
      'cleanerStatusProgress': cleanerStatusProgress,
      'bonusLedger': [
        {
          'id': 'bonus_unlock_1',
          'type': 'unlock',
          'title': 'Разблокирован недельный бонус',
          'subtitle': 'Доступен к выводу после выдержки 7 дней',
          'amount': unlockedBonusAmount,
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 1)),
          ),
        },
        {
          'id': 'bonus_weekly_1',
          'type': 'weekly_bonus',
          'title': 'Еженедельный бонус за площадь',
          'subtitle': 'Выполнен план по уборкам за неделю',
          'amount': lockedBonusAmount,
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 3)),
          ),
          'locked': true,
        },
      ],
      'menu': [
        {'title': 'Расписание работы', 'subtitle': 'Гибкий график'},
        {'title': 'Выплаты', 'subtitle': 'История начислений и выводов'},
        {'title': 'Документы', 'subtitle': 'Проверено'},
      ],
    };
  }

  Map<String, dynamic> _debugCleanerVerification() {
    return {
      'status': 'approved',
      'expiresAt': '2026-12-31',
      'selfieUrl': 'debug://selfie',
      'selfieWithIdUrl': 'debug://selfie-with-id',
      'idDocumentUrl': 'debug://id-document',
      'policeClearanceUrl': 'debug://police-clearance',
      'psychDispenserUrl': 'debug://psych-dispenser',
      'phthisiatricianUrl': 'debug://phthisiatrician',
      'residenceProofUrl': 'debug://residence-proof',
      'rejectionReason': '',
    };
  }

  List<Map<String, dynamic>> _debugCleanerOrders() {
    return _debugCleanerOrdersState ??= _loadDebugList('cleaner_orders') ??
        [
          {
            'id': 'ord_1',
            'customerOrderId': 'cust_order_done_1',
            'cleanerId': 'cleaner_demo',
            'status': 'completed',
            'dateText': '09.05.2026',
            'time': '10:00 - 13:00',
            'client': 'Асет',
            'customerName': 'Асет',
            'customerPhone': '+7 708 636 21 53',
            'residentialComplex': 'ЖК Триумф',
            'entrance': '4',
            'apartment': '45',
            'accessMethod': 'Ключ у консьержа',
            'address': 'ЖК Триумф, кв. 45',
            'package': '4 раза в месяц',
            'price': 6250,
            'area': 100,
          },
        ];
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCleanerOrdersStream() {
    final cleanerId = _uidOrNull ?? 'cleaner_demo';
    return _debugSharedCleanerSlotsStream().map((items) {
      final filtered = items
          .where(
            (item) => (item['cleanerId'] ?? cleanerId).toString() == cleanerId,
          )
          .toList();
      return _mergeDebugCleanerOrders(filtered);
    });
  }

  List<Map<String, dynamic>> _mergeDebugCleanerOrders(
    List<Map<String, dynamic>> remoteSlots,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final order in _debugCleanerOrders()) {
      final orderId =
          (order['customerOrderId'] ?? order['orderId'] ?? order['id'] ?? '')
              .toString();
      if (orderId.isEmpty) {
        continue;
      }
      merged[orderId] = {
        ...order,
        'id': (order['id'] ?? 'debug_cleaner_order_$orderId').toString(),
        'customerOrderId': orderId,
      };
    }

    final slots = _mergeDebugCleanerSlots(remoteSlots);
    for (final slot in slots) {
      final orderId = (slot['customerOrderId'] ??
              slot['sourceOrderId'] ??
              slot['orderId'] ??
              slot['id'] ??
              '')
          .toString();
      if (orderId.isEmpty) {
        continue;
      }
      final scheduledFor = _toDateTime(slot['scheduledFor'] ?? slot['date']);
      final dateText =
          '${scheduledFor.day.toString().padLeft(2, '0')}.${scheduledFor.month.toString().padLeft(2, '0')}.${scheduledFor.year}';
      merged[orderId] = {
        ...merged[orderId] ?? const <String, dynamic>{},
        'id': (merged[orderId]?['id'] ?? 'debug_cleaner_order_$orderId')
            .toString(),
        'customerOrderId': orderId,
        'cleanerId': slot['cleanerId'] ?? 'cleaner_demo',
        'status': slot['status'] ?? merged[orderId]?['status'] ?? 'assigned',
        'dateText': dateText,
        'time': (slot['time'] ?? '10:00 - 13:00').toString(),
        'client': slot['customerName'] ??
            slot['client'] ??
            merged[orderId]?['client'],
        'customerName': slot['customerName'] ??
            slot['client'] ??
            merged[orderId]?['customerName'],
        'customerPhone':
            slot['customerPhone'] ?? merged[orderId]?['customerPhone'],
        'residentialComplex': slot['residentialComplex'] ??
            merged[orderId]?['residentialComplex'],
        'entrance': slot['entrance'] ?? merged[orderId]?['entrance'],
        'apartment': slot['apartment'] ?? merged[orderId]?['apartment'],
        'accessMethod':
            slot['accessMethod'] ?? merged[orderId]?['accessMethod'],
        'address': slot['address'] ?? merged[orderId]?['address'],
        'package': slot['package'] ?? merged[orderId]?['package'],
        'price': slot['price'] ?? merged[orderId]?['price'] ?? 0,
        'area': slot['area'] ?? merged[orderId]?['area'] ?? 0,
        'estimatedDurationMinutes': slot['estimatedDurationMinutes'] ??
            merged[orderId]?['estimatedDurationMinutes'],
        'totalDurationMinutes': slot['totalDurationMinutes'] ??
            merged[orderId]?['totalDurationMinutes'],
        'updatedAt': slot['updatedAt'] ?? merged[orderId]?['updatedAt'],
        if (slot['completedAt'] != null ||
            merged[orderId]?['completedAt'] != null)
          'completedAt': slot['completedAt'] ?? merged[orderId]?['completedAt'],
      };
    }

    final items = merged.values.toList();
    items.sort((a, b) {
      final left = _parseDateTextOrTimestamp(
        a['dateText'],
        a['completedAt'] ?? a['updatedAt'],
      );
      final right = _parseDateTextOrTimestamp(
        b['dateText'],
        b['completedAt'] ?? b['updatedAt'],
      );
      return right.compareTo(left);
    });
    return items;
  }

  DateTime _parseDateTextOrTimestamp(Object? dateText, Object? fallback) {
    final raw = (dateText ?? '').toString().trim();
    if (raw.isNotEmpty) {
      final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(raw);
      if (match != null) {
        final day = int.tryParse(match.group(1) ?? '') ?? 1;
        final month = int.tryParse(match.group(2) ?? '') ?? 1;
        final year = int.tryParse(match.group(3) ?? '') ?? 1970;
        return DateTime(year, month, day);
      }
    }
    return _toDateTime(fallback);
  }

  List<Map<String, dynamic>> _debugCleanerScheduleSlots() {
    return _debugCleanerScheduleSlotsState ??=
        _loadDebugList('cleaner_slots') ??
            (() {
              final now = DateTime.now();
              return [
                {
                  'id': 'slot_1',
                  'sourceOrderId': 'cust_order_active_1',
                  'customerOrderId': 'cust_order_active_1',
                  'cleanerId': 'cleaner_demo',
                  'status': 'assigned',
                  'scheduledFor': Timestamp.fromDate(
                    DateTime(now.year, now.month, now.day, 10, 0),
                  ),
                  'date': Timestamp.fromDate(
                    DateTime(now.year, now.month, now.day, 10, 0),
                  ),
                  'time': '10:00 - 13:00',
                  'client': 'Асет',
                  'customerName': 'Асет',
                  'customerPhone': '+7 708 636 21 53',
                  'residentialComplex': 'ЖК Триумф',
                  'entrance': '4',
                  'apartment': '45',
                  'accessMethod': 'Ключ у консьержа',
                  'estimatedDurationMinutes': 180,
                  'totalDurationMinutes': 180,
                  'area': 100,
                  'address': 'ЖК Триумф, кв. 45',
                  'package': '4 раза в месяц',
                  'price': 6250,
                },
                {
                  'id': 'slot_2',
                  'sourceOrderId': 'cust_order_active_2',
                  'customerOrderId': 'cust_order_active_2',
                  'cleanerId': 'cleaner_demo',
                  'status': 'assigned',
                  'scheduledFor': Timestamp.fromDate(
                    DateTime(now.year, now.month, now.day, 15, 0),
                  ),
                  'date': Timestamp.fromDate(
                    DateTime(now.year, now.month, now.day, 15, 0),
                  ),
                  'time': '15:00 - 18:00',
                  'client': 'Анна',
                  'customerName': 'Анна',
                  'customerPhone': '+7 701 555 44 33',
                  'residentialComplex': 'ЖК Изумрудный',
                  'entrance': '2',
                  'apartment': '12',
                  'accessMethod': 'Домофон',
                  'estimatedDurationMinutes': 180,
                  'totalDurationMinutes': 180,
                  'area': 80,
                  'address': 'ЖК Изумрудный, кв. 12',
                  'package': '2 раза в месяц',
                  'price': 5400,
                },
              ];
            })();
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCleanerSlotsStream() {
    final cleanerId = _uidOrNull ?? 'cleaner_demo';
    return _db.collection('debug_bridge_cleaner_slots').snapshots().map((snap) {
      final remote = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where(
            (item) => (item['cleanerId'] ?? cleanerId).toString() == cleanerId,
          )
          .toList();
      return _mergeDebugCleanerSlots(remote);
    });
  }

  List<Map<String, dynamic>> _mergeDebugCleanerSlots(
    List<Map<String, dynamic>> remote,
  ) {
    final local = List<Map<String, dynamic>>.from(_debugCleanerScheduleSlots());
    final merged = <String, Map<String, dynamic>>{};
    for (final item in [...local, ...remote]) {
      final id =
          (item['id'] ?? item['sourceOrderId'] ?? item['customerOrderId'] ?? '')
              .toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...item,
        'id': id,
      };
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final left = _toDateTime(a['scheduledFor'] ?? a['date']);
      final right = _toDateTime(b['scheduledFor'] ?? b['date']);
      return left.compareTo(right);
    });
    return items;
  }

  List<Map<String, dynamic>> _debugComplaints() {
    final base = _debugComplaintsState ??= _loadDebugList('complaints') ??
        (_isDebugAdmin
            ? <Map<String, dynamic>>[
                {
                  'id': 'debug_complaint_seed_1',
                  'orderId': 'cust_order_done_1',
                  'customerId': 'customer_demo',
                  'text': 'После уборки остались разводы на зеркале в ванной.',
                  'photoUrls': const <String>[],
                  'status': 'open',
                  'createdAt': Timestamp.now(),
                },
              ]
            : <Map<String, dynamic>>[]);
    if (_isDebugAdmin) {
      final action = DebugSession.value('debug_action')?.trim();
      final complaintId = DebugSession.value('debug_complaint_id')?.trim();
      final status = DebugSession.value(
        'debug_complaint_status',
      )?.trim().toLowerCase();
      if (action == 'resolve_complaint' &&
          complaintId != null &&
          complaintId.isNotEmpty &&
          status != null &&
          status.isNotEmpty) {
        return base
            .map(
              (item) => item['id'] == complaintId
                  ? {
                      ...item,
                      'status': status,
                      'resolution': status == 'compensated'
                          ? 'Компенсация клиенту'
                          : status == 'refund'
                              ? 'Полный возврат'
                              : 'Жалоба закрыта',
                      'compensationAmount': status == 'compensated' ? 5000 : 0,
                    }
                  : item,
            )
            .toList();
      }
    }
    return base;
  }

  List<Map<String, dynamic>> _debugReviews() {
    return _debugReviewsState ??= _loadDebugList('reviews') ??
        (_isDebugAdmin
            ? <Map<String, dynamic>>[
                {
                  'id': 'cust_order_done_1',
                  'orderId': 'cust_order_done_1',
                  'customerId': 'customer_demo',
                  'rating': 5,
                  'text': 'Все прошло хорошо, уборка была аккуратной.',
                  'positiveTraits': const ['Вежливая', 'Опрятная'],
                  'negativeTraits': const <String>[],
                  'photoUrl': null,
                  'createdAt': Timestamp.now(),
                },
              ]
            : <Map<String, dynamic>>[]);
  }

  List<Map<String, dynamic>> _debugCleanerPayouts() {
    final now = DateTime.now();
    return [
      {
        'id': 'pay_1',
        'cleanerId': 'cleaner_demo',
        'amount': 24000,
        'status': 'completed',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      },
      {
        'id': 'pay_2',
        'cleanerId': 'cleaner_demo',
        'amount': 18500,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
      },
    ];
  }

  List<Map<String, dynamic>> _debugAdminWaitlist() {
    return <Map<String, dynamic>>[
      {
        'id': 'wait_1',
        'houseId': 'emerald_1',
        'userId': 'customer_demo',
        'source': 'app',
        'createdAt': Timestamp.now(),
      },
      {
        'id': 'wait_2',
        'houseId': 'triumph_1',
        'userId': 'customer_waiting_2',
        'source': 'invite_neighbors',
        'createdAt': Timestamp.now(),
      },
    ];
  }

  List<Map<String, dynamic>> _debugAdminReferralStats() {
    final customerProfile = _debugCustomerProfile();
    final customerPaid =
        (customerProfile['referralQualifiedCount'] as num?)?.toInt() ?? 0;
    final customerBonus =
        (customerProfile['bonusPoints'] as num?)?.toInt() ?? 0;
    final customerRegistered =
        customerPaid == 0 ? 0 : math.max(customerPaid, 5);
    final customerInvited =
        customerRegistered == 0 ? 0 : math.max(customerRegistered, 8);
    return <Map<String, dynamic>>[
      {
        'id': 'customer_demo',
        'invited': customerInvited,
        'registered': customerRegistered,
        'paid': customerPaid,
        'bonus': customerBonus,
      },
      {
        'id': 'customer_ref_2',
        'invited': 4,
        'registered': 2,
        'paid': 1,
        'bonus': 2000,
      },
    ];
  }

  List<Map<String, dynamic>> _debugServiceZones() {
    return <Map<String, dynamic>>[
      {
        'id': 'zone_astana_active',
        'title': 'Центральный кластер',
        'city': 'Астана',
        'status': 'active',
        'centerLat': 51.1288,
        'centerLng': 71.4304,
      },
      {
        'id': 'zone_astana_activating',
        'title': 'Южный кластер',
        'city': 'Астана',
        'status': 'activating',
        'centerLat': 51.1077,
        'centerLng': 71.4011,
      },
      {
        'id': 'zone_astana_planned',
        'title': 'Левый берег',
        'city': 'Астана',
        'status': 'planned',
        'centerLat': 51.1556,
        'centerLng': 71.4704,
      },
    ];
  }

  List<Map<String, dynamic>> _debugHouses() {
    return <Map<String, dynamic>>[
      {
        'id': 'triumph_1',
        'title': 'ЖК Триумф',
        'residentialComplex': 'ЖК Триумф',
        'address': 'ЖК Триумф, подъезд 1',
        'status': 'IN_PROGRESS',
        'lat': 51.1276,
        'lng': 71.4275,
        'threshold': 20,
        'current_users': 8,
        'zoneId': 'zone_astana_active',
      },
      {
        'id': 'emerald_1',
        'title': 'ЖК Изумрудный',
        'residentialComplex': 'ЖК Изумрудный',
        'address': 'ЖК Изумрудный, подъезд 2',
        'status': 'ACTIVE',
        'lat': 51.1099,
        'lng': 71.4038,
        'threshold': 20,
        'current_users': 24,
        'zoneId': 'zone_astana_activating',
      },
      {
        'id': 'capital_park_1',
        'title': 'ЖК Capital Park',
        'residentialComplex': 'ЖК Capital Park',
        'address': 'ЖК Capital Park, блок C',
        'status': 'INACTIVE',
        'lat': 51.1518,
        'lng': 71.4738,
        'threshold': 20,
        'current_users': 3,
        'zoneId': 'zone_astana_planned',
      },
    ];
  }

  Stream<List<Map<String, dynamic>>> _debugSharedHousesStream() {
    return _db.collection('debug_bridge_houses').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      return _mergeDebugHouses(remote);
    });
  }

  List<Map<String, dynamic>> _mergeDebugHouses(
    List<Map<String, dynamic>> remote,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final house in [..._debugHouses(), ...remote]) {
      final id = (house['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...house,
        'id': id,
      };
    }
    final items = merged.values.toList();
    items.sort(
      (a, b) => (a['address'] ?? a['id']).toString().compareTo(
            (b['address'] ?? b['id']).toString(),
          ),
    );
    return items;
  }

  Stream<List<Map<String, dynamic>>> _debugSharedWaitlistStream({
    String? houseId,
  }) {
    return _db.collection('debug_bridge_house_waitlist').snapshots().map((
      snap,
    ) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = _mergeDebugWaitlist(remote);
      if (houseId == null || houseId.isEmpty) {
        return merged;
      }
      return merged
          .where((item) => (item['houseId'] ?? '').toString() == houseId)
          .toList();
    });
  }

  List<Map<String, dynamic>> _mergeDebugWaitlist(
    List<Map<String, dynamic>> remote,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final item in [..._debugAdminWaitlist(), ...remote]) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...item,
        'id': id,
      };
    }
    final items = merged.values.toList();
    items.sort(
      (a, b) => _timestampMillis(
        b['createdAt'],
      ).compareTo(_timestampMillis(a['createdAt'])),
    );
    return items;
  }

  List<Map<String, dynamic>> _debugCleanerVideos() {
    final now = DateTime.now();
    return [
      {
        'id': 'vid_1',
        'title': 'Как подготовить квартиру к уборке',
        'description': 'Короткий чек-лист перед началом уборки.',
        'category': 'Стандарты',
        'videoUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'audienceType': 'cleaner',
        'isActive': true,
        'publishedAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 2)),
        ),
      },
      {
        'id': 'vid_2',
        'title': 'Фотоотчет без ошибок',
        'description': 'Как правильно сделать финальные фото после уборки.',
        'category': 'Фотоотчет',
        'videoUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'audienceType': 'cleaner',
        'isActive': true,
        'publishedAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 5)),
        ),
      },
    ];
  }

  List<Map<String, dynamic>> _debugAdminVideoContent() {
    final persisted = _loadDebugList('admin_videos');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    final merged = <String, Map<String, dynamic>>{};
    for (final video in [..._debugClientVideos(), ..._debugCleanerVideos()]) {
      final id = (video['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...video,
        'id': id,
        'isActive': video['isActive'] ?? true,
        'isRequired': video['isRequired'] ?? false,
      };
    }
    final items = merged.values.toList();
    items.sort((a, b) => _sortByPublishedAtDesc(a, b));
    return items;
  }

  List<Map<String, dynamic>> _debugAdminInfoContent() {
    final persisted = _loadDebugList('admin_info_content');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return <Map<String, dynamic>>[
      {
        'id': 'packages_benefits',
        'key': 'packages_benefits',
        'title': 'Чем больше уборок — тем выгоднее',
        'shortInfo':
            'Подписки помогают снизить стоимость уборки и закрепить удобные даты.',
        'fullInfo':
            'Чем чаще уборка, тем ниже стоимость одного выезда. Подписка также упрощает планирование и закрепление удобных слотов.',
        'type': 'package',
        'sortOrder': 10,
        'isActive': true,
      },
      {
        'id': 'multi_apartment_discount',
        'key': 'multi_apartment_discount',
        'title': 'Скидки по количеству квартир',
        'shortInfo': '1 квартира — 3%, 10 квартир — 7%, 20 квартир — 10%',
        'fullInfo':
            'Размер скидки зависит от количества квартир в одном адресном сценарии обслуживания. Финальная скидка применяется при подтверждении заказа.',
        'type': 'package',
        'sortOrder': 20,
        'isActive': true,
      },
      {
        'id': 'bonus_balance_info',
        'key': 'bonus_balance_info',
        'title': 'Ваш бонусный баланс',
        'shortInfo': 'Реферальная программа активна.',
        'fullInfo':
            'Бонусы начисляются за выполненные условия программы и могут быть использованы в рамках правил приложения.',
        'type': 'ui_text',
        'sortOrder': 30,
        'isActive': true,
      },
      {
        'id': 'bonus_progress_info',
        'key': 'bonus_progress_info',
        'title': 'Скидка по уровням',
        'shortInfo': 'Как работает прогресс и уровни скидок.',
        'fullInfo':
            'Чем больше завершенных и оплаченных заказов, тем выше уровень клиента и доступная скидка на будущие услуги.',
        'type': 'ui_text',
        'sortOrder': 40,
        'isActive': true,
      },
      {
        'id': 'addon_windows',
        'key': 'addon_windows',
        'title': 'Мытье окон',
        'shortInfo':
            'Дополнительная услуга для стандартной и генеральной уборки.',
        'fullInfo':
            'Стоимость рассчитывается отдельно. В зависимости от конфигурации окон и степени загрязнения время выполнения может увеличиться.',
        'type': 'addon',
        'sortOrder': 50,
        'isActive': true,
        'price': 5000,
      },
    ];
  }

  List<Map<String, dynamic>> _debugAdminPackages() {
    final persisted = _loadDebugList('admin_packages');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return <Map<String, dynamic>>[
      {
        'id': 'single',
        'name': 'Разовый пакет',
        'price': 0,
        'frequency': 'Разовая уборка',
        'features': [
          'Поддерживающая уборка',
          'Стоимость зависит от площади квартиры',
        ],
        'popular': false,
        'sortOrder': 1,
        'isActive': true,
        'cleaningsPerMonth': 1,
        'billingPeriodMonths': 1,
        'discountPercent': 0,
      },
      {
        'id': 'basic',
        'name': 'Два раза в месяц',
        'price': 0,
        'frequency': '2 раза в месяц',
        'features': [
          'Поддерживающая уборка',
          'Площадь подтверждается отдельно',
        ],
        'popular': false,
        'sortOrder': 2,
        'isActive': true,
        'cleaningsPerMonth': 2,
        'billingPeriodMonths': 1,
        'discountPercent': 0,
      },
      {
        'id': 'standard',
        'name': '4 раза в месяц',
        'price': 0,
        'frequency': '4 раза в месяц',
        'features': [
          'Поддерживающая уборка',
          'Оптимальный выбор для регулярного графика',
        ],
        'popular': true,
        'sortOrder': 3,
        'isActive': true,
        'cleaningsPerMonth': 4,
        'billingPeriodMonths': 1,
        'discountPercent': 0,
      },
      {
        'id': 'premium',
        'name': '8 раз в месяц',
        'price': 0,
        'frequency': '8 раз в месяц',
        'features': [
          'Максимальная частота уборок',
          'Подходит для плотного графика',
        ],
        'popular': false,
        'sortOrder': 4,
        'isActive': true,
        'cleaningsPerMonth': 8,
        'billingPeriodMonths': 1,
        'discountPercent': 0,
      },
      {
        'id': 'quarter',
        'name': 'Квартальный пакет',
        'price': 0,
        'frequency': 'Квартальный пакет',
        'features': [
          'Подписка на 3 месяца',
          'Выбор 2, 4 или 8 уборок в месяц',
          'Скидка 10% от общей суммы',
        ],
        'popular': false,
        'sortOrder': 5,
        'isActive': true,
        'isQuarterly': true,
        'billingPeriodMonths': 3,
        'discountPercent': 10,
      },
      {
        'id': 'general_cleaning',
        'name': 'Генеральная уборка',
        'price': 45000,
        'frequency': 'Разовая',
        'features': [
          'Глубокая уборка кухни и санузлов',
          'Мытье фасадов и доступных поверхностей',
          'Удаление стойких загрязнений',
        ],
        'popular': false,
        'sortOrder': 6,
        'isActive': true,
      },
      {
        'id': 'post_renovation',
        'name': 'Уборка после ремонта',
        'price': 60000,
        'frequency': 'Разовая',
        'features': [
          'Удаление строительной пыли',
          'Очистка поверхностей после ремонта',
          'Вынос мелкого строительного мусора',
        ],
        'popular': false,
        'sortOrder': 7,
        'isActive': true,
      },
    ];
  }

  Map<String, dynamic> _debugAdminPolicies() {
    final persisted = _loadDebugMap('admin_policies');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return <String, dynamic>{
      'referralBonusAmount': 2000,
      'defaultHouseThreshold': 20,
      'areaVerificationTolerance': 0,
      'cleanerReliableAreaThreshold': 12000,
      'cleanerReliableBonusAmount': 100000,
      'cleanerExpertAreaThreshold': 30000,
      'cleanerExpertBonusAmount': 200000,
      'cleanerLegendAreaThreshold': 65000,
      'cleanerLegendBonusAmount': 500000,
      'cleanerWeeklyAreaThreshold': 1300,
      'cleanerWeeklyAreaBonusAmount': 5000,
      'cleanerWeeklyAddonBonusThreshold1': 30000,
      'cleanerWeeklyAddonBonusAmount1': 4000,
      'cleanerWeeklyAddonBonusThreshold2': 50000,
      'cleanerWeeklyAddonBonusAmount2': 6000,
      'cleanerDailyIncome': 13500,
      'cleanerSqmRate': 60,
      'cleanerWeeklyCashoutPercent': 30,
      'cleanerWeeklyCashoutCooldownDays': 7,
      'cleanerFullCashoutCooldownDays': 30,
      'cleaningMinutesPerSqm': 1.6,
      'cleaningBaseMinutes': 30,
      'cleaningMinMinutes': 120,
      'cleaningMaxMinutes': 480,
    };
  }

  List<Map<String, dynamic>> _debugAdminPromoBanners() {
    final persisted = _loadDebugList('admin_promo_banners');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return <Map<String, dynamic>>[
      {
        'id': 'banner_bonus',
        'title': 'Получи бонусы',
        'subtitle': 'Приглашай друзей и получай 2000 ₸ за каждого.',
        'imageUrl': '',
        'ctaLabel': 'Подробнее',
        'route': '/client/bonus',
        'sortOrder': 1,
        'isActive': true,
      },
      {
        'id': 'banner_packages',
        'title': 'Подберите удобный пакет',
        'subtitle': '2, 4 или 8 уборок в месяц в одном оформлении.',
        'imageUrl': '',
        'ctaLabel': 'Выбрать пакет',
        'route': '/client/packages',
        'sortOrder': 2,
        'isActive': true,
      },
    ];
  }

  List<Map<String, dynamic>> _debugAdminPromotions() {
    final persisted = _loadDebugList('admin_promotions');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _debugAdminAddonGroups() {
    final persisted = _loadDebugList('admin_addon_groups');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return AppConfigService.defaultAddonGroupConfigs
        .map((group) => Map<String, dynamic>.from(group))
        .toList();
  }

  List<Map<String, dynamic>> _debugAdminChecklistTemplates() {
    final persisted = _loadDebugList('admin_checklist_templates');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return AppConfigService.defaultCleanerChecklistTemplates
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> saveAdminVideo(Map<String, dynamic> videoData) async {
    final videoId = (videoData['id'] ?? '').toString();
    if (videoId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final updated = _debugAdminVideoContent()
          .where((item) => (item['id'] ?? '').toString() != videoId)
          .toList()
        ..add(Map<String, dynamic>.from(videoData));
      debugStorageWrite(
        _debugStorageKey('admin_videos'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_video_content').doc(videoId).set({
        ...videoData,
        'id': videoId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance
        .postMap('/admin/videos', body: {...videoData, 'id': videoId});
  }

  Future<void> saveAdminInfoContent(Map<String, dynamic> infoData) async {
    final infoId = (infoData['key'] ?? infoData['id'] ?? '').toString();
    if (infoId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final updated = _debugAdminInfoContent()
          .where(
            (item) => (item['id'] ?? item['key'] ?? '').toString() != infoId,
          )
          .toList()
        ..add({...Map<String, dynamic>.from(infoData), 'id': infoId});
      debugStorageWrite(
        _debugStorageKey('admin_info_content'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_info_content').doc(infoId).set({
        ...infoData,
        'id': infoId,
        'key': infoId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/content-pages',
      body: {
        'slug': infoId,
        'titleRu':
            (infoData['title'] ?? infoData['titleRu'] ?? infoId).toString(),
        'titleKk': infoData['titleKk'],
        'bodyRu': (infoData['body'] ?? infoData['bodyRu'] ?? '').toString(),
        'bodyKk': infoData['bodyKk'],
        'kind': (infoData['kind'] ?? 'info').toString(),
        'active': infoData['isActive'] != false && infoData['active'] != false,
      },
    );
  }

  Future<int> _addonBonusSpendPercent() async {
    try {
      final promotions =
          await AppConfigService.instance.promotionsStream().first;
      var percent = 50;
      for (final promotion in promotions) {
        final target = (promotion['rewardTarget'] ?? 'addons').toString();
        if (target != 'addons' && target != 'all') {
          continue;
        }
        final value = (promotion['maxSpendPercent'] as num?)?.toInt() ?? 50;
        if (value > percent) {
          percent = value;
        }
      }
      return percent.clamp(0, 100).toInt();
    } catch (_) {
      return 50;
    }
  }

  Future<void> syncAdminTranslationSources() async {
    final sourceSet = kDefaultTranslationSources
        .map(TranslationController.normalizeSource)
        .where((source) => source.isNotEmpty)
        .toSet();
    sourceSet.addAll(await _dynamicTranslationSources());
    final sources = sourceSet.toList()..sort();
    if (_isDebugAdmin) {
      final current = {
        for (final item in _debugAdminTranslations())
          (item['id'] ?? '').toString(): Map<String, dynamic>.from(item),
      };
      for (final source in sources) {
        final key = TranslationController.translationKey(source);
        current[key] = {
          ...(current[key] ?? <String, dynamic>{}),
          'id': key,
          'source': source,
          'locales': {
            'ru': source,
            ...?kBuiltinTranslations[source],
            ...Map<String, dynamic>.from(
              ((current[key] ?? const {})['locales'] as Map?) ??
                  const <String, dynamic>{},
            ),
          },
        };
      }
      debugStorageWrite(
        _debugStorageKey('admin_translations'),
        jsonEncode(_jsonSafe(current.values.toList())),
      );
      final batch = _db.batch();
      final collection = _db.collection('debug_bridge_translations');
      for (final item in current.values) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        batch.set(
            collection.doc(id),
            {
              ...item,
              'updatedAt': Timestamp.now(),
              'sourceDebugUid': 'admin_demo',
            },
            SetOptions(merge: true));
      }
      await batch.commit();
      _notifyDebugStateChanged();
      return;
    }

    final items = sources.map((source) {
      final locales = <String, dynamic>{
        'ru': source,
        ...?kBuiltinTranslations[source],
      };
      return {
        'key': TranslationController.translationKey(source),
        'ru': locales['ru'] ?? source,
        'kk': locales['kk'],
        'namespace': 'app',
      };
    }).toList();
    for (var i = 0; i < items.length; i += 250) {
      await BackendApiService.instance.postMap(
        '/admin/translations/bulk',
        body: {
          'items': items.sublist(
            i,
            i + 250 > items.length ? items.length : i + 250,
          ),
        },
      );
    }
  }

  Future<Set<String>> _dynamicTranslationSources() async {
    if (_isDebugAdmin) {
      return const <String>{};
    }
    const collections = <String>[
      'customer_packages',
      'addons_config',
      'promotions',
      'home_banners',
      'info_content',
      'videos',
      'legal_documents',
      'checklist_templates',
      'app_tutorials',
    ];
    const fields = <String>{
      'title',
      'name',
      'label',
      'subtitle',
      'description',
      'shortInfo',
      'fullInfo',
      'longDescription',
      'hint',
      'category',
      'body',
      'terms',
      'privacy',
    };
    final sources = <String>{};

    void scanValue(Object? value) {
      if (value == null) {
        return;
      }
      if (value is String) {
        final normalized = TranslationController.normalizeSource(value);
        if (normalized.isNotEmpty && normalized.length <= 1200) {
          sources.add(normalized);
        }
        return;
      }
      if (value is Iterable) {
        for (final item in value) {
          scanValue(item);
        }
        return;
      }
      if (value is Map) {
        value.forEach((key, nested) {
          final keyText = key.toString();
          if (fields.contains(keyText) ||
              keyText.endsWith('Locales') ||
              keyText.endsWith('Translations') ||
              nested is Iterable ||
              nested is Map) {
            scanValue(nested);
          }
        });
      }
    }

    try {
      final config = await BackendApiService.instance.getMap(
        '/app/runtime-config',
        authenticated: false,
      );
      scanValue(config);
    } catch (_) {
      // Runtime config is optional during local development.
    }
    return sources;
  }

  Future<void> saveAdminTranslation({
    required String key,
    required String source,
    required Map<String, dynamic> locales,
  }) async {
    if (_isDebugAdmin) {
      final updated = _debugAdminTranslations()
          .where((item) => (item['id'] ?? '').toString() != key)
          .toList()
        ..add({
          'id': key,
          'source': source,
          'locales': locales,
          'updatedBy': _uidOrNull ?? 'system',
        });
      debugStorageWrite(
        _debugStorageKey('admin_translations'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_translations').doc(key).set({
        'id': key,
        'source': source,
        'locales': locales,
        'updatedAt': Timestamp.now(),
        'updatedBy': _uidOrNull ?? 'system',
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/translations',
      body: {
        'key': key,
        'ru': (locales['ru'] ?? source).toString(),
        'kk': locales['kk']?.toString(),
        'namespace': 'app',
      },
    );
  }

  List<Map<String, dynamic>> _debugAdminTranslations() {
    final persisted = _loadDebugList('admin_translations');
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    final sources = kDefaultTranslationSources
        .map(TranslationController.normalizeSource)
        .where((source) => source.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return sources
        .map(
          (source) => <String, dynamic>{
            'id': TranslationController.translationKey(source),
            'source': source,
            'locales': <String, dynamic>{'ru': source, 'kk': '', 'en': ''},
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _debugAdminSavedViews() {
    final persisted = _loadDebugList('admin_saved_views');
    if (persisted != null) {
      return persisted;
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _debugClientVideos() {
    final now = DateTime.now();
    return [
      {
        'id': 'client_vid_1',
        'title': 'Как подготовить квартиру к уборке',
        'description':
            'Уберите личные вещи с поверхностей. Освободите доступ к раковине, плите и полу. Ценные вещи лучше убрать заранее.',
        'category': 'Подготовка',
        'videoUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'audienceType': 'client',
        'isActive': true,
        'publishedAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 1)),
        ),
      },
      {
        'id': 'client_vid_2',
        'title': 'Что входит в стандартную уборку',
        'description':
            'Показываем зоны стандартной уборки: полы, кухня, санузел, пыль на доступных поверхностях и вынос мусора.',
        'category': 'Услуги',
        'videoUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'audienceType': 'client',
        'isActive': true,
        'publishedAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 4)),
        ),
      },
    ];
  }

  List<Map<String, dynamic>> _debugCleanerVideoViews() {
    return [
      {
        'id': 'view_1',
        'userId': 'cleaner_demo',
        'videoId': 'vid_1',
        'completed': true,
      },
    ];
  }

  List<Map<String, dynamic>> _debugClientVideoViews() {
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _debugVideoViews() {
    final persisted = _loadDebugList('user_video_views');
    if (persisted != null) {
      return persisted;
    }
    return _isDebugCleaner
        ? _debugCleanerVideoViews()
        : _debugClientVideoViews();
  }

  Stream<Map<String, dynamic>?> _debugSharedCleanerProfileStream() {
    final cleanerId = _uidOrNull ?? 'cleaner_demo';
    return Stream.multi((controller) {
      Map<String, dynamic>? remoteCleaner;
      List<Map<String, dynamic>> sharedSlots = _mergeDebugCleanerSlots(
        const [],
      );
      List<Map<String, dynamic>> sharedPayouts = _debugCleanerPayouts();

      void emit() {
        final sharedOrders = _mergeDebugCleanerOrders(sharedSlots);
        final base = _buildDebugCleanerProfile(
          slotsOverride: sharedSlots,
          ordersOverride: sharedOrders,
          payoutsOverride: sharedPayouts,
        );
        controller.add({
          ...base,
          ...remoteCleaner ?? const <String, dynamic>{},
          'id': cleanerId,
        });
      }

      final cleanerSub = _db
          .collection('debug_bridge_cleaners')
          .doc(cleanerId)
          .snapshots()
          .listen((doc) {
        remoteCleaner = doc.data();
        emit();
      });
      final slotsSub = _debugSharedCleanerSlotsStream().listen((items) {
        sharedSlots = items;
        emit();
      });
      final payoutsSub = _debugSharedCleanerPayoutsStream().listen((items) {
        sharedPayouts = items;
        emit();
      });

      emit();
      controller.onCancel = () async {
        await cleanerSub.cancel();
        await slotsSub.cancel();
        await payoutsSub.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedAdminCleanersStream() {
    return _db.collection('debug_bridge_cleaners').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = <String, Map<String, dynamic>>{};
      for (final item in [..._debugAdminCleaners(), ...remote]) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
        };
      }
      return merged.values.toList();
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedClustersStream() {
    return _db.collection('debug_bridge_clusters').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = <String, Map<String, dynamic>>{};
      for (final item in [..._debugClusters(), ...remote]) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
        };
      }
      final items = merged.values.toList()
        ..sort(
          (a, b) => (a['name'] ?? a['id']).toString().compareTo(
                (b['name'] ?? b['id']).toString(),
              ),
        );
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedServiceZonesStream() {
    return _db.collection('debug_bridge_service_zones').snapshots().map((snap) {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final merged = <String, Map<String, dynamic>>{};
      for (final item in [..._debugServiceZones(), ...remote]) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
        };
      }
      final items = merged.values.toList()
        ..sort(
          (a, b) => (a['title'] ?? a['id']).toString().compareTo(
                (b['title'] ?? b['id']).toString(),
              ),
        );
      return items;
    });
  }

  Stream<List<Map<String, dynamic>>> chatMessagesStream(String orderId) {
    if (_isDebugCustomer || _isDebugCleaner) {
      return Stream.multi((controller) {
        var canAccess = false;
        List<Map<String, dynamic>> messages = const <Map<String, dynamic>>[];

        void emit() => controller.add(canAccess ? messages : const []);

        final accessSub = _debugCanAccessOrderStream(orderId).listen((value) {
          canAccess = value;
          emit();
        });
        final messagesSub = _debugSharedChatMessagesStream(orderId).listen((
          items,
        ) {
          messages = items;
          emit();
        });

        emit();
        controller.onCancel = () async {
          await accessSub.cancel();
          await messagesSub.cancel();
        };
      });
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      return Stream.multi((controller) {
        var canAccess = false;

        void emit() => controller.add(
              canAccess ? _temporaryChatMessages(orderId) : const [],
            );

        final accessSub = _temporaryCanAccessOrderStream(orderId).listen((
          value,
        ) {
          canAccess = value;
          emit();
        });
        final stateSub = _debugStateChanges.stream.listen((_) => emit());

        emit();
        controller.onCancel = () async {
          await accessSub.cancel();
          await stateSub.cancel();
        };
      });
    }
    return _backendPollingStream(() async {
      final chatId = await _backendChatIdForOrder(orderId, create: false);
      if (chatId == null) return const <Map<String, dynamic>>[];
      final items = await BackendApiService.instance.getList(
        '/chats/$chatId/messages',
      );
      return items.map(_mapBackendChatMessage).toList();
    });
  }

  Future<List<Map<String, dynamic>>> _loadChatMessagesViaCallable(
    String orderId,
  ) async {
    final chatId = await _backendChatIdForOrder(orderId, create: false);
    if (chatId == null) return const <Map<String, dynamic>>[];
    final items = await BackendApiService.instance.getList(
      '/chats/$chatId/messages',
    );
    return items.map(_mapBackendChatMessage).toList();
  }

  Future<String?> _backendChatIdForOrder(
    String orderId, {
    bool create = true,
  }) async {
    final chat = await _backendChatForOrder(orderId, create: create);
    return chat == null ? null : (chat['id'] ?? '').toString();
  }

  Future<Map<String, dynamic>?> _backendChatForOrder(
    String orderId, {
    bool create = true,
  }) async {
    final chats = await BackendApiService.instance.getList('/chats');
    for (final chat in chats) {
      if ((chat['order_id'] ?? chat['orderId'] ?? '').toString() == orderId) {
        return chat;
      }
    }
    if (!create) return null;
    final chat = await BackendApiService.instance.postMap(
      '/chats',
      body: {'type': 'order', 'orderId': orderId},
    );
    return chat;
  }

  Future<String?> _backendChatIdForComplaint(
    String complaintId, {
    bool create = true,
  }) async {
    final chats = await BackendApiService.instance.getList('/chats');
    for (final chat in chats) {
      if ((chat['complaint_id'] ?? chat['complaintId'] ?? '').toString() ==
          complaintId) {
        return (chat['id'] ?? '').toString();
      }
    }
    if (!create) return null;
    final chat = await BackendApiService.instance.postMap(
      '/chats',
      body: {'type': 'complaint', 'complaintId': complaintId},
    );
    return (chat['id'] ?? '').toString();
  }

  Map<String, dynamic> _mapBackendChatSummary(Map<String, dynamic> item) {
    final orderId = (item['order_id'] ?? item['orderId'] ?? '').toString();
    final complaintId =
        (item['complaint_id'] ?? item['complaintId'] ?? '').toString();
    final chatId = (item['id'] ?? '').toString();
    final targetId = orderId.isNotEmpty ? orderId : chatId;
    return {
      'id': targetId,
      'chatId': chatId,
      'orderId': orderId.isNotEmpty ? orderId : targetId,
      'complaintId': complaintId,
      'type': item['type'] ?? (complaintId.isNotEmpty ? 'complaint' : 'order'),
      'unreadCount': item['unread_count'] ?? item['unreadCount'] ?? 0,
      'messageCount': item['message_count'] ?? item['messageCount'] ?? 0,
      'lastMessageAt': item['last_message_at'] ?? item['lastMessageAt'],
      'updatedAt':
          item['last_message_at'] ?? item['updated_at'] ?? item['created_at'],
      'createdAt': item['created_at'],
      'participants': item['participants'] ?? const [],
    };
  }

  Map<String, dynamic> _mapBackendChatMessage(Map<String, dynamic> item) {
    final normalized = {
      'id': item['id'],
      'chatId': item['chat_id'],
      'senderId': item['sender_id'],
      'senderRole': item['sender_role'],
      'senderName': item['sender_name'],
      'senderPhone': item['sender_phone'],
      'text': item['message_ru'] ?? item['message'] ?? '',
      'message': item['message_ru'] ?? item['message'] ?? '',
      'fileUrl': item['file_url'],
      'type': item['file_url'] == null ? 'text' : 'file',
      'createdAt': item['created_at'],
      'updatedAt': item['updated_at'],
    };
    return _normalizeChatMessage(normalized);
  }

  Map<String, dynamic> _normalizeChatMessage(Map<String, dynamic> item) {
    final normalized = Map<String, dynamic>.from(item);
    final createdAt = normalized['createdAt'];
    final createdAtMillis = normalized['createdAtMillis'];
    if (createdAt is! Timestamp &&
        createdAtMillis is num &&
        createdAtMillis > 0) {
      normalized['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(
        createdAtMillis.toInt(),
      );
    } else if (createdAt is String) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) {
        normalized['createdAt'] = Timestamp.fromDate(parsed);
      }
    }
    return normalized;
  }

  Future<String> sendChatMessage({
    required String orderId,
    required String senderId,
    required String senderRole,
    required String text,
  }) async {
    if (_isDebugCustomer || _isDebugCleaner) {
      if (!await _debugCanAccessOrder(orderId)) {
        return orderId;
      }
      final now = Timestamp.now();
      await _db
          .collection('debug_bridge_chat_messages')
          .doc('debug_chat_message_${now.millisecondsSinceEpoch}')
          .set({
        'orderId': orderId,
        'senderId': senderId,
        'senderRole': senderRole,
        'text': text,
        'type': 'text',
        'createdAt': now,
        'readBy': [senderId],
      });
      _notifyDebugStateChanged();
      return orderId;
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return orderId;
      }
      final now = Timestamp.now();
      final messages = _temporaryChatMessages(orderId);
      messages.add({
        'id': 'temp_chat_message_${now.millisecondsSinceEpoch}',
        'orderId': orderId,
        'senderId': senderId,
        'senderRole': senderRole,
        'text': text,
        'type': 'text',
        'createdAt': now,
        'readBy': [senderId],
      });
      _notifyDebugStateChanged();
      return orderId;
    }
    final chatId = await _backendChatIdForOrder(orderId);
    if (chatId == null || chatId.isEmpty) return orderId;
    await BackendApiService.instance.postMap(
      '/chats/$chatId/messages',
      body: {'message': text},
    );
    return orderId;
  }

  Future<String> createOrOpenOrderChat({required String orderId}) async {
    if (_isDebugCustomer || _isDebugCleaner) {
      if (!await _debugCanAccessOrder(orderId)) {
        return orderId;
      }
      _debugChatMessages(orderId);
      _notifyDebugStateChanged();
      return orderId;
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return orderId;
      }
      _temporaryChatMessages(orderId);
      _notifyDebugStateChanged();
      return orderId;
    }
    await _backendChatIdForOrder(orderId);
    return orderId;
  }

  Future<String> createOrOpenComplaintChat({
    required String complaintId,
  }) async {
    if (_isDebugAdmin) {
      final chatId = 'complaint_$complaintId';
      _debugChatMessages(chatId);
      _notifyDebugStateChanged();
      return chatId;
    }
    final chatId = await _backendChatIdForComplaint(complaintId);
    return chatId ?? 'complaint_$complaintId';
  }

  Future<String> markChatAsRead({required String orderId}) async {
    if (_isDebugCustomer || _isDebugCleaner) {
      if (!await _debugCanAccessOrder(orderId)) {
        return orderId;
      }
      final currentUserId = _uidOrNull;
      if (currentUserId == null) {
        return orderId;
      }
      final snap = await _db
          .collection('debug_bridge_chat_messages')
          .where('orderId', isEqualTo: orderId)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        final next = Map<String, dynamic>.from(doc.data());
        final readBy = ((next['readBy'] ?? const []) as List)
            .map((item) => item.toString())
            .toSet();
        readBy.add(currentUserId);
        batch.set(
            doc.reference,
            {
              'readBy': readBy.toList(),
            },
            SetOptions(merge: true));
      }
      if (snap.docs.isNotEmpty) {
        await batch.commit();
      }
      _notifyDebugStateChanged();
      return orderId;
    }
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return orderId;
      }
      final currentUserId = _uidOrNull;
      if (currentUserId == null) {
        return orderId;
      }
      final messages = _temporaryChatMessages(orderId);
      for (var i = 0; i < messages.length; i++) {
        final next = Map<String, dynamic>.from(messages[i]);
        final readBy = ((next['readBy'] ?? const []) as List)
            .map((item) => item.toString())
            .toSet();
        readBy.add(currentUserId);
        next['readBy'] = readBy.toList();
        messages[i] = next;
      }
      _notifyDebugStateChanged();
      return orderId;
    }
    final chatId = await _backendChatIdForOrder(orderId, create: false);
    if (chatId != null && chatId.isNotEmpty) {
      await BackendApiService.instance.postMap('/chats/$chatId/read');
    }
    return orderId;
  }

  Future<void> submitComplaint({
    required String orderId,
    required String customerId,
    required String text,
    String? photoUrl,
    List<String> photoUrls = const [],
  }) async {
    final normalizedPhotoUrls = photoUrls
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(5)
        .toList();
    if (_isDebugCustomer) {
      if (!await _debugCanAccessOrder(orderId)) {
        return;
      }
      final complaints = _debugComplaints()
        ..insert(0, {
          'id': 'debug_complaint_${DateTime.now().millisecondsSinceEpoch}',
          'orderId': orderId,
          'customerId': customerId,
          'text': text,
          'photoUrl': photoUrl,
          'photoUrls': normalizedPhotoUrls,
          'status': 'open',
          'createdAt': Timestamp.now(),
        });
      _debugComplaintsState = complaints;
      _notifyDebugStateChanged();
      try {
        await _db
            .collection('debug_bridge_complaints')
            .doc('debug_${customerId}_$orderId')
            .set({
          'sourceDebugUid': _uidOrNull ?? 'customer_demo',
          'orderId': orderId,
          'customerId': customerId,
          'text': text,
          'photoUrl': photoUrl,
          'photoUrls': normalizedPhotoUrls,
          'status': 'open',
          'createdAt': Timestamp.now(),
        });
      } catch (_) {
        // Shared debug bridge is best-effort; local flow must still work.
      }
      return;
    }
    if (_isTemporaryCustomerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return;
      }
      final complaints = _debugComplaints()
        ..insert(0, {
          'id': 'temp_complaint_${DateTime.now().millisecondsSinceEpoch}',
          'orderId': orderId,
          'customerId': customerId,
          'text': text,
          'photoUrl': photoUrl,
          'photoUrls': normalizedPhotoUrls,
          'status': 'open',
          'createdAt': Timestamp.now(),
        });
      _debugComplaintsState = complaints;
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/complaints',
      body: {
        'orderId': orderId,
        'title': text.isEmpty ? 'Жалоба по заказу' : text,
        'body': text,
        'photoUrl': photoUrl,
        'photoUrls': normalizedPhotoUrls,
      },
    );
  }

  Future<void> uploadPhotoReport({
    required String orderId,
    required String cleanerId,
    required List<String> photoUrls,
  }) async {
    if (_isDebugCleaner) {
      if (!await _debugCanAccessOrder(orderId)) {
        return;
      }
      final payload = {
        'orderId': orderId,
        'cleanerId': cleanerId,
        'photoUrls': photoUrls,
        'createdAt': Timestamp.now(),
      };
      _debugPhotoReportsState.add(payload);
      await _db
          .collection('debug_bridge_photo_reports')
          .doc(orderId)
          .set(payload, SetOptions(merge: true));
      await _db.collection('debug_bridge_orders').doc(orderId).set({
        'photoUrls': photoUrls,
        'photoReportSubmittedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      await _db.collection('debug_bridge_cleaner_slots').doc(orderId).set({
        'photoUrls': photoUrls,
        'photoReportSubmittedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    if (_isTemporaryCleanerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return;
      }
      _debugPhotoReportsState.add({
        'orderId': orderId,
        'cleanerId': cleanerId,
        'photoUrls': photoUrls,
        'createdAt': Timestamp.now(),
      });
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/orders/$orderId/photo-report',
      body: {'cleanerId': cleanerId, 'photoUrls': photoUrls},
    );
  }

  Future<void> saveCleanerChecklist({
    required String orderId,
    required List<String> completedTasks,
    required List<String> addons,
    List<String> orderedAddons = const [],
    List<Map<String, dynamic>> addonsDetailed = const [],
    String? note,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      throw StateError('Не найден ID заказа для чек-листа.');
    }
    if (_isDebugCleaner) {
      if (!await _debugCanAccessOrder(normalizedOrderId)) {
        throw StateError('Нет доступа к этому заказу для чек-листа.');
      }
      final payload = {
        'orderId': normalizedOrderId,
        'cleanerId': _uidOrNull ?? 'cleaner_demo',
        'completedTasks': completedTasks,
        'addons': addons,
        'orderedAddons': orderedAddons,
        'addonsDetailed': addonsDetailed,
        'note': note,
        'completedAt': Timestamp.now(),
      };
      _debugCleanerChecklistState[normalizedOrderId] = payload;
      await _db
          .collection('debug_bridge_cleaner_checklists')
          .doc(normalizedOrderId)
          .set(payload, SetOptions(merge: true));
      _addLocalCustomerChecklistNotification(normalizedOrderId);
      _notifyDebugStateChanged();
      return;
    }
    if (_isTemporaryCleanerSession) {
      if (!await _temporaryCanAccessOrder(normalizedOrderId)) {
        throw StateError('Нет доступа к этому заказу для чек-листа.');
      }
      _debugCleanerChecklistState[normalizedOrderId] = {
        'orderId': normalizedOrderId,
        'cleanerId': _uidOrNull ?? 'temp_cleaner',
        'completedTasks': completedTasks,
        'addons': addons,
        'orderedAddons': orderedAddons,
        'addonsDetailed': addonsDetailed,
        'note': note,
        'completedAt': Timestamp.now(),
      };
      _addLocalCustomerChecklistNotification(normalizedOrderId);
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/orders/$normalizedOrderId/checklist',
      body: {
        'completedTasks': completedTasks,
        'addons': addons,
        'orderedAddons': orderedAddons,
        'addonsDetailed': addonsDetailed,
        'note': note,
      },
    );
  }

  void _addLocalCustomerChecklistNotification(String orderId) {
    final notifications = [..._debugNotifications()];
    notifications.insert(0, {
      'id': 'checklist_${orderId}_${DateTime.now().millisecondsSinceEpoch}',
      'userId': 'customer_demo',
      'type': 'cleaner_checklist_completed',
      'title': 'Чек-лист уборки заполнен',
      'body': 'Уборщица отметила выполненные пункты по заказу.',
      'payload': {'orderId': orderId, 'route': '/client/orders'},
      'read': false,
      'createdAt': Timestamp.now(),
    });
    _debugNotificationsState = notifications;
  }

  Future<void> submitReview({
    required String orderId,
    required int rating,
    required String text,
    List<String> positiveTraits = const [],
    List<String> negativeTraits = const [],
    String? photoUrl,
  }) async {
    if (_isDebugCustomer) {
      if (!await _debugCanAccessOrder(orderId)) {
        return;
      }
      final reviews = _debugReviews()
        ..removeWhere(
          (item) => item['orderId'] == orderId || item['id'] == orderId,
        )
        ..insert(0, {
          'id': orderId,
          'orderId': orderId,
          'customerId': _uidOrNull ?? 'customer_demo',
          'rating': rating,
          'text': text,
          'positiveTraits': positiveTraits,
          'negativeTraits': negativeTraits,
          'photoUrl': photoUrl,
          'createdAt': Timestamp.now(),
        });
      _debugReviewsState = reviews;
      _notifyDebugStateChanged();
      try {
        await _db.collection('debug_bridge_reviews').doc(orderId).set({
          'sourceDebugUid': _uidOrNull ?? 'customer_demo',
          'orderId': orderId,
          'customerId': _uidOrNull ?? 'customer_demo',
          'rating': rating,
          'text': text,
          'positiveTraits': positiveTraits,
          'negativeTraits': negativeTraits,
          'photoUrl': photoUrl,
          'createdAt': Timestamp.now(),
        });
      } catch (_) {
        // Shared debug bridge is best-effort; local flow must still work.
      }
      return;
    }
    if (_isTemporaryCustomerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return;
      }
      final reviews = _debugReviews()
        ..removeWhere(
          (item) => item['orderId'] == orderId || item['id'] == orderId,
        )
        ..insert(0, {
          'id': orderId,
          'orderId': orderId,
          'customerId': _uidOrNull ?? 'temp_customer',
          'rating': rating,
          'text': text,
          'positiveTraits': positiveTraits,
          'negativeTraits': negativeTraits,
          'photoUrl': photoUrl,
          'createdAt': Timestamp.now(),
        });
      _debugReviewsState = reviews;
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/reviews',
      body: {
        'orderId': orderId,
        'rating': rating,
        'comment': text,
        'positiveTraits': positiveTraits,
        'negativeTraits': negativeTraits,
        'photoUrl': photoUrl,
      },
    );
  }

  Future<void> submitCustomerReview({
    required String orderId,
    required int rating,
    String text = '',
  }) async {
    final normalizedRating = rating.clamp(1, 5);
    if (_isDebugCleaner || _isTemporaryCleanerSession) {
      final now = Timestamp.now();
      await _db.collection('debug_bridge_customer_reviews').doc(orderId).set({
        'id': orderId,
        'orderId': orderId,
        'cleanerId': _uidOrNull ?? 'cleaner_demo',
        'rating': normalizedRating,
        'text': text.trim(),
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
      return;
    }
    await BackendApiService.instance.postMap(
      '/reviews',
      body: {
        'orderId': orderId,
        'rating': normalizedRating,
        'comment': text.trim(),
      },
    );
  }

  Stream<List<Map<String, dynamic>>> complaintsStream({bool admin = false}) {
    if (_isDebugAdmin) {
      return _debugSharedComplaintsStream();
    }
    if (_isDebugCustomer) {
      return _debugSharedCustomerComplaintsStream();
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(() {
        final complaints = _debugComplaints();
        final ownedOrderIds = _temporaryCustomerOrders()
            .map((item) => (item['id'] ?? item['orderId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        final customerId = _uidOrNull ?? '';
        return complaints.where((item) {
          final orderId = (item['orderId'] ?? '').toString();
          final itemCustomerId = (item['customerId'] ?? '').toString();
          return ownedOrderIds.contains(orderId) &&
              (itemCustomerId.isEmpty || itemCustomerId == customerId);
        }).toList()
          ..sort((a, b) {
            final aMs = _timestampMillis(a['createdAt']);
            final bMs = _timestampMillis(b['createdAt']);
            return bMs.compareTo(aMs);
          });
      });
    }
    return _backendPollingStream(() async {
      return (await BackendApiService.instance
              .getList(admin ? '/admin/complaints' : '/complaints'))
          .map((
        item,
      ) {
        return {
          'id': item['id'],
          'orderId': item['order_id'],
          'customerId': item['customer_id'],
          'cleanerId': item['cleaner_id'],
          'text': item['body'] ?? item['title'] ?? '',
          'title': item['title'],
          'photoUrls': item['photo_urls'] ?? const [],
          'status': item['status'],
          'createdAt': item['created_at'],
          'updatedAt': item['updated_at'],
        };
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> reviewsStream() {
    if (_isDebugAdmin) {
      return _debugSharedReviewsStream();
    }
    if (_isDebugCustomer) {
      return _debugSharedCustomerReviewsStream();
    }
    if (_isTemporaryCustomerSession) {
      return _debugSnapshotStream(() {
        final reviews = _debugReviews();
        final ownedOrderIds = _temporaryCustomerOrders()
            .map((item) => (item['id'] ?? item['orderId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        final customerId = _uidOrNull ?? '';
        return reviews.where((item) {
          final orderId = (item['orderId'] ?? item['id'] ?? '').toString();
          final itemCustomerId = (item['customerId'] ?? '').toString();
          return ownedOrderIds.contains(orderId) &&
              (itemCustomerId.isEmpty || itemCustomerId == customerId);
        }).toList()
          ..sort((a, b) {
            final aMs = _timestampMillis(a['createdAt']);
            final bMs = _timestampMillis(b['createdAt']);
            return bMs.compareTo(aMs);
          });
      });
    }
    return _backendPollingStream(() async {
      return (await BackendApiService.instance.getList('/reviews')).map((item) {
        return {
          'id': item['id'],
          'orderId': item['order_id'],
          'customerId': item['customer_id'],
          'cleanerId': item['cleaner_id'],
          'rating': _num(item['rating']).toInt(),
          'photoUrl': item['photo_url'],
          'authorRole': item['author_role'] ?? 'customer',
          'positiveTraits': item['positive_traits'] ?? const [],
          'negativeTraits': item['negative_traits'] ?? const [],
          'text': item['comment'] ?? '',
          'customerName': item['customer_name'],
          'customerPhone': item['customer_phone'],
          'cleanerName': item['cleaner_name'],
          'cleanerPhone': item['cleaner_phone'],
          'createdAt': item['created_at'],
        };
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> adminReviewsStream() {
    if (_isDebugAdmin) {
      return _combineLatestLists(
        _debugSharedReviewsStream(),
        _debugSharedOrdersStream(),
        _enrichReviewsWithOrders,
      );
    }
    return _combineLatestLists(
      _backendPollingStream(() async {
        return (await BackendApiService.instance.getList('/admin/reviews')).map(
          (item) {
            return {
              'id': item['id'],
              'orderId': item['order_id'],
              'customerId': item['customer_id'],
              'cleanerId': item['cleaner_id'],
              'rating': _num(item['rating']).toInt(),
              'photoUrl': item['photo_url'],
              'authorRole': item['author_role'] ?? 'customer',
              'positiveTraits': item['positive_traits'] ?? const [],
              'negativeTraits': item['negative_traits'] ?? const [],
              'text': item['comment'] ?? '',
              'customerName': item['customer_name'],
              'customerPhone': item['customer_phone'],
              'cleanerName': item['cleaner_name'],
              'cleanerPhone': item['cleaner_phone'],
              'createdAt': item['created_at'],
            };
          },
        ).toList();
      }),
      adminOrdersStream(),
      _enrichReviewsWithOrders,
    );
  }

  List<Map<String, dynamic>> _enrichReviewsWithOrders(
    List<Map<String, dynamic>> reviews,
    List<Map<String, dynamic>> orders,
  ) {
    final ordersById = <String, Map<String, dynamic>>{};
    for (final order in orders) {
      final id = (order['id'] ?? order['orderId'] ?? '').toString().trim();
      if (id.isNotEmpty) {
        ordersById[id] = order;
      }
    }
    return reviews.map((review) {
      final orderId = (review['orderId'] ?? review['id'] ?? '').toString();
      final order = ordersById[orderId] ?? const <String, dynamic>{};
      return {
        ...order,
        ...review,
        'id': review['id'] ?? orderId,
        'orderId': orderId,
        'customerId': review['customerId'] ?? order['customerId'],
        'cleanerId': review['cleanerId'] ?? order['cleanerId'],
        'customerName': review['customerName'] ?? order['customerName'],
        'customerPhone': review['customerPhone'] ?? order['customerPhone'],
        'cleanerName': review['cleanerName'] ?? order['cleanerName'],
        'cleanerPhone': review['cleanerPhone'] ?? order['cleanerPhone'],
        'orderAddress': order['address'] ?? order['houseAddress'],
        'orderDate': order['scheduledDate'] ?? order['date'],
        'orderTime': order['time'],
      };
    }).toList()
      ..sort(
        (a, b) => _timestampMillis(
          b['createdAt'],
        ).compareTo(_timestampMillis(a['createdAt'])),
      );
  }

  Stream<List<Map<String, dynamic>>> reviewsForCleanerStream() {
    final uid = _uidOrNull;
    if (uid == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    if (_isDebugCleaner) {
      return _debugSharedCleanerOrdersStream().asyncMap((orders) async {
        final reviews = await _debugSharedReviewsStream().first;
        final orderIds = <String>{};
        for (final order in orders) {
          final id = (order['customerOrderId'] ??
                  order['orderId'] ??
                  order['id'] ??
                  '')
              .toString();
          if (id.isNotEmpty) {
            orderIds.add(id);
          }
        }
        return reviews
            .where(
              (review) => orderIds.contains(
                (review['orderId'] ?? review['id'] ?? '').toString(),
              ),
            )
            .toList()
          ..sort((a, b) {
            final da = _reviewDate(b);
            final db_ = _reviewDate(a);
            return da.compareTo(db_);
          });
      });
    }
    if (_isTemporaryCleanerSession) {
      return _debugSnapshotStream(() {
        final reviews = _debugReviews();
        final orderIds = _temporaryCleanerOrders()
            .map(
              (item) => (item['customerOrderId'] ??
                      item['orderId'] ??
                      item['id'] ??
                      '')
                  .toString(),
            )
            .where((id) => id.isNotEmpty)
            .toSet();
        return reviews
            .where(
              (review) => orderIds.contains(
                (review['orderId'] ?? review['id'] ?? '').toString(),
              ),
            )
            .toList()
          ..sort((a, b) {
            final da = _reviewDate(b);
            final db_ = _reviewDate(a);
            return da.compareTo(db_);
          });
      });
    }
    return _backendPollingStream(() async {
      return (await BackendApiService.instance.getList('/reviews')).map((item) {
        return {
          'id': item['id'],
          'orderId': item['order_id'],
          'customerId': item['customer_id'],
          'cleanerId': item['cleaner_id'],
          'rating': _num(item['rating']).toInt(),
          'photoUrl': item['photo_url'],
          'authorRole': item['author_role'] ?? 'customer',
          'positiveTraits': item['positive_traits'] ?? const [],
          'negativeTraits': item['negative_traits'] ?? const [],
          'text': item['comment'] ?? '',
          'customerName': item['customer_name'],
          'customerPhone': item['customer_phone'],
          'createdAt': item['created_at'],
        };
      }).toList()
        ..sort((a, b) {
          final da = _reviewDate(b);
          final db_ = _reviewDate(a);
          return da.compareTo(db_);
        });
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedComplaintsStream() {
    return _db
        .collection('debug_bridge_complaints')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snap) async {
      final remote = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      await _applyDebugComplaintBridgeActionIfNeeded(remote);
      return _mergeDebugComplaints(remote);
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCustomerComplaintsStream() {
    return Stream.multi((controller) {
      List<Map<String, dynamic>> complaints = const <Map<String, dynamic>>[];
      Set<String> ownedOrderIds = const <String>{};
      final customerId = _uidOrNull ?? 'customer_demo';

      void emit() {
        controller.add(
          complaints.where((item) {
            final orderId = (item['orderId'] ?? '').toString();
            final itemCustomerId = (item['customerId'] ?? '').toString();
            return ownedOrderIds.contains(orderId) &&
                (itemCustomerId.isEmpty || itemCustomerId == customerId);
          }).toList(),
        );
      }

      final complaintsSub = _debugSharedComplaintsStream().listen((items) {
        complaints = items;
        emit();
      });
      final ordersSub = _debugSharedCustomerOrdersStream().listen((items) {
        ownedOrderIds = items
            .map((item) => (item['id'] ?? item['orderId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        emit();
      });

      emit();
      controller.onCancel = () async {
        await complaintsSub.cancel();
        await ordersSub.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> _debugSharedReviewsStream() {
    return _db
        .collection('debug_bridge_reviews')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => _mergeDebugReviews(
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
          ),
        );
  }

  Stream<List<Map<String, dynamic>>> _debugSharedCustomerReviewsStream() {
    return Stream.multi((controller) {
      List<Map<String, dynamic>> reviews = const <Map<String, dynamic>>[];
      Set<String> ownedOrderIds = const <String>{};
      final customerId = _uidOrNull ?? 'customer_demo';

      void emit() {
        controller.add(
          reviews.where((item) {
            final orderId = (item['orderId'] ?? item['id'] ?? '').toString();
            final itemCustomerId = (item['customerId'] ?? '').toString();
            return ownedOrderIds.contains(orderId) &&
                (itemCustomerId.isEmpty || itemCustomerId == customerId);
          }).toList(),
        );
      }

      final reviewsSub = _debugSharedReviewsStream().listen((items) {
        reviews = items;
        emit();
      });
      final ordersSub = _debugSharedCustomerOrdersStream().listen((items) {
        ownedOrderIds = items
            .map((item) => (item['id'] ?? item['orderId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        emit();
      });

      emit();
      controller.onCancel = () async {
        await reviewsSub.cancel();
        await ordersSub.cancel();
      };
    });
  }

  List<Map<String, dynamic>> _mergeDebugComplaints(
    List<Map<String, dynamic>> remote,
  ) {
    final local = List<Map<String, dynamic>>.from(_debugComplaints());
    final merged = <String, Map<String, dynamic>>{};
    final bridgeKeys = <String, String>{};
    for (final item in [...local, ...remote]) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final sourceDebugUid = (item['sourceDebugUid'] ?? '').toString();
      if (sourceDebugUid.isNotEmpty) {
        final bridgeKey = [
          sourceDebugUid,
          (item['customerId'] ?? '').toString(),
          (item['orderId'] ?? '').toString(),
        ].join('|');
        final existingId = bridgeKeys[bridgeKey];
        if (existingId != null) {
          final existing = merged[existingId];
          final existingMs =
              existing == null ? 0 : _timestampMillis(existing['createdAt']);
          final currentMs = _timestampMillis(item['createdAt']);
          if (currentMs >= existingMs) {
            merged.remove(existingId);
            merged[id] = item;
            bridgeKeys[bridgeKey] = id;
          }
          continue;
        }
        bridgeKeys[bridgeKey] = id;
      }
      merged[id] = item;
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final aMs = _timestampMillis(a['createdAt']);
      final bMs = _timestampMillis(b['createdAt']);
      return bMs.compareTo(aMs);
    });
    return items;
  }

  Future<void> _applyDebugComplaintBridgeActionIfNeeded(
    List<Map<String, dynamic>> remote,
  ) async {
    if (!_isDebugAdmin) {
      return;
    }
    final action = DebugSession.value('debug_action')?.trim();
    final complaintId = DebugSession.value('debug_complaint_id')?.trim();
    final status = DebugSession.value(
      'debug_complaint_status',
    )?.trim().toLowerCase();
    if (action != 'resolve_complaint' ||
        complaintId == null ||
        complaintId.isEmpty ||
        status == null ||
        status.isEmpty ||
        complaintId.startsWith('debug_complaint_seed_')) {
      return;
    }
    Map<String, dynamic>? target;
    for (final item in remote) {
      if (item['id'] == complaintId) {
        target = item;
        break;
      }
    }
    if (target == null) {
      return;
    }
    if ((target['status'] ?? 'open').toString() == status) {
      return;
    }
    try {
      await _db.collection('debug_bridge_complaints').doc(complaintId).set({
        'status': status,
        'resolution': status == 'compensated'
            ? 'Компенсация клиенту'
            : status == 'refund'
                ? 'Полный возврат'
                : 'Жалоба закрыта',
        'compensationAmount': status == 'compensated' ? 5000 : 0,
        'resolvedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore in debug mode; the UI can still apply a local override.
    }
  }

  List<Map<String, dynamic>> _mergeDebugReviews(
    List<Map<String, dynamic>> remote,
  ) {
    final local = List<Map<String, dynamic>>.from(_debugReviews());
    final merged = <String, Map<String, dynamic>>{};
    for (final item in [...local, ...remote]) {
      final id = (item['id'] ?? item['orderId'] ?? '').toString();
      if (id.isEmpty) continue;
      merged[id] = item;
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final aMs = _timestampMillis(a['createdAt']);
      final bMs = _timestampMillis(b['createdAt']);
      return bMs.compareTo(aMs);
    });
    return items;
  }

  static DateTime _reviewDate(Map<String, dynamic> review) {
    final value = review['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  Stream<Map<String, dynamic>?> cleanerChecklistStream(String orderId) {
    if (_isDebugCleaner) {
      return Stream.multi((controller) {
        var canAccess = false;
        Map<String, dynamic>? checklist;

        void emit() => controller.add(canAccess ? checklist : null);

        final accessSub = _debugCanAccessOrderStream(orderId).listen((value) {
          canAccess = value;
          emit();
        });
        final checklistSub = _db
            .collection('debug_bridge_cleaner_checklists')
            .doc(orderId)
            .snapshots()
            .listen((doc) {
          final remote = doc.data();
          if (remote != null) {
            checklist = {'id': doc.id, ...remote};
          } else {
            final local = _debugCleanerChecklistState[orderId];
            checklist = local == null ? null : {'id': orderId, ...local};
          }
          emit();
        });

        emit();
        controller.onCancel = () async {
          await accessSub.cancel();
          await checklistSub.cancel();
        };
      });
    }
    if (_isTemporaryCleanerSession) {
      return Stream.multi((controller) {
        var canAccess = false;

        void emit() {
          final local = _debugCleanerChecklistState[orderId];
          controller.add(
            canAccess && local != null ? {'id': orderId, ...local} : null,
          );
        }

        final accessSub = _temporaryCanAccessOrderStream(orderId).listen((
          value,
        ) {
          canAccess = value;
          emit();
        });
        final stateSub = _debugStateChanges.stream.listen((_) => emit());

        emit();
        controller.onCancel = () async {
          await accessSub.cancel();
          await stateSub.cancel();
        };
      });
    }
    return _backendPollingStream(() async {
      final data = await BackendApiService.instance.getMap(
        '/orders/$orderId/checklist',
      );
      final report = Map<String, dynamic>.from(
        (data['report'] as Map?) ?? const <String, dynamic>{},
      );
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (report.isEmpty && items.isEmpty) {
        return null;
      }
      return {'id': orderId, ...report, 'items': items};
    });
  }

  Stream<Map<String, dynamic>?> cleanerChecklistForOrderIdsStream(
    Iterable<String> orderIds,
  ) {
    final ids = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != 'null')
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return Stream.value(null);
    }
    if (ids.length == 1) {
      return cleanerChecklistStream(ids.first).map((data) {
        if (data == null) return null;
        return {'id': ids.first, ...data};
      });
    }
    return Stream.multi((controller) {
      final values = <String, Map<String, dynamic>?>{};
      final subscriptions = <StreamSubscription<Map<String, dynamic>?>>[];

      void emit() {
        for (final id in ids) {
          final data = values[id];
          if (data != null) {
            controller.add({'id': id, ...data});
            return;
          }
        }
        controller.add(null);
      }

      for (final id in ids) {
        subscriptions.add(
          cleanerChecklistStream(id).listen((data) {
            values[id] = data;
            emit();
          }, onError: controller.addError),
        );
      }

      emit();
      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  Future<void> requestWeeklyPayout({required String cleanerId}) async {
    if (_isDebugAdmin) {
      final now = DateTime.now();
      final effectiveCleanerId =
          cleanerId == 'all' ? 'cleaner_demo' : cleanerId;
      await _db
          .collection('debug_bridge_payouts')
          .doc(
            'debug_payout_${effectiveCleanerId}_${now.millisecondsSinceEpoch}',
          )
          .set({
        'cleanerId': effectiveCleanerId,
        'amount': 19200,
        'gross': 24000,
        'net': 19200,
        'tax': 4800,
        'status': 'pending',
        'weekId':
            '${now.year}-W${(((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).floor() + 1).toString().padLeft(2, '0')}',
        'createdAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/payouts',
      body: {'cleanerId': cleanerId, 'payoutType': 'weekly'},
    );
  }

  Future<void> _requestWeeklyPayoutDirect({required String cleanerId}) async {
    await BackendApiService.instance.postMap(
      '/admin/payouts',
      body: {'cleanerId': cleanerId, 'payoutType': 'weekly', 'amount': 0},
    );
  }

  Future<Map<String, dynamic>> requestCleanerCashout({
    required String payoutType,
    int? amount,
  }) async {
    if (_isDebugCleaner) {
      final cleanerId = _uidOrNull ?? 'cleaner_demo';
      final profile = _buildDebugCleanerProfile(
        slotsOverride: _debugCleanerScheduleSlots(),
        ordersOverride: _debugCleanerOrders(),
        payoutsOverride: _debugCleanerPayouts(),
      );
      final normalizedPayoutType = payoutType.trim().toLowerCase();
      final requestedAmount = amount ??
          (normalizedPayoutType == 'full'
              ? ((profile['availableFullCashoutAmount'] as num?)?.toInt() ?? 0)
              : ((profile['availableWeeklyCashoutAmount'] as num?)?.toInt() ??
                  (profile['availableWithdrawalAmount'] as num?)?.toInt() ??
                  0));
      final safeAmount = math.max(requestedAmount, 0);
      final now = DateTime.now();
      final payoutId =
          'debug_cashout_${cleanerId}_${now.millisecondsSinceEpoch}';
      await _db.collection('debug_bridge_payouts').doc(payoutId).set({
        'cleanerId': cleanerId,
        'amount': safeAmount,
        'gross': safeAmount,
        'net': safeAmount,
        'tax': 0,
        'status': 'pending',
        'payoutType': normalizedPayoutType,
        'createdAt': Timestamp.fromDate(now),
        'sourceDebugUid': cleanerId,
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'cleanerId': cleanerId,
        'payoutId': payoutId,
        'status': 'pending',
        'amount': safeAmount,
        'payoutType': normalizedPayoutType,
      };
    }
    if (_isTemporaryCleanerSession) {
      final cleanerId = _uidOrNull ?? 'temp_cleaner';
      final payouts = List<Map<String, dynamic>>.from(
        _temporaryCleanerPayouts(),
      );
      final normalizedPayoutType = payoutType.trim().toLowerCase();
      final safeAmount = math.max(amount ?? 0, 0);
      final now = DateTime.now();
      final payoutId =
          'temp_cashout_${cleanerId}_${now.millisecondsSinceEpoch}';
      payouts.insert(0, {
        'id': payoutId,
        'cleanerId': cleanerId,
        'amount': safeAmount,
        'gross': safeAmount,
        'net': safeAmount,
        'tax': 0,
        'status': 'pending',
        'payoutType': normalizedPayoutType,
        'createdAt': now.toIso8601String(),
      });
      debugStorageWrite(
        _debugStorageKey('cleaner_payouts'),
        jsonEncode(_jsonSafe(payouts)),
      );
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'cleanerId': cleanerId,
        'payoutId': payoutId,
        'status': 'pending',
        'amount': safeAmount,
        'payoutType': normalizedPayoutType,
        'localFallback': true,
      };
    }
    return BackendApiService.instance.postMap(
      '/payouts',
      body: {'payoutType': payoutType, 'amount': amount},
    );
  }

  Future<Map<String, dynamic>> requestCleanerManualPayout({
    required String kaspiPhone,
    required int amount,
  }) async {
    final normalizedPhone = kaspiPhone.trim();
    final safeAmount = amount;
    if (normalizedPhone.isEmpty) {
      throw StateError('Введите номер Kaspi.');
    }
    if (safeAmount <= 0) {
      throw StateError('Введите сумму вывода больше 0.');
    }

    final cleanerId = _uidOrNull ??
        (_isDebugCleaner
            ? 'cleaner_demo'
            : _isTemporaryCleanerSession
                ? 'temp_cleaner'
                : '');
    if (cleanerId.isEmpty) {
      throw StateError('Нужно войти как уборщица.');
    }

    final now = DateTime.now();
    final payoutId = 'manual_payout_${cleanerId}_${now.millisecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'cleanerId': cleanerId,
      'requestedBy': cleanerId,
      'amount': safeAmount,
      'gross': safeAmount,
      'net': safeAmount,
      'tax': 0,
      'status': 'pending',
      'payoutType': 'manual',
      'provider': 'kaspi_manual_request',
      'kaspiPhone': normalizedPhone,
      'currency': 'KZT',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'directWrite': true,
      'source': 'cleaner_profile',
    };

    if (_isDebugCleaner) {
      await _db.collection('debug_bridge_payouts').doc(payoutId).set({
        ...payload,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'sourceDebugUid': cleanerId,
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'cleanerId': cleanerId,
        'payoutId': payoutId,
        'status': 'pending',
        'amount': safeAmount,
      };
    }

    if (_isTemporaryCleanerSession) {
      final payouts = List<Map<String, dynamic>>.from(
        _temporaryCleanerPayouts(),
      );
      payouts.insert(0, {
        'id': payoutId,
        ...payload,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      debugStorageWrite(
        _debugStorageKey('cleaner_payouts'),
        jsonEncode(_jsonSafe(payouts)),
      );
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'cleanerId': cleanerId,
        'payoutId': payoutId,
        'status': 'pending',
        'amount': safeAmount,
        'localFallback': true,
      };
    }

    return BackendApiService.instance.postMap(
      '/payouts',
      body: {
        'payoutType': 'manual',
        'amount': safeAmount,
        'kaspiPhone': normalizedPhone,
      },
    );
  }

  Future<Map<String, dynamic>> reviewCleanerPayout({
    required String payoutId,
    required bool approved,
  }) async {
    final id = payoutId.trim();
    if (id.isEmpty) {
      throw StateError('Не передан payoutId.');
    }
    final status = approved ? 'approved' : 'rejected';
    final payload = <String, dynamic>{
      'status': status,
      'approved': approved,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _uidOrNull,
      'updatedAt': FieldValue.serverTimestamp(),
      if (approved) 'approvedAt': FieldValue.serverTimestamp(),
      if (!approved) 'rejectedAt': FieldValue.serverTimestamp(),
    };

    if (_isDebugAdmin) {
      await _db.collection('debug_bridge_payouts').doc(id).set({
        ...payload,
        'reviewedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        if (approved) 'approvedAt': Timestamp.now(),
        if (!approved) 'rejectedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return {'ok': true, 'payoutId': id, 'status': status};
    }

    final result = await BackendApiService.instance.patchMap(
      '/admin/payouts/$id',
      body: {'status': approved ? 'approved' : 'rejected'},
    );
    return {'ok': true, 'payoutId': id, 'status': status, 'payout': result};
  }

  Future<Map<String, dynamic>> evaluateCleanerStatus({
    String? cleanerId,
  }) async {
    if (_isTemporaryCleanerSession) {
      final profile = _temporaryCleanerProfile();
      return {
        'ok': true,
        'cleanerId': cleanerId ?? _uidOrNull,
        'verificationStatus':
            (profile['verificationStatus'] ?? 'pending').toString(),
        'status': (profile['status'] ?? 'active').toString(),
      };
    }
    final id = (cleanerId ?? _uidOrNull ?? '').trim();
    final data = id.isNotEmpty
        ? await BackendApiService.instance.getMap('/admin/cleaners/$id/details')
        : await BackendApiService.instance.getMap('/cleaner/profile');
    final cleaner = Map<String, dynamic>.from(
      (data['cleaner'] ?? data['user'] ?? data) as Map,
    );
    return {
      'ok': true,
      'cleanerId': id,
      'verificationStatus': (cleaner['verificationStatus'] ??
              cleaner['verification_status'] ??
              cleaner['status'] ??
              'pending')
          .toString(),
      'status': (cleaner['status'] ?? 'active').toString(),
      'profile': data,
    };
  }

  Future<Map<String, dynamic>> calculateDailySchedule({
    String? cleanerId,
    required DateTime date,
  }) async {
    if (_isDebugCleaner) {
      final sharedSlots = await _debugSharedCleanerSlotsStream().first;
      return _buildDailyScheduleSummary(sharedSlots, date);
    }
    if (_isTemporaryCleanerSession) {
      return _buildDailyScheduleSummary(_temporaryCleanerScheduleSlots(), date);
    }
    return _calculateDailyScheduleDirect(
      cleanerId: cleanerId ?? _uid,
      date: date,
    );
  }

  Future<Map<String, dynamic>> _calculateDailyScheduleDirect({
    required String cleanerId,
    required DateTime date,
  }) async {
    final sources = <Map<String, dynamic>>[];
    Future<void> addQuery(String collection) async {
      try {
        final snap = await _db
            .collection(collection)
            .where('cleanerId', isEqualTo: cleanerId)
            .get();
        sources.addAll(
          snap.docs.map(
            (doc) => {
              'id': doc.id,
              ...doc.data(),
              'sourceCollection': collection,
            },
          ),
        );
      } catch (_) {
        // A missing collection or denied optional source should not break calendar.
      }
    }

    await Future.wait([
      addQuery('schedule_slots'),
      addQuery('cleaner_orders'),
      addQuery('cleaner_shifts'),
    ]);
    return _buildDailyScheduleSummary(sources, date);
  }

  Map<String, dynamic> _buildDailyScheduleSummary(
    List<Map<String, dynamic>> sourceSlots,
    DateTime date,
  ) {
    final targetDate = DateTime(date.year, date.month, date.day);
    final merged = <String, Map<String, dynamic>>{};
    for (final slot in sourceSlots) {
      final id = (slot['id'] ??
              slot['sourceOrderId'] ??
              slot['customerOrderId'] ??
              slot['orderId'] ??
              '')
          .toString();
      if (id.isEmpty) {
        continue;
      }
      merged[id] = {
        ...merged[id] ?? const <String, dynamic>{},
        ...slot,
        'id': id,
      };
    }
    final slots = merged.values.where((slot) {
      final slotDate = _toDateTime(
        slot['scheduledFor'] ??
            slot['date'] ??
            slot['scheduledDateKey'] ??
            slot['createdAt'],
      );
      final status = (slot['status'] ?? '').toString().toLowerCase();
      return slotDate.year == targetDate.year &&
          slotDate.month == targetDate.month &&
          slotDate.day == targetDate.day &&
          status != 'completed' &&
          status != 'cancelled' &&
          status != 'canceled';
    }).toList()
      ..sort(
        (a, b) => _toDateTime(
          a['scheduledFor'] ?? a['date'],
        ).compareTo(_toDateTime(b['scheduledFor'] ?? b['date'])),
      );
    final occupiedMinutes = slots.fold<int>(
      0,
      (totalMinutes, slot) => totalMinutes + _scheduleSlotDurationMinutes(slot),
    );
    final totalArea = slots.fold<int>(
      0,
      (total, slot) => total + ((slot['area'] as num?)?.toInt() ?? 0),
    );
    final totalAddonCount = slots.fold<int>(
      0,
      (total, slot) =>
          total +
          (((slot['addonsDetailed'] as List?)?.length) ??
              ((slot['addons'] as List?)?.length) ??
              0),
    );
    return {
      'summary': {
        'occupiedHours': (occupiedMinutes / 60).toStringAsFixed(1),
        'limitHours': 8.5,
        'remainingMinutes': (510 - occupiedMinutes).clamp(0, 510),
        'totalArea': totalArea,
        'limitArea': 220,
        'remainingArea': (220 - totalArea).clamp(0, 220),
        'totalAddonCount': totalAddonCount,
        'overbooked': occupiedMinutes > 510,
      },
      'slots': slots,
      'localFallback': true,
    };
  }

  int _scheduleSlotDurationMinutes(Map<String, dynamic> slot) {
    final explicit = (slot['totalDurationMinutes'] as num?)?.toInt() ??
        (slot['estimatedDurationMinutes'] as num?)?.toInt();
    if (explicit != null && explicit > 0) {
      return explicit;
    }
    final area = (slot['area'] as num?)?.toInt() ?? 0;
    if (area > 0) {
      return (90 + area * 1.2).round().clamp(90, 420);
    }
    return 120;
  }

  Future<Map<String, dynamic>> recalculateScheduleAfterAddon({
    required String orderId,
  }) async {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      Map<String, dynamic>? order;
      try {
        order = _temporaryCustomerOrders()
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (item) =>
                  (item?['id'] ?? item?['orderId'] ?? '').toString() == orderId,
            );
      } catch (_) {
        order = null;
      }
      Map<String, dynamic>? slot;
      try {
        slot = _temporaryCustomerScheduleSlots()
            .cast<Map<String, dynamic>?>()
            .firstWhere((item) {
          final itemOrderId = (item?['customerOrderId'] ??
                  item?['orderId'] ??
                  item?['id'] ??
                  '')
              .toString();
          return itemOrderId == orderId;
        });
      } catch (_) {
        slot = null;
      }
      final addonsDetailed = (order?['addonsDetailed'] as List?)
              ?.cast<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          (slot?['addonsDetailed'] as List?)
              ?.cast<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const <Map<String, dynamic>>[];
      final baseMinutes = ((slot?['estimatedDurationMinutes'] ??
                  order?['estimatedDurationMinutes']) as num?)
              ?.toInt() ??
          180;
      final addonMinutes = addonsDetailed.fold<int>(
        0,
        (total, addon) =>
            total +
            (((addon['durationMinutes'] as num?)?.toInt() ??
                (((addon['quantity'] as num?)?.toInt() ?? 1) * 15))),
      );
      final totalDurationMinutes = baseMinutes + addonMinutes;
      return {
        'ok': true,
        'orderId': orderId,
        'estimatedDurationMinutes': baseMinutes,
        'addonDurationMinutes': addonMinutes,
        'totalDurationMinutes': totalDurationMinutes,
        'localFallback': true,
      };
    }
    final orders = await BackendApiService.instance.getList('/orders');
    final order = orders
        .cast<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .firstWhere(
          (item) => (item['id'] ?? '').toString() == orderId,
          orElse: () => const <String, dynamic>{},
        );
    final duration = _num(
      order['estimatedDurationMinutes'] ??
          order['estimated_duration_minutes'] ??
          0,
    ).round();
    return {
      'ok': true,
      'orderId': orderId,
      'estimatedDurationMinutes': duration,
      'totalDurationMinutes': duration,
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> notifyClientDelay({
    required String orderId,
    String mode = 'delay',
    int minutes = 0,
    String? customBody,
  }) async {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      final now = Timestamp.now();
      final notifications = [..._debugNotifications()];
      final body = customBody ??
          (mode == 'delay'
              ? 'Уборка по заказу задерживается на $minutes мин.'
              : 'Статус заказа обновлен.');
      notifications.insert(0, {
        'id':
            'temp_notify_client_${orderId}_${DateTime.now().millisecondsSinceEpoch}',
        'userId':
            _uidOrNull ?? AuthService.temporarySessionUid ?? 'temp_customer',
        'type': 'order_delay',
        'title': 'Обновление по заказу',
        'body': body,
        'payload': {'orderId': orderId, 'mode': mode, 'minutes': minutes},
        'read': false,
        'createdAt': now,
      });
      _debugNotificationsState = notifications;
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'orderId': orderId,
        'mode': mode,
        'minutes': minutes,
        'localFallback': true,
      };
    }
    return BackendApiService.instance.postMap(
      '/orders/$orderId/notify',
      body: {
        'target': 'customer',
        'type': 'order_delay',
        'titleRu': 'Обновление по заказу',
        'bodyRu': customBody ??
            (mode == 'delay'
                ? 'Уборка по заказу задерживается на $minutes мин.'
                : 'Статус заказа обновлен.'),
      },
    );
  }

  Future<Map<String, dynamic>> notifyCleanerUpdate({
    required String orderId,
    String? customBody,
    String type = 'schedule_update',
  }) async {
    if (_isTemporaryCustomerSession || _isTemporaryCleanerSession) {
      final now = Timestamp.now();
      final notifications = [..._debugNotifications()];
      notifications.insert(0, {
        'id':
            'temp_notify_cleaner_${orderId}_${DateTime.now().millisecondsSinceEpoch}',
        'userId':
            _uidOrNull ?? AuthService.temporarySessionUid ?? 'temp_cleaner',
        'type': type,
        'title': 'Изменение по заказу',
        'body': customBody ?? 'Данные по заказу были обновлены.',
        'payload': {'orderId': orderId, 'type': type},
        'read': false,
        'createdAt': now,
      });
      _debugNotificationsState = notifications;
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'orderId': orderId,
        'type': type,
        'localFallback': true,
      };
    }
    return BackendApiService.instance.postMap(
      '/orders/$orderId/notify',
      body: {
        'target': 'cleaner',
        'type': type,
        'titleRu': 'Изменение по заказу',
        'bodyRu': customBody ?? 'Данные по заказу были обновлены.',
      },
    );
  }

  Future<Map<String, dynamic>> createOrderAndInvoice({
    required int amount,
    required String customerId,
    required String packageName,
    String? packageId,
    String? pricingMode,
    int? cleaningsPerMonth,
    required String accessMethod,
    required List<String> addons,
    List<Map<String, dynamic>> addonsDetailed = const [],
    required String frequencyLabel,
    required int rooms,
    required int bathrooms,
    required int area,
    String? address,
    String? residentialComplex,
    String? entrance,
    String? apartment,
    String? houseId,
    String? slotId,
    String? sourceOrderId,
    String? subscriptionId,
    int billingPeriodMonths = 1,
    int bonusToSpend = 0,
  }) async {
    final effectiveCustomerId = customerId.trim().isNotEmpty
        ? customerId.trim()
        : (_uidOrNull ?? 'temp_customer');
    if (_isTemporaryCustomerSession) {
      return _createLocalCustomerOrderFallback(
        amount: amount,
        customerId: effectiveCustomerId,
        packageName: packageName,
        packageId: packageId,
        cleaningsPerMonth: cleaningsPerMonth,
        accessMethod: accessMethod,
        addons: addons,
        addonsDetailed: addonsDetailed,
        frequencyLabel: frequencyLabel,
        area: area,
        address: address,
        residentialComplex: residentialComplex,
        entrance: entrance,
        apartment: apartment,
        houseId: houseId,
        slotId: slotId,
        sourceOrderId: sourceOrderId,
        subscriptionId: subscriptionId,
        billingPeriodMonths: billingPeriodMonths,
      );
    }
    if (_isDebugCustomer) {
      bool isPendingDebugOrder(Map<String, dynamic> item) {
        final status = (item['status'] ?? '').toString().toLowerCase();
        final paymentStatus =
            (item['paymentStatus'] ?? '').toString().toLowerCase();
        return status == 'pending_assignment' ||
            status == 'pending_payment' ||
            paymentStatus == 'pending_invoice' ||
            paymentStatus == 'invoice_requested' ||
            paymentStatus == 'initiated';
      }

      final currentCustomerId = _uidOrNull ?? 'customer_demo';
      if (effectiveCustomerId != currentCustomerId) {
        return {
          'ok': false,
          'customerId': effectiveCustomerId,
          'amount': amount,
        };
      }
      final orderId = 'debug_order_${DateTime.now().millisecondsSinceEpoch}';
      final now = Timestamp.now();
      final stalePendingOrderIds = <String>{};
      final orders = _debugCustomerOrders()
        ..removeWhere((item) {
          final shouldRemove = isPendingDebugOrder(item);
          if (shouldRemove) {
            final staleOrderId =
                (item['id'] ?? item['orderId'] ?? '').toString().trim();
            if (staleOrderId.isNotEmpty) {
              stalePendingOrderIds.add(staleOrderId);
            }
          }
          return shouldRemove;
        });
      final scheduleSlots = _debugCustomerScheduleSlots()
        ..removeWhere((item) {
          final linkedOrderId =
              (item['sourceOrderId'] ?? item['customerOrderId'] ?? '')
                  .toString()
                  .trim();
          return linkedOrderId.isNotEmpty &&
              stalePendingOrderIds.contains(linkedOrderId);
        });
      try {
        final sharedOrders = await _debugSharedCustomerOrdersStream().first;
        final batch = _db.batch();
        var dirty = false;
        for (final item in sharedOrders.where(isPendingDebugOrder)) {
          final staleOrderId =
              (item['id'] ?? item['orderId'] ?? '').toString().trim();
          if (staleOrderId.isEmpty) {
            continue;
          }
          stalePendingOrderIds.add(staleOrderId);
          dirty = true;
          batch.delete(_db.collection('debug_bridge_orders').doc(staleOrderId));
          batch.delete(
            _db.collection('debug_bridge_cleaner_slots').doc(staleOrderId),
          );
        }
        if (dirty) {
          await batch.commit();
        }
      } catch (_) {
        // Shared debug cleanup is best-effort; local customer flow must still work.
      }
      scheduleSlots.removeWhere((item) {
        final linkedOrderId =
            (item['sourceOrderId'] ?? item['customerOrderId'] ?? '')
                .toString()
                .trim();
        return linkedOrderId.isNotEmpty &&
            stalePendingOrderIds.contains(linkedOrderId);
      });
      final order = {
        'id': orderId,
        'status': 'pending_payment',
        'paymentStatus': 'pending_invoice',
        'scheduledFor': now,
        'date': DateTime.now().toIso8601String(),
        'time': 'Ожидает выбора даты',
        'package': packageName,
        'price': amount,
        'residentialComplex': residentialComplex ?? 'ЖК Триумф',
        'address': address ?? 'ЖК Триумф, кв. 45',
        'customerId': effectiveCustomerId,
        'customerName': 'Асет',
        'customerPhone': '+7 708 636 21 53',
        'cleanerName': 'Будет назначен',
        'cleanerPhone': '',
        'kaspiPhone': '',
        'createdAt': now,
        'updatedAt': now,
        'frequencyLabel': frequencyLabel,
        'billingPeriodMonths': billingPeriodMonths,
        'cleaningsPerMonth': cleaningsPerMonth ?? 1,
        'area': area,
        'currency': 'KZT',
        'accessMethod': accessMethod,
        'addons': addons,
        'addonsDetailed': addonsDetailed,
        'rooms': rooms,
        'bathrooms': bathrooms,
        'bonusToSpend': bonusToSpend,
        if (entrance != null && entrance.isNotEmpty) 'entrance': entrance,
        if (apartment != null && apartment.isNotEmpty) 'apartment': apartment,
        if (houseId != null && houseId.isNotEmpty) 'houseId': houseId,
        if (slotId != null && slotId.isNotEmpty) 'slotId': slotId,
        if (sourceOrderId != null && sourceOrderId.isNotEmpty)
          'sourceOrderId': sourceOrderId,
        if (subscriptionId != null && subscriptionId.isNotEmpty)
          'subscriptionId': subscriptionId,
      };
      orders.insert(0, order);
      try {
        await _db.collection('debug_bridge_orders').doc(orderId).set({
          ...order,
          'orderId': orderId,
          'orderStatus': 'pending_payment',
          'sourceDebugUid': _uidOrNull ?? 'customer_demo',
        }, SetOptions(merge: true));
      } catch (_) {
        // Shared debug bridge is best-effort; local customer flow must still work.
      }
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'orderId': orderId,
        'customerId': effectiveCustomerId,
        'amount': amount,
        'localFallback': false,
      };
    }
    if (_useDebugFixtures) {
      return {
        'ok': true,
        'orderId': 'debug_order_${DateTime.now().millisecondsSinceEpoch}',
        'customerId': effectiveCustomerId,
        'amount': amount,
        'localFallback': false,
      };
    }

    final normalizedSourceOrderId = (sourceOrderId ?? '').trim();
    final normalizedSubscriptionId = (subscriptionId ?? '').trim();
    final normalizedPackageId = (packageId ?? '').trim();
    try {
      if (normalizedSourceOrderId.isNotEmpty) {
        final payment = await BackendApiService.instance.postMap(
          '/orders/$normalizedSourceOrderId/pay',
          body: {
            'provider': 'manual',
            'useBonus': bonusToSpend > 0,
            'requestedBonus': bonusToSpend,
            'maxBonusPercent': bonusToSpend >= amount ? 100 : 50,
          },
        );
        final paymentData = Map<String, dynamic>.from(
          (payment['payment'] as Map?) ?? payment,
        );
        final paymentId = (paymentData['id'] ?? '').toString();
        return {
          'ok': true,
          'orderId': paymentId.isNotEmpty ? paymentId : normalizedSourceOrderId,
          'paymentId': paymentId,
          'sourceOrderId': normalizedSourceOrderId,
          'customerId': effectiveCustomerId,
          'amount': _num(
            payment['payableAmount'] ?? paymentData['amount'],
          ).round(),
          'finalAmount': _num(
            payment['payableAmount'] ?? paymentData['amount'],
          ).round(),
          'bonusAppliedAmount': _num(
            payment['bonusAmount'] ?? paymentData['bonus_amount'],
          ).round(),
          'localFallback': false,
          'backend': true,
        };
      }

      if (normalizedSubscriptionId.isEmpty &&
          normalizedPackageId.isNotEmpty &&
          normalizedPackageId != 'addons_only') {
        final addressId = await _backendPrimaryAddressId();
        final result = await BackendApiService.instance.postMap(
          '/packages/purchase',
          body: {
            'packageId': normalizedPackageId,
            'cleaningsPerMonth': cleaningsPerMonth,
            'addonsDetailed': addonsDetailed,
            'useBonus': bonusToSpend > 0,
            'requestedBonus': bonusToSpend,
            if (addressId != null && addressId.isNotEmpty)
              'addressId': addressId,
            'provider': 'manual',
          },
        );
        final paymentData = Map<String, dynamic>.from(
          (result['payment'] as Map?) ?? const <String, dynamic>{},
        );
        final customerPackage = Map<String, dynamic>.from(
          (result['customerPackage'] as Map?) ?? const <String, dynamic>{},
        );
        final paymentId = (paymentData['id'] ?? '').toString();
        return {
          'ok': true,
          'orderId': paymentId,
          'paymentId': paymentId,
          'customerPackageId': customerPackage['id'],
          'customerId': effectiveCustomerId,
          'amount': _num(
            result['payableAmount'] ?? paymentData['amount'],
          ).round(),
          'finalAmount': _num(
            result['payableAmount'] ?? paymentData['amount'],
          ).round(),
          'bonusAppliedAmount': _num(
            result['bonusAmount'] ?? paymentData['bonus_amount'],
          ).round(),
          'localFallback': false,
          'backend': true,
        };
      }
    } on BackendApiException {
      rethrow;
    }

    throw FlutterError(
      'Этот тип оформления ещё не подключён к новому backend. Обновите сценарий оплаты или попробуйте позже.',
    );
  }

  Future<void> freezeSubscription({required int days}) async {
    if (days <= 0) throw FlutterError('Укажите срок заморозки.');
    final packages = await BackendApiService.instance.getList('/packages/my');
    final active =
        packages.where((item) => item['status'] == 'active').toList();
    if (active.isEmpty) throw FlutterError('Активный пакет не найден.');
    await BackendApiService.instance.postMap(
        '/packages/my/${active.first['id']}/freeze',
        body: {'days': days});
  }

  Future<void> saveReferralCode({required String code}) async {
    if (code.trim().isEmpty) {
      return;
    }
    await BackendApiService.instance
        .postMap('/referrals', body: {'code': code.trim().toUpperCase()});
  }

  Future<Map<String, dynamic>> ensureReferralLink() =>
      BackendApiService.instance.getMap('/referrals');

  DateTime _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse('$value') ?? DateTime.now();
  }

  Future<void> applyReferralCodeIfMissing(String code) async {
    if (code.trim().isEmpty) return;
    final current = await BackendApiService.instance.getMap('/referrals');
    if ((current['referredByCode'] ?? '').toString().isNotEmpty) return;
    await BackendApiService.instance
        .postMap('/referrals', body: {'code': code.trim()});
  }

  Future<Map<String, dynamic>> getReferralStats({String? userId}) =>
      BackendApiService.instance.getMap('/referrals');

  Future<Map<String, dynamic>> verifyApartmentArea({
    String? userId,
    required int actualArea,
    String? areaTechnicalPlanUrl,
    String? documentFileId,
  }) async {
    if (_isDebugCustomer) {
      final currentUid = _uidOrNull ?? 'customer_demo';
      final uid = userId ?? currentUid;
      if (uid != currentUid) {
        return {
          'ok': false,
          'areaVerified': false,
          'pendingReview': false,
          'bonusAmount': 0,
        };
      }
      final current = _debugCustomerProfile();
      final initialArea =
          (current['apartmentArea'] ?? current['area'] ?? 0) as num? ?? 0;
      final difference = actualArea - initialArea.toInt();
      final reportId = 'debug_area_$uid';
      _debugCustomerProfileState = {
        ...current,
        'area': actualArea,
        'apartmentArea': actualArea,
        'areaVerified': false,
        'areaStatus': 'PENDING_REVIEW',
        if (areaTechnicalPlanUrl != null && areaTechnicalPlanUrl.isNotEmpty)
          'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
      };
      try {
        await _db.collection('debug_bridge_customer_profiles').doc(uid).set({
          'area': actualArea,
          'apartmentArea': actualArea,
          'areaVerified': false,
          'areaStatus': 'PENDING_REVIEW',
          if (areaTechnicalPlanUrl != null && areaTechnicalPlanUrl.isNotEmpty)
            'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
          'updatedAt': Timestamp.now(),
          'sourceDebugUid': uid,
        }, SetOptions(merge: true));
        await _db.collection('debug_bridge_area_reports').doc(reportId).set({
          'userId': uid,
          'houseId': (current['houseId'] ?? '').toString(),
          'initialArea': initialArea.toInt(),
          'actualArea': actualArea,
          'difference': difference,
          'status': 'open',
          'createdAt': Timestamp.now(),
          'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
          'sourceDebugUid': uid,
        }, SetOptions(merge: true));
      } catch (_) {}
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'areaVerified': false,
        'pendingReview': true,
        'bonusAmount': 0,
        'reportId': reportId,
      };
    }
    if (_isTemporaryCustomerSession) {
      final currentUid = _uidOrNull ?? (userId ?? 'temp_customer');
      final current = _temporaryCustomerProfile();
      final initialArea =
          (current['apartmentArea'] ?? current['area'] ?? 0) as num? ?? 0;
      final difference = actualArea - initialArea.toInt();
      final reportId = 'temp_area_$currentUid';
      await updateCustomerProfile({
        'area': actualArea,
        'apartmentArea': actualArea,
        'areaVerified': false,
        'areaStatus': 'PENDING_REVIEW',
        if (areaTechnicalPlanUrl != null && areaTechnicalPlanUrl.isNotEmpty)
          'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
      });
      return {
        'ok': true,
        'areaVerified': false,
        'pendingReview': true,
        'bonusAmount': 0,
        'reportId': reportId,
        'difference': difference,
      };
    }
    final addressId = await _backendPrimaryAddressId();
    final result = await BackendApiService.instance.postMap(
      '/quality-checks/from-file',
      body: {
        'actualArea': actualArea,
        if (documentFileId != null) 'fileId': documentFileId,
        if (addressId != null) 'addressId': addressId,
        if (areaTechnicalPlanUrl != null && areaTechnicalPlanUrl.isNotEmpty)
          'fileUrl': areaTechnicalPlanUrl,
      },
    );
    final request = Map<String, dynamic>.from(
      (result['request'] as Map?) ?? result,
    );
    return {
      'ok': true,
      'userId': userId ?? _uidOrNull,
      'actualArea': actualArea,
      'areaVerified': false,
      'pendingReview': true,
      'bonusAwarded': false,
      'bonusAmount': 0,
      'reportId': request['id'],
      'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> _verifyApartmentAreaDirect({
    String? userId,
    required int actualArea,
    String? areaTechnicalPlanUrl,
  }) async {
    final uid = userId ?? _uidOrNull ?? '';
    if (_uidOrNull != null && uid != _uidOrNull) {
      throw FlutterError('Можно отправить на проверку только свой профиль.');
    }
    if (actualArea <= 0) {
      throw FlutterError('Площадь должна быть больше 0.');
    }
    final addressId = await _backendPrimaryAddressId();
    final result = await BackendApiService.instance.postMap(
      '/quality-checks/from-file',
      body: {
        'actualArea': actualArea,
        if (addressId != null) 'addressId': addressId,
        if (areaTechnicalPlanUrl != null && areaTechnicalPlanUrl.isNotEmpty)
          'fileUrl': areaTechnicalPlanUrl,
      },
    );
    final request = Map<String, dynamic>.from(
      (result['request'] as Map?) ?? result,
    );
    return {
      'ok': true,
      'userId': uid,
      'actualArea': actualArea,
      'areaVerified': false,
      'areaStatus': 'PENDING_REVIEW',
      'pendingReview': true,
      'bonusAwarded': false,
      'bonusAmount': 0,
      'reportId': request['id'],
      'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> requestAreaQualityCheck({
    String? userId,
    required int actualArea,
    required String preferredDate,
    required String preferredTime,
    String? orderId,
  }) async {
    final uid = userId ?? _uid;
    if (_isDebugCustomer || _isTemporaryCustomerSession) {
      return _requestAreaQualityCheckDirect(
        userId: uid,
        actualArea: actualArea,
        preferredDate: preferredDate,
        preferredTime: preferredTime,
        orderId: orderId,
      );
    }
    final addressId = await _backendPrimaryAddressId();
    final result = await BackendApiService.instance.postMap(
      '/quality-checks/from-file',
      body: {
        'actualArea': actualArea,
        if (addressId != null) 'addressId': addressId,
        'preferredDate': preferredDate,
        'preferredTime': preferredTime,
        if (orderId != null) 'orderId': orderId,
      },
    );
    final request = Map<String, dynamic>.from(
      (result['request'] as Map?) ?? result,
    );
    return {
      'ok': true,
      'reportId': request['id'],
      'userId': uid,
      'actualArea': actualArea,
      'preferredDate': preferredDate,
      'preferredTime': preferredTime,
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> _requestAreaQualityCheckDirect({
    required String userId,
    required int actualArea,
    required String preferredDate,
    required String preferredTime,
    String? orderId,
  }) async {
    if (actualArea <= 0) {
      throw FlutterError('Площадь должна быть больше 0.');
    }
    if (preferredDate.trim().isEmpty || preferredTime.trim().isEmpty) {
      throw FlutterError('Выберите дату и время проверки.');
    }
    final addressId = await _backendPrimaryAddressId();
    final result = await BackendApiService.instance.postMap(
      '/quality-checks/from-file',
      body: {
        'actualArea': actualArea,
        if (addressId != null) 'addressId': addressId,
        'preferredDate': preferredDate,
        'preferredTime': preferredTime,
        if (orderId != null) 'orderId': orderId,
      },
    );
    final request = Map<String, dynamic>.from(
      (result['request'] as Map?) ?? result,
    );
    return {
      'ok': true,
      'reportId': request['id'],
      'userId': userId,
      'actualArea': actualArea,
      'preferredDate': preferredDate,
      'preferredTime': preferredTime,
      'backend': true,
    };
  }

  Future<void> resolveAreaMismatchReport(String reportId) async {
    if (_isDebugAdmin) {
      final reportDoc =
          await _db.collection('debug_bridge_area_reports').doc(reportId).get();
      final report = reportDoc.data() ?? const <String, dynamic>{};
      final userId = (report['userId'] ?? '').toString();
      final actualArea = (report['actualArea'] as num?)?.toInt() ?? 0;
      await _db.collection('debug_bridge_area_reports').doc(reportId).set({
        'status': 'resolved',
        'resolvedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      if (userId.isNotEmpty) {
        await _db.collection('debug_bridge_customer_profiles').doc(userId).set({
          'area': actualArea,
          'apartmentArea': actualArea,
          'areaVerified': true,
          'areaStatus': 'VERIFIED',
          'updatedAt': Timestamp.now(),
          'sourceDebugUid': 'admin_demo',
        }, SetOptions(merge: true));
      }
      return;
    }
    final details = await BackendApiService.instance.getMap(
      '/admin/quality-checks/$reportId/details',
    );
    final qualityCheck = Map<String, dynamic>.from(
      (details['qualityCheck'] as Map?) ?? const <String, dynamic>{},
    );
    final actualArea = _num(
      qualityCheck['requested_area'] ??
          qualityCheck['requestedArea'] ??
          qualityCheck['area'],
    ).round();
    await BackendApiService.instance.postMap(
      '/admin/quality-checks/$reportId/approve',
      body: {'approvedArea': actualArea, 'recalculationAmount': 0},
    );
  }

  Future<void> confirmApartmentAreaByQualityControl({
    required String userId,
    required int actualArea,
  }) async {
    if (userId.trim().isEmpty || actualArea <= 0) {
      throw FlutterError('Укажите корректного клиента и площадь.');
    }
    await BackendApiService.instance.postMap(
      '/admin/users/$userId/confirm-area',
      body: {'actualArea': actualArea},
    );
  }

  Future<void> updateAreaMismatchReport(
    String reportId,
    Map<String, dynamic> data,
  ) async {
    if (reportId.trim().isEmpty) {
      return;
    }
    await BackendApiService.instance.patchMap(
      '/admin/quality-checks/$reportId',
      body: data,
    );
  }

  Future<void> updateCustomerOrder(
    String orderId,
    Map<String, dynamic> data,
  ) async {
    if (orderId.trim().isEmpty) {
      return;
    }
    await BackendApiService.instance.patchMap(
      '/admin/orders/$orderId',
      body: data,
    );
  }

  Future<void> createAreaRecalculationPayment({
    required String orderId,
    required Map<String, dynamic> order,
    required int previousArea,
    required int actualArea,
    required int previousPaidAmount,
    required int recalculatedAmount,
    required int amountDue,
    required String reportId,
  }) async {
    if (orderId.trim().isEmpty || amountDue <= 0) {
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/quality-checks/$reportId/approve',
      body: {
        'approvedArea': actualArea,
        'recalculationAmount': amountDue,
        'orderId': orderId,
        'previousArea': previousArea,
        'previousPaidAmount': previousPaidAmount,
        'recalculatedAmount': recalculatedAmount,
      },
    );
  }

  Future<Map<String, dynamic>> getCustomPackageQuote({
    required int rooms,
    required int bathrooms,
    required int area,
    required int frequency,
    int billingPeriodMonths = 1,
    required bool windows,
    required bool ironing,
    required bool balcony,
    List<Map<String, dynamic>> addonsDetailed = const [],
  }) async {
    if (_useDebugFixtures || _isTemporaryCustomerSession) {
      return _localCustomPackageQuote(
        rooms: rooms,
        bathrooms: bathrooms,
        area: area,
        frequency: frequency,
        billingPeriodMonths: billingPeriodMonths,
        addonsDetailed: addonsDetailed,
      );
    }
    final result = await BackendApiService.instance.postMap(
      '/legacy/custom-package/calculate',
      body: {
        'rooms': rooms,
        'bathrooms': bathrooms,
        'area': area,
        'cleaningCount': frequency,
        'frequency': frequency,
        'billingPeriodMonths': billingPeriodMonths,
        'windows': windows,
        'ironing': ironing,
        'balcony': balcony,
        'addonsDetailed': addonsDetailed,
      },
    );
    return Map<String, dynamic>.from((result['calculation'] as Map?) ?? result);
  }

  Map<String, dynamic> _localCustomPackageQuote({
    required int rooms,
    required int bathrooms,
    required int area,
    required int frequency,
    required int billingPeriodMonths,
    List<Map<String, dynamic>> addonsDetailed = const [],
  }) {
    final normalizedFrequency = frequency < 1 ? 1 : frequency;
    final normalizedBilling = billingPeriodMonths < 1 ? 1 : billingPeriodMonths;
    final normalizedArea = area < 0 ? 0 : area;
    final basePerCleaning =
        (normalizedArea * 120 + rooms * 2000 + bathrooms * 1500).round();
    final billableAddonTotal = addonsDetailed.fold<int>(0, (total, raw) {
      final item = Map<String, dynamic>.from(raw);
      if (item['separatePayment'] == true) {
        return total;
      }
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final price = (item['price'] as num?)?.toInt() ?? 0;
      return total + (quantity * price);
    });
    final separatePaymentAddonTotal = addonsDetailed.fold<int>(0, (total, raw) {
      final item = Map<String, dynamic>.from(raw);
      if (item['separatePayment'] != true) {
        return total;
      }
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final price = (item['price'] as num?)?.toInt() ?? 0;
      return total + (quantity * price);
    });
    final cleaningCount = normalizedFrequency * normalizedBilling;
    final discountRate = normalizedBilling >= 3 && normalizedFrequency > 1
        ? 0.20
        : normalizedFrequency >= 4
            ? 0.12
            : normalizedFrequency >= 2
                ? 0.07
                : 0.0;
    final subtotal = (basePerCleaning * cleaningCount) + billableAddonTotal;
    final discountAmount = (subtotal * discountRate).round();
    final separatePaymentAddons = addonsDetailed
        .where((item) => item['separatePayment'] == true)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return {
      'perCleaningPrice': basePerCleaning + billableAddonTotal,
      'monthlyPrice': subtotal - discountAmount,
      'subtotal': subtotal,
      'discountRate': discountRate,
      'discountAmount': discountAmount,
      'cleaningCount': cleaningCount,
      'billingPeriodMonths': normalizedBilling,
      'addonTotalPrice': billableAddonTotal + separatePaymentAddonTotal,
      'addonsBillableTotal': billableAddonTotal,
      'addonsSeparatePaymentTotal': separatePaymentAddonTotal,
      'separatePaymentAddons': separatePaymentAddons,
    };
  }

  Future<Map<String, dynamic>> saveCustomPackageDraft({
    required int rooms,
    required int bathrooms,
    required int area,
    required int frequency,
    required String frequencyLabel,
    int billingPeriodMonths = 1,
    required bool windows,
    required bool ironing,
    required bool balcony,
    List<Map<String, dynamic>> addonsDetailed = const [],
    required String accessMethod,
    List<String> preferredDays = const [],
    List<String> preferredTimeRanges = const [],
  }) async {
    if (_isTemporaryCustomerSession) {
      final draftId =
          'temp_custom_draft_${DateTime.now().millisecondsSinceEpoch}';
      final quote = _localCustomPackageQuote(
        rooms: rooms,
        bathrooms: bathrooms,
        area: area,
        frequency: frequency,
        billingPeriodMonths: billingPeriodMonths,
        addonsDetailed: addonsDetailed,
      );
      final payload = {
        'id': draftId,
        'customerId': _uidOrNull ?? 'temp_customer',
        'rooms': rooms,
        'bathrooms': bathrooms,
        'area': area,
        'frequency': frequency,
        'frequencyLabel': frequencyLabel,
        'billingPeriodMonths': billingPeriodMonths,
        'windows': windows,
        'ironing': ironing,
        'balcony': balcony,
        'addonsDetailed': addonsDetailed,
        'accessMethod': accessMethod,
        'preferredDays': preferredDays,
        'preferredTimeRanges': preferredTimeRanges,
        'quote': quote,
        'updatedAt': DateTime.now().toIso8601String(),
        'localFallback': true,
      };
      debugStorageWrite(
        _debugStorageKey('custom_package_draft'),
        jsonEncode(_jsonSafe(payload)),
      );
      _notifyDebugStateChanged();
      return {'ok': true, 'draftId': draftId, 'localFallback': true, ...quote};
    }
    final result = await BackendApiService.instance.postMap(
      '/legacy/custom-package/draft',
      body: {
        'rooms': rooms,
        'bathrooms': bathrooms,
        'area': area,
        'cleaningCount': frequency,
        'frequency': frequency,
        'frequencyLabel': frequencyLabel,
        'billingPeriodMonths': billingPeriodMonths,
        'windows': windows,
        'ironing': ironing,
        'balcony': balcony,
        'addonsDetailed': addonsDetailed,
        'accessMethod': accessMethod,
        'preferredDays': preferredDays,
        'preferredTimeRanges': preferredTimeRanges,
      },
    );
    final draft = Map<String, dynamic>.from(
      (result['draft'] as Map?) ?? result,
    );
    return {
      'ok': true,
      'draftId': draft['id'],
      ...draft,
      if (draft['calculation'] is Map)
        ...Map<String, dynamic>.from(draft['calculation'] as Map),
    };
  }

  Future<void> advanceOrderStatus({
    required String orderId,
    required String toStatus,
  }) async {
    if (_isTemporaryCleanerSession) {
      if (!await _temporaryCanAccessOrder(orderId)) {
        return;
      }
      final statusValue = toStatus == 'completed' ? 'completed' : 'in_progress';
      final now = Timestamp.now();
      final slots = _temporaryCleanerScheduleSlots();
      final slotIndex = slots.indexWhere((slot) {
        final ids = [
          slot['sourceOrderId']?.toString(),
          slot['customerOrderId']?.toString(),
          slot['orderId']?.toString(),
          slot['id']?.toString(),
        ];
        return ids.contains(orderId);
      });
      if (slotIndex != -1) {
        final next = Map<String, dynamic>.from(slots[slotIndex]);
        next['status'] = statusValue;
        next['updatedAt'] = now;
        if (statusValue == 'completed') {
          next['completedAt'] = now;
        }
        slots[slotIndex] = next;
        _debugCleanerScheduleSlotsState = slots;
      }
      final orders = _temporaryCleanerOrders();
      final orderIndex = orders.indexWhere((item) {
        final ids = [
          item['customerOrderId']?.toString(),
          item['orderId']?.toString(),
          item['id']?.toString(),
        ];
        return ids.contains(orderId);
      });
      if (orderIndex != -1) {
        final next = Map<String, dynamic>.from(orders[orderIndex]);
        next['status'] = toStatus;
        next['updatedAt'] = now;
        if (statusValue == 'completed') {
          next['completedAt'] = now;
        }
        orders[orderIndex] = next;
        _debugCleanerOrdersState = orders;
      }
      _notifyDebugStateChanged();
      return;
    }
    if (_isDebugCleaner) {
      if (!await _debugCanAccessOrder(orderId)) {
        return;
      }
      final statusValue = toStatus == 'completed' ? 'completed' : 'in_progress';
      final now = Timestamp.now();
      final slots = _debugCleanerScheduleSlots();
      final slotIndex = slots.indexWhere((slot) {
        final ids = [
          slot['sourceOrderId']?.toString(),
          slot['customerOrderId']?.toString(),
          slot['id']?.toString(),
        ];
        return ids.contains(orderId);
      });
      if (slotIndex != -1) {
        final next = Map<String, dynamic>.from(slots[slotIndex]);
        next['status'] = statusValue;
        next['updatedAt'] = now;
        if (statusValue == 'completed') {
          next['completedAt'] = now;
        }
        slots[slotIndex] = next;
      }
      final orders = _debugCleanerOrders();
      final orderIndex = orders.indexWhere((item) {
        final ids = [
          item['customerOrderId']?.toString(),
          item['id']?.toString(),
        ];
        return ids.contains(orderId);
      });
      if (orderIndex != -1) {
        final next = Map<String, dynamic>.from(orders[orderIndex]);
        next['status'] = toStatus;
        next['updatedAt'] = now;
        if (statusValue == 'completed') {
          next['completedAt'] = now;
        }
        orders[orderIndex] = next;
      } else if (slotIndex != -1) {
        final slot = slots[slotIndex];
        final slotDate = _toDateTime(slot['scheduledFor'] ?? slot['date']);
        orders.add({
          'id': 'debug_cleaner_order_$orderId',
          'customerOrderId': orderId,
          'cleanerId': _uidOrNull ?? 'cleaner_demo',
          'status': toStatus,
          'dateText':
              '${slotDate.day.toString().padLeft(2, '0')}.${slotDate.month.toString().padLeft(2, '0')}.${slotDate.year}',
          'time': (slot['time'] ?? '10:00 - 13:00').toString(),
          'client': slot['customerName'] ?? slot['client'] ?? 'Клиент',
          'customerName': slot['customerName'] ?? slot['client'] ?? 'Клиент',
          'customerPhone': slot['customerPhone'] ?? '',
          'residentialComplex': slot['residentialComplex'] ?? '',
          'entrance': slot['entrance'] ?? '',
          'apartment': slot['apartment'] ?? '',
          'accessMethod': slot['accessMethod'] ?? '',
          'address': slot['address'] ?? '',
          'package': slot['package'] ?? '',
          'price': slot['price'] ?? 0,
          'estimatedDurationMinutes': slot['estimatedDurationMinutes'],
          'totalDurationMinutes': slot['totalDurationMinutes'],
          'area': slot['area'] ?? 0,
          'updatedAt': now,
          if (statusValue == 'completed') 'completedAt': now,
        });
      }
      await _db.collection('debug_bridge_orders').doc(orderId).set({
        'status': toStatus,
        'updatedAt': now,
        if (statusValue == 'completed') 'completedAt': now,
      }, SetOptions(merge: true));
      await _db.collection('debug_bridge_cleaner_slots').doc(orderId).set({
        'status': statusValue,
        'updatedAt': now,
        if (statusValue == 'completed') 'completedAt': now,
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/orders/$orderId/status',
      body: {'status': toStatus},
    );
  }

  Future<void> confirmCleaningStart({
    required String orderId,
    required bool confirmed,
  }) async {
    if (_isTemporaryCleanerSession || _isDebugCleaner) {
      final now = Timestamp.now();
      final statusValue = confirmed ? 'in_progress' : 'start_pending';
      final payload = <String, dynamic>{
        'status': statusValue,
        'orderStatus': statusValue,
        'cleaningStartConfirmed': confirmed,
        'cleaningStartRejected': !confirmed,
        'updatedAt': now,
        if (confirmed) 'cleaningStartConfirmedAt': now,
        if (!confirmed) 'cleaningStartRejectedAt': now,
      };
      await _db
          .collection('debug_bridge_cleaner_slots')
          .doc(orderId)
          .set(payload, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/orders/$orderId/confirm-start',
      body: {'confirmed': confirmed},
    );
  }

  Future<void> acceptOrderOffer({required String offerId}) async {
    if (_isTemporaryCleanerSession || _isDebugCleaner) {
      throw FlutterError(
        'Подтверждение заказа доступно только в полноценной сессии уборщицы.',
      );
    }
    await BackendApiService.instance.postMap('/orders/$offerId/offers/accept');
  }

  Future<Map<String, dynamic>> submitCleanerAddonRequest({
    required String slotId,
    required List<Map<String, dynamic>> addonsDetailed,
    String? note,
  }) async {
    return BackendApiService.instance.postMap(
      '/orders/$slotId/addon-requests',
      body: {'addonsDetailed': addonsDetailed, if (note != null) 'note': note},
    );
  }

  Future<Map<String, dynamic>> approveCleanerAddonRequest({
    required String requestId,
    String? kaspiPhone,
    String paymentMethod = 'kaspi',
    int bonusToSpend = 0,
  }) async {
    return BackendApiService.instance.postMap(
      '/orders/$requestId/addon-requests/approve',
      body: {
        'kaspiPhone': kaspiPhone,
        'paymentMethod': paymentMethod,
        'bonusToSpend': bonusToSpend,
      },
    );
  }

  Future<Map<String, dynamic>> _approveCleanerAddonRequestDirect({
    required String requestId,
    String? kaspiPhone,
    String paymentMethod = 'kaspi',
    int bonusToSpend = 0,
  }) async {
    return approveCleanerAddonRequest(
      requestId: requestId,
      kaspiPhone: kaspiPhone,
      paymentMethod: paymentMethod,
      bonusToSpend: bonusToSpend,
    );
  }

  Future<Map<String, dynamic>> rejectCleanerAddonRequest({
    required String requestId,
  }) async {
    return BackendApiService.instance.postMap(
      '/orders/$requestId/addon-requests/reject',
    );
  }

  Future<Map<String, dynamic>> _applyAddonRequestToSlotDirect(
    String addonRequestId, {
    String? note,
  }) async {
    return BackendApiService.instance.postMap(
      '/payments/addon_$addonRequestId/confirm',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
  }

  Future<void> rejectOrderOffer({required String offerId}) async {
    if (_isTemporaryCleanerSession || _isDebugCleaner) {
      throw FlutterError(
        'Отказ от заказа доступен только в полноценной сессии уборщицы.',
      );
    }
    await BackendApiService.instance.postMap('/orders/$offerId/offers/decline');
  }

  Future<void> _acceptOrderOfferDirect({required String offerId}) async {
    await BackendApiService.instance.postMap('/orders/$offerId/offers/accept');
  }

  Future<Map<String, dynamic>> _scheduleSlotAssignmentSource(
    String slotId,
  ) async {
    final orders = await BackendApiService.instance.getList(
      '/admin/orders',
      query: {'search': slotId, 'limit': '1'},
    );
    return orders.isEmpty ? {'id': slotId} : orders.first;
  }

  Future<void> _rejectOrderOfferDirect({required String offerId}) async {
    await BackendApiService.instance.postMap('/orders/$offerId/offers/decline');
  }

  Future<Map<String, dynamic>> cancelScheduleSlot({
    required String slotId,
  }) async {
    if (_isTemporaryCustomerSession) {
      final now = Timestamp.now();
      final slots = _temporaryCustomerScheduleSlots();
      final slotIndex = slots.indexWhere(
        (slot) => (slot['id'] ?? '').toString() == slotId,
      );
      if (slotIndex == -1) {
        return {'ok': true, 'penaltyApplied': false, 'localFallback': true};
      }
      final slot = Map<String, dynamic>.from(slots.removeAt(slotIndex));
      final orderId = (slot['sourceOrderId'] ??
              slot['customerOrderId'] ??
              slot['orderId'] ??
              '')
          .toString();
      if (orderId.isNotEmpty) {
        final orders = _temporaryCustomerOrders();
        final orderIndex = orders.indexWhere((item) {
          final ids = [item['id']?.toString(), item['orderId']?.toString()];
          return ids.contains(orderId);
        });
        if (orderIndex != -1) {
          final next = Map<String, dynamic>.from(orders[orderIndex]);
          next['status'] = 'cancelled';
          next['orderStatus'] = 'cancelled';
          next['updatedAt'] = now;
          next['cancelledAt'] = now;
          orders[orderIndex] = next;
          _debugCustomerOrdersState = orders;
        }
      }
      final subscriptionId = (slot['subscriptionId'] ?? '').toString();
      if (subscriptionId.isNotEmpty) {
        final subscriptions = _temporaryCustomerSubscriptions();
        final subscriptionIndex = subscriptions.indexWhere(
          (item) => (item['id'] ?? '').toString() == subscriptionId,
        );
        if (subscriptionIndex != -1) {
          final subscription = Map<String, dynamic>.from(
            subscriptions[subscriptionIndex],
          );
          _restoreOneCleaningAfterCancel(subscription, now);
          subscriptions[subscriptionIndex] = subscription;
          _debugCustomerSubscriptionsState = subscriptions;
        }
      }
      _debugCustomerScheduleSlotsState = slots;
      _notifyDebugStateChanged();
      return {'ok': true, 'penaltyApplied': false, 'localFallback': true};
    }
    if (_isDebugCustomer) {
      final now = Timestamp.now();
      final slots = _debugCustomerScheduleSlots();
      final slotIndex = slots.indexWhere((slot) => slot['id'] == slotId);
      Map<String, dynamic>? slot;
      if (slotIndex != -1) {
        slot = Map<String, dynamic>.from(slots.removeAt(slotIndex));
      } else {
        final sharedSlots =
            await _debugSharedCustomerScheduleSlotsStream().first;
        final sharedMatch =
            sharedSlots.cast<Map<String, dynamic>?>().firstWhere(
                  (item) => item?['id']?.toString() == slotId,
                  orElse: () => null,
                );
        if (sharedMatch != null) {
          slot = Map<String, dynamic>.from(sharedMatch);
        }
      }
      if (slot == null) {
        return {'ok': true, 'penaltyApplied': false};
      }
      final orderId = (slot['sourceOrderId'] ??
              slot['customerOrderId'] ??
              slot['orderId'] ??
              '')
          .toString();
      if (orderId.isNotEmpty) {
        final orders = _debugCustomerOrders();
        final orderIndex = orders.indexWhere((item) {
          final ids = [item['id']?.toString(), item['orderId']?.toString()];
          return ids.contains(orderId);
        });
        if (orderIndex != -1) {
          final next = Map<String, dynamic>.from(orders[orderIndex]);
          next['status'] = 'cancelled';
          next['orderStatus'] = 'cancelled';
          next['updatedAt'] = now;
          next['cancelledAt'] = now;
          orders[orderIndex] = next;
        }
        try {
          await _db.collection('debug_bridge_orders').doc(orderId).set({
            'status': 'cancelled',
            'orderStatus': 'cancelled',
            'updatedAt': now,
            'cancelledAt': now,
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
          }, SetOptions(merge: true));
          await _db.collection('debug_bridge_cleaner_slots').doc(orderId).set({
            'status': 'cancelled',
            'updatedAt': now,
            'cancelledAt': now,
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
          }, SetOptions(merge: true));
        } catch (_) {
          // Shared debug bridge is best-effort; local customer flow must still work.
        }
      }
      final subscriptionId = (slot['subscriptionId'] ?? '').toString();
      if (subscriptionId.isNotEmpty) {
        final subscriptions = await _debugMergedCustomerSubscriptions();
        final subscriptionIndex = subscriptions.indexWhere(
          (item) => item['id'] == subscriptionId,
        );
        if (subscriptionIndex != -1) {
          final subscription = Map<String, dynamic>.from(
            subscriptions[subscriptionIndex],
          );
          _restoreOneCleaningAfterCancel(subscription, now);
          subscriptions[subscriptionIndex] = subscription;
          _debugCustomerSubscriptionsState = subscriptions;
          await _db
              .collection('debug_bridge_customer_subscriptions')
              .doc(subscriptionId)
              .set({
            'scheduledVisits': subscription['scheduledVisits'],
            'remainingCleanings': subscription['remainingCleanings'],
            'updatedAt': now,
          }, SetOptions(merge: true));
        }
      }
      _notifyDebugStateChanged();
      return {'ok': true, 'penaltyApplied': false};
    }
    if (_isTemporaryCustomerSession) {
      final slots = _temporaryCustomerScheduleSlots();
      final slotIndex = slots.indexWhere(
        (slot) => slot['id']?.toString() == slotId,
      );
      if (slotIndex == -1) {
        return {'ok': true, 'penaltyApplied': false};
      }
      final slot = Map<String, dynamic>.from(slots.removeAt(slotIndex));
      final now = Timestamp.now();
      final orderId = (slot['sourceOrderId'] ??
              slot['customerOrderId'] ??
              slot['orderId'] ??
              '')
          .toString();
      if (orderId.isNotEmpty) {
        final orders = _temporaryCustomerOrders();
        final orderIndex = orders.indexWhere((item) {
          final ids = [item['id']?.toString(), item['orderId']?.toString()];
          return ids.contains(orderId);
        });
        if (orderIndex != -1) {
          final next = Map<String, dynamic>.from(orders[orderIndex]);
          next['status'] = 'cancelled';
          next['orderStatus'] = 'cancelled';
          next['updatedAt'] = now;
          next['cancelledAt'] = now;
          orders[orderIndex] = next;
          _debugCustomerOrdersState = orders;
        }
      }
      final subscriptionId = (slot['subscriptionId'] ?? '').toString();
      if (subscriptionId.isNotEmpty) {
        final subscriptions = _temporaryCustomerSubscriptions();
        final subscriptionIndex = subscriptions.indexWhere(
          (item) => item['id'] == subscriptionId,
        );
        if (subscriptionIndex != -1) {
          final subscription = Map<String, dynamic>.from(
            subscriptions[subscriptionIndex],
          );
          _restoreOneCleaningAfterCancel(subscription, now);
          subscriptions[subscriptionIndex] = subscription;
          _debugCustomerSubscriptionsState = subscriptions;
        }
      }
      _debugCustomerScheduleSlotsState = slots;
      _notifyDebugStateChanged();
      return {'ok': true, 'penaltyApplied': false};
    }
    final result = await BackendApiService.instance.postMap(
      '/orders/$slotId/cancel',
      body: {'reason': 'Отменено клиентом'},
    );
    return {'ok': true, 'slotId': slotId, 'order': result};
  }

  Future<Map<String, dynamic>> getAvailableDates({
    required String subscriptionId,
    required DateTime month,
  }) async {
    if (_isDebugCustomer) {
      if (!await _debugOwnsSubscription(subscriptionId)) {
        return {
          'ok': false,
          'subscriptionId': subscriptionId,
          'availableDates': const <String>[],
        };
      }
      return _debugAvailableDates(month);
    }
    if (_isTemporaryCustomerSession) {
      final ownsSubscription = _temporaryCustomerSubscriptions().any(
        (item) => (item['id'] ?? '').toString() == subscriptionId,
      );
      if (!ownsSubscription) {
        return {
          'ok': false,
          'subscriptionId': subscriptionId,
          'availableDates': const <String>[],
          'dates': const <Map<String, dynamic>>[],
        };
      }
      return _debugAvailableDates(month);
    }
    return _getAvailableDatesDirect(
      subscriptionId: subscriptionId,
      month: month,
    );
  }

  Future<Map<String, dynamic>> getAvailableSlots({
    required String subscriptionId,
    required DateTime date,
  }) async {
    if (_isDebugCustomer) {
      if (!await _debugOwnsSubscription(subscriptionId)) {
        return {
          'ok': false,
          'subscriptionId': subscriptionId,
          'availableSlots': const <Map<String, dynamic>>[],
        };
      }
      return _debugAvailableSlots(date);
    }
    if (_isTemporaryCustomerSession) {
      final ownsSubscription = _temporaryCustomerSubscriptions().any(
        (item) => (item['id'] ?? '').toString() == subscriptionId,
      );
      if (!ownsSubscription) {
        return {
          'ok': false,
          'subscriptionId': subscriptionId,
          'availableSlots': const <Map<String, dynamic>>[],
          'slots': const <Map<String, dynamic>>[],
        };
      }
      return _debugAvailableSlots(date);
    }
    return _getAvailableSlotsDirect(subscriptionId: subscriptionId, date: date);
  }

  Future<Map<String, dynamic>> _getAvailableDatesDirect({
    required String subscriptionId,
    required DateTime month,
  }) async {
    final subscription = await _loadOwnedSubscription(subscriptionId);
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final today = DateTime.now();
    var cursor = monthStart;
    final minDate = LaunchConfig.bookingFloor(today);
    if (cursor.isBefore(minDate)) {
      cursor = minDate;
    }
    final validFrom = _asDay(subscription['validFrom']) ?? minDate;
    final validUntil = _effectiveSubscriptionValidUntil(subscription);
    final bookedOrders = await BackendApiService.instance.getList('/orders');
    final bookedDateKeys = bookedOrders
        .where(_isActiveScheduleSlot)
        .where(
          (slot) =>
              (slot['customer_package_id'] ?? '').toString() == subscriptionId,
        )
        .map((slot) => (slot['scheduled_date'] ?? '').toString())
        .where((key) => key.isNotEmpty)
        .toSet();
    final dates = <Map<String, dynamic>>[];
    while (!cursor.isAfter(monthEnd)) {
      final dateKey = _isoDate(cursor);
      final day = DateTime(cursor.year, cursor.month, cursor.day);
      if (!day.isBefore(validFrom) &&
          !day.isAfter(validUntil) &&
          !bookedDateKeys.contains(dateKey)) {
        try {
          final slots = await _loadBackendAvailableSlots(
            dateKey: dateKey,
            addressId: (subscription['addressId'] ?? '').toString(),
          );
          if (slots.isNotEmpty) {
            dates.add({
              'date': dateKey,
              'availableSlotsCount': slots.length,
              'backend': true,
            });
          }
        } catch (_) {
          // If backend cannot calculate this day, keep it unavailable.
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return {'ok': true, 'dates': dates, 'backend': true};
  }

  Future<Map<String, dynamic>> _getAvailableSlotsDirect({
    required String subscriptionId,
    required DateTime date,
  }) async {
    final dateKey = _isoDate(date);
    final subscription = await _loadOwnedSubscription(subscriptionId);
    final slots = await _loadBackendAvailableSlots(
      dateKey: dateKey,
      addressId: (subscription['addressId'] ?? '').toString(),
    );
    return {'ok': true, 'date': dateKey, 'slots': slots, 'backend': true};
  }

  Future<List<Map<String, dynamic>>> _loadBackendAvailableSlots({
    required String dateKey,
    String? addressId,
    List<String> addonIds = const [],
  }) async {
    final rows = await BackendApiService.instance.getList(
      '/scheduling/available-slots',
      query: {
        'date': dateKey,
        if (addressId != null && addressId.trim().isNotEmpty)
          'addressId': addressId.trim(),
        if (addonIds.isNotEmpty) 'addonIds': addonIds.join(','),
      },
    );
    return rows.map((slot) {
      final start = (slot['startTime'] ?? '').toString();
      final end = (slot['endTime'] ?? '').toString();
      return {
        ...slot,
        'time': end.isEmpty ? start : '$start - $end',
        'availableCleaners': _num(slot['cleanersCount']).toInt(),
        'totalDurationMinutes': _num(slot['durationMinutes']).toInt(),
        'backend': true,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _loadOwnedSubscription(
    String subscriptionId,
  ) async {
    final rows = await BackendApiService.instance.getList('/packages/my');
    final item = rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) => (row?['id'] ?? '').toString() == subscriptionId,
          orElse: () => null,
        );
    if (item == null) {
      throw StateError('Пакет не найден.');
    }
    return _mapBackendCustomerPackage(item);
  }

  bool _isActiveScheduleSlot(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString();
    final orderStatus = (slot['orderStatus'] ?? '').toString();
    if (status == 'canceled' ||
        status == 'cancelled' ||
        status == 'completed' ||
        orderStatus == 'canceled' ||
        orderStatus == 'cancelled' ||
        orderStatus == 'completed') {
      return false;
    }
    return true;
  }

  DateTime? _asDay(dynamic value) {
    DateTime? parsed;
    if (value is Timestamp) {
      parsed = value.toDate();
    } else if (value is DateTime) {
      parsed = value;
    } else if (value != null) {
      parsed = DateTime.tryParse(value.toString());
    }
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _subscriptionHasRemainingVisits(Map<String, dynamic> subscription) {
    final explicitRemaining =
        (subscription['remainingVisits'] as num?)?.toInt();
    if (explicitRemaining != null && explicitRemaining > 0) {
      return true;
    }
    final included = (subscription['includedVisits'] as num?)?.toInt() ??
        (subscription['visitsIncluded'] as num?)?.toInt() ??
        (subscription['totalVisits'] as num?)?.toInt() ??
        1;
    final used = (subscription['usedVisits'] as num?)?.toInt() ??
        (subscription['completedVisits'] as num?)?.toInt() ??
        0;
    return included - used > 0;
  }

  int _subscriptionMaxCleanings(Map<String, dynamic> subscription) {
    for (final key in const [
      'cleaningsPerMonth',
      'includedVisits',
      'visitsIncluded',
      'totalVisits',
      'totalCleanings',
      'cleaningCount',
      'packageCleanings',
    ]) {
      final value = (subscription[key] as num?)?.toInt();
      if (value != null && value > 0) {
        return value;
      }
    }
    final frequency = PackageCatalogUtils.cleaningsPerMonth(subscription);
    return frequency > 0 ? frequency : 99;
  }

  void _restoreOneCleaningAfterCancel(
    Map<String, dynamic> subscription,
    Object now,
  ) {
    final scheduledVisits =
        (subscription['scheduledVisits'] as num?)?.toInt() ?? 0;
    final remainingCleanings =
        (subscription['remainingCleanings'] as num?)?.toInt() ?? 0;
    final maxCleanings = _subscriptionMaxCleanings(subscription);
    subscription['scheduledVisits'] = (scheduledVisits - 1).clamp(0, 999);
    if (scheduledVisits > 0) {
      subscription['remainingCleanings'] = (remainingCleanings + 1).clamp(
        0,
        maxCleanings,
      );
    }
    subscription['updatedAt'] = now;
  }

  DateTime _effectiveSubscriptionValidUntil(Map<String, dynamic> subscription) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentValidUntil = _asDay(subscription['validUntil']) ??
        DateTime(now.year, now.month + 3, now.day);
    final status =
        (subscription['status'] ?? subscription['subscriptionStatus'] ?? '')
            .toString()
            .toLowerCase();
    if (status == 'active' &&
        _subscriptionHasRemainingVisits(subscription) &&
        currentValidUntil.isBefore(today)) {
      return DateTime(now.year, now.month + 1, now.day);
    }
    return currentValidUntil;
  }

  String _isoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _timeAfterMinutes(String start, int minutes) {
    final parts = start.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final end = DateTime(
      2000,
      1,
      1,
      hour,
      minute,
    ).add(Duration(minutes: minutes));
    return '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _normalizeSelectionAddonsDetailed(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      return (item['key'] ?? item['label'] ?? '').toString().isNotEmpty;
    }).map((item) {
      final quantity =
          ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      return {...item, 'quantity': quantity};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> subscriptionPurchasedAddons(
    Map<String, dynamic> subscription,
  ) async {
    final byKey = <String, Map<String, dynamic>>{};

    void addItems(dynamic raw) {
      for (final item in _normalizeSelectionAddonsDetailed(raw)) {
        final key = (item['key'] ?? item['label'] ?? '').toString();
        final previous = byKey[key];
        if (previous == null) {
          byKey[key] = Map<String, dynamic>.from(item);
        } else {
          byKey[key] = {
            ...previous,
            ...item,
            'quantity': ((previous['quantity'] as num?)?.toInt() ?? 1) +
                ((item['quantity'] as num?)?.toInt() ?? 1),
          };
        }
      }
    }

    void addFrom(Map<String, dynamic> source) {
      addItems(source['addonsDetailed']);
      addItems(source['separatePaymentAddons']);
      addItems(source['addons']);
    }

    addFrom(subscription);
    if (byKey.isNotEmpty) {
      return byKey.values.toList();
    }

    final ids = <String>{
      for (final key in const [
        'sourceOrderId',
        'orderId',
        'customerOrderId',
        'paymentId',
        'sourcePaymentId',
      ])
        if ((subscription[key] ?? '').toString().trim().isNotEmpty)
          (subscription[key] ?? '').toString().trim(),
    };
    final id = (subscription['id'] ?? '').toString().trim();
    if (id.startsWith('sub_') && id.length > 4) {
      ids.add(id.substring(4));
    }

    for (final sourceId in ids) {
      try {
        final details = await BackendApiService.instance.getMap(
          '/orders/$sourceId/details',
        );
        addFrom(Map<String, dynamic>.from(details['order'] ?? const {}));
        addItems(details['addons']);
        addItems(details['payments']);
      } catch (_) {
        // Details may be unavailable for legacy/local subscriptions.
      }
      if (byKey.isNotEmpty) {
        break;
      }
    }

    return byKey.values.toList();
  }

  List<String> _selectionAddonLabels(List<Map<String, dynamic>> items) {
    return items
        .map((item) => (item['label'] ?? item['key'] ?? '').toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  int _selectionAddonAmount(List<Map<String, dynamic>> items) {
    var total = 0;
    for (final item in items) {
      final price = (item['price'] as num?)?.toInt() ?? 0;
      final quantity =
          ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      total += price * quantity;
    }
    return total;
  }

  List<Map<String, dynamic>> _mergeDetailedAddons(dynamic base, dynamic extra) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final item in [
      ..._normalizeSelectionAddonsDetailed(base),
      ..._normalizeSelectionAddonsDetailed(extra),
    ]) {
      final key = (item['key'] ?? item['label'] ?? '').toString().trim();
      if (key.isEmpty) {
        continue;
      }
      final previous = byKey[key];
      if (previous == null) {
        byKey[key] = Map<String, dynamic>.from(item);
        continue;
      }
      final previousQuantity =
          ((previous['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      final nextQuantity =
          ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      byKey[key] = {
        ...previous,
        ...item,
        'quantity': previousQuantity + nextQuantity,
      };
    }
    return byKey.values.toList();
  }

  List<Map<String, dynamic>> _subtractDetailedAddons(
    dynamic base,
    dynamic removing, {
    dynamic fallbackLabels,
  }) {
    final removeByKey = <String, int>{};
    String itemKey(Map<String, dynamic> item) =>
        (item['key'] ?? item['label'] ?? item['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    for (final item in _normalizeSelectionAddonsDetailed(removing)) {
      final key = itemKey(item);
      if (key.isEmpty) continue;
      final quantity =
          ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      removeByKey[key] = (removeByKey[key] ?? 0) + quantity;
    }
    if (fallbackLabels is List) {
      for (final label in fallbackLabels) {
        final key = label.toString().trim().toLowerCase();
        if (key.isNotEmpty) {
          removeByKey.putIfAbsent(key, () => 1);
        }
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final item in _normalizeSelectionAddonsDetailed(base)) {
      final key = itemKey(item);
      final removeQuantity = removeByKey[key] ?? 0;
      if (removeQuantity <= 0) {
        result.add(item);
        continue;
      }
      final quantity =
          ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      final remaining = quantity - removeQuantity;
      if (remaining > 0) {
        result.add({...item, 'quantity': remaining});
      }
      removeByKey[key] = (removeQuantity - quantity).clamp(0, 999).toInt();
    }
    return result;
  }

  Future<void> _rollbackAddonRequestFromSlotDirect(
    String addonRequestId,
  ) async {
    await BackendApiService.instance.postMap(
      '/orders/$addonRequestId/addon-requests/reject',
    );
  }

  Future<Map<String, dynamic>> bookSchedule({
    required String subscriptionId,
    required List<Map<String, dynamic>> selections,
  }) async {
    if (_isDebugCustomer) {
      final subscriptions = await _debugMergedCustomerSubscriptions();
      final subscriptionIndex = subscriptions.indexWhere(
        (item) => item['id'] == subscriptionId,
      );
      if (subscriptionIndex == -1) {
        return {'ok': true, 'scheduledCount': 0};
      }

      final subscription = Map<String, dynamic>.from(
        subscriptions[subscriptionIndex],
      );
      final slots = _debugCustomerScheduleSlots();
      final monthlyPrice = (subscription['price'] as num?)?.toInt() ?? 0;
      final includedVisits =
          (subscription['includedVisits'] as num?)?.toInt() ??
              (subscription['cleaningsPerMonth'] as num?)?.toInt() ??
              1;
      final perCleaningPrice = includedVisits > 0
          ? (monthlyPrice / includedVisits).round()
          : monthlyPrice;
      final area = (subscription['area'] as num?)?.toInt() ?? 100;
      final now = DateTime.now();
      final nowTs = Timestamp.fromDate(now);
      for (final selection in selections) {
        final dateKey = (selection['date'] ?? '').toString();
        final time = (selection['time'] ?? '').toString();
        final date = DateTime.tryParse(dateKey);
        if (date == null || time.isEmpty) {
          continue;
        }
        final selectionAddonsDetailed = _normalizeSelectionAddonsDetailed(
          selection['addonsDetailed'],
        );
        final selectionAddons = _selectionAddonLabels(selectionAddonsDetailed);
        final orderId =
            'debug_order_${date.millisecondsSinceEpoch}_${time.hashCode.abs()}';
        final slotId =
            'debug_slot_${date.millisecondsSinceEpoch}_${time.hashCode}';
        final scheduledFor = Timestamp.fromDate(date);
        slots.add({
          'id': slotId,
          'sourceOrderId': orderId,
          'subscriptionId': subscriptionId,
          'status': 'pending_assignment',
          'scheduledFor': scheduledFor,
          'date': date.toIso8601String(),
          'time': time,
          'package': subscription['package'],
          'residentialComplex': 'ЖК Триумф',
          'address': 'ЖК Триумф, кв. 45',
          'cleanerName': 'Будет назначен',
          'cleanerPhone': '',
          'customerId': 'customer_demo',
          'totalDurationMinutes': 180,
          'addons': selectionAddons,
          'addonsDetailed': selectionAddonsDetailed,
          'area': area,
          'price': perCleaningPrice,
          'createdAt': nowTs,
        });
        try {
          await _db.collection('debug_bridge_orders').doc(orderId).set({
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
            'id': orderId,
            'orderId': orderId,
            'customerId': 'customer_demo',
            'customerName': 'Асет',
            'customerPhone': '+7 708 636 21 53',
            'subscriptionId': subscriptionId,
            'status': 'pending_assignment',
            'orderStatus': 'pending_assignment',
            'paymentStatus': 'paid',
            'scheduledFor': scheduledFor,
            'time': time,
            'package': subscription['package'],
            'frequencyLabel':
                subscription['frequencyLabel'] ?? subscription['package'],
            'price': perCleaningPrice,
            'area': area,
            'addons': selectionAddons,
            'addonsDetailed': selectionAddonsDetailed,
            'address': 'ЖК Триумф, кв. 45',
            'residentialComplex': 'ЖК Триумф',
            'createdAt': nowTs,
            'updatedAt': nowTs,
          }, SetOptions(merge: true));
          await _db.collection('debug_bridge_cleaner_slots').doc(orderId).set({
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
            'id': orderId,
            'sourceOrderId': orderId,
            'customerOrderId': orderId,
            'subscriptionId': subscriptionId,
            'customerId': 'customer_demo',
            'status': 'pending_assignment',
            'scheduledFor': scheduledFor,
            'date': scheduledFor,
            'time': time,
            'customerName': 'Асет',
            'customerPhone': '+7 708 636 21 53',
            'residentialComplex': 'ЖК Триумф',
            'address': 'ЖК Триумф, кв. 45',
            'package': subscription['package'],
            'price': perCleaningPrice,
            'area': area,
            'addons': selectionAddons,
            'addonsDetailed': selectionAddonsDetailed,
            'totalDurationMinutes': 180,
            'estimatedDurationMinutes': 180,
            'createdAt': nowTs,
            'updatedAt': nowTs,
          }, SetOptions(merge: true));
        } catch (_) {
          // Shared debug bridge is best-effort; local customer flow must still work.
        }
      }

      final scheduledVisits =
          (subscription['scheduledVisits'] as num?)?.toInt() ?? 0;
      final remainingCleanings =
          (subscription['remainingCleanings'] as num?)?.toInt() ?? 0;
      subscription['scheduledVisits'] = scheduledVisits + selections.length;
      subscription['remainingCleanings'] =
          (remainingCleanings - selections.length).clamp(0, 99);
      subscriptions[subscriptionIndex] = subscription;
      _debugCustomerSubscriptionsState = subscriptions;
      await _db
          .collection('debug_bridge_customer_subscriptions')
          .doc(subscriptionId)
          .set({
        'scheduledVisits': subscription['scheduledVisits'],
        'remainingCleanings': subscription['remainingCleanings'],
        'updatedAt': nowTs,
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return {'ok': true, 'scheduledCount': selections.length};
    }
    if (_isTemporaryCustomerSession) {
      final subscriptions = _temporaryCustomerSubscriptions();
      final subscriptionIndex = subscriptions.indexWhere(
        (item) => item['id'] == subscriptionId,
      );
      if (subscriptionIndex == -1) {
        return {'ok': true, 'scheduledCount': 0, 'localFallback': true};
      }

      final subscription = Map<String, dynamic>.from(
        subscriptions[subscriptionIndex],
      );
      final slots = _temporaryCustomerScheduleSlots();
      final orders = _temporaryCustomerOrders();
      final profile = _temporaryCustomerProfile();
      final monthlyPrice = (subscription['price'] as num?)?.toInt() ?? 0;
      final includedVisits =
          (subscription['includedVisits'] as num?)?.toInt() ??
              (subscription['cleaningsPerMonth'] as num?)?.toInt() ??
              1;
      final perCleaningPrice = includedVisits > 0
          ? (monthlyPrice / includedVisits).round()
          : monthlyPrice;
      final area = (subscription['area'] as num?)?.toInt() ?? 100;
      final now = DateTime.now();
      final nowTs = Timestamp.fromDate(now);
      final customerId = _uidOrNull ?? 'temp_customer';
      final customerName =
          (profile['name'] ?? profile['fullName'] ?? 'Пользователь').toString();
      final customerPhone = (profile['phone'] ?? '').toString();
      String address = '';
      final addresses = (profile['addresses'] as List?) ?? const [];
      if (addresses.isNotEmpty) {
        address = ((addresses.first as Map)['address'] ?? '').toString();
      }
      if (address.isEmpty) {
        final menu = (profile['menu'] as List?) ?? const [];
        if (menu.isNotEmpty) {
          address = ((menu.first as Map)['subtitle'] ?? '').toString();
        }
      }
      for (final selection in selections) {
        final dateKey = (selection['date'] ?? '').toString();
        final time = (selection['time'] ?? '').toString();
        final date = DateTime.tryParse(dateKey);
        if (date == null || time.isEmpty) {
          continue;
        }
        final selectionAddonsDetailed = _normalizeSelectionAddonsDetailed(
          selection['addonsDetailed'],
        );
        final selectionAddons = _selectionAddonLabels(selectionAddonsDetailed);
        final orderId =
            'temp_sched_order_${date.millisecondsSinceEpoch}_${time.hashCode.abs()}';
        final slotId =
            'temp_sched_slot_${date.millisecondsSinceEpoch}_${time.hashCode.abs()}';
        final scheduledFor = Timestamp.fromDate(date);
        slots.add({
          'id': slotId,
          'sourceOrderId': orderId,
          'subscriptionId': subscriptionId,
          'status': 'pending_assignment',
          'scheduledFor': scheduledFor,
          'date': date.toIso8601String(),
          'time': time,
          'package': subscription['package'],
          'address': address,
          'customerId': customerId,
          'cleanerName': 'Будет назначен',
          'cleanerPhone': '',
          'totalDurationMinutes': 180,
          'price': perCleaningPrice,
          'addons': selectionAddons,
          'addonsDetailed': selectionAddonsDetailed,
          'area': area,
          'createdAt': nowTs,
          'updatedAt': nowTs,
        });
        orders.add({
          'id': orderId,
          'orderId': orderId,
          'customerId': customerId,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'subscriptionId': subscriptionId,
          'status': 'pending_assignment',
          'orderStatus': 'pending_assignment',
          'paymentStatus': 'paid',
          'scheduledFor': scheduledFor,
          'date': scheduledFor,
          'time': time,
          'package': subscription['package'],
          'frequencyLabel':
              subscription['frequencyLabel'] ?? subscription['package'],
          'price': perCleaningPrice,
          'addons': selectionAddons,
          'addonsDetailed': selectionAddonsDetailed,
          'area': area,
          'address': address,
          'createdAt': nowTs,
          'updatedAt': nowTs,
        });
      }

      final scheduledVisits =
          (subscription['scheduledVisits'] as num?)?.toInt() ?? 0;
      final remainingCleanings =
          (subscription['remainingCleanings'] as num?)?.toInt() ?? 0;
      subscription['scheduledVisits'] = scheduledVisits + selections.length;
      subscription['remainingCleanings'] =
          (remainingCleanings - selections.length).clamp(0, 99);
      subscription['updatedAt'] = nowTs;
      subscriptions[subscriptionIndex] = subscription;
      _debugCustomerScheduleSlotsState = slots;
      _debugCustomerOrdersState = orders;
      _debugCustomerSubscriptionsState = subscriptions;
      _debugCustomerProfileState = {
        ...profile,
        'ordersCount': orders.length,
        'updatedAt': nowTs,
      };
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'scheduledCount': selections.length,
        'localFallback': true,
      };
    }
    return _bookScheduleDirect(
      subscriptionId: subscriptionId,
      selections: selections,
    );
  }

  Future<Map<String, dynamic>> _bookScheduleDirect({
    required String subscriptionId,
    required List<Map<String, dynamic>> selections,
  }) async {
    var backendScheduledCount = 0;
    final createdOrders = <Map<String, dynamic>>[];
    final paymentResults = <Map<String, dynamic>>[];
    for (final selection in selections) {
      final dateKey = (selection['date'] ?? '').toString();
      final time = (selection['time'] ?? '').toString().trim();
      final startTime = time.split(' - ').first.trim();
      if (dateKey.isEmpty || startTime.isEmpty) {
        continue;
      }
      final addonIds =
          _normalizeSelectionAddonsDetailed(selection['addonsDetailed'])
              .map(
                (addon) => (addon['id'] ?? addon['addonId'] ?? '').toString(),
              )
              .where((id) => id.isNotEmpty)
              .toList();
      final created = await BackendApiService.instance.postMap(
        '/orders',
        body: {
          'customerPackageId': subscriptionId,
          'date': dateKey,
          'startTime': startTime,
          if (addonIds.isNotEmpty) 'addonIds': addonIds,
        },
      );
      createdOrders.add(created);
      backendScheduledCount++;
      final order = created['order'];
      final orderId = order is Map ? (order['id'] ?? '').toString() : '';
      final bonusToSpend = math.max(
        0,
        (selection['bonusToSpend'] as num?)?.toInt() ?? 0,
      );
      final kaspiPhone = (selection['kaspiPhone'] ?? '').toString().trim();
      if (orderId.isNotEmpty && (addonIds.isNotEmpty || bonusToSpend > 0)) {
        final payment = await BackendApiService.instance.postMap(
          '/orders/$orderId/pay',
          body: {
            'provider': 'kaspi',
            'useBonus': bonusToSpend > 0,
            'requestedBonus': bonusToSpend,
            if (kaspiPhone.isNotEmpty) 'invoicePhone': kaspiPhone,
          },
        );
        paymentResults.add(payment);
      }
    }
    return {
      'ok': true,
      'scheduledCount': backendScheduledCount,
      'orders': createdOrders,
      'payments': paymentResults,
      'backend': true,
    };
  }

  int _scheduleAreaMinutes(int area) {
    if (area <= 0) {
      return 120;
    }
    return (90 + area * 1.2).round().clamp(90, 420);
  }

  Future<Map<String, dynamic>> reschedule({
    required String slotId,
    required DateTime date,
    required String time,
  }) async {
    if (_isTemporaryCustomerSession) {
      final slots = _temporaryCustomerScheduleSlots();
      final index = slots.indexWhere(
        (slot) => slot['id']?.toString() == slotId,
      );
      if (index == -1) {
        return {'ok': true, 'slotId': slotId, 'localFallback': true};
      }
      final next = Map<String, dynamic>.from(slots[index]);
      next['time'] = time.trim();
      next['scheduledFor'] = Timestamp.fromDate(date);
      next['date'] = date.toIso8601String();
      next['status'] = 'rescheduled';
      next['updatedAt'] = Timestamp.now();
      slots[index] = next;
      _debugCustomerScheduleSlotsState = slots;
      final orderId = (next['sourceOrderId'] ??
              next['customerOrderId'] ??
              next['orderId'] ??
              '')
          .toString();
      if (orderId.isNotEmpty) {
        final orders = _temporaryCustomerOrders();
        final orderIndex = orders.indexWhere((item) {
          final ids = [item['id']?.toString(), item['orderId']?.toString()];
          return ids.contains(orderId);
        });
        if (orderIndex != -1) {
          final order = Map<String, dynamic>.from(orders[orderIndex]);
          order['time'] = time.trim();
          order['scheduledFor'] = Timestamp.fromDate(date);
          order['date'] = Timestamp.fromDate(date);
          order['status'] = 'rescheduled';
          order['orderStatus'] = 'rescheduled';
          order['updatedAt'] = next['updatedAt'];
          orders[orderIndex] = order;
          _debugCustomerOrdersState = orders;
        }
      }
      _notifyDebugStateChanged();
      return {'ok': true, 'slotId': slotId, 'localFallback': true};
    }
    final result = await BackendApiService.instance.postMap(
      '/orders/$slotId/reschedule',
      body: {'date': _dateOnlyText(date), 'time': time},
    );
    return {'ok': true, 'slotId': slotId, 'order': result};
  }

  Future<Map<String, dynamic>> updateScheduledCleaning({
    required String slotId,
    DateTime? date,
    String? time,
    List<Map<String, dynamic>>? addonsDetailed,
  }) async {
    if (_isTemporaryCustomerSession) {
      final slots = _temporaryCustomerScheduleSlots();
      final index = slots.indexWhere(
        (slot) => slot['id']?.toString() == slotId,
      );
      if (index == -1) {
        return {'ok': true, 'slotId': slotId, 'localFallback': true};
      }
      final next = Map<String, dynamic>.from(slots[index]);
      final orderId = (next['sourceOrderId'] ??
              next['customerOrderId'] ??
              next['orderId'] ??
              '')
          .toString();
      if (date != null) {
        final existing = _toDateTime(next['scheduledFor'] ?? next['date']);
        final merged = DateTime(
          date.year,
          date.month,
          date.day,
          existing.hour,
          existing.minute,
        );
        next['scheduledFor'] = Timestamp.fromDate(merged);
        next['date'] = merged.toIso8601String();
      }
      if (time != null && time.trim().isNotEmpty) {
        next['time'] = time.trim();
        final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(time);
        if (match != null) {
          final base = _toDateTime(next['scheduledFor'] ?? next['date']);
          final hour = int.tryParse(match.group(1) ?? '') ?? base.hour;
          final minute = int.tryParse(match.group(2) ?? '') ?? base.minute;
          final merged = DateTime(
            base.year,
            base.month,
            base.day,
            hour,
            minute,
          );
          next['scheduledFor'] = Timestamp.fromDate(merged);
          next['date'] = merged.toIso8601String();
        }
      }
      if (addonsDetailed != null) {
        next['addonsDetailed'] = addonsDetailed;
      }
      next['updatedAt'] = Timestamp.now();
      slots[index] = next;
      _debugCustomerScheduleSlotsState = slots;
      if (orderId.isNotEmpty) {
        final orders = _temporaryCustomerOrders();
        final orderIndex = orders.indexWhere((item) {
          final ids = [item['id']?.toString(), item['orderId']?.toString()];
          return ids.contains(orderId);
        });
        if (orderIndex != -1) {
          final order = Map<String, dynamic>.from(orders[orderIndex]);
          if (next['scheduledFor'] != null) {
            order['scheduledFor'] = next['scheduledFor'];
            order['date'] = next['scheduledFor'];
          }
          if (next['time'] != null) {
            order['time'] = next['time'];
          }
          if (addonsDetailed != null) {
            order['addonsDetailed'] = addonsDetailed;
          }
          order['updatedAt'] = next['updatedAt'];
          orders[orderIndex] = order;
          _debugCustomerOrdersState = orders;
        }
      }
      _notifyDebugStateChanged();
      return {'ok': true, 'slotId': slotId, 'localFallback': true};
    }
    if (_isDebugCustomer) {
      final slots = _debugCustomerScheduleSlots();
      final index = slots.indexWhere(
        (slot) => slot['id']?.toString() == slotId,
      );
      Map<String, dynamic>? baseSlot;
      if (index != -1) {
        baseSlot = Map<String, dynamic>.from(slots[index]);
      } else {
        final sharedSlots =
            await _debugSharedCustomerScheduleSlotsStream().first;
        final sharedMatch =
            sharedSlots.cast<Map<String, dynamic>?>().firstWhere(
                  (item) => item?['id']?.toString() == slotId,
                  orElse: () => null,
                );
        if (sharedMatch != null) {
          baseSlot = Map<String, dynamic>.from(sharedMatch);
        }
      }
      if (baseSlot == null) {
        return {'ok': true, 'slotId': slotId};
      }
      final next = Map<String, dynamic>.from(baseSlot);
      final orderId = (next['sourceOrderId'] ??
              next['customerOrderId'] ??
              next['orderId'] ??
              '')
          .toString();
      if (date != null) {
        final existing = _toDateTime(next['scheduledFor'] ?? next['date']);
        final merged = DateTime(
          date.year,
          date.month,
          date.day,
          existing.hour,
          existing.minute,
        );
        next['scheduledFor'] = Timestamp.fromDate(merged);
        next['date'] = merged.toIso8601String();
      }
      if (time != null && time.trim().isNotEmpty) {
        next['time'] = time.trim();
        final match = RegExp(r'(\\d{1,2}):(\\d{2})').firstMatch(time);
        if (match != null) {
          final base = _toDateTime(next['scheduledFor'] ?? next['date']);
          final hour = int.tryParse(match.group(1) ?? '') ?? base.hour;
          final minute = int.tryParse(match.group(2) ?? '') ?? base.minute;
          final merged = DateTime(
            base.year,
            base.month,
            base.day,
            hour,
            minute,
          );
          next['scheduledFor'] = Timestamp.fromDate(merged);
          next['date'] = merged.toIso8601String();
        }
      }
      if (addonsDetailed != null) {
        next['addonsDetailed'] = addonsDetailed;
      }
      next['updatedAt'] = Timestamp.now();
      if (index != -1) {
        slots[index] = next;
      } else {
        slots.add(next);
      }
      if (orderId.isNotEmpty) {
        try {
          await _db.collection('debug_bridge_orders').doc(orderId).set({
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
            if (next['scheduledFor'] != null)
              'scheduledFor': next['scheduledFor'],
            if (next['time'] != null) 'time': next['time'],
            if (addonsDetailed != null) 'addonsDetailed': addonsDetailed,
            'updatedAt': next['updatedAt'],
          }, SetOptions(merge: true));
          await _db.collection('debug_bridge_cleaner_slots').doc(orderId).set({
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
            if (next['scheduledFor'] != null)
              'scheduledFor': next['scheduledFor'],
            if (next['date'] != null)
              'date': next['scheduledFor'] ?? next['date'],
            if (next['time'] != null) 'time': next['time'],
            if (addonsDetailed != null) 'addonsDetailed': addonsDetailed,
            'updatedAt': next['updatedAt'],
          }, SetOptions(merge: true));
        } catch (_) {
          // Shared debug bridge is best-effort; local customer flow must still work.
        }
      }
      _notifyDebugStateChanged();
      return {'ok': true, 'slotId': slotId};
    }
    Map<String, dynamic> result = {};
    if (date != null || time != null) {
      result = await BackendApiService.instance
          .postMap('/orders/$slotId/reschedule', body: {
        if (date != null) 'date': _dateOnlyText(date),
        if (time != null) 'time': time.split(' - ').first,
      });
    }
    if (addonsDetailed != null) {
      result = await BackendApiService.instance.postMap(
          '/orders/$slotId/addons',
          body: {'addonsDetailed': addonsDetailed});
    }
    return {...result, 'ok': true, 'slotId': slotId};
  }

  Future<Map<String, dynamic>> submitKaspiInvoiceRequest({
    required String orderId,
    required String kaspiPhone,
  }) async {
    if (_isLocalFallbackOrderId(orderId)) {
      return _submitLocalKaspiInvoiceFallback(
        orderId: orderId,
        kaspiPhone: kaspiPhone,
      );
    }
    if (_isDebugCustomer) {
      if (!await _debugCanAccessOrder(orderId)) {
        return {'ok': false, 'orderId': orderId, 'kaspiPhone': kaspiPhone};
      }
      final orders = _debugCustomerOrders();
      final index = orders.indexWhere(
        (item) => item['id']?.toString() == orderId,
      );
      if (index != -1) {
        final updatedOrder = {
          ...orders[index],
          'paymentStatus': 'invoice_requested',
          'kaspiPhone': kaspiPhone,
          'status': 'pending_assignment',
        };
        orders[index] = updatedOrder;
        try {
          await _db.collection('debug_bridge_orders').doc(orderId).set({
            'sourceDebugUid': _uidOrNull ?? 'customer_demo',
            'orderId': orderId,
            'paymentStatus': 'invoice_requested',
            'kaspiPhone': kaspiPhone,
            'status': 'pending_assignment',
            'orderStatus': 'pending_assignment',
            'customerId': updatedOrder['customerId'] ?? 'customer_demo',
            'customerName': updatedOrder['customerName'] ?? 'Асет',
            'customerPhone':
                updatedOrder['customerPhone'] ?? '+7 708 636 21 53',
            'address': updatedOrder['address'],
            'package': updatedOrder['package'],
            'price': updatedOrder['price'],
            'scheduledFor': updatedOrder['scheduledFor'],
            'createdAt': updatedOrder['createdAt'] ?? Timestamp.now(),
            'updatedAt': Timestamp.now(),
          }, SetOptions(merge: true));
        } catch (_) {
          // Shared debug bridge is best-effort; local flow must still work.
        }
        _notifyDebugStateChanged();
      }
      return {
        'ok': true,
        'orderId': orderId,
        'kaspiPhone': kaspiPhone,
        'localFallback': false,
      };
    }
    if (_useDebugFixtures) {
      return {
        'ok': true,
        'orderId': orderId,
        'kaspiPhone': kaspiPhone,
        'localFallback': false,
      };
    }

    try {
      final result = await BackendApiService.instance.postMap(
        '/payments/$orderId/kaspi-invoice',
        body: {'invoicePhone': kaspiPhone},
      );
      return {...result, 'localFallback': false, 'backend': true};
    } on BackendApiException catch (error) {
      if (error.statusCode == 404) {
        final result = await BackendApiService.instance.postMap(
          '/orders/$orderId/pay',
          body: {'provider': 'kaspi', 'invoicePhone': kaspiPhone},
        );
        return {...result, 'localFallback': false, 'backend': true};
      }
      throw FlutterError(error.message);
    }
  }

  Future<Map<String, dynamic>> createBccPaymentSession({
    required String orderId,
  }) async {
    if (_isDebugCustomer ||
        _useDebugFixtures ||
        _isLocalFallbackOrderId(orderId)) {
      return {
        'ok': true,
        'orderId': orderId,
        'provider': 'bcc_ecommerce_webview',
        'paymentHtml': '''
<!doctype html>
<html lang="ru">
<meta name="viewport" content="width=device-width, initial-scale=1">
<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f6fbf7;font-family:Arial;color:#263f34">
  <div style="text-align:center;padding:24px">
    <h3>Тестовая онлайн-оплата</h3>
    <p>Заказ $orderId</p>
  </div>
</body>
</html>
''',
        'actionUrl': 'about:blank',
        'localFallback': false,
      };
    }

    try {
      final result = await BackendApiService.instance.postMap(
        '/payments/$orderId/bcc-session',
      );
      return {...result, 'backend': true};
    } on BackendApiException catch (error) {
      if (error.statusCode == 404) {
        final payment = await BackendApiService.instance.postMap(
          '/orders/$orderId/pay',
          body: {'provider': 'bcc'},
        );
        final paymentId =
            ((payment['payment'] as Map?)?['id'] ?? '').toString();
        if (paymentId.isEmpty) {
          throw FlutterError('Не удалось создать онлайн-оплату.');
        }
        final result = await BackendApiService.instance.postMap(
          '/payments/$paymentId/bcc-session',
        );
        return {...result, 'backend': true};
      }
      throw FlutterError(error.message);
    }
  }

  Future<Map<String, dynamic>> _createLocalCustomerOrderFallback({
    required int amount,
    required String customerId,
    required String packageName,
    String? packageId,
    int? cleaningsPerMonth,
    required String accessMethod,
    required List<String> addons,
    List<Map<String, dynamic>> addonsDetailed = const [],
    required String frequencyLabel,
    required int area,
    String? address,
    String? residentialComplex,
    String? entrance,
    String? apartment,
    String? houseId,
    String? slotId,
    String? sourceOrderId,
    String? subscriptionId,
    int billingPeriodMonths = 1,
  }) async {
    final orderId = 'temp_order_${DateTime.now().millisecondsSinceEpoch}';
    final effectiveCustomerId = customerId.trim().isNotEmpty
        ? customerId.trim()
        : (_uidOrNull ?? AuthService.temporarySessionUid ?? 'temp_customer');
    final now = DateTime.now().toIso8601String();
    final house = await _resolveHouseForAssignment({
      'houseId': houseId ?? '',
      'address': address ?? '',
      'residentialComplex': residentialComplex ?? '',
    });
    final resolvedHouseId = houseId?.trim().isNotEmpty == true
        ? houseId!.trim()
        : (house?['id'] ?? '').toString();
    final resolvedAddress = (address ?? '').trim().isNotEmpty
        ? address!.trim()
        : (house?['address'] ?? '').toString();
    final resolvedResidentialComplex = (residentialComplex ?? '')
            .trim()
            .isNotEmpty
        ? residentialComplex!.trim()
        : (house?['residentialComplex'] ?? house?['title'] ?? '').toString();
    final serviceArea = (house?['serviceArea'] ??
            house?['zoneId'] ??
            house?['clusterName'] ??
            '')
        .toString();
    final serviceAreaId =
        (house?['serviceAreaId'] ?? house?['zoneId'] ?? '').toString();
    final zoneId = (house?['zoneId'] ?? '').toString();
    final clusterName = (house?['clusterName'] ?? '').toString();
    final orders = _temporaryCustomerOrders()
      ..removeWhere((item) {
        final status = (item['status'] ?? '').toString().toLowerCase();
        final paymentStatus =
            (item['paymentStatus'] ?? '').toString().toLowerCase();
        return _matchesCurrentCustomerOrder(item) &&
            (status == 'pending_payment' ||
                status == 'pending_assignment' ||
                paymentStatus == 'pending_invoice' ||
                paymentStatus == 'invoice_requested');
      });
    orders.insert(0, {
      'id': orderId,
      'status': 'pending_payment',
      'paymentStatus': 'pending_invoice',
      'customerId': effectiveCustomerId,
      'package': packageName,
      'packageId': packageId,
      'price': amount,
      'area': area,
      'address': resolvedAddress,
      'residentialComplex': resolvedResidentialComplex,
      'entrance': entrance ?? '',
      'apartment': apartment ?? '',
      'houseId': resolvedHouseId,
      if (slotId != null && slotId.isNotEmpty) 'slotId': slotId,
      if (sourceOrderId != null && sourceOrderId.isNotEmpty)
        'sourceOrderId': sourceOrderId,
      if (subscriptionId != null && subscriptionId.isNotEmpty)
        'subscriptionId': subscriptionId,
      'serviceArea': serviceArea,
      'serviceAreaId': serviceAreaId,
      'zoneId': zoneId,
      'clusterName': clusterName,
      'addons': addons,
      'addonsDetailed': addonsDetailed,
      'frequencyLabel': frequencyLabel,
      'billingPeriodMonths': billingPeriodMonths,
      'cleaningsPerMonth': cleaningsPerMonth ?? 1,
      'accessMethod': accessMethod,
      'createdAt': now,
      'updatedAt': now,
      'customerName': 'Пользователь',
      'customerPhone': '',
      'localFallback': true,
    });
    _storeTemporaryCustomerOrders(orders);
    try {
      await _db.collection('debug_bridge_orders').doc(orderId).set({
        'id': orderId,
        'orderId': orderId,
        'sourceDebugUid': _uidOrNull ?? effectiveCustomerId,
        'customerId': effectiveCustomerId,
        'status': 'pending_payment',
        'orderStatus': 'pending_payment',
        'paymentStatus': 'pending_invoice',
        'package': packageName,
        'packageId': packageId,
        'price': amount,
        'currency': 'KZT',
        'area': area,
        'address': resolvedAddress,
        'residentialComplex': resolvedResidentialComplex,
        'entrance': entrance ?? '',
        'apartment': apartment ?? '',
        'houseId': resolvedHouseId,
        'serviceArea': serviceArea,
        'serviceAreaId': serviceAreaId,
        'zoneId': zoneId,
        'clusterName': clusterName,
        'addons': addons,
        'addonsDetailed': addonsDetailed,
        'frequencyLabel': frequencyLabel,
        'billingPeriodMonths': billingPeriodMonths,
        'cleaningsPerMonth': cleaningsPerMonth ?? 1,
        'accessMethod': accessMethod,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'customerName': 'Пользователь',
        'customerPhone': '',
        'localFallback': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // Cross-domain debug bridge is best-effort; local customer flow must still work.
    }
    return {
      'ok': true,
      'orderId': orderId,
      'customerId': effectiveCustomerId,
      'amount': amount,
      'temporary': true,
      'localFallback': true,
    };
  }

  Future<Map<String, dynamic>> _submitLocalKaspiInvoiceFallback({
    required String orderId,
    required String kaspiPhone,
  }) async {
    final orders = _temporaryCustomerOrders();
    final index = orders.indexWhere(
      (item) => item['id']?.toString() == orderId,
    );
    if (index != -1) {
      orders[index] = {
        ...orders[index],
        'paymentStatus': 'invoice_requested',
        'status': 'pending_assignment',
        'kaspiPhone': kaspiPhone,
        'updatedAt': DateTime.now().toIso8601String(),
        'localFallback': true,
      };
      _storeTemporaryCustomerOrders(orders);
    }
    try {
      await _db.collection('debug_bridge_orders').doc(orderId).set({
        'orderId': orderId,
        'sourceDebugUid': _uidOrNull ?? 'temp_customer',
        'paymentStatus': 'invoice_requested',
        'status': 'pending_assignment',
        'orderStatus': 'pending_assignment',
        'kaspiPhone': kaspiPhone,
        'updatedAt': Timestamp.now(),
        'localFallback': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // Cross-domain debug bridge is best-effort; local customer flow must still work.
    }
    return {
      'ok': true,
      'orderId': orderId,
      'kaspiPhone': kaspiPhone,
      'temporary': true,
      'localFallback': true,
    };
  }

  Future<Map<String, dynamic>> _cancelLocalPendingOrderFallback({
    required String orderId,
  }) async {
    final orders = _temporaryCustomerOrders();
    final index = orders.indexWhere(
      (item) => item['id']?.toString() == orderId,
    );
    if (index == -1) {
      return {'ok': true, 'orderId': orderId, 'localFallback': true};
    }
    orders[index] = {
      ...orders[index],
      'status': 'canceled',
      'orderStatus': 'canceled',
      'paymentStatus': 'canceled',
      'updatedAt': DateTime.now().toIso8601String(),
      'cancelledAt': DateTime.now().toIso8601String(),
      'localFallback': true,
    };
    _storeTemporaryCustomerOrders(orders);
    try {
      await _db.collection('debug_bridge_orders').doc(orderId).set({
        'orderId': orderId,
        'sourceDebugUid': _uidOrNull ?? 'temp_customer',
        'status': 'canceled',
        'orderStatus': 'canceled',
        'paymentStatus': 'canceled',
        'updatedAt': Timestamp.now(),
        'cancelledAt': Timestamp.now(),
        'localFallback': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // Cross-domain debug bridge is best-effort; local customer flow must still work.
    }
    return {'ok': true, 'orderId': orderId, 'localFallback': true};
  }

  Future<Map<String, dynamic>> cancelPendingOrder({
    required String orderId,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      throw FlutterError('У заказа нет номера для отмены.');
    }
    orderId = normalizedOrderId;
    if (_isTemporaryCustomerSession || _isLocalFallbackOrderId(orderId)) {
      return _cancelLocalPendingOrderFallback(orderId: orderId);
    }
    if (_isDebugCustomer) {
      if (!await _debugCanAccessOrder(orderId)) {
        return {'ok': false, 'orderId': orderId};
      }
      final orders = _debugCustomerOrders();
      final index = orders.indexWhere(
        (item) => item['id']?.toString() == orderId,
      );
      if (index != -1) {
        orders[index] = {
          ...orders[index],
          'status': 'canceled',
          'orderStatus': 'canceled',
          'paymentStatus': 'canceled',
          'updatedAt': Timestamp.now(),
          'cancelledAt': Timestamp.now(),
        };
      }
      try {
        await _db.collection('debug_bridge_orders').doc(orderId).set({
          'orderId': orderId,
          'sourceDebugUid': _uidOrNull ?? 'customer_demo',
          'status': 'canceled',
          'orderStatus': 'canceled',
          'paymentStatus': 'canceled',
          'updatedAt': Timestamp.now(),
          'cancelledAt': Timestamp.now(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Shared debug bridge is best-effort; local customer flow must still work.
      }
      _notifyDebugStateChanged();
      return {'ok': true, 'orderId': orderId};
    }
    if (_useDebugFixtures) {
      return {'ok': true, 'orderId': orderId};
    }

    try {
      final mapped = await BackendApiService.instance.postMap(
        '/orders/$orderId/cancel',
      );
      try {
        await _db.collection('debug_bridge_orders').doc(orderId).set({
          'orderId': orderId,
          'sourceDebugUid': _uidOrNull ?? 'customer',
          'status': 'canceled',
          'orderStatus': 'canceled',
          'paymentStatus': 'canceled',
          'updatedAt': Timestamp.now(),
          'cancelledAt': Timestamp.now(),
          'localFallback': false,
        }, SetOptions(merge: true));
      } catch (_) {
        // Bridge sync is best-effort; live cancellation must still succeed.
      }
      return mapped;
    } catch (_) {
      return _cancelPendingOrderDirect(orderId: orderId);
    }
  }

  Future<Map<String, dynamic>> _cancelPendingOrderDirect({
    required String orderId,
  }) async {
    return BackendApiService.instance.postMap('/orders/$orderId/cancel');
  }

  bool _matchesCurrentCustomerOrder(Map<String, dynamic> item) {
    final currentCustomerId = _uidOrNull?.trim();
    final orderCustomerId = (item['customerId'] ?? '').toString().trim();
    if (currentCustomerId == null || currentCustomerId.isEmpty) {
      return true;
    }
    if (orderCustomerId.isEmpty) {
      return true;
    }
    return orderCustomerId == currentCustomerId;
  }

  Stream<List<Map<String, dynamic>>> _customerBridgeOrdersStream(String uid) {
    final localOrderIds = _temporaryCustomerOrders()
        .map((item) => (item['id'] ?? item['orderId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    return _resilientStream<List<Map<String, dynamic>>>(
      _queryStreamOnce(_db.collection('debug_bridge_orders')).map((docs) {
        final items = docs.where((item) {
          final orderId = (item['id'] ?? item['orderId'] ?? '').toString();
          final customerId = (item['customerId'] ?? '').toString().trim();
          final sourceDebugUid =
              (item['sourceDebugUid'] ?? '').toString().trim();
          return customerId == uid ||
              sourceDebugUid == uid ||
              localOrderIds.contains(orderId);
        }).toList();
        items.sort((a, b) {
          final aDate = _toDateTime(a['updatedAt'] ?? a['createdAt']);
          final bDate = _toDateTime(b['updatedAt'] ?? b['createdAt']);
          return bDate.compareTo(aDate);
        });
        return items;
      }),
      fallback: () => const <Map<String, dynamic>>[],
    );
  }

  bool _isLocalFallbackOrder(Map<String, dynamic> item) {
    final orderId = (item['id'] ?? item['orderId'] ?? '').toString().trim();
    if (orderId.startsWith('temp_order_')) {
      return true;
    }
    return item['localFallback'] == true;
  }

  bool _isLocalFallbackOrderId(String orderId) =>
      orderId.trim().startsWith('temp_order_');

  List<Map<String, dynamic>> _mergeLocalFallbackOrders(
    List<Map<String, dynamic>> liveOrders,
    List<Map<String, dynamic>> fallbackOrders,
  ) {
    if (fallbackOrders.isEmpty) {
      return liveOrders;
    }
    final fallbackIds = fallbackOrders
        .map((item) => (item['id'] ?? item['orderId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final merged = <Map<String, dynamic>>[
      ...fallbackOrders,
      ...liveOrders.where((item) {
        final id = (item['id'] ?? item['orderId'] ?? '').toString().trim();
        return id.isEmpty || !fallbackIds.contains(id);
      }),
    ];
    merged.sort((a, b) {
      final aDate = _toDateTime(a['updatedAt'] ?? a['createdAt']);
      final bDate = _toDateTime(b['updatedAt'] ?? b['createdAt']);
      return bDate.compareTo(aDate);
    });
    return merged;
  }

  List<Map<String, dynamic>> _mergeCustomerOrderSources({
    required List<Map<String, dynamic>> fallbackOrders,
    required List<Map<String, dynamic>> liveOrders,
    required List<Map<String, dynamic>> bridgeOrders,
  }) {
    final merged = <String, Map<String, dynamic>>{};
    final priorities = <String, int>{};
    final sources = [fallbackOrders, liveOrders, bridgeOrders];
    for (var priority = 0; priority < sources.length; priority++) {
      final source = sources[priority];
      for (final item in source) {
        final id = (item['id'] ?? item['orderId'] ?? '').toString().trim();
        if (id.isEmpty) {
          continue;
        }
        final existing = merged[id];
        if (existing != null) {
          final existingMs = _timestampMillis(
            existing['updatedAt'] ??
                existing['reviewedAt'] ??
                existing['createdAt'],
          );
          final itemMs = _timestampMillis(
            item['updatedAt'] ?? item['reviewedAt'] ?? item['createdAt'],
          );
          final existingPriority = priorities[id] ?? 0;
          if (itemMs < existingMs ||
              (itemMs == existingMs && priority < existingPriority)) {
            continue;
          }
        }
        merged[id] = {
          ...merged[id] ?? const <String, dynamic>{},
          ...item,
          'id': id,
          'orderId': item['orderId'] ?? id,
        };
        priorities[id] = priority;
      }
    }
    final items = merged.values.toList();
    items.sort((a, b) {
      final aDate = _toDateTime(a['updatedAt'] ?? a['createdAt']);
      final bDate = _toDateTime(b['updatedAt'] ?? b['createdAt']);
      return bDate.compareTo(aDate);
    });
    return items;
  }

  List<Map<String, dynamic>> _temporaryCustomerOrders() {
    if (_debugCustomerOrdersState != null) {
      return _debugCustomerOrdersState!
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    final persisted = _loadDebugList('customer_orders');
    _debugCustomerOrdersState = persisted ?? <Map<String, dynamic>>[];
    return _debugCustomerOrdersState!
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _storeTemporaryCustomerOrders(List<Map<String, dynamic>> orders) {
    _debugCustomerOrdersState =
        orders.map((item) => Map<String, dynamic>.from(item)).toList();
    debugStorageWrite(
      _debugStorageKey('customer_orders'),
      jsonEncode(_jsonSafe(_debugCustomerOrdersState)),
    );
    if (!_debugStateChanges.isClosed) {
      _debugStateChanges.add(null);
    }
  }

  Future<Map<String, dynamic>> _enrichedOrderForAssignment(
    String orderId,
    Map<String, dynamic> baseOrder,
  ) async {
    final merged = <String, dynamic>{
      ...baseOrder,
      'id': orderId,
      'orderId': orderId,
    };
    try {
      final details = await BackendApiService.instance.getMap(
        '/orders/$orderId/details',
      );
      final backendOrder = Map<String, dynamic>.from(
        (details['order'] as Map?) ?? const <String, dynamic>{},
      );
      merged.addAll(backendOrder);
      merged['customerId'] ??= backendOrder['customer_id'];
      merged['cleanerId'] ??= backendOrder['cleaner_id'];
      merged['customerName'] ??= backendOrder['customer_name'];
      merged['customerPhone'] ??= backendOrder['customer_phone'];
      merged['cleanerName'] ??= backendOrder['cleaner_name'];
      merged['cleanerPhone'] ??= backendOrder['cleaner_phone'];
    } catch (_) {}
    final customerId = (merged['customerId'] ?? '').toString().trim();
    if (customerId.isNotEmpty) {
      final customer = <String, dynamic>{
        'name': merged['customerName'],
        'phone': merged['customerPhone'],
        'address': merged['address'],
        'residentialComplex': merged['residentialComplex'],
        'houseId': merged['houseId'],
        'serviceArea': merged['serviceArea'],
        'serviceAreaId': merged['serviceAreaId'],
        'zoneId': merged['zoneId'],
        'clusterName': merged['clusterName'],
        'entrance': merged['entrance'],
        'apartment': merged['apartment'],
      };
      for (final key in [
        'address',
        'residentialComplex',
        'houseId',
        'serviceArea',
        'serviceAreaId',
        'zoneId',
        'clusterName',
        'entrance',
        'apartment',
        'customerPhone',
      ]) {
        final current = (merged[key] ?? '').toString().trim();
        if (current.isEmpty && customer[key] != null) {
          merged[key] = customer[key];
        }
      }
      if ((merged['customerName'] ?? '').toString().trim().isEmpty &&
          (customer['name'] ?? '').toString().trim().isNotEmpty) {
        merged['customerName'] = customer['name'];
      }
    }
    final house = await _resolveHouseForAssignment(merged);
    if (house != null) {
      for (final key in [
        'houseId',
        'serviceArea',
        'serviceAreaId',
        'zoneId',
        'clusterName',
        'residentialComplex',
        'address',
      ]) {
        final current = (merged[key] ?? '').toString().trim();
        if (current.isEmpty && house[key] != null) {
          merged[key] = house[key];
        }
      }
      merged['houseStatus'] = house['status'] ?? merged['houseStatus'];
    }
    return merged;
  }

  Future<Map<String, dynamic>?> _resolveHouseForAssignment(
    Map<String, dynamic> order,
  ) async {
    final houseId = (order['houseId'] ?? '').toString().trim();
    final address = (order['address'] ?? '').toString().trim().toLowerCase();
    if (houseId.isEmpty && address.isEmpty) {
      return null;
    }
    final houses = await BackendApiService.instance.getList(
      '/geo/connected-houses',
    );
    for (final raw in houses) {
      final data = Map<String, dynamic>.from(raw);
      final id = (data['id'] ?? '').toString();
      if (houseId.isNotEmpty && id == houseId) {
        return data;
      }
      final itemAddress = (data['address'] ??
              '${data['street_ru'] ?? data['street'] ?? ''} ${data['house'] ?? ''}')
          .toString()
          .trim()
          .toLowerCase();
      final complex =
          (data['residential_complex_ru'] ?? data['residentialComplex'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      if (address.isNotEmpty &&
          (itemAddress == address ||
              itemAddress.contains(address) ||
              complex.contains(address))) {
        return data;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> reviewManualPayment({
    required String orderId,
    required bool approved,
    String? note,
  }) async {
    if (_isDebugAdmin) {
      final paymentStatus = approved ? 'paid' : 'failed';
      final orderStatus = approved ? 'pending_assignment' : 'canceled';
      final visibleStatus = approved ? 'pending' : 'canceled';
      final orders = _debugCustomerOrders();
      final orderIndex = orders.indexWhere(
        (item) => item['id']?.toString() == orderId,
      );
      Map<String, dynamic>? baseOrder;
      if (orderIndex != -1) {
        baseOrder = Map<String, dynamic>.from(orders[orderIndex]);
      } else {
        final sharedOrders = await adminOrdersStream().first;
        final sharedMatch =
            sharedOrders.cast<Map<String, dynamic>?>().firstWhere(
                  (item) => item?['id']?.toString() == orderId,
                  orElse: () => null,
                );
        if (sharedMatch != null) {
          baseOrder = Map<String, dynamic>.from(sharedMatch);
        }
      }
      if (baseOrder != null) {
        final updatedOrder = {
          ...baseOrder,
          'id': orderId,
          'paymentStatus': paymentStatus,
          'status': visibleStatus,
          'orderStatus': orderStatus,
          'paidAt': approved ? Timestamp.now() : null,
        };
        if (orderIndex != -1) {
          orders[orderIndex] = updatedOrder;
        } else {
          orders.insert(0, updatedOrder);
        }
        _debugCustomerOrdersState = orders;
        try {
          await _db.collection('debug_bridge_orders').doc(orderId).set({
            'sourceDebugUid': 'admin_demo',
            'orderId': orderId,
            'paymentStatus': paymentStatus,
            'status': visibleStatus,
            'orderStatus': orderStatus,
            'customerId': updatedOrder['customerId'] ?? 'customer_demo',
            'customerName': updatedOrder['customerName'] ?? 'Асет',
            'customerPhone':
                updatedOrder['customerPhone'] ?? '+7 708 636 21 53',
            'address': updatedOrder['address'],
            'package': updatedOrder['package'],
            'price': updatedOrder['price'],
            'scheduledFor': updatedOrder['scheduledFor'],
            'createdAt': updatedOrder['createdAt'] ?? Timestamp.now(),
            'reviewedAt': Timestamp.now(),
            'paidAt': approved ? Timestamp.now() : null,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }, SetOptions(merge: true));
          final subscriptionId = 'sub_$orderId';
          if (approved) {
            final now = DateTime.now();
            final cleaningsPerMonth = PackageCatalogUtils.cleaningsPerMonth(
              updatedOrder,
            );
            final billingPeriodMonths = PackageCatalogUtils.billingPeriodMonths(
              updatedOrder,
            );
            final includedVisits = cleaningsPerMonth * billingPeriodMonths;
            final currentPeriodEnd = DateTime(now.year, now.month + 1, now.day);
            await _db
                .collection('debug_bridge_customer_subscriptions')
                .doc(subscriptionId)
                .set({
              'sourceDebugUid': 'admin_demo',
              'id': subscriptionId,
              'customerId': updatedOrder['customerId'] ?? 'customer_demo',
              'status': 'active',
              'packageId': updatedOrder['packageId'],
              'package': updatedOrder['package'] ?? 'Разовый пакет',
              'frequencyLabel': updatedOrder['frequencyLabel'] ??
                  updatedOrder['package'] ??
                  '1 раз',
              'price': updatedOrder['price'] ?? 0,
              'billingPeriodMonths': billingPeriodMonths,
              'cleaningsPerMonth': cleaningsPerMonth,
              'includedVisits': includedVisits,
              'totalIncludedVisits': includedVisits,
              'monthlyIncludedVisits': cleaningsPerMonth,
              'currentPeriodIncludedVisits': cleaningsPerMonth,
              'usedVisits': 0,
              'scheduledVisits': 0,
              'currentPeriodUsedVisits': 0,
              'currentPeriodScheduledVisits': 0,
              'currentPeriodRemainingVisits': cleaningsPerMonth,
              'remainingCleanings': cleaningsPerMonth,
              'remainingVisits': cleaningsPerMonth,
              'totalRemainingVisits': includedVisits,
              'area': updatedOrder['area'] ?? 100,
              'createdAt': Timestamp.now(),
              'updatedAt': Timestamp.now(),
              'currentPeriodStart': Timestamp.now(),
              'currentPeriodEnd': Timestamp.fromDate(currentPeriodEnd),
              'nextPaymentDate': DateTime(
                now.year,
                now.month + billingPeriodMonths,
                now.day,
              ).toIso8601String(),
            }, SetOptions(merge: true));
          } else {
            await _db
                .collection('debug_bridge_customer_subscriptions')
                .doc(subscriptionId)
                .set({
              'sourceDebugUid': 'admin_demo',
              'id': subscriptionId,
              'customerId': updatedOrder['customerId'] ?? 'customer_demo',
              'status': 'cancelled',
              'remainingCleanings': 0,
              'scheduledVisits': 0,
              'updatedAt': Timestamp.now(),
              'rejectedAt': Timestamp.now(),
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            }, SetOptions(merge: true));
          }
        } catch (_) {
          // Shared debug bridge is best-effort; local flow must still work.
        }
      }
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'orderId': orderId,
        'approved': approved,
        'status': paymentStatus,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      };
    }
    return BackendApiService.instance.postMap(
      approved ? '/payments/$orderId/confirm' : '/payments/$orderId/reject',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
  }

  Future<Map<String, dynamic>> _reviewManualPaymentDirect({
    required String orderId,
    required bool approved,
    String? note,
  }) async {
    final result = approved
        ? await BackendApiService.instance.postMap('/payments/$orderId/confirm')
        : await BackendApiService.instance.postMap(
            '/payments/$orderId/reject',
            body: {if (note != null && note.trim().isNotEmpty) 'note': note},
          );
    return {
      ...result,
      'orderId': orderId,
      'approved': approved,
      'status': approved ? 'paid' : 'failed',
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> _reviewAreaRecalculationPaymentDirect({
    required String paymentId,
    required Map<String, dynamic> paymentData,
    required bool approved,
    String? note,
  }) async {
    final result = approved
        ? await BackendApiService.instance.postMap(
            '/payments/$paymentId/confirm',
          )
        : await BackendApiService.instance.postMap(
            '/payments/$paymentId/reject',
            body: {if (note != null && note.trim().isNotEmpty) 'note': note},
          );
    return {
      ...result,
      'paymentId': paymentId,
      'approved': approved,
      'status': approved ? 'paid' : 'failed',
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> _reviewAddonsOnlyOrderPaymentDirect({
    required String orderId,
    required Map<String, dynamic> orderData,
    String? note,
  }) async {
    final result = await BackendApiService.instance.postMap(
      '/payments/$orderId/confirm',
    );
    return {
      ...result,
      'orderId': orderId,
      'approved': true,
      'status': 'paid',
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> _reviewAddonRequestPaymentDirect({
    required String paymentId,
    required Map<String, dynamic> paymentData,
    required bool approved,
    String? note,
  }) async {
    final result = approved
        ? await BackendApiService.instance.postMap(
            '/payments/$paymentId/confirm',
          )
        : await BackendApiService.instance.postMap(
            '/payments/$paymentId/reject',
            body: {if (note != null && note.trim().isNotEmpty) 'note': note},
          );
    return {
      ...result,
      'orderId': paymentId,
      'addonRequestId': paymentData['addonRequestId'],
      'approved': approved,
      'status': approved ? 'paid' : 'failed',
      'backend': true,
    };
  }

  Future<void> _applyReferralPaymentBonusAfterReview(String orderId) async {
    return;
  }

  Future<void> _applyReferralPaymentBonusDirect(
    String orderId,
    Map<String, dynamic> orderData,
  ) async {
    return;
  }

  Future<void> _recalculateReferralStatsDirect(String userId) async {
    return;
  }

  int _referralDiscountPercentForCount(int count) {
    if (count >= 20) {
      return 10;
    }
    if (count >= 10) {
      return 7;
    }
    if (count >= 5) {
      return 3;
    }
    return 0;
  }

  Future<void> createAdminAction(Map<String, dynamic> data) async {
    if (_isDebugAdmin) {
      if ((data['type'] ?? '').toString() == 'complaint_resolution') {
        final complaintId = (data['complaintId'] ?? '').toString();
        final status =
            (data['status'] ?? 'resolved').toString().trim().toLowerCase();
        if (complaintId.isNotEmpty &&
            !complaintId.startsWith('debug_complaint_seed_')) {
          try {
            await _db
                .collection('debug_bridge_complaints')
                .doc(complaintId)
                .set({
              'status': status,
              'resolution': data['resolution'],
              'compensationAmount': data['compensationAmount'],
              'resolvedAt': Timestamp.now(),
            }, SetOptions(merge: true));
          } catch (_) {
            // Fall back to in-memory debug state below.
          }
        }
        final complaints = _debugComplaints()
            .map(
              (item) => item['id'] == complaintId
                  ? {
                      ...item,
                      'status': status,
                      'resolution': data['resolution'],
                      'compensationAmount': data['compensationAmount'],
                    }
                  : item,
            )
            .toList();
        _debugComplaintsState = complaints;
        _notifyDebugStateChanged();
      }
      if ((data['type'] ?? '').toString() == 'order_status') {
        final orderId = (data['orderId'] ?? '').toString();
        final rawToStatus = (data['toStatus'] ?? '').toString().toLowerCase();
        final toStatus = rawToStatus == 'canceled' ? 'cancelled' : rawToStatus;
        if (orderId.isNotEmpty && toStatus.isNotEmpty) {
          final localOrders = _debugCustomerOrders();
          final orderIndex = localOrders.indexWhere(
            (item) => item['id']?.toString() == orderId,
          );
          Map<String, dynamic>? baseOrder;
          if (orderIndex != -1) {
            baseOrder = Map<String, dynamic>.from(localOrders[orderIndex]);
          } else {
            final sharedOrders = await adminOrdersStream().first;
            final sharedMatch =
                sharedOrders.cast<Map<String, dynamic>?>().firstWhere(
                      (item) => item?['id']?.toString() == orderId,
                      orElse: () => null,
                    );
            if (sharedMatch != null) {
              baseOrder = Map<String, dynamic>.from(sharedMatch);
            }
          }
          Map<String, dynamic>? updatedOrder;
          final orders = List<Map<String, dynamic>>.from(localOrders);
          if (baseOrder != null) {
            updatedOrder = {
              ...baseOrder,
              'id': orderId,
              'status': toStatus,
              'orderStatus': toStatus,
            };
            if (orderIndex != -1) {
              orders[orderIndex] = updatedOrder;
            } else {
              orders.insert(0, updatedOrder);
            }
          }
          _debugCustomerOrdersState = orders;
          if (updatedOrder != null) {
            final now = Timestamp.now();
            try {
              await _db.collection('debug_bridge_orders').doc(orderId).set({
                'sourceDebugUid': 'admin_demo',
                'orderId': orderId,
                'status': toStatus,
                'orderStatus': toStatus,
                'paymentStatus': updatedOrder['paymentStatus'],
                'customerId': updatedOrder['customerId'] ?? 'customer_demo',
                'customerName': updatedOrder['customerName'] ?? 'Асет',
                'customerPhone':
                    updatedOrder['customerPhone'] ?? '+7 708 636 21 53',
                'address': updatedOrder['address'],
                'package': updatedOrder['package'],
                'price': updatedOrder['price'],
                'scheduledFor': updatedOrder['scheduledFor'],
                'createdAt': updatedOrder['createdAt'] ?? Timestamp.now(),
                'updatedAt': now,
              }, SetOptions(merge: true));
              await _db
                  .collection('debug_bridge_cleaner_slots')
                  .doc(orderId)
                  .set({
                'sourceDebugUid': 'admin_demo',
                'status': toStatus,
                'updatedAt': now,
                if (toStatus == 'completed') 'completedAt': now,
                if (toStatus == 'cancelled') 'cancelledAt': now,
              }, SetOptions(merge: true));
            } catch (_) {
              // Shared debug bridge is best-effort; local flow must still work.
            }
          }
          _notifyDebugStateChanged();
        }
      }
      if ((data['type'] ?? '').toString() == 'assign_cleaner') {
        final orderId = (data['orderId'] ?? '').toString();
        final cleanerId = (data['cleanerId'] ?? '').toString();
        final cleanerName = (data['cleanerName'] ?? cleanerId).toString();
        final time = (data['time'] ?? '10:00 - 13:00').toString();
        final address = (data['address'] ?? '').toString();
        final scheduledDateRaw = (data['scheduledDate'] ?? '').toString();
        if (orderId.isNotEmpty && cleanerId.isNotEmpty) {
          final parsedScheduledDate = DateTime.tryParse(scheduledDateRaw);
          final localOrders = _debugCustomerOrders();
          final orderIndex = localOrders.indexWhere(
            (item) => item['id']?.toString() == orderId,
          );
          Map<String, dynamic>? baseOrder;
          if (orderIndex != -1) {
            baseOrder = Map<String, dynamic>.from(localOrders[orderIndex]);
          } else {
            final sharedOrders = await adminOrdersStream().first;
            final sharedMatch =
                sharedOrders.cast<Map<String, dynamic>?>().firstWhere(
                      (item) => item?['id']?.toString() == orderId,
                      orElse: () => null,
                    );
            if (sharedMatch != null) {
              baseOrder = Map<String, dynamic>.from(sharedMatch);
            }
          }
          Map<String, dynamic>? updatedOrder;
          final orders = List<Map<String, dynamic>>.from(localOrders);
          if (baseOrder != null) {
            final scheduledFor = parsedScheduledDate != null
                ? Timestamp.fromDate(parsedScheduledDate)
                : (baseOrder['scheduledFor'] ?? Timestamp.now());
            updatedOrder = {
              ...baseOrder,
              'id': orderId,
              'cleanerId': cleanerId,
              'cleanerName': cleanerName,
              'time': time,
              'address': address.isNotEmpty ? address : baseOrder['address'],
              'status': 'assigned',
              'orderStatus': 'assigned',
              'scheduledFor': scheduledFor,
            };
            if (orderIndex != -1) {
              orders[orderIndex] = updatedOrder;
            } else {
              orders.insert(0, updatedOrder);
            }
          }
          _debugCustomerOrdersState = orders;
          if (updatedOrder != null) {
            final scheduledFor =
                updatedOrder['scheduledFor'] ?? Timestamp.now();
            try {
              await _db.collection('debug_bridge_orders').doc(orderId).set({
                'sourceDebugUid': 'admin_demo',
                'orderId': orderId,
                'cleanerId': cleanerId,
                'cleanerName': cleanerName,
                'time': time,
                'address': updatedOrder['address'],
                'status': 'assigned',
                'orderStatus': 'assigned',
                'paymentStatus': updatedOrder['paymentStatus'],
                'customerId': updatedOrder['customerId'] ?? 'customer_demo',
                'customerName': updatedOrder['customerName'] ?? 'Асет',
                'customerPhone':
                    updatedOrder['customerPhone'] ?? '+7 708 636 21 53',
                'package': updatedOrder['package'],
                'price': updatedOrder['price'],
                'scheduledFor': scheduledFor,
                'createdAt': updatedOrder['createdAt'] ?? Timestamp.now(),
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));
              await _db
                  .collection('debug_bridge_cleaner_slots')
                  .doc(orderId)
                  .set({
                'sourceDebugUid': 'admin_demo',
                'id': orderId,
                'sourceOrderId': orderId,
                'customerOrderId': orderId,
                'cleanerId': cleanerId,
                'status': 'assigned',
                'scheduledFor': scheduledFor,
                'date': scheduledFor,
                'time': time,
                'client': updatedOrder['customerName'] ?? 'Асет',
                'customerName': updatedOrder['customerName'] ?? 'Асет',
                'customerPhone':
                    updatedOrder['customerPhone'] ?? '+7 708 636 21 53',
                'residentialComplex':
                    updatedOrder['residentialComplex'] ?? 'ЖК Триумф',
                'address': updatedOrder['address'],
                'package': updatedOrder['package'] ?? '4 раза в месяц',
                'price': updatedOrder['price'] ?? 0,
                'totalDurationMinutes': 180,
                'estimatedDurationMinutes': 180,
                'accessMethod': updatedOrder['accessMethod'] ?? '',
                'entrance': updatedOrder['entrance'] ?? '',
                'apartment': updatedOrder['apartment'] ?? '',
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));
            } catch (_) {
              // Shared debug bridge is best-effort; local flow must still work.
            }
          }
          _notifyDebugStateChanged();
        }
      }
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/audit',
      body: {
        'action': data['action'] ?? 'admin.action',
        'entityType': data['entityType'],
        'entityId': data['entityId'],
        'payload': data,
      },
    );
  }

  Future<void> assignCleanerFromAdmin({
    required String orderId,
    required String cleanerId,
    required String cleanerName,
    required DateTime scheduledDate,
    required String time,
    required String address,
    String scopeType = 'order',
  }) async {
    await BackendApiService.instance.postMap(
      '/admin/orders/$orderId/assign-cleaner',
      body: {'cleanerId': cleanerId},
    );
  }

  Future<void> upsertCluster({
    required String clusterId,
    required Map<String, dynamic> data,
  }) async {
    final residentialComplex =
        (data['residentialComplex'] ?? data['name'] ?? clusterId)
            .toString()
            .trim();
    final clusterName = (data['name'] ?? residentialComplex).toString().trim();
    final housePayload = {
      'id': clusterId,
      'title': residentialComplex.isNotEmpty ? residentialComplex : clusterName,
      'residentialComplex':
          residentialComplex.isNotEmpty ? residentialComplex : clusterName,
      'address':
          residentialComplex.isNotEmpty ? residentialComplex : clusterName,
      'clusterId': clusterId,
      'clusterName': clusterName,
      'serviceArea': clusterName,
      'status': (data['status'] ?? 'ACTIVE').toString().toUpperCase(),
      'threshold': data['threshold'] ?? 1,
      'current_users': data['current_users'] ?? 1,
      'updatedAt': Timestamp.now(),
      if (data['lat'] != null) 'lat': data['lat'],
      if (data['lng'] != null) 'lng': data['lng'],
      if (data['zoneId'] != null) 'zoneId': data['zoneId'],
    };
    if (_isDebugAdmin) {
      await _db.collection('debug_bridge_clusters').doc(clusterId).set({
        ...data,
        'id': clusterId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      await _db.collection('debug_bridge_houses').doc(clusterId).set({
        ...housePayload,
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/connected-houses',
      body: {
        'city': data['city'] ?? 'Астана',
        'streetRu':
            data['streetRu'] ?? data['street'] ?? housePayload['address'],
        'streetKk': data['streetKk'],
        'house': data['house'] ?? data['building'] ?? clusterId,
        'residentialComplexRu': residentialComplex,
        'residentialComplexKk': data['residentialComplexKk'],
        'zoneId': data['zoneId'],
        'latitude': data['lat'] ?? data['latitude'],
        'longitude': data['lng'] ?? data['longitude'],
        'active': (housePayload['status'] ?? 'ACTIVE').toString() == 'ACTIVE',
      },
    );
  }

  Future<void> upsertHouse({
    required String houseId,
    required Map<String, dynamic> data,
  }) async {
    int parseInt(dynamic value, int fallback) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse((value ?? '').toString()) ?? fallback;
    }

    final normalizedData = <String, dynamic>{...data};
    final status =
        (normalizedData['status'] ?? 'ACTIVE').toString().trim().toUpperCase();
    normalizedData['id'] = houseId;
    normalizedData['title'] =
        (normalizedData['title'] ?? normalizedData['address'] ?? houseId)
            .toString()
            .trim();
    normalizedData['address'] =
        (normalizedData['address'] ?? normalizedData['title'] ?? houseId)
            .toString()
            .trim();
    normalizedData['residentialComplex'] =
        (normalizedData['residentialComplex'] ?? normalizedData['title'] ?? '')
            .toString()
            .trim();
    normalizedData['serviceArea'] = (normalizedData['serviceArea'] ??
            normalizedData['clusterName'] ??
            normalizedData['residentialComplex'] ??
            normalizedData['address'])
        .toString()
        .trim();
    normalizedData['status'] = status.isEmpty ? 'ACTIVE' : status;
    normalizedData['threshold'] = parseInt(normalizedData['threshold'], 1);
    normalizedData['current_users'] = parseInt(
      normalizedData['current_users'],
      1,
    );
    normalizedData['updatedAt'] = Timestamp.now();

    if (_isDebugAdmin) {
      await _db.collection('debug_bridge_houses').doc(houseId).set({
        ...normalizedData,
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/connected-houses',
      body: {
        'city': normalizedData['city'] ?? 'Астана',
        'streetRu': normalizedData['streetRu'] ??
            normalizedData['street'] ??
            normalizedData['address'],
        'streetKk': normalizedData['streetKk'],
        'house':
            normalizedData['house'] ?? normalizedData['building'] ?? houseId,
        'residentialComplexRu': normalizedData['residentialComplex'],
        'residentialComplexKk': normalizedData['residentialComplexKk'],
        'zoneId': normalizedData['zoneId'],
        'latitude': normalizedData['lat'] ?? normalizedData['latitude'],
        'longitude': normalizedData['lng'] ?? normalizedData['longitude'],
        'active': normalizedData['status'] == 'ACTIVE',
      },
    );
  }

  Future<void> upsertServiceZone({
    required String zoneId,
    required Map<String, dynamic> data,
  }) async {
    final normalizedData = <String, dynamic>{...data};
    normalizedData['id'] = zoneId;
    normalizedData['title'] =
        (normalizedData['title'] ?? zoneId).toString().trim();
    normalizedData['status'] =
        (normalizedData['status'] ?? 'active').toString().trim().toLowerCase();
    normalizedData['updatedAt'] = Timestamp.now();

    if (_isDebugAdmin) {
      await _db.collection('debug_bridge_service_zones').doc(zoneId).set({
        ...normalizedData,
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/service-zones',
      body: {
        'nameRu': normalizedData['title'],
        'nameKk': normalizedData['titleKk'],
        'city': normalizedData['city'] ?? 'Астана',
        'polygon': normalizedData['polygon'],
        'active': normalizedData['status'] == 'active',
      },
    );
  }

  Future<Map<String, dynamic>> importHousesForServiceZone({
    required String zoneId,
  }) async {
    if (_isDebugAdmin) {
      return {'ok': true, 'zoneId': zoneId, 'importedCount': 0, 'debug': true};
    }
    return {
      'ok': true,
      'zoneId': zoneId,
      'importedCount': 0,
      'message': 'Импорт домов выполняется через backend-админку.',
    };
  }

  Future<void> deleteServiceZone(String zoneId) async {
    final normalizedZoneId = zoneId.trim();
    if (normalizedZoneId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      await _db
          .collection('debug_bridge_service_zones')
          .doc(normalizedZoneId)
          .delete();
      final houses = await _db
          .collection('debug_bridge_houses')
          .where('zoneId', isEqualTo: normalizedZoneId)
          .get();
      final batch = _db.batch();
      for (final doc in houses.docs) {
        batch.update(doc.reference, {
          'zoneId': FieldValue.delete(),
          'serviceAreaId': FieldValue.delete(),
          'serviceArea': FieldValue.delete(),
          'clusterName': FieldValue.delete(),
        });
      }
      await batch.commit();
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.patchMap(
      '/admin/$normalizedZoneId/active'.replaceFirst(
        '/admin/$normalizedZoneId',
        '/admin/zones/$normalizedZoneId',
      ),
      body: {'active': false},
    );
  }

  Future<void> upsertCleaner({
    required String cleanerId,
    required Map<String, dynamic> data,
  }) async {
    final normalizedData = <String, dynamic>{...data};
    final rawVerificationStatus =
        normalizedData['verificationStatus']?.toString().trim();
    if (rawVerificationStatus != null && rawVerificationStatus.isNotEmpty) {
      normalizedData['verificationStatus'] =
          rawVerificationStatus.toLowerCase();
    }
    if (_isDebugAdmin) {
      await _db.collection('debug_bridge_cleaners').doc(cleanerId).set({
        ...normalizedData,
        'id': cleanerId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.patchMap(
      '/admin/cleaners/$cleanerId',
      body: {
        if (normalizedData['name'] != null) 'fullName': normalizedData['name'],
        if (normalizedData['fullName'] != null)
          'fullName': normalizedData['fullName'],
        if (normalizedData['phone'] != null) 'phone': normalizedData['phone'],
        if (normalizedData['email'] != null) 'email': normalizedData['email'],
        if (normalizedData['city'] != null) 'city': normalizedData['city'],
        if (normalizedData['status'] != null)
          'status': normalizedData['status'],
        if (normalizedData['verificationStatus'] != null)
          'verificationStatus': normalizedData['verificationStatus'],
        if (normalizedData['monthlyAreaLimit'] != null)
          'monthlyAreaLimit': normalizedData['monthlyAreaLimit'],
        if (normalizedData['dailyWorkLimitMinutes'] != null)
          'dailyWorkLimitMinutes': normalizedData['dailyWorkLimitMinutes'],
      },
    );
  }

  Future<void> deleteCleaner(String cleanerId) async {
    final normalizedCleanerId = cleanerId.trim();
    if (normalizedCleanerId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final batch = _db.batch();
      batch.delete(
        _db.collection('debug_bridge_cleaners').doc(normalizedCleanerId),
      );
      batch.delete(
        _db
            .collection('debug_bridge_cleaner_verifications')
            .doc(normalizedCleanerId),
      );
      await batch.commit();
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.delete(
      '/admin/cleaners/$normalizedCleanerId',
    );
  }

  Future<Map<String, dynamic>?> getHouseStats({required String houseId}) async {
    if (houseId.trim().isEmpty) return null;
    return BackendApiService.instance
        .getMap('/geo/houses/$houseId/stats', authenticated: false);
  }

  Future<Map<String, dynamic>> joinWaitlist({
    required String houseId,
    String source = 'app',
  }) async {
    if (_isTemporaryCustomerSession) {
      final userId = _uidOrNull ?? 'temp_customer';
      final docId = '${houseId}_$userId';
      final waitlist = List<Map<String, dynamic>>.from(
        _temporaryHouseWaitlist(),
      );
      waitlist.removeWhere((item) => (item['id'] ?? '').toString() == docId);
      waitlist.add({
        'id': docId,
        'houseId': houseId,
        'userId': userId,
        'source': source,
        'createdAt': DateTime.now().toIso8601String(),
      });
      debugStorageWrite(
        _debugStorageKey('house_waitlist'),
        jsonEncode(_jsonSafe(waitlist)),
      );
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'houseId': houseId,
        'joined': true,
        'localFallback': true,
      };
    }
    if (_useDebugFixtures) {
      final userId = _uidOrNull ?? 'guest';
      final docId = '${houseId}_$userId';
      await _db.collection('debug_bridge_house_waitlist').doc(docId).set({
        'houseId': houseId,
        'userId': userId,
        'source': source,
        'createdAt': Timestamp.now(),
      }, SetOptions(merge: true));
      await _syncDebugHouseProgress(houseId);
      return {'ok': true, 'houseId': houseId, 'joined': true};
    }
    return BackendApiService.instance
        .postMap('/geo/houses/$houseId/waitlist', body: {'source': source});
  }

  Future<Map<String, dynamic>> inviteNeighbors({
    required String houseId,
    String? invitedPhone,
  }) async {
    if (_isTemporaryCustomerSession) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final docId = '${houseId}_invite_$timestamp';
      final waitlist = List<Map<String, dynamic>>.from(
        _temporaryHouseWaitlist(),
      );
      waitlist.add({
        'id': docId,
        'houseId': houseId,
        'userId': invitedPhone?.trim().isNotEmpty == true
            ? invitedPhone!.trim()
            : 'neighbor_$timestamp',
        'source': 'invite_neighbors',
        'invitedPhone': invitedPhone?.trim(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      debugStorageWrite(
        _debugStorageKey('house_waitlist'),
        jsonEncode(_jsonSafe(waitlist)),
      );
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'houseId': houseId,
        'inviteLink': 'https://domly.kz/invite/$houseId',
        'localFallback': true,
      };
    }
    if (_useDebugFixtures) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final docId = '${houseId}_invite_$timestamp';
      await _db.collection('debug_bridge_house_waitlist').doc(docId).set({
        'houseId': houseId,
        'userId': invitedPhone?.trim().isNotEmpty == true
            ? invitedPhone!.trim()
            : 'neighbor_$timestamp',
        'source': 'invite_neighbors',
        'invitedPhone': invitedPhone?.trim(),
        'createdAt': Timestamp.now(),
      }, SetOptions(merge: true));
      await _syncDebugHouseProgress(houseId);
      return {
        'ok': true,
        'houseId': houseId,
        'inviteLink': 'https://domly.kz/invite/$houseId',
      };
    }
    return BackendApiService.instance.postMap('/geo/houses/$houseId/invite');
  }

  Future<Map<String, dynamic>> requestServiceAddress({
    required String residentialComplex,
    required String address,
    String city = '',
    String addressPlaceId = '',
    double? lat,
    double? lng,
    String entrance = '',
    String apartment = '',
    required int area,
  }) async {
    final normalizedAddress =
        address.trim().isEmpty ? residentialComplex.trim() : address.trim();
    final normalizedResidential = residentialComplex.trim().isEmpty
        ? normalizedAddress
        : residentialComplex.trim();
    if (normalizedAddress.isEmpty) {
      throw FlutterError('Укажите адрес дома.');
    }
    final houseId =
        'requested_${DateTime.now().millisecondsSinceEpoch}_${normalizedAddress.hashCode.abs()}';
    final waitlistId =
        '${_uidOrNull ?? AuthService.temporarySessionUid ?? 'customer'}_$houseId';
    final house = {
      'id': houseId,
      'title': normalizedResidential,
      'residentialComplex': normalizedResidential,
      'address': normalizedAddress,
      'addressPlaceId': addressPlaceId,
      'city': city,
      'cityNormalized': city.trim().toLowerCase(),
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'status': 'IN_PROGRESS',
      'threshold': 20,
      'current_users': 1,
      'total_users': 1,
      'source': 'customer_request',
      'requestedBy': _uidOrNull ?? AuthService.temporarySessionUid,
      'requestedAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    final waitlistEntry = {
      'id': waitlistId,
      'houseId': houseId,
      'userId': _uidOrNull ?? AuthService.temporarySessionUid,
      'status': 'waiting',
      'source': 'address_request',
      'residentialComplex': normalizedResidential,
      'address': normalizedAddress,
      'entrance': entrance,
      'apartment': apartment,
      'area': area,
      'city': city,
      'cityNormalized': city.trim().toLowerCase(),
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (_isTemporaryCustomerSession || _useDebugFixtures) {
      final houses = _loadDebugList('houses') ?? <Map<String, dynamic>>[];
      houses.removeWhere((item) => (item['id'] ?? '').toString() == houseId);
      houses.add(house);
      debugStorageWrite(
        _debugStorageKey('houses'),
        jsonEncode(_jsonSafe(houses)),
      );
      final waitlist =
          _loadDebugList('house_waitlist') ?? <Map<String, dynamic>>[];
      waitlist.removeWhere(
        (item) => (item['id'] ?? '').toString() == waitlistId,
      );
      waitlist.add(waitlistEntry);
      debugStorageWrite(
        _debugStorageKey('house_waitlist'),
        jsonEncode(_jsonSafe(waitlist)),
      );
      try {
        await _db.collection('debug_bridge_houses').doc(houseId).set({
          ...house,
          'requestedAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
        await _db
            .collection('debug_bridge_house_waitlist')
            .doc(waitlistId)
            .set({
          ...waitlistEntry,
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
      } catch (_) {}
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'houseId': houseId,
        'status': 'IN_PROGRESS',
        'address': normalizedAddress,
        'residentialComplex': normalizedResidential,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'localFallback': true,
      };
    }
    return BackendApiService.instance.postMap(
      '/geo/service-address-requests',
      body: {
        'residentialComplex': normalizedResidential,
        'address': normalizedAddress,
        'addressPlaceId': addressPlaceId,
        'city': city,
        'lat': lat,
        'lng': lng,
        'entrance': entrance,
        'apartment': apartment,
        'area': area,
      },
    );
  }

  Future<Map<String, dynamic>> activateHouseIfThresholdReached({
    required String houseId,
  }) async {
    if (_useDebugFixtures || _isDebugAdmin) {
      return _syncDebugHouseProgress(houseId, activateWhenReady: true);
    }
    return {
      'ok': true,
      'houseId': houseId,
      'activated': false,
      'status': 'IN_PROGRESS',
      'backend': true,
    };
  }

  Future<Map<String, dynamic>> _syncDebugHouseProgress(
    String houseId, {
    bool activateWhenReady = false,
  }) async {
    final housesSnap = await _db.collection('debug_bridge_houses').get();
    final house = _mergeDebugHouses(
      housesSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
    ).firstWhere(
      (item) => (item['id'] ?? '').toString() == houseId,
      orElse: () => {
        'id': houseId,
        'status': 'INACTIVE',
        'threshold': 20,
        'current_users': 0,
      },
    );
    final waitlistSnap =
        await _db.collection('debug_bridge_house_waitlist').get();
    final count = _mergeDebugWaitlist(
      waitlistSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
    ).where((item) => (item['houseId'] ?? '').toString() == houseId).length;
    final threshold = (house['threshold'] as num?)?.toInt() ?? 20;
    final current = math.max(
      (house['current_users'] as num?)?.toInt() ?? 0,
      count,
    );
    final shouldActivate = activateWhenReady && current >= threshold;
    final status = shouldActivate
        ? 'ACTIVE'
        : current > 0
            ? 'IN_PROGRESS'
            : (house['status'] ?? 'INACTIVE').toString();
    await _db.collection('debug_bridge_houses').doc(houseId).set({
      'current_users': current,
      'total_users': current,
      'status': status,
      if (shouldActivate) 'activatedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
    return {
      'ok': true,
      'houseId': houseId,
      'activated': shouldActivate,
      'status': status,
      'currentUsers': current,
      'threshold': threshold,
      'remaining': math.max(threshold - current, 0),
    };
  }

  Future<Map<String, dynamic>> submitCleanerVerification(
    Map<String, dynamic> payload,
  ) async {
    if (_isDebugCleaner) {
      final cleanerId = _uidOrNull ?? 'cleaner_demo';
      final normalizedPayload = <String, dynamic>{...payload};
      final expiresAt = normalizedPayload['expiresAt']?.toString().trim();
      if (expiresAt != null && expiresAt.isEmpty) {
        normalizedPayload.remove('expiresAt');
      } else if (expiresAt != null) {
        normalizedPayload['expiresAt'] = expiresAt;
      }
      final now = Timestamp.now();
      await _db
          .collection('debug_bridge_cleaner_verifications')
          .doc(cleanerId)
          .set({
        ...normalizedPayload,
        'cleanerId': cleanerId,
        'status': 'pending',
        'rejectionReason': '',
        'submittedAt': now,
        'updatedAt': now,
        'sourceDebugUid': cleanerId,
      }, SetOptions(merge: true));
      await _db.collection('debug_bridge_cleaners').doc(cleanerId).set({
        'verificationStatus': 'pending',
        'updatedAt': now,
        'sourceDebugUid': cleanerId,
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return {'ok': true, 'cleanerId': cleanerId, 'status': 'pending'};
    }
    if (_isTemporaryCleanerSession) {
      final cleanerId = _uidOrNull ?? 'temp_cleaner';
      final normalizedPayload = <String, dynamic>{...payload};
      final expiresAt = normalizedPayload['expiresAt']?.toString().trim();
      if (expiresAt != null && expiresAt.isEmpty) {
        normalizedPayload.remove('expiresAt');
      } else if (expiresAt != null) {
        normalizedPayload['expiresAt'] = expiresAt;
      }
      final mergedVerification = <String, dynamic>{
        ..._temporaryCleanerVerification(),
        ...normalizedPayload,
        'cleanerId': cleanerId,
        'status': 'pending',
        'verificationStatus': 'pending',
        'rejectionReason': '',
        'submittedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      debugStorageWrite(
        _debugStorageKey('cleaner_verification'),
        jsonEncode(_jsonSafe(mergedVerification)),
      );
      await updateCleanerProfile({'verificationStatus': 'pending'});
      _notifyDebugStateChanged();
      return {
        'ok': true,
        'cleanerId': cleanerId,
        'status': 'pending',
        'localFallback': true,
      };
    }
    return BackendApiService.instance.postMap(
      '/cleaner/verification',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> reviewCleanerVerification({
    required String cleanerId,
    required String status,
    String? rejectionReason,
  }) async {
    final normalizedStatus = status.trim().toLowerCase();
    if (_isDebugAdmin) {
      await _db
          .collection('debug_bridge_cleaner_verifications')
          .doc(cleanerId)
          .set({
        'cleanerId': cleanerId,
        'status': normalizedStatus,
        'rejectionReason': rejectionReason ?? '',
        'reviewedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        if (normalizedStatus == 'approved') 'approvedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      return {
        'ok': true,
        'cleanerId': cleanerId,
        'status': normalizedStatus,
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          'rejectionReason': rejectionReason,
      };
    }
    return BackendApiService.instance.patchMap(
      '/admin/cleaners/$cleanerId/verification',
      body: {
        'status': normalizedStatus,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      },
    );
  }

  Future<Map<String, dynamic>> _reviewCleanerVerificationDirect({
    required String cleanerId,
    required String status,
    String? rejectionReason,
  }) async {
    return BackendApiService.instance.patchMap(
      '/admin/cleaners/$cleanerId/verification',
      body: {
        'status': status,
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          'rejectionReason': rejectionReason,
      },
    );
  }

  Future<void> saveAdminSavedView(Map<String, dynamic> view) async {
    if (_isDebugAdmin) {
      final currentViews = _debugAdminSavedViews()
          .where(
            (item) =>
                (item['id'] ?? '').toString() != (view['id'] ?? '').toString(),
          )
          .toList()
        ..add(Map<String, dynamic>.from(view));
      debugStorageWrite(
        _debugStorageKey('admin_saved_views'),
        jsonEncode(_jsonSafe(currentViews)),
      );
      _notifyDebugStateChanged();
      return;
    }

    await BackendApiService.instance.postMap(
      '/admin/settings',
      body: {'key': 'admin_saved_view_${view['id']}', 'value': view},
    );
  }

  Future<void> saveAdminPackage(Map<String, dynamic> packageData) async {
    final packageId = (packageData['id'] ?? '').toString();
    if (packageId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final updated = _debugAdminPackages()
          .where((item) => (item['id'] ?? '').toString() != packageId)
          .toList()
        ..add(Map<String, dynamic>.from(packageData));
      debugStorageWrite(
        _debugStorageKey('admin_packages'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db
          .collection('debug_bridge_customer_packages')
          .doc(packageId)
          .set({
        ...packageData,
        'id': packageId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    final monthlyVisits = packageData['cleaningsPerMonth'] ??
        packageData['cleaningCount'] ??
        packageData['includedVisits'] ??
        2;
    final metadata = <String, dynamic>{
      'items': packageData['features'] is List ? packageData['features'] : [],
      'isQuarterly': packageData['isQuarterly'] == true,
      'discountPercent': packageData['discountPercent'] ?? 0,
      'sortOrder': packageData['sortOrder'] ?? 0,
      'frequency': packageData['frequency'],
      'popular': packageData['popular'] == true,
      'shortInfo': packageData['shortInfo'] ?? '',
      'fullInfo': packageData['fullInfo'] ?? '',
    };
    final body = <String, dynamic>{
      'nameRu': packageData['name'] ?? packageData['title'] ?? packageId,
      'nameKk': packageData['nameKk'] ?? packageData['name_kk'],
      'descriptionRu':
          packageData['fullInfo'] ?? packageData['description'] ?? '',
      'descriptionKk': packageData['descriptionKk'],
      'cleaningCount': monthlyVisits,
      'months':
          packageData['billingPeriodMonths'] ?? packageData['months'] ?? 1,
      'basePrice': 0,
      'pricePerM2': packageData['price'] ?? packageData['pricePerM2'] ?? 0,
      'active': packageData['isActive'] ?? packageData['active'] ?? true,
      'features': metadata,
    };
    if (_looksLikeUuid(packageId)) {
      await BackendApiService.instance
          .patchMap('/admin/catalog/packages/$packageId', body: body);
    } else {
      await BackendApiService.instance
          .postMap('/admin/catalog/packages', body: body);
    }
  }

  Future<void> deleteAdminPackage(String packageId) async {
    if (_isDebugAdmin) {
      final updated = _debugAdminPackages()
          .where((item) => (item['id'] ?? '').toString() != packageId)
          .toList();
      debugStorageWrite(
        _debugStorageKey('admin_packages'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db
          .collection('debug_bridge_customer_packages')
          .doc(packageId)
          .delete();
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.patchMap(
      '/admin/packages/$packageId/active',
      body: {'active': false},
    );
  }

  Future<void> saveAdminPromotion(Map<String, dynamic> promotionData) async {
    final promotionId = (promotionData['id'] ?? '').toString().trim();
    if (promotionId.isEmpty) {
      return;
    }
    final data = {
      ...promotionData,
      'id': promotionId,
      'updatedAt':
          _isDebugAdmin ? Timestamp.now() : FieldValue.serverTimestamp(),
    };
    if (_isDebugAdmin) {
      final updated = _debugAdminPromotions()
          .where((item) => (item['id'] ?? '').toString() != promotionId)
          .toList()
        ..add(Map<String, dynamic>.from(data));
      debugStorageWrite(
        _debugStorageKey('admin_promotions'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_promotions').doc(promotionId).set({
        ...data,
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    final promotionBody = promotionRequestBody(data);
    if (_looksLikeUuid(promotionId)) {
      await BackendApiService.instance.patchMap(
        '/admin/promotions/$promotionId',
        body: promotionBody,
      );
    } else {
      await BackendApiService.instance.postMap(
        '/admin/promotions',
        body: promotionBody,
      );
    }
  }

  Future<void> deleteAdminPromotion(String promotionId) async {
    final normalizedPromotionId = promotionId.trim();
    if (normalizedPromotionId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final updated = _debugAdminPromotions()
          .where(
            (item) => (item['id'] ?? '').toString() != normalizedPromotionId,
          )
          .toList();
      debugStorageWrite(
        _debugStorageKey('admin_promotions'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db
          .collection('debug_bridge_promotions')
          .doc(normalizedPromotionId)
          .delete();
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.delete('/admin/promotions/$normalizedPromotionId');
  }

  Future<void> updateAdminPolicies(Map<String, dynamic> data) async {
    if (_isDebugAdmin) {
      final updated = {..._debugAdminPolicies(), ...data};
      debugStorageWrite(
        _debugStorageKey('admin_policies'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_policies').doc('main').set({
        ...updated,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/admin/content-pages',
      body: {
        'slug': 'privacy',
        'titleRu': data['privacyTitle'] ?? 'Политика конфиденциальности',
        'titleKk': data['privacyTitleKk'],
        'bodyRu': data['privacy'] ?? data['privacyRu'] ?? '',
        'bodyKk': data['privacyKk'],
        'kind': 'privacy',
        'active': true,
      },
    );
    await BackendApiService.instance.postMap(
      '/admin/content-pages',
      body: {
        'slug': 'offer',
        'titleRu': data['offerTitle'] ?? 'Публичная оферта',
        'titleKk': data['offerTitleKk'],
        'bodyRu': data['offer'] ?? data['offerRu'] ?? '',
        'bodyKk': data['offerKk'],
        'kind': 'offer',
        'active': true,
      },
    );
  }

  Future<void> saveAdminPromoBanners(List<Map<String, dynamic>> banners) async {
    if (_isDebugAdmin) {
      debugStorageWrite(
        _debugStorageKey('admin_promo_banners'),
        jsonEncode(_jsonSafe(banners)),
      );
      final batch = _db.batch();
      final collection = _db.collection('debug_bridge_promo_banners');
      for (final banner in banners) {
        final bannerId = (banner['id'] ?? '').toString();
        if (bannerId.isEmpty) {
          continue;
        }
        batch.set(
            collection.doc(bannerId),
            {
              ...banner,
              'id': bannerId,
              'updatedAt': Timestamp.now(),
              'sourceDebugUid': 'admin_demo',
            },
            SetOptions(merge: true));
      }
      await batch.commit();
      _notifyDebugStateChanged();
      return;
    }
    for (final banner in banners) {
      final bannerId = (banner['id'] ?? '').toString();
      final bannerBody = bannerRequestBody(banner);
      if (_looksLikeUuid(bannerId)) {
        await BackendApiService.instance.patchMap(
          '/admin/banners/$bannerId',
          body: bannerBody,
        );
      } else {
        await BackendApiService.instance.postMap(
          '/admin/banners',
          body: bannerBody,
        );
      }
    }
  }

  Future<String?> _saveAddonGroupToBackend(Map<String, dynamic> group) async {
    final title = (group['title'] ??
            group['label'] ??
            group['name'] ??
            group['key'] ??
            group['id'] ??
            '')
        .toString()
        .trim();
    if (title.isEmpty) return null;
    final body = <String, dynamic>{
      'titleRu': title,
      'titleKk': group['titleKk'] ?? group['labelKk'] ?? group['nameKk'],
      'sortOrder': group['sortOrder'] ?? group['order'] ?? 0,
      'active': group['active'] ?? group['isActive'] ?? true,
    };
    final id = (group['id'] ?? group['key'] ?? '').toString();
    final saved = _looksLikeUuid(id)
        ? await BackendApiService.instance
            .patchMap('/admin/catalog/addon-groups/$id', body: body)
        : await BackendApiService.instance
            .postMap('/admin/catalog/addon-groups', body: body);
    return (saved['id'] ?? saved['group_id']).toString();
  }

  Future<void> _saveAddonItemsToBackend(
    String groupId,
    List<Map<String, dynamic>> items,
  ) async {
    String? backendGroupId = _looksLikeUuid(groupId) ? groupId : null;
    if (backendGroupId == null && groupId.trim().isNotEmpty) {
      backendGroupId = await _saveAddonGroupToBackend({'title': groupId});
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final title = (item['title'] ??
              item['label'] ??
              item['name'] ??
              item['key'] ??
              item['id'] ??
              '')
          .toString()
          .trim();
      if (title.isEmpty) continue;
      final body = {
        'groupId': backendGroupId,
        'titleRu': title,
        'titleKk': item['titleKk'] ?? item['labelKk'] ?? item['nameKk'],
        'descriptionRu':
            item['description'] ?? item['shortInfo'] ?? item['fullInfo'],
        'descriptionKk': item['descriptionKk'],
        'hintRu': item['hint'] ?? item['note'],
        'hintKk': item['hintKk'],
        'pricingType': item['pricingType'] ?? 'fixed',
        'price': item['price'] ??
            item['unitPrice'] ??
            item['amount'] ??
            item['cost'] ??
            0,
        'durationMinutes': item['durationMinutes'] ?? 0,
        'paidSeparately':
            item['paidSeparately'] ?? item['separatePayment'] ?? false,
        'active': item['active'] ?? item['isActive'] ?? true,
        'sortOrder': item['sortOrder'] ?? i,
      };
      final itemId = (item['id'] ?? item['key'] ?? '').toString();
      if (_looksLikeUuid(itemId)) {
        await BackendApiService.instance.patchMap(
          '/admin/catalog/addons/$itemId',
          body: body,
        );
      } else {
        await BackendApiService.instance.postMap(
          '/admin/catalog/addons',
          body: body,
        );
      }
    }
  }

  Future<void> syncDefaultAdminAddonCatalog() async {
    final defaults = _addonGroupsWithDefaultDurations(
      AppConfigService.defaultAddonGroupConfigs,
    );
    if (_isDebugAdmin) {
      debugStorageWrite(
        _debugStorageKey('admin_addon_groups'),
        jsonEncode(_jsonSafe(defaults)),
      );
      final batch = _db.batch();
      final collection = _db.collection('debug_bridge_addon_groups');
      for (final group in defaults) {
        final key = (group['key'] ?? '').toString();
        if (key.isEmpty) {
          continue;
        }
        batch.set(
            collection.doc(key),
            {
              ...group,
              'id': key,
              'key': key,
              'updatedAt': Timestamp.now(),
              'sourceDebugUid': 'admin_demo',
            },
            SetOptions(merge: true));
      }
      await batch.commit();
      _notifyDebugStateChanged();
      return;
    }
    for (final group in defaults) {
      await _saveAddonGroupToBackend(group);
      await _saveAddonItemsToBackend(
        (group['key'] ?? group['id'] ?? group['title'] ?? '').toString(),
        ((group['items'] ?? const []) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
    }
  }

  List<Map<String, dynamic>> _addonGroupsWithDefaultDurations(
    List<Map<String, dynamic>> groups,
  ) {
    const durations = <String, int>{
      'window_standard': 15,
      'window_panorama': 20,
      'window_mosquito': 10,
      'balcony_window_standard': 15,
      'balcony_panorama': 20,
      'balcony_balcony': 20,
      'balcony_loggia': 20,
      'balcony_terrace': 30,
      'kitchen_oven': 25,
      'kitchen_hood': 25,
      'kitchen_fridge': 25,
      'kitchen_facades': 30,
      'kitchen_full_set': 60,
      'kitchen_stove': 20,
      'kitchen_microwave': 15,
      'kitchen_apron': 15,
      'kitchen_dishes_hand': 25,
      'kitchen_dishwasher_loading': 10,
      'bath_tile_walls': 30,
      'bath_glass_walls': 25,
      'bath_washer_wipe': 10,
      'textile_bed_linen_ironing': 20,
      'textile_clothes_ironing': 20,
      'textile_curtains_ironing': 35,
      'textile_bed_change': 15,
      'hard_chandelier_standard': 25,
      'hard_chandelier_complex': 45,
      'hard_chandelier_super': 70,
      'hard_lamps': 15,
      'hard_upper_shelves': 25,
      'hard_baseboards': 20,
      'hard_doors': 15,
      'hard_cobweb': 20,
      'furniture_sofa': 60,
      'furniture_mattress': 45,
      'carpet_cleaning': 60,
    };
    return groups.map((group) {
      final copy = Map<String, dynamic>.from(group);
      copy['items'] = ((copy['items'] ?? const []) as List).map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        final key = (item['key'] ?? '').toString();
        item['durationMinutes'] =
            (item['durationMinutes'] as num?)?.toInt() ?? durations[key] ?? 15;
        return item;
      }).toList();
      return copy;
    }).toList();
  }

  Future<void> saveAdminAddonGroup(Map<String, dynamic> groupData) async {
    final groupId = (groupData['key'] ?? groupData['id'] ?? '').toString();
    if (groupId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final updated = _debugAdminAddonGroups()
          .where(
            (item) => (item['key'] ?? item['id'] ?? '').toString() != groupId,
          )
          .toList()
        ..add({
          ...Map<String, dynamic>.from(groupData),
          'id': groupId,
          'key': groupId,
        });
      debugStorageWrite(
        _debugStorageKey('admin_addon_groups'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_addon_groups').doc(groupId).set({
        ...groupData,
        'id': groupId,
        'key': groupId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await _saveAddonGroupToBackend(groupData);
  }

  Future<void> saveAdminAddonGroupItems(
    String groupId,
    List<Map<String, dynamic>> items,
  ) async {
    if (_isDebugAdmin) {
      final updated = _debugAdminAddonGroups().map((group) {
        final id = (group['key'] ?? group['id'] ?? '').toString();
        if (id != groupId) {
          return group;
        }
        return {...group, 'items': items};
      }).toList();
      debugStorageWrite(
        _debugStorageKey('admin_addon_groups'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db.collection('debug_bridge_addon_groups').doc(groupId).set({
        'items': items,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await _saveAddonItemsToBackend(groupId, items);
  }

  Future<void> _syncAllAddonGroupsToPricingCatalog() async {
    return;
  }

  Future<void> syncDefaultAdminChecklistTemplates() async {
    if (_isDebugAdmin) {
      const defaults = AppConfigService.defaultCleanerChecklistTemplates;
      debugStorageWrite(
        _debugStorageKey('admin_checklist_templates'),
        jsonEncode(_jsonSafe(defaults)),
      );
      final batch = _db.batch();
      final collection = _db.collection('debug_bridge_checklist_templates');
      for (final item in defaults) {
        final key = (item['key'] ?? '').toString();
        if (key.isEmpty) {
          continue;
        }
        batch.set(
            collection.doc(key),
            {
              ...item,
              'id': key,
              'key': key,
              'updatedAt': Timestamp.now(),
              'sourceDebugUid': 'admin_demo',
            },
            SetOptions(merge: true));
      }
      await batch.commit();
      _notifyDebugStateChanged();
      return;
    }
    for (final item in AppConfigService.defaultCleanerChecklistTemplates) {
      await _saveChecklistTemplateToBackend(Map<String, dynamic>.from(item));
    }
  }

  Future<void> saveAdminChecklistTemplate(
    Map<String, dynamic> templateData,
  ) async {
    final templateId =
        (templateData['key'] ?? templateData['id'] ?? '').toString();
    if (templateId.isEmpty) {
      return;
    }
    if (_isDebugAdmin) {
      final updated = _debugAdminChecklistTemplates()
          .where(
            (item) =>
                (item['key'] ?? item['id'] ?? '').toString() != templateId,
          )
          .toList()
        ..add({
          ...Map<String, dynamic>.from(templateData),
          'id': templateId,
          'key': templateId,
        });
      debugStorageWrite(
        _debugStorageKey('admin_checklist_templates'),
        jsonEncode(_jsonSafe(updated)),
      );
      await _db
          .collection('debug_bridge_checklist_templates')
          .doc(templateId)
          .set({
        ...templateData,
        'id': templateId,
        'key': templateId,
        'updatedAt': Timestamp.now(),
        'sourceDebugUid': 'admin_demo',
      }, SetOptions(merge: true));
      _notifyDebugStateChanged();
      return;
    }
    await _saveChecklistTemplateToBackend(templateData);
  }

  Future<void> _saveChecklistTemplateToBackend(
    Map<String, dynamic> templateData,
  ) async {
    final templateId =
        (templateData['id'] ?? templateData['key'] ?? '').toString();
    final title = (templateData['title'] ?? templateData['name'] ?? templateId)
        .toString()
        .trim();
    if (title.isEmpty) return;
    Map<String, dynamic> saved;
    final body = {
      'packageId': templateData['packageId'],
      'titleRu': title,
      'titleKk': templateData['titleKk'] ?? templateData['nameKk'],
      'active': templateData['active'] ?? templateData['isActive'] ?? true,
    };
    if (_looksLikeUuid(templateId)) {
      saved = await BackendApiService.instance.patchMap(
        '/admin/checklist-templates/$templateId',
        body: body,
      );
    } else {
      saved = await BackendApiService.instance.postMap(
        '/admin/checklist-templates',
        body: body,
      );
    }
    final backendTemplateId = (saved['id'] ?? templateId).toString();
    final items = (templateData['items'] ?? const []) as List;
    for (var i = 0; i < items.length; i++) {
      final raw = items[i];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final text = (item['title'] ?? item['label'] ?? item['text'] ?? '')
          .toString()
          .trim();
      if (text.isEmpty) continue;
      await BackendApiService.instance.postMap(
        '/admin/checklist-templates/$backendTemplateId/items',
        body: {
          'titleRu': text,
          'titleKk': item['titleKk'] ?? item['labelKk'] ?? item['textKk'],
          'sortOrder': item['sortOrder'] ?? i,
        },
      );
    }
  }

  Future<void> deleteAdminSavedView(String viewId) async {
    if (_isDebugAdmin) {
      final currentViews = _debugAdminSavedViews()
          .where((item) => (item['id'] ?? '').toString() != viewId)
          .toList();
      debugStorageWrite(
        _debugStorageKey('admin_saved_views'),
        jsonEncode(_jsonSafe(currentViews)),
      );
      _notifyDebugStateChanged();
      return;
    }

    await BackendApiService.instance.postMap(
      '/admin/settings',
      body: {
        'key': 'admin_saved_view_$viewId',
        'value': {'id': viewId, 'deleted': true},
      },
    );
  }

  Future<void> markVideoViewed({
    required String videoId,
    required String audienceType,
    bool completed = true,
    int lastProgressSeconds = 0,
  }) async {
    if (_useDebugFixtures ||
        _isTemporaryCustomerSession ||
        _isTemporaryCleanerSession) {
      final resolvedUid = _uidOrNull ?? 'debug_user';
      final viewId = '${resolvedUid}_$videoId';
      final updated = _debugVideoViews()
          .where((item) => (item['id'] ?? '').toString() != viewId)
          .toList()
        ..add({
          'id': viewId,
          'userId': resolvedUid,
          'videoId': videoId,
          'audienceType': audienceType,
          'viewedAt': Timestamp.now(),
          'completed': completed,
          'lastProgressSeconds': lastProgressSeconds,
          'updatedAt': Timestamp.now(),
        });
      debugStorageWrite(
        _debugStorageKey('user_video_views'),
        jsonEncode(_jsonSafe(updated)),
      );
      _notifyDebugStateChanged();
      return;
    }
    await BackendApiService.instance.postMap(
      '/training/videos/$videoId/viewed',
      body: {
        'audienceType': audienceType,
        'completed': completed,
        'lastProgressSeconds': lastProgressSeconds,
      },
    );
  }

  int _sortByPublishedAtDesc(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftMs = _timestampMillis(left['publishedAt']);
    final rightMs = _timestampMillis(right['publishedAt']);
    return rightMs.compareTo(leftMs);
  }

  int _timestampMillis(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return DateTime.tryParse(value?.toString() ?? '')?.millisecondsSinceEpoch ??
        0;
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }
}
