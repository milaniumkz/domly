import 'dart:async';
import 'dart:convert';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/notification_count_stream.dart';
import 'package:domly/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('badge refreshes a count without downloading history and discards old-account results', () async {
    final store = SessionStore(surface: SessionSurface.customer);
    await store.saveBackendSession(const BackendSession(accessToken: 'fixture',
        refreshToken: 'fixture', userId: 'customer', role: 'customer'));
    var count = 3430, calls = 0, current = true;
    Completer<void>? hold;
    final api = BackendApiService.forTesting(sessionStore: store,
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/notifications/unread-count'));
        calls++;
        if (hold != null) await hold!.future;
        return http.Response(jsonEncode({'ok': true, 'data': {'count': count}}), 200);
      }));
    final values = <int>[];
    final sub = notificationCountStream(api, isCurrentUser: () => current).listen(values.add);
    Future<void> until(bool Function() done) async {
      for(var i=0;i<200&&!done();i++) { await Future<void>.delayed(const Duration(milliseconds: 5)); }
      expect(done(), isTrue);
    }
    await until(() => values.isNotEmpty);
    expect(values, [3430]);
    count++; api.dataRevision.value++;
    await until(() => values.length == 2);
    expect(values.last, 3431);
    hold = Completer<void>(); api.dataRevision.value++;
    await until(() => calls == 3);
    current = false; hold!.complete();
    await until(() => values.length == 3);
    expect(values.last, 0);
    await sub.cancel();
    api.dataRevision.value++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 3);
  });
}
