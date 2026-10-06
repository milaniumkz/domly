import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('domly/offer_alert_sound');

void primeOfferAlertSound() {
  _channel.invokeMethod<void>('prime');
}

void startOfferAlertSound({
  bool enabled = true,
  double volume = 1,
  int soundIndex = 0,
}) {
  if (!enabled) {
    stopOfferAlertSound();
    return;
  }
  _channel.invokeMethod<void>('start', {
    'volume': volume.clamp(0.0, 1.0),
    'soundIndex': soundIndex.clamp(0, 20),
  });
}

void stopOfferAlertSound() {
  _channel.invokeMethod<void>('stop');
}
