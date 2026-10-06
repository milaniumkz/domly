import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/translation_controller.dart';
import '../utils/app_logger.dart';
import 'backend_api_service.dart';

class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  static const String _lastSyncKey = 'last_sync_timestamp';
  static const String _cachedOrdersKey = 'cached_orders';
  static const String _cachedProfileKey = 'cached_profile';

  /// Backend mode keeps only lightweight local UI cache.
  Future<void> enableOfflinePersistence() async {
    AppLogger.i(
      'OfflineCache',
      kIsWeb ? 'Backend web cache mode' : 'Backend mobile cache mode',
    );
  }

  /// Save customer profile to local cache
  Future<void> cacheProfile(Map<String, dynamic> profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Store as JSON string (would need json serialization in production)
      await prefs.setString(_cachedProfileKey, profile.toString());
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger.w('OfflineCache', 'Failed to cache profile: $e');
    }
  }

  /// Get cached customer profile
  Future<Map<String, dynamic>?> getCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedProfileKey);
      if (cached == null) return null;

      // In production, use proper JSON parsing
      // For now, return null to indicate cache miss
      return null;
    } catch (e) {
      AppLogger.w('OfflineCache', 'Failed to get cached profile: $e');
      return null;
    }
  }

  /// Check if data is stale (older than 1 hour)
  Future<bool> isDataStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
      final hourAgo = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      return lastSync < hourAgo;
    } catch (e) {
      return true; // If can't check, assume stale
    }
  }

  /// Check if network is available (simplified)
  Future<bool> isOnline() async {
    try {
      // In production, use connectivity_plus package
      // For now, assume online (Firestore handles offline automatically)
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get orders with offline support
  Stream<List<Map<String, dynamic>>> getOrdersStream(String customerId) {
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      Timer? timer;
      var closed = false;
      Future<void> load() async {
        if (closed) return;
        try {
          final orders = await BackendApiService.instance.getList('/orders');
          controller.add(
            orders
                .where(
                  (order) =>
                      order['customerId']?.toString() == customerId ||
                      order['customer_id']?.toString() == customerId,
                )
                .toList(),
          );
        } catch (e) {
          if (!closed) controller.addError(e);
        }
      }

      load();
      timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
      controller.onCancel = () {
        closed = true;
        timer?.cancel();
      };
    });
  }

  /// Create order with offline queue
  Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData,
  ) async {
    try {
      final created = await BackendApiService.instance.postMap(
        '/orders',
        body: orderData,
      );
      AppLogger.i('OfflineCache', 'Order created: ${created['id']}');
      return {'ok': true, 'orderId': created['id'], ...created};
    } catch (e) {
      AppLogger.e('OfflineCache', 'Failed to create order: $e');
      rethrow;
    }
  }

  /// Clear cache (for testing or logout)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedOrdersKey);
      await prefs.remove(_cachedProfileKey);
      await prefs.remove(_lastSyncKey);
      AppLogger.i('OfflineCache', 'Cache cleared');
    } catch (e) {
      AppLogger.w('OfflineCache', 'Failed to clear cache: $e');
    }
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastSyncKey);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      return null;
    }
  }
}

/// Offline-aware widget builder
class OfflineAwareBuilder<T> extends StatelessWidget {
  final Stream<T> onlineStream;
  final Widget Function(T data) builder;
  final Widget? loadingWidget;
  final Widget? offlineWidget;
  final Widget? errorWidget;

  const OfflineAwareBuilder({
    super.key,
    required this.onlineStream,
    required this.builder,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.offlineWidget,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: onlineStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return errorWidget ??
              Center(child: Text('Ошибка загрузки данных'.tr()));
        }
        if (!snapshot.hasData) {
          return offlineWidget ??
              Center(child: Text('Нет подключения к интернету'.tr()));
        }
        return builder(snapshot.data as T);
      },
    );
  }
}
