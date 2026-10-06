import 'dart:async';

import 'package:flutter/services.dart';

Timer? _timer;

void primeOfferAlertSound() {}

void startOfferAlertSound({
  bool enabled = true,
  double volume = 1,
  int soundIndex = 0,
}) {
  if (!enabled) {
    stopOfferAlertSound();
    return;
  }
  if (_timer != null) {
    return;
  }
  _playAlert();
  _timer = Timer.periodic(const Duration(seconds: 2), (_) => _playAlert());
}

void stopOfferAlertSound() {
  _timer?.cancel();
  _timer = null;
}

void _playAlert() {
  SystemSound.play(SystemSoundType.alert);
  HapticFeedback.vibrate();
}
