import '../utils/banner_data.dart';
import 'dart:async';

import '../utils/backend_compat.dart';
import 'package:flutter/foundation.dart';

import '../app/debug_session.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';

/// AppConfigService provides centralized, admin-driven configuration
/// for packages, add-ons, bonuses, referrals, promos, and UI content.
/// All values have sensible defaults and won't crash the app if missing.
class AppConfigService {
  AppConfigService._();

  static final AppConfigService instance = AppConfigService._();
  dynamic get _db =>
      throw StateError('Firestore отключён: данные идут через backend.');

  Stream<T> _backendPollingStream<T>(Future<T> Function() loader) {
    return Stream<T>.multi((controller) {
      Timer? timer;
      var closed = false;
      Future<void> emit() async {
        if (closed) return;
        try {
          controller.add(await loader());
        } catch (_) {
          if (!closed) {
            controller.addError('Сервис временно недоступен.');
          }
        }
      }

      emit();
      timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
      controller.onCancel = () {
        closed = true;
        timer?.cancel();
      };
    });
  }

  Future<Map<String, dynamic>> _backendBootstrap() async {
    final data = await BackendApiService.instance.getMap(
      '/app/bootstrap',
      authenticated: false,
    );
    return data;
  }

  Future<Map<String, dynamic>> _backendSettings() async {
    final data = await _backendBootstrap();
    return Map<String, dynamic>.from(
      (data['settings'] as Map?) ?? const <String, dynamic>{},
    );
  }

  Stream<Map<String, dynamic>?> _safeDocStream(dynamic ref) {
    return ref.snapshots().map((doc) => doc.data());
  }

  Stream<List<Map<String, dynamic>>> _safeQueryStream(dynamic query) {
    List<Map<String, dynamic>> mapDocs(dynamic snap) {
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    }

    return query.snapshots().map(mapDocs);
  }

  // ============================================================================
  // APP CONFIG - Single document with all app-wide settings
  // ============================================================================

  /// Stream the main app config document
  Stream<Map<String, dynamic>?> appConfigStream() {
    if (kIsWeb && DebugSession.enabled) {
      return _safeDocStream(
        _db.collection('debug_bridge_policies').doc('main'),
      );
    }
    return _backendPollingStream(() async {
      final data = await _backendBootstrap();
      return Map<String, dynamic>.from(
        (data['settings'] as Map?) ?? const <String, dynamic>{},
      );
    });
  }

  /// Get app config once (no stream)
  Future<Map<String, dynamic>?> getAppConfig() async {
    if (AuthService.hasTemporarySession) {
      return const <String, dynamic>{};
    }
    if (kIsWeb && DebugSession.enabled) {
      final bridgeDoc = await _db
          .collection('debug_bridge_policies')
          .doc('main')
          .get();
      if (bridgeDoc.data() != null) {
        return bridgeDoc.data();
      }
    }
    return _backendSettings();
  }

  Stream<List<Map<String, dynamic>>> promoBannersStream() {
    if (kIsWeb && DebugSession.enabled) {
      return _safeQueryStream(_db.collection('debug_bridge_promo_banners')).map(
        (docs) {
          final items = docs.where((item) => item['isActive'] != false).toList()
            ..sort((a, b) {
              final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
              final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
              return aOrder.compareTo(bOrder);
            });
          return items;
        },
      );
    }
    return _backendPollingStream(() async {
      final data = await _backendBootstrap();
      final catalog = Map<String, dynamic>.from(
        (data['catalog'] as Map?) ?? const <String, dynamic>{},
      );
      return _mapBackendBanners(catalog['banners'], placement: 'home_top');
    });
  }

  Stream<List<Map<String, dynamic>>> promotionsStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    if (kIsWeb && DebugSession.enabled) {
      return _safeQueryStream(
        _db.collection('debug_bridge_promotions'),
      ).map(_sortActivePromotions);
    }
    return _backendPollingStream(() async {
      final data = await _backendBootstrap();
      final catalog = Map<String, dynamic>.from(
        (data['catalog'] as Map?) ?? const <String, dynamic>{},
      );
      return _sortActivePromotions(
        _mapBackendPromotions(catalog['promotions']),
      );
    });
  }

  List<Map<String, dynamic>> _sortActivePromotions(
    List<Map<String, dynamic>> docs,
  ) {
    final items = docs.where((item) => item['isActive'] != false).toList()
      ..sort((a, b) {
        final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
        final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
        if (aOrder != bOrder) {
          return aOrder.compareTo(bOrder);
        }
        return (a['title'] ?? a['id']).toString().compareTo(
          (b['title'] ?? b['id']).toString(),
        );
      });
    return items;
  }

  // ============================================================================
  // INFO CONTENT - Editable info cards for packages, add-ons, promos, etc.
  // ============================================================================

  /// Stream all info content documents
  Stream<List<Map<String, dynamic>>> infoContentStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    if (kIsWeb && DebugSession.enabled) {
      return _safeQueryStream(
        _db
            .collection('debug_bridge_info_content')
            .orderBy('sortOrder', descending: false),
      );
    }
    return _backendPollingStream(_backendInfoContent);
  }

  /// Get info content by key (e.g., 'package_2x_month', 'addon_window_standard')
  Future<Map<String, dynamic>?> getInfoContent(String key) async {
    if (AuthService.hasTemporarySession) {
      return null;
    }
    if (kIsWeb && DebugSession.enabled) {
      final bridgeDoc = await _db
          .collection('debug_bridge_info_content')
          .doc(key)
          .get();
      if (bridgeDoc.data() != null) {
        return bridgeDoc.data();
      }
    }
    final items = await _backendInfoContent();
    for (final item in items) {
      if ((item['key'] ?? item['id']).toString() == key) {
        return item;
      }
    }
    return null;
  }

  /// Stream specific info content by key
  Stream<Map<String, dynamic>?> infoContentStreamByKey(String key) {
    if (AuthService.hasTemporarySession) {
      return Stream.value(null);
    }
    if (kIsWeb && DebugSession.enabled) {
      return _safeDocStream(
        _db.collection('debug_bridge_info_content').doc(key),
      );
    }
    return _backendPollingStream(() => getInfoContent(key));
  }

  // ============================================================================
  // PACKAGES CONFIG - Admin can manage package prices, names, info text
  // ============================================================================

  /// Update package config (admin only)
  Future<void> updatePackageConfig(
    String packageId,
    Map<String, dynamic> data,
  ) async {
    await BackendApiService.instance.patchMap(
      '/admin/catalog/packages/$packageId',
      body: data,
    );
  }

  // ============================================================================
  // ADD-ONS CONFIG - Admin can manage add-on prices, descriptions, info
  // ============================================================================

  /// Stream all add-on configs
  Stream<List<Map<String, dynamic>>> addonsConfigStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _backendPollingStream(() async {
      final groups = await _backendAddonGroups();
      final items = <Map<String, dynamic>>[];
      for (final group in groups) {
        final groupKey = (group['key'] ?? group['id'] ?? '').toString();
        for (final raw in (group['items'] as List? ?? const [])) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          item['group'] = groupKey;
          item['groupLabel'] = group['label'];
          items.add(item);
        }
      }
      items.sort((a, b) {
        final aGroup = (a['group'] ?? '').toString();
        final bGroup = (b['group'] ?? '').toString();
        final byGroup = aGroup.compareTo(bGroup);
        if (byGroup != 0) {
          return byGroup;
        }
        final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
        final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
        return aOrder.compareTo(bOrder);
      });
      return items;
    });
  }

  /// Get add-on config by key
  Future<Map<String, dynamic>?> getAddonConfig(String addonKey) async {
    if (AuthService.hasTemporarySession) {
      return null;
    }
    final items = await addonsConfigStream().first;
    for (final item in items) {
      if ((item['key'] ?? item['id']).toString() == addonKey) {
        return item;
      }
    }
    return null;
  }

  /// Stream grouped add-on catalog for calculator / booking screens.
  Stream<List<Map<String, dynamic>>> addonGroupConfigsStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(
        defaultAddonGroupConfigs
            .map((group) => Map<String, dynamic>.from(group))
            .toList(),
      );
    }
    if (kIsWeb && DebugSession.enabled) {
      return _safeQueryStream(
        _db
            .collection('debug_bridge_addon_groups')
            .orderBy('sortOrder', descending: false),
      ).map((docs) {
        if (docs.isEmpty) {
          return defaultAddonGroupConfigs
              .map((group) => Map<String, dynamic>.from(group))
              .toList();
        }
        final groups =
            docs
                .map(
                  (doc) => {
                    ...doc,
                    'key': (doc['key'] ?? doc['id']).toString(),
                  },
                )
                .where((group) => group['isActive'] != false)
                .toList()
              ..sort((a, b) {
                final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
                final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
                return aOrder.compareTo(bOrder);
              });
        for (final group in groups) {
          final items =
              ((group['items'] ?? const []) as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .where((item) => item['isActive'] != false)
                  .toList()
                ..sort((a, b) {
                  final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
                  final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
                  return aOrder.compareTo(bOrder);
                });
          group['items'] = items;
        }
        return groups.isEmpty
            ? defaultAddonGroupConfigs
                  .map((group) => Map<String, dynamic>.from(group))
                  .toList()
            : groups;
      });
    }
    return _backendPollingStream(_backendAddonGroups);
  }

  Future<List<Map<String, dynamic>>> getAddonGroupConfigs() async {
    if (AuthService.hasTemporarySession) {
      return defaultAddonGroupConfigs
          .map((group) => Map<String, dynamic>.from(group))
          .toList();
    }
    return _backendAddonGroups();
  }

  /// Stream checklist template groups for cleaner checklist.
  Stream<List<Map<String, dynamic>>> cleanerChecklistTemplatesStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(
        defaultCleanerChecklistTemplates
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
    }
    if (kIsWeb && DebugSession.enabled) {
      return _safeQueryStream(
        _db
            .collection('debug_bridge_checklist_templates')
            .orderBy('sortOrder', descending: false),
      ).map((docs) {
        if (docs.isEmpty) {
          return defaultCleanerChecklistTemplates
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
        final items =
            docs
                .map(
                  (doc) => {
                    ...doc,
                    'key': (doc['key'] ?? doc['id']).toString(),
                  },
                )
                .where((item) => item['isActive'] != false)
                .toList()
              ..sort((a, b) {
                final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
                final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
                return aOrder.compareTo(bOrder);
              });
        return items.isEmpty
            ? defaultCleanerChecklistTemplates
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : items;
      });
    }
    return _backendPollingStream(_backendChecklistTemplates);
  }

  Future<List<Map<String, dynamic>>> _backendChecklistTemplates() async {
    final data = await _backendBootstrap();
    final catalog = Map<String, dynamic>.from(
      (data['catalog'] as Map?) ?? const <String, dynamic>{},
    );
    final raw =
        (catalog['checklistTemplates'] ??
                catalog['checklists'] ??
                catalog['checklist_templates'])
            as List?;
    final items =
        (raw ?? const [])
            .whereType<Map>()
            .map((doc) => Map<String, dynamic>.from(doc))
            .map(
              (doc) => {
                ...doc,
                'key': (doc['key'] ?? doc['id']).toString(),
                'title': doc['title_ru'] ?? doc['title'] ?? '',
                'titleKk': doc['title_kk'],
                'description':
                    doc['description_ru'] ?? doc['description'] ?? '',
                'descriptionKk': doc['description_kk'],
                'sortOrder': doc['sort_order'] ?? doc['sortOrder'] ?? 999,
                'isActive': doc['active'] != false,
              },
            )
            .where((item) => item['isActive'] != false)
            .toList()
          ..sort(_bySortOrder);
    return items.isEmpty
        ? defaultCleanerChecklistTemplates
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : items;
  }

  Future<List<Map<String, dynamic>>> _backendAddonGroups() async {
    final data = await _backendBootstrap();
    final catalog = Map<String, dynamic>.from(
      (data['catalog'] as Map?) ?? const <String, dynamic>{},
    );
    final groups = (catalog['addonGroups'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => _mapBackendAddonGroup(Map<String, dynamic>.from(raw)))
        .toList();
    final addons = (catalog['addons'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => _mapBackendAddon(Map<String, dynamic>.from(raw)))
        .toList();
    for (final group in groups) {
      final groupId = group['id']?.toString();
      final items =
          addons
              .where((addon) => addon['groupId']?.toString() == groupId)
              .toList()
            ..sort(_bySortOrder);
      group['items'] = items;
    }
    groups.sort(_bySortOrder);
    final nonEmpty = groups
        .where((group) => ((group['items'] as List?) ?? const []).isNotEmpty)
        .toList();
    return nonEmpty.isEmpty
        ? defaultAddonGroupConfigs
              .map((group) => Map<String, dynamic>.from(group))
              .toList()
        : nonEmpty;
  }

  Future<List<Map<String, dynamic>>> _backendInfoContent() async {
    final data = await _backendBootstrap();
    final catalog = Map<String, dynamic>.from(
      (data['catalog'] as Map?) ?? const <String, dynamic>{},
    );
    final items = <Map<String, dynamic>>[];

    void addItem(Map<String, dynamic> item) {
      final key = (item['key'] ?? item['id'] ?? '').toString();
      if (key.isEmpty) return;
      items.add({
        'id': key,
        'key': key,
        'title': item['title_ru'] ?? item['name_ru'] ?? item['title'] ?? '',
        'titleKk': item['title_kk'] ?? item['name_kk'],
        'description':
            item['description_ru'] ??
            item['description'] ??
            item['body_ru'] ??
            '',
        'descriptionKk': item['description_kk'] ?? item['body_kk'],
        'body':
            item['body_ru'] ??
            item['description_ru'] ??
            item['description'] ??
            '',
        'bodyKk': item['body_kk'] ?? item['description_kk'],
        'sortOrder': item['sort_order'] ?? item['sortOrder'] ?? 999,
        'isActive': item['active'] != false && item['isActive'] != false,
      });
    }

    for (final sourceKey in const [
      'infoContent',
      'info_content',
      'packages',
      'addons',
      'promotions',
      'banners',
    ]) {
      for (final raw in (catalog[sourceKey] as List? ?? const [])) {
        if (raw is Map) addItem(Map<String, dynamic>.from(raw));
      }
    }

    items.sort(_bySortOrder);
    return items;
  }

  List<Map<String, dynamic>> _mapBackendBanners(
    dynamic raw, {
    String? placement,
  }) {
    final items =
        (raw as List? ?? const [])
            .whereType<Map>()
            .map((item) => mapBackendBanner(Map<String, dynamic>.from(item)))
            .where((item) {
              if (item['active'] == false) return false;
              if (placement == null) return true;
              return item['placement']?.toString() == placement;
            })
            .map(
              (item) => {
                'id': item['id'],
                'title': item['title_ru'] ?? item['title'] ?? '',
                'titleKk': item['title_kk'],
                'subtitle': item['subtitle_ru'] ?? item['subtitle'] ?? '',
                'subtitleKk': item['subtitle_kk'],
                'description': item['description_ru'] ?? '',
                'descriptionKk': item['description_kk'],
                'imageUrl': item['image_url'] ?? item['imageUrl'] ?? '',
                'bannerImageUrl': item['image_url'] ?? item['imageUrl'] ?? '',
                'route': item['route'] ?? '',
                'externalUrl':
                    item['external_url'] ?? item['externalUrl'] ?? '',
                'ctaLabel': item['cta_label_ru'] ?? item['ctaLabel'] ?? '',
                'ctaLabelKk': item['cta_label_kk'],
                'sortOrder': item['sort_order'] ?? item['sortOrder'] ?? 999,
                'isActive': item['active'] != false,
              },
            )
            .toList()
          ..sort(_bySortOrder);
    return items;
  }

  List<Map<String, dynamic>> _mapBackendPromotions(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['active'] != false)
        .map(
          (item) => {
            'id': item['id'],
            'title': item['title_ru'] ?? '',
            'titleKk': item['title_kk'],
            'description': item['description_ru'] ?? '',
            'descriptionKk': item['description_kk'],
            'fullInfo': item['description_ru'] ?? '',
            'rewardMode': item['reward_type'] == 'percent'
                ? 'percent'
                : 'fixed',
            'rewardAmount': item['reward_type'] == 'fixed'
                ? _num(item['reward_value'])
                : 0,
            'rewardPercent': item['reward_type'] == 'percent'
                ? _num(item['reward_value'])
                : 0,
            'packageId': item['package_id'],
            'sortOrder': item['sort_order'] ?? item['sortOrder'] ?? 999,
            'isActive': item['active'] != false,
            'oncePerCustomer': item['once_per_customer'] == true,
            'homeBannerImageUrl': item['home_banner_image_url'] ?? '',
            'bannerImageUrl': item['banner_image_url'] ?? '',
          },
        )
        .toList();
  }

  Map<String, dynamic> _mapBackendAddonGroup(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'key': item['id']?.toString() ?? '',
      'label': item['title_ru'] ?? '',
      'labelKk': item['title_kk'],
      'sortOrder': item['sort_order'] ?? item['sortOrder'] ?? 999,
      'isActive': item['active'] != false,
      'items': <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _mapBackendAddon(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'key': item['id']?.toString() ?? '',
      'groupId': item['group_id'],
      'label': item['title_ru'] ?? '',
      'labelKk': item['title_kk'],
      'description': item['description_ru'] ?? '',
      'descriptionKk': item['description_kk'],
      'hint': item['hint_ru'] ?? '',
      'hintKk': item['hint_kk'],
      'price': _num(item['price']).round(),
      'durationMinutes': _num(item['duration_minutes']).round(),
      'pricingType': item['pricing_type'] ?? 'fixed',
      'supportsQuantity': item['pricing_type'] != 'fixed_per_order',
      'separatePayment': item['paid_separately'] == true,
      'sortOrder': item['sort_order'] ?? item['sortOrder'] ?? 999,
      'isActive': item['active'] != false,
    };
  }

  static int _bySortOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
    final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
    return aOrder.compareTo(bOrder);
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  static const List<Map<String, dynamic>> defaultAddonGroupConfigs = [
    {
      'key': 'windows',
      'label': 'Окна и стекла',
      'note': null,
      'sortOrder': 10,
      'isActive': true,
      'items': [
        {
          'key': 'window_standard',
          'label': 'Мытье окон стандарт',
          'price': 3000,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'window_panorama',
          'label': 'Панорама',
          'price': 5500,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 20,
          'isActive': true,
        },
        {
          'key': 'window_mosquito',
          'label': 'Мытье москитных сеток',
          'price': 1200,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 30,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'balcony',
      'label': 'Балкон',
      'note': null,
      'sortOrder': 20,
      'isActive': true,
      'items': [
        {
          'key': 'balcony_window_standard',
          'label': 'Мытье окон стандарт',
          'price': 3000,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'balcony_panorama',
          'label': 'Панорама',
          'price': 5500,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 20,
          'isActive': true,
        },
        {
          'key': 'balcony_balcony',
          'label': 'Балкон',
          'price': 2500,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 30,
          'isActive': true,
        },
        {
          'key': 'balcony_loggia',
          'label': 'Лоджия',
          'price': 2500,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 40,
          'isActive': true,
        },
        {
          'key': 'balcony_terrace',
          'label': 'Терасса',
          'price': 5000,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 50,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'kitchen',
      'label': 'Кухня',
      'note': null,
      'sortOrder': 30,
      'isActive': true,
      'items': [
        {
          'key': 'kitchen_oven',
          'label': 'Чистка духовки внутри',
          'price': 2500,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'kitchen_hood',
          'label': 'Чистка вытяжки и фильтров',
          'price': 2200,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 20,
          'isActive': true,
        },
        {
          'key': 'kitchen_fridge',
          'label': 'Мытье холодильника внутри',
          'price': 2500,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 30,
          'isActive': true,
        },
        {
          'key': 'kitchen_facades',
          'label': 'Мытье фасадов кухонного гарнитура',
          'price': 3000,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 40,
          'isActive': true,
        },
        {
          'key': 'kitchen_full_set',
          'label': 'Полное мытье кухонного гарнитура',
          'price': 6500,
          'supportsQuantity': false,
          'separatePayment': false,
          'note': 'Внутри и снаружи',
          'sortOrder': 50,
          'isActive': true,
        },
        {
          'key': 'kitchen_stove',
          'label': 'Чистка плит и варочных панелей',
          'price': 1800,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 60,
          'isActive': true,
        },
        {
          'key': 'kitchen_microwave',
          'label': 'Чистка микроволновки',
          'price': 1200,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 70,
          'isActive': true,
        },
        {
          'key': 'kitchen_apron',
          'label': 'Мытье фартука',
          'price': 1500,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 80,
          'isActive': true,
        },
        {
          'key': 'kitchen_dishes_hand',
          'label': 'Мытье посуды вручную',
          'price': 2500,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 90,
          'isActive': true,
        },
        {
          'key': 'kitchen_dishwasher_loading',
          'label': 'Загрузка посуды в посудомойку',
          'price': 800,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 100,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'bathroom',
      'label': 'Санузлы',
      'note': null,
      'sortOrder': 40,
      'isActive': true,
      'items': [
        {
          'key': 'bath_tile_walls',
          'label': 'Стены кафель',
          'price': 3000,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'bath_glass_walls',
          'label': 'Стеклянные стены душа и ванны',
          'price': 2800,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 20,
          'isActive': true,
        },
        {
          'key': 'bath_washer_wipe',
          'label': 'Протирка стиральной машины',
          'price': 900,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 30,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'textile',
      'label': 'Комфорт и текстиль',
      'note': null,
      'sortOrder': 50,
      'isActive': true,
      'items': [
        {
          'key': 'textile_bed_linen_ironing',
          'label': 'Глажка постельного белья',
          'price': 1800,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'textile_clothes_ironing',
          'label': 'Глажка одежды',
          'price': 1800,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 20,
          'isActive': true,
        },
        {
          'key': 'textile_curtains_ironing',
          'label': 'Глажка штор',
          'price': 3500,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 30,
          'isActive': true,
        },
        {
          'key': 'textile_bed_change',
          'label': 'Замена постельного белья и заправка кроватей',
          'price': 1500,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 40,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'hard',
      'label': 'Труднодоступные зоны',
      'note': null,
      'sortOrder': 60,
      'isActive': true,
      'items': [
        {
          'key': 'hard_chandelier_standard',
          'label': 'Чистка люстр стандартная',
          'price': 2500,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'hard_chandelier_complex',
          'label': 'Чистка люстр сложная',
          'price': 4500,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 20,
          'isActive': true,
        },
        {
          'key': 'hard_chandelier_super',
          'label': 'Чистка люстр супер сложная',
          'price': 7000,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 30,
          'isActive': true,
        },
        {
          'key': 'hard_lamps',
          'label': 'Светильники и плафоны',
          'price': 1200,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 40,
          'isActive': true,
        },
        {
          'key': 'hard_upper_shelves',
          'label': 'Чистка верхних полок, антресолей и шкафов',
          'price': 1800,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 50,
          'isActive': true,
        },
        {
          'key': 'hard_baseboards',
          'label': 'Чистка плинтусов',
          'price': 1400,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 60,
          'isActive': true,
        },
        {
          'key': 'hard_doors',
          'label': 'Мытье дверей',
          'price': 900,
          'supportsQuantity': true,
          'separatePayment': false,
          'sortOrder': 70,
          'isActive': true,
        },
        {
          'key': 'hard_cobweb',
          'label': 'Удаление паутины и пыли в труднодоступных местах',
          'price': 1600,
          'supportsQuantity': false,
          'separatePayment': false,
          'sortOrder': 80,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'furniture',
      'label': 'Мебель и поверхности',
      'note': 'Данная услуга оплачивается отдельно при оценке специалиста.',
      'sortOrder': 70,
      'isActive': true,
      'items': [
        {
          'key': 'furniture_sofa',
          'label': 'Химчистка диванов',
          'price': 9000,
          'supportsQuantity': true,
          'separatePayment': true,
          'note': 'Данная услуга оплачивается отдельно при оценке специалиста.',
          'sortOrder': 10,
          'isActive': true,
        },
        {
          'key': 'furniture_mattress',
          'label': 'Химчистка матрасов',
          'price': 7000,
          'supportsQuantity': true,
          'separatePayment': true,
          'note': 'Данная услуга оплачивается отдельно при оценке специалиста.',
          'sortOrder': 20,
          'isActive': true,
        },
      ],
    },
    {
      'key': 'carpet',
      'label': 'Химчистка ковров и паласов',
      'note': 'Данная услуга оплачивается отдельно при оценке специалиста.',
      'sortOrder': 80,
      'isActive': true,
      'items': [
        {
          'key': 'carpet_cleaning',
          'label': 'Химчистка ковров и паласов',
          'price': 0,
          'supportsQuantity': true,
          'separatePayment': true,
          'note': 'Данная услуга оплачивается отдельно при оценке специалиста.',
          'sortOrder': 10,
          'isActive': true,
        },
      ],
    },
  ];

  static const List<Map<String, dynamic>> defaultCleanerChecklistTemplates = [
    {
      'key': 'base_tasks',
      'title': 'Основные этапы уборки',
      'description': '',
      'sortOrder': 10,
      'isActive': true,
      'items': [
        'Протереть пыль',
        'Пропылесосить',
        'Вымыть пол',
        'Очистить кухню',
        'Очистить санузел',
      ],
    },
    {
      'key': 'addon_tasks',
      'title': 'Дополнительные услуги',
      'description': 'Отметьте, если предложено или выполнено',
      'sortOrder': 20,
      'isActive': true,
      'items': [
        'Мытье окон',
        'Глажка белья',
        'Уборка балкона',
        'Химчистка мебели',
        'Глубокая уборка кухни',
      ],
    },
  ];

  // ============================================================================
  // REFERRAL CONFIG - Admin can manage referral bonuses, conditions
  // ============================================================================

  /// Stream referral config
  Stream<Map<String, dynamic>?> referralConfigStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(Map<String, dynamic>.from(_defaultReferralConfig));
    }
    if (kIsWeb && DebugSession.enabled) {
      return appConfigStream().map((config) => _debugReferralConfig(config));
    }
    return _backendPollingStream(() async {
      return _debugReferralConfig(await _backendSettings());
    });
  }

  /// Get referral config once
  Future<Map<String, dynamic>> getReferralConfig() async {
    if (AuthService.hasTemporarySession) {
      return Map<String, dynamic>.from(_defaultReferralConfig);
    }
    if (kIsWeb && DebugSession.enabled) {
      return _debugReferralConfig(await getAppConfig());
    }
    return _debugReferralConfig(await _backendSettings());
  }

  static const Map<String, dynamic> _defaultReferralConfig = {
    'bonusPerReferral': 2000,
    'milestoneCount': 5,
    'milestoneBonus': 10000,
    'apartmentTiers': [
      {'count': 5, 'discount': 3},
      {'count': 10, 'discount': 7},
      {'count': 20, 'discount': 10},
    ],
    'title': 'Бонусы за приглашение',
    'subtitle': 'Приглашай друзей и получай скидки',
    'description': 'Отправь реферальную ссылку другу или подруге',
    'bonusDescription':
        '2000 ₸ на доп. услуги после покупки пакета вашим рефералом',
    'milestoneDescription': 'Пригласите 5 человек',
    'infoNote':
        'Бонусы за приглашение начисляются после покупки вашим рефералом любого пакета. Реферальные скидки (3%, 7%, 10%) действуют на все виды услуг на постоянной основе.',
  };

  // ============================================================================
  // AREA CONFIRMATION CONFIG - Admin can manage bonus amount, conditions
  // ============================================================================

  /// Stream area confirmation config
  Stream<Map<String, dynamic>?> areaConfigStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(Map<String, dynamic>.from(_defaultAreaConfig));
    }
    if (kIsWeb && DebugSession.enabled) {
      return appConfigStream().map((config) => _debugAreaConfig(config));
    }
    return _backendPollingStream(() async {
      return _debugAreaConfig(await _backendSettings());
    });
  }

  /// Get area confirmation config once
  Future<Map<String, dynamic>> getAreaConfig() async {
    if (AuthService.hasTemporarySession) {
      return Map<String, dynamic>.from(_defaultAreaConfig);
    }
    if (kIsWeb && DebugSession.enabled) {
      return _debugAreaConfig(await getAppConfig());
    }
    return _debugAreaConfig(await _backendSettings());
  }

  static const Map<String, dynamic> _defaultAreaConfig = {
    'bonusAmount': 2000,
    'title': 'Подтверждение площади',
    'description':
        'Подтвердите площадь квартиры и получите бонус на доп. услуги',
    'buttonText': 'Проверить / Подтвердить',
    'uploadEnabled': true,
    'techPlanRequired': false,
  };

  // ============================================================================
  // WORKER BONUSES CONFIG
  // ============================================================================

  /// Stream worker bonus config
  Stream<Map<String, dynamic>?> workerBonusConfigStream() {
    if (AuthService.hasTemporarySession) {
      return Stream.value(Map<String, dynamic>.from(_defaultWorkerBonusConfig));
    }
    if (kIsWeb && DebugSession.enabled) {
      return appConfigStream().map((config) => _debugWorkerBonusConfig(config));
    }
    return _backendPollingStream(() async {
      return _debugWorkerBonusConfig(await _backendSettings());
    });
  }

  /// Get worker bonus config once
  Future<Map<String, dynamic>> getWorkerBonusConfig() async {
    if (AuthService.hasTemporarySession) {
      return Map<String, dynamic>.from(_defaultWorkerBonusConfig);
    }
    if (kIsWeb && DebugSession.enabled) {
      return _debugWorkerBonusConfig(await getAppConfig());
    }
    return _debugWorkerBonusConfig(await _backendSettings());
  }

  static const Map<String, dynamic> _defaultWorkerBonusConfig = {
    'bonusesVisible': true,
    'title': 'Бонусы и достижения',
    'description':
        'Ваши бонусы зависят от качества и количества выполненной работы',
  };

  Map<String, dynamic> _debugReferralConfig(Map<String, dynamic>? config) {
    final base = Map<String, dynamic>.from(_defaultReferralConfig);
    if (config == null) {
      return base;
    }
    return {
      ...base,
      'bonusPerReferral':
          (config['referralBonusAmount'] as num?)?.toInt() ??
          base['bonusPerReferral'],
    };
  }

  Map<String, dynamic> _debugAreaConfig(Map<String, dynamic>? config) {
    final base = Map<String, dynamic>.from(_defaultAreaConfig);
    if (config == null) {
      return base;
    }
    return {
      ...base,
      'tolerance': (config['areaVerificationTolerance'] as num?)?.toInt() ?? 0,
      'defaultHouseThreshold':
          (config['defaultHouseThreshold'] as num?)?.toInt() ?? 20,
    };
  }

  Map<String, dynamic> _debugWorkerBonusConfig(Map<String, dynamic>? config) {
    final base = Map<String, dynamic>.from(_defaultWorkerBonusConfig);
    if (config == null) {
      return base;
    }
    return {
      ...base,
      'dailyIncome': (config['cleanerDailyIncome'] as num?)?.toInt() ?? 13500,
      'weeklyCashoutPercent':
          (config['cleanerWeeklyCashoutPercent'] as num?)?.toInt() ?? 30,
      'weeklyCashoutCooldownDays':
          (config['cleanerWeeklyCashoutCooldownDays'] as num?)?.toInt() ?? 7,
      'fullCashoutCooldownDays':
          (config['cleanerFullCashoutCooldownDays'] as num?)?.toInt() ?? 30,
      'reliableAreaThreshold':
          (config['cleanerReliableAreaThreshold'] as num?)?.toInt() ?? 12000,
      'reliableBonusAmount':
          (config['cleanerReliableBonusAmount'] as num?)?.toInt() ?? 100000,
      'expertAreaThreshold':
          (config['cleanerExpertAreaThreshold'] as num?)?.toInt() ?? 30000,
      'expertBonusAmount':
          (config['cleanerExpertBonusAmount'] as num?)?.toInt() ?? 200000,
      'legendAreaThreshold':
          (config['cleanerLegendAreaThreshold'] as num?)?.toInt() ?? 65000,
      'legendBonusAmount':
          (config['cleanerLegendBonusAmount'] as num?)?.toInt() ?? 500000,
      'weeklyAreaThreshold':
          (config['cleanerWeeklyAreaThreshold'] as num?)?.toInt() ?? 1300,
      'weeklyAreaBonusAmount':
          (config['cleanerWeeklyAreaBonusAmount'] as num?)?.toInt() ?? 5000,
      'weeklyAddonBonusThreshold1':
          (config['cleanerWeeklyAddonBonusThreshold1'] as num?)?.toInt() ??
          30000,
      'weeklyAddonBonusAmount1':
          (config['cleanerWeeklyAddonBonusAmount1'] as num?)?.toInt() ?? 4000,
      'weeklyAddonBonusThreshold2':
          (config['cleanerWeeklyAddonBonusThreshold2'] as num?)?.toInt() ??
          50000,
      'weeklyAddonBonusAmount2':
          (config['cleanerWeeklyAddonBonusAmount2'] as num?)?.toInt() ?? 6000,
    };
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Get a string value with fallback
  String getString(Map<String, dynamic>? config, String key, String fallback) {
    if (config == null) return fallback;
    return (config[key] ?? fallback).toString();
  }

  /// Get an int value with fallback
  int getInt(Map<String, dynamic>? config, String key, int fallback) {
    if (config == null) return fallback;
    return (config[key] as num?)?.toInt() ?? fallback;
  }

  /// Get a double value with fallback
  double getDouble(Map<String, dynamic>? config, String key, double fallback) {
    if (config == null) return fallback;
    return (config[key] as num?)?.toDouble() ?? fallback;
  }

  /// Get a bool value with fallback
  bool getBool(Map<String, dynamic>? config, String key, bool fallback) {
    if (config == null) return fallback;
    final value = config[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return fallback;
  }
}
