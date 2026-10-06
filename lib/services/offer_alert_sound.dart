import 'offer_alert_sound_stub.dart'
    if (dart.library.io) 'offer_alert_sound_mobile.dart'
    if (dart.library.html) 'offer_alert_sound_web.dart' as impl;

class OfferAlertSound {
  OfferAlertSound._();

  static const soundOptions = <String>[
    'Системный звук',
    'Спокойные колокольчики',
    'Тройной быстрый сигнал',
    'Мягкий дверной звонок',
    'Плавная сирена',
    'Резкий писк',
    'Диспетчерский сигнал',
    'Сирена туда-обратно',
    'Радар',
    'Длинная тревога',
    'Низкий гонг',
    'Сканер',
    'Большой колокол',
    'Очень частый писк',
    'Подъём тревоги',
    'Мягкий аккорд',
    'Резкий двойной удар',
    'Аварийная серия',
    'Спокойный звон',
    'Короткие импульсы',
    'Максимальная тревога',
  ];

  static void prime() => impl.primeOfferAlertSound();

  static void start({
    bool enabled = true,
    double volume = 1,
    int soundIndex = 0,
  }) =>
      impl.startOfferAlertSound(
        enabled: enabled,
        volume: volume,
        soundIndex: soundIndex,
      );

  static void stop() => impl.stopOfferAlertSound();
}
