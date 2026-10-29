import 'dart:convert';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/package_purchase_service.dart';
import 'package:domly/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('unpaid package cards allow cancellation, paid or closed cards do not',
      () {
    final purchase = {
      'type': 'package_purchase',
      'orderStatus': 'pending_payment',
      'paymentStatus': 'invoice_requested'
    };
    expect(canCancelPendingPayment(purchase), isTrue);
    expect(canCancelPendingPayment({...purchase, 'paymentStatus': 'paid'}),
        isFalse);
    expect(canCancelPendingPayment({...purchase, 'orderStatus': 'cancelled'}),
        isFalse);
    expect(canCancelPendingPayment({...purchase, 'paymentStatus': 'refunded'}),
        isFalse);
  });
  test(
      'cancelling a package closes its purchase using its payment ID and refreshes views',
      () async {
    var requests = 0;
    final api = BackendApiService.forTesting(
        sessionStore: SessionStore(),
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.path,
              endsWith('/payments/invoice-1/cancel-purchase'));
          return http.Response(
              jsonEncode({
                'ok': true,
                'data': {'cancelled': true, 'bonusReturned': 0}
              }),
              200);
        }));
    expect((await cancelUnpaidPackage(api, 'invoice-1'))['cancelled'], isTrue);
    expect(requests, 1);
    expect(api.dataRevision.value, 1);
  });
}
