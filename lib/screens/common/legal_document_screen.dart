import 'package:flutter/material.dart';

import '../../localization/translation_controller.dart';
import '../../services/app_config_service.dart';
import '../../theme/app_theme.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.contentKey,
    required this.fallback,
  });

  static const String offerRoute = '/legal/offer';
  static const String privacyRoute = '/legal/privacy';

  final String contentKey;
  final LegalDocumentFallback fallback;

  static LegalDocumentScreen offer() => const LegalDocumentScreen(
        contentKey: LegalDocumentFallback.offerKey,
        fallback: LegalDocumentFallback.offer,
      );

  static LegalDocumentScreen privacy() => const LegalDocumentScreen(
        contentKey: LegalDocumentFallback.privacyKey,
        fallback: LegalDocumentFallback.privacy,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: StreamBuilder<Map<String, dynamic>?>(
                  stream: AppConfigService.instance
                      .infoContentStreamByKey(contentKey),
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    final title = _read(data, 'title', fallback.title);
                    final shortInfo =
                        _read(data, 'shortInfo', fallback.shortInfo);
                    final fullInfo = _read(data, 'fullInfo', fallback.fullInfo);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: AppTheme.darkText,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            if (shortInfo.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                shortInfo,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppTheme.mutedText,
                                      height: 1.45,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            Text(
                              fullInfo,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.darkText,
                                    height: 1.55,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 0, 0),
              child: Material(
                color: Colors.white.withValues(alpha: 0.94),
                shape: const CircleBorder(),
                elevation: 8,
                shadowColor: Colors.black26,
                child: IconButton(
                  tooltip: 'Назад',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      navigator.pushReplacementNamed('/login');
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _read(Map<String, dynamic>? data, String key, String fallbackValue) {
    String clean(String value) => value
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'^\s*\*\s+', multiLine: true), '• ')
        .replaceAll(RegExp(r'^\s*---+\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (data == null) {
      return clean(fallbackValue.tr());
    }
    return clean(TranslationController.localizedValue(
      data,
      [key],
      fallback: fallbackValue,
    ));
  }
}

class LegalDocumentFallback {
  const LegalDocumentFallback({
    required this.title,
    required this.shortInfo,
    required this.fullInfo,
  });

  static const offerKey = 'legal_offer';
  static const privacyKey = 'legal_privacy';

  final String title;
  final String shortInfo;
  final String fullInfo;

  static const offer = LegalDocumentFallback(
    title: 'Договор оферты DOMLY',
    shortInfo:
        'Публичные условия оказания услуг уборки, оплаты, отмены и возврата.',
    fullInfo: '''
1. Модель работы
DOMLY принимает заявки клиента на уборку квартиры или дома, рассчитывает стоимость по выбранному пакету, площади и дополнительным услугам, принимает оплату и передает заказ исполнителю. Исполнитель выполняет уборку по чек-листу, клиент может общаться с исполнителем и поддержкой через приложение.

2. Оплата
Клиент оплачивает пакет уборки или дополнительные услуги банковской картой через интернет-эквайринг либо через Kaspi.kz. Заказ считается подтвержденным после успешной оплаты или подтверждения счета.

3. Проверка площади
Если площадь не подтверждена, DOMLY может запросить проверку квадратуры отделом контроля качества. После подтверждения площади стоимость заказа может быть пересчитана.

4. Отмена и возврат
Отмена и возврат рассматриваются администрацией DOMLY по обращению клиента. Возврат выполняется тем же способом, которым была произведена оплата, если это поддерживается платежной системой.

5. Реквизиты организации
Наименование: ТОО «DomLY»
БИН: 260440000313
Юридический адрес: Адрес уточняется
Банк: АО «Банк ЦентрКредит»
ИИК: KZ11 8562 2031 5395 7207
БИК: KCJBKZKX
КБе: 17
Телефон: +7 778 111 0170
Email: milaniumkz@yandex.kz
''',
  );

  static const privacy = LegalDocumentFallback(
    title: 'Политика конфиденциальности DOMLY',
    shortInfo:
        'Как DOMLY собирает, использует и защищает данные пользователей и исполнителей.',
    fullInfo: '''
1. Какие данные собираются
DOMLY может собирать имя, номер телефона, адрес, город, координаты дома, данные заказов, оплат, сообщений, фотографий отчетов, жалоб, отзывов и техническую информацию приложения.

2. Для чего используются данные
Данные нужны для регистрации, подтверждения адреса и площади, расчета стоимости, приема оплаты, назначения исполнителя, выполнения уборки, поддержки клиента, уведомлений и контроля качества.

3. Передача данных
DOMLY передает исполнителю только данные, необходимые для выполнения заказа: адрес, время, параметры уборки, чек-лист и контактные данные для связи по заказу. Данные оплаты обрабатываются платежными провайдерами.

4. Хранение и защита
DOMLY хранит данные в облачной инфраструктуре Firebase и применяет технические меры защиты доступа. Доступ к данным предоставляется только пользователю, исполнителю, администратору и сервисным ролям в рамках их задач.

5. Права пользователя
Пользователь может запросить уточнение, исправление или удаление своих данных через поддержку DOMLY, если хранение этих данных больше не требуется для исполнения обязательств и требований закона.

6. Реквизиты организации
Наименование: ТОО «DomLY»
БИН: 260440000313
Юридический адрес: Адрес уточняется
Телефон: +7 778 111 0170
Email: milaniumkz@yandex.kz
''',
  );
}
