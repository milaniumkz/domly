import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'concurrent unauthorized requests share refresh failure without unhandled errors',
      () async {
    final store = SessionStore(surface: SessionSurface.customer);
    await store.saveBackendSession(const BackendSession(
        accessToken: 'expired',
        refreshToken: 'invalid',
        userId: 'user',
        role: 'customer'));
    var refreshes = 0;
    final api = BackendApiService.forTesting(
        sessionStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'unauthenticated',
                  'message': 'Login required'
                }
              }),
              401);
        }));
    await Future.wait(List.generate(
        3,
        (_) => expectLater(
            api.getMap('/orders'), throwsA(isA<BackendApiException>()))));
    expect(refreshes, 1);
    expect(await store.backendSession(), isNull);
  });
  test('temporary refresh outage preserves the session for retry', () async {
    final store = SessionStore(surface: SessionSurface.customer);
    await store.saveBackendSession(const BackendSession(
        accessToken: 'expired',
        refreshToken: 'valid',
        userId: 'user',
        role: 'customer'));
    final api = BackendApiService.forTesting(
        sessionStore: store,
        client: MockClient((request) async => http.Response(
            '{}', request.url.path.endsWith('/auth/refresh') ? 503 : 401)));
    await expectLater(
        api.getMap('/orders'), throwsA(isA<BackendApiException>()));
    expect(await store.refreshToken(), 'valid');
  });
  test('successful mutations refresh live data immediately; errors do not',
      () async {
    final api = BackendApiService.forTesting(
        sessionStore: SessionStore(surface: SessionSurface.customer),
        client: MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/failed')
                ? {
                    'error': {'code': 'conflict', 'message': 'Conflict'}
                  }
                : {
                    'data': {'ok': true}
                  }),
            request.url.path.endsWith('/failed') ? 409 : 200)));
    await api.getMap('/orders');
    expect(api.dataRevision.value, 0);
    await api.postMap('/orders/one/status', body: {'status': 'in_progress'});
    expect(api.dataRevision.value, 1);
    await expectLater(
        api.postMap('/failed', body: {}), throwsA(isA<BackendApiException>()));
    expect(api.dataRevision.value, 1);
  });
}
