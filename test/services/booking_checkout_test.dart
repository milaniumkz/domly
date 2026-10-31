import 'dart:convert';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/booking_checkout_service.dart';
import 'package:domly/services/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> requests;
  late BookingCheckoutService checkout;
  var serverAmount = 43;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    serverAmount = 43;
    final store = SessionStore(surface: SessionSurface.customer);
    await store.saveBackendSession(const BackendSession(
        accessToken: 'fixture',
        refreshToken: 'fixture',
        userId: 'customer',
        role: 'customer'));
    checkout = BookingCheckoutService(BackendApiService.forTesting(
        sessionStore: store,
        client: MockClient((request) async {
          requests.add(request);
          final data = request.url.path.endsWith('/orders')
              ? {
                  'order': {'id': 'order-1', 'addon_amount': '$serverAmount'}
                }
              : {
                  'payment': {'id': 'payment-1', 'amount': serverAmount},
                  'payableAmount': serverAmount
                };
          return http.Response(jsonEncode({'ok': true, 'data': data}), 200,
              headers: {'content-type': 'application/json'});
        })));
  });
  Map<String, dynamic> selection(
          {String provider = 'bcc',
          String? phone,
          int bonus = 0,
          bool separate = false}) =>
      {
        'date': '2039-11-02',
        'time': '14:00 - 16:55',
        'paymentProvider': provider,
        if (phone != null) 'kaspiPhone': phone,
        'bonusToSpend': bonus,
        'newAddonsDetailed': [
          {
            'key': 'test-addon',
            'price': 43,
            'quantity': 1,
            'separatePayment': separate
          }
        ]
      };
  Future<Map<String, dynamic>> book(Map<String, dynamic> item) => checkout.book(
      subscriptionId: 'wallet',
      selections: [item],
      createRequestKey: () => 'fixture-key');

  test('BCC booking of 43 tenge extra needs no Kaspi phone and charges BCC',
      () async {
    final result = await book(selection());
    expect(requests.length, 2);
    expect(requests.first.url.path.endsWith('/orders'), isTrue);
    final payment = jsonDecode(requests.last.body) as Map;
    expect(payment['provider'], 'bcc');
    expect(payment.containsKey('invoicePhone'), isFalse);
    expect(payment['useBonus'], isFalse);
    expect(result['addonPaymentIds'], ['payment-1']);
  });
  test('BCC supports partial bonus payment without asking for Kaspi', () async {
    await book(selection(bonus: 20));
    final payment = jsonDecode(requests.last.body) as Map;
    expect(payment['provider'], 'bcc');
    expect(payment['requestedBonus'], 20);
    expect(payment['useBonus'], isTrue);
    expect(payment.containsKey('invoicePhone'), isFalse);
  });
  test('Kaspi still requires a phone before creating an unpaid booking',
      () async {
    await expectLater(
        book(selection(provider: 'kaspi')), throwsA(isA<FlutterError>()));
    expect(requests, isEmpty);
    await book(selection(provider: 'kaspi', phone: '+77000000000'));
    final payment = jsonDecode(requests.last.body) as Map;
    expect(payment['provider'], 'kaspi');
    expect(payment['invoicePhone'], '+77000000000');
  });
  test('fully bonus-funded extras do not require a Kaspi phone', () async {
    await book(selection(provider: 'kaspi', bonus: 43));
    final payment = jsonDecode(requests.last.body) as Map;
    expect(payment['requestedBonus'], 43);
    expect(payment['useBonus'], isTrue);
  });
  test('separately paid specialist service creates no upfront payment',
      () async {
    serverAmount = 0;
    final result = await book(selection(provider: 'kaspi', separate: true));
    expect(requests.length, 1);
    expect(result['addonPaymentIds'], isEmpty);
  });
  test('legacy selections retain Kaspi phone validation', () async {
    final legacy = selection()..remove('paymentProvider');
    await expectLater(book(legacy), throwsA(isA<FlutterError>()));
    expect(requests, isEmpty);
  });
  test('unknown providers cannot silently create Kaspi orders', () async {
    await expectLater(book(selection(provider: 'other')), throwsArgumentError);
    expect(requests, isEmpty);
  });
}
