import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:domly/services/assistant_guest_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'first-open identity is random, stable and separate from account credentials',
      () async {
    final keys = <String>[];
    final client = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      if (request.url.path.endsWith('/guest-session')) {
        keys.add(
            (jsonDecode(request.body) as Map)['installationKey'] as String);
        return http.Response(
            jsonEncode({
              'data': {'chatId': 'guest-chat'}
            }),
            200);
      }
      expect(request.headers['x-assistant-session'], keys.first);
      return http.Response(jsonEncode({'data': []}), 200);
    });
    final service = AssistantGuestService(client: client, enablePush: false);
    await Future.wait([service.initialize(), service.initialize()]);
    expect(keys.length, 1);
    expect(keys.first, matches(RegExp(r'^[a-f0-9]{64}$')));
    await service.initialize();
    expect(keys.last, keys.first);
    expect(await service.messages().first, isEmpty);
    client.close();
  });
  test('unconfigured assistant can retry without breaking first-open identity',
      () async {
    var ready = false;
    final keys = <String>[];
    final client = MockClient((request) async {
      keys.add((jsonDecode(request.body) as Map)['installationKey'] as String);
      return http.Response(
          jsonEncode(ready
              ? {
                  'data': {'chatId': 'guest-chat'}
                }
              : {'message': 'Помощник пока не подключён.'}),
          ready ? 200 : 503,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = AssistantGuestService(client: client, enablePush: false);
    await expectLater(service.initialize(), throwsStateError);
    ready = true;
    await service.initialize();
    expect(keys[0], keys[1]);
    client.close();
  });
}
