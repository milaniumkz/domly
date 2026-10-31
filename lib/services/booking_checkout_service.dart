import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../utils/booking_addon_data.dart';
import 'backend_api_service.dart';

/// Saves bookings using the customer's selected payment provider for new extras.
class BookingCheckoutService {
  BookingCheckoutService(this._api);
  final BackendApiService _api;

  Future<Map<String, dynamic>> book({
    required String subscriptionId,
    required List<Map<String, dynamic>> selections,
    required String Function() createRequestKey,
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
      final addonIds = bookingAddonIds(selection);
      final addonDetails = <Map<String, dynamic>>[
        ...(selection['newAddonsDetailed'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)),
      ];
      final bonusToSpend = math.max(
        0,
        (selection['bonusToSpend'] as num?)?.toInt() ?? 0,
      );
      final kaspiPhone = (selection['kaspiPhone'] ?? '').toString().trim();
      final provider = (selection['paymentProvider'] ?? 'kaspi').toString();
      if (!['bcc', 'kaspi'].contains(provider)) {
        throw ArgumentError('Unsupported booking payment provider');
      }
      final quotedAddons = billableBookingAddonsAmount(addonDetails);
      if (provider == 'kaspi' &&
          addonDetails.isNotEmpty &&
          kaspiPhone.isEmpty &&
          bonusToSpend < quotedAddons) {
        throw FlutterError('Укажите номер Kaspi для оплаты доп. услуг.');
      }
      final created = await _api.postMap(
        '/orders',
        body: {
          'idempotencyKey': createRequestKey(),
          'customerPackageId': subscriptionId,
          'date': dateKey,
          'startTime': startTime,
          if (addonDetails.isNotEmpty) 'addonsDetailed': addonDetails,
          if (addonDetails.isEmpty && addonIds.isNotEmpty) 'addonIds': addonIds,
        },
      );
      createdOrders.add(created);
      backendScheduledCount++;
      final order = created['order'];
      final orderId = order is Map ? (order['id'] ?? '').toString() : '';
      final addonAmount =
          order is Map ? (num.tryParse('${order['addon_amount']}') ?? 0) : 0;
      if (orderId.isNotEmpty && addonAmount > 0) {
        if (provider == 'kaspi' &&
            kaspiPhone.isEmpty &&
            bonusToSpend < addonAmount) {
          throw FlutterError('Укажите номер Kaspi для оплаты доп. услуг.');
        }
        final payment = await _api.postMap(
          '/orders/$orderId/pay',
          body: {
            'provider': provider,
            'useBonus': bonusToSpend > 0,
            'requestedBonus': bonusToSpend,
            if (provider == 'kaspi' && kaspiPhone.isNotEmpty)
              'invoicePhone': kaspiPhone,
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
      'addonPaymentIds': paymentResults
          .map((result) => result['payment'])
          .whereType<Map>()
          .map((payment) => payment['id'].toString())
          .toList(),
      'backend': true,
    };
  }
}
