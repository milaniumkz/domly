import 'dart:async';
import 'dart:convert';
import 'package:domly/services/realtime_updates.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continuous events refresh views without waiting for the event stream to become quiet', () async {
    final source = StreamController<List<int>>();
    final connected = Completer<void>();
    var changes = 0;
    final client = MockClient.streaming((request, body) async {
      connected.complete();
      return http.StreamedResponse(source.stream, 200,
          headers: {'content-type': 'text/event-stream'});
    });
    final updates = RealtimeUpdates(createClient: () => client,
        tokenLoader: () async => 'fixture', onChanged: () => changes++);
    updates.start('customer');
    await connected.future;
    for (var i = 0; i < 15; i++) {
      source.add(utf8.encode('event: message\ndata: {"type":"notification"}\n\n'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final duringStream = changes;
    updates.stop();
    await source.close();
    expect(duringStream, greaterThanOrEqualTo(2));
    expect(duringStream, lessThan(15));
  });
  test(
      'authenticated server events refresh views; heartbeats and stopped sessions do not',
      () async {
    final source = StreamController<List<int>>();
    var changes = 0;
    final connected = Completer<void>();
    final client = MockClient.streaming((request, body) async {
      expect(request.headers['Authorization'], 'Bearer fixture');
      expect(request.url.query, isEmpty);
      connected.complete();
      return http.StreamedResponse(source.stream, 200,
          headers: {'content-type': 'text/event-stream'});
    });
    final updates = RealtimeUpdates(
        createClient: () => client,
        tokenLoader: () async => 'fixture',
        onChanged: () => changes++);
    updates.start('customer');
    await connected.future;
    source.add(utf8.encode(
        'data: {"type":"connected"}\n\nevent: ping\ndata: {"time":"now"}\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(changes, 0);
    source.add(utf8.encode(
        'data: {"type":"notification"}\n\ndata: {"type":"order_status"}\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(changes, 1);
    updates.stop();
    source.add(utf8.encode('data: {"type":"notification"}\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(changes, 1);
    await source.close();
  });
}
