import 'dart:async';
import 'package:flutter/foundation.dart';

bool _sameSnapshot(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map)
    return a.length == b.length &&
        a.keys.every(
            (key) => b.containsKey(key) && _sameSnapshot(a[key], b[key]));
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameSnapshot(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Keeps the last successful view during transient polling failures and emits
/// only changed snapshots. Refreshes are serialized; disposal stops delivery.
Stream<T> stablePollingStream<T>(
  Future<T> Function() loader, {
  Duration interval = const Duration(seconds: 20),
  Listenable? refresh,
}) =>
    Stream<T>.multi((controller) {
      var closed = false, loading = false, queued = false, hasValue = false;
      T? previous;
      Future<void> load() async {
        if (closed) return;
        if (loading) {
          queued = true;
          return;
        }
        loading = true;
        try {
          final value = await loader();
          if (!closed && (!hasValue || !_sameSnapshot(previous, value))) {
            previous = value;
            hasValue = true;
            controller.add(value);
          }
        } catch (error, stack) {
          if (!closed && !hasValue) controller.addError(error, stack);
        } finally {
          loading = false;
          if (queued && !closed) {
            queued = false;
            unawaited(load());
          }
        }
      }

      void refreshNow() => unawaited(load());
      refresh?.addListener(refreshNow);
      final timer = Timer.periodic(interval, (_) => refreshNow());
      refreshNow();
      controller.onCancel = () {
        closed = true;
        timer.cancel();
        refresh?.removeListener(refreshNow);
      };
    });
