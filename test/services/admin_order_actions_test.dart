import 'dart:convert';
import 'package:domly/services/admin_order_actions.dart';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'administrator cancellation updates the order instead of only adding an audit event',
      () async {
    final store = SessionStore(surface: SessionSurface.admin);
    await store.saveBackendSession(const BackendSession(
        accessToken: 'admin-test',
        refreshToken: 'refresh',
        userId: 'admin',
        role: 'superadmin'));
    var calls = 0;
    final api = BackendApiService.forTesting(
        sessionStore: store,
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'PATCH');
          expect(request.url.path, endsWith('/admin/orders/order-1'));
          expect(request.headers['Authorization'], 'Bearer admin-test');
          expect(jsonDecode(request.body), {'status': 'cancelled'});
          return http.Response(
              jsonEncode({
                'ok': true,
                'data': {'id': 'order-1', 'status': 'cancelled'}
              }),
              200);
        }));
    await changeAdminOrderStatus(api, 'order-1', 'canceled');
    expect(calls, 1);
    expect(api.dataRevision.value, 1);
  });
  test(
      'server rejection remains a failure rather than a successful status change',
      () async {
    final api = BackendApiService.forTesting(
        sessionStore: SessionStore(surface: SessionSurface.admin),
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'ok': false,
              'error': {
                'code': 'invalid_transition',
                'message': 'Заказ уже завершён'
              }
            }),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    await expectLater(
        changeAdminOrderStatus(api, 'order', 'cancelled'),
        throwsA(isA<BackendApiException>()
            .having((e) => e.statusCode, 'status', 409)));
    expect(api.dataRevision.value, 0);
  });
}
