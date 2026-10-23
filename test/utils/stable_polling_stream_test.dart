import 'dart:async';
import 'package:domly/utils/stable_polling_stream.dart';
import 'package:domly/utils/service_coverage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('city-wide Astana coverage does not depend on a building enrollment',
      () {
    for (final city in [
      'Астана',
      'г. Астана',
      'Astana',
      'Нур-Султан',
      'Nur-Sultan'
    ]) {
      expect(hasCityWideService(city), isTrue, reason: city);
    }
    expect(hasCityWideService('Алматы'), isFalse);
    expect(hasCityWideService('Астана, другой город'), isFalse);
    expect(hasCityWideService(null), isFalse);
  });
  test(
      'unchanged snapshots and transient errors keep the existing view; real changes arrive',
      () async {
    final refresh = ValueNotifier(0);
    final values = <Map<String, dynamic>>[], errors = <Object>[];
    var count = 0, fail = false, value = 1;
    final sub = stablePollingStream(() async {
      count++;
      if (fail) throw StateError('offline');
      return {
        'orders': [
          {'status': value}
        ]
      };
    }, interval: const Duration(days: 1), refresh: refresh)
        .listen(values.add, onError: errors.add);
    await flush();
    expect(values, hasLength(1));
    refresh.value++;
    await flush();
    expect(values, hasLength(1));
    fail = true;
    refresh.value++;
    await flush();
    expect(values, hasLength(1));
    expect(errors, isEmpty);
    fail = false;
    value = 2;
    refresh.value++;
    await flush();
    expect(values, hasLength(2));
    expect(values.last['orders'][0]['status'], 2);
    await sub.cancel();
    final before = count;
    refresh.value++;
    await flush();
    expect(count, before);
    refresh.dispose();
  });
  test('initial failure is visible, later successful retry recovers', () async {
    final refresh = ValueNotifier(0);
    var fail = true;
    final values = <int>[], errors = <Object>[];
    final sub = stablePollingStream(() async {
      if (fail) throw StateError('offline');
      return 7;
    }, interval: const Duration(days: 1), refresh: refresh)
        .listen(values.add, onError: errors.add);
    await flush();
    expect(errors, hasLength(1));
    expect(values, isEmpty);
    fail = false;
    refresh.value++;
    await flush();
    expect(values, [7]);
    await sub.cancel();
    refresh.dispose();
  });
  test(
      'overlapping refreshes are coalesced and late results stop after cancellation',
      () async {
    final refresh = ValueNotifier(0), first = Completer<int>();
    var calls = 0;
    final values = <int>[];
    final sub = stablePollingStream(() {
      calls++;
      return calls == 1 ? first.future : Future.value(2);
    }, interval: const Duration(days: 1), refresh: refresh)
        .listen(values.add);
    await flush();
    for (var i = 0; i < 10; i++) {
      refresh.value++;
    }
    expect(calls, 1);
    first.complete(1);
    await flush();
    expect(calls, 2);
    expect(values, [1, 2]);
    await sub.cancel();
    refresh.dispose();
  });
}
