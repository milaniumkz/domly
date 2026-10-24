import 'dart:convert';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('bulk settings accepts the existing list response and preserves authentication', () async {
    final store = SessionStore(surface: SessionSurface.admin);
    await store.saveBackendSession(const BackendSession(accessToken: 'admin-test', refreshToken: 'refresh', userId: 'admin', role: 'superadmin'));
    final api = BackendApiService.forTesting(sessionStore: store, client: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/admin/settings'));
      expect(request.headers['Authorization'], 'Bearer admin-test');
      expect(jsonDecode(request.body), {'settings': {'cleaningBaseMinutes': 30}});
      return http.Response(jsonEncode({'ok': true, 'data': [{'key':'cleaningBaseMinutes','value':30}]}), 200);
    }));
    final rows = await api.postList('/admin/settings', body: {'settings': {'cleaningBaseMinutes': 30}});
    expect(rows.single, {'key':'cleaningBaseMinutes','value':30});
  });
  test('a rejected settings update is not treated as saved', () async {
    final store = SessionStore(surface: SessionSurface.admin);
    await store.saveBackendSession(const BackendSession(accessToken: 'admin-test', refreshToken: 'refresh', userId: 'admin', role: 'superadmin'));
    final api = BackendApiService.forTesting(sessionStore: store, client: MockClient((_) async => http.Response(jsonEncode({'ok':false,'error':{'code':'forbidden','message':'Недостаточно прав'}}),403)));
    await expectLater(api.postList('/admin/settings', body: {'settings': {}}), throwsA(isA<BackendApiException>().having((e)=>e.statusCode,'status',403)));
  });
}
