import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

class CustomerProgressInfo extends StatelessWidget {
  const CustomerProgressInfo({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    final rules = (profile['customer_tier_rules'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
      ..sort((a, b) => _number(a['minMonthlySpent'])
          .compareTo(_number(b['minMonthlySpent'])));
    final spent = _number(profile['monthly_spent']);
    final current = '${profile['tier'] ?? ''}';
    final next = rules
        .where((rule) => _number(rule['minMonthlySpent']) > spent)
        .firstOrNull;
    final locale = context
            .dependOnInheritedWidgetOfExactType<TranslationScope>()
            ?.notifier
            ?.localeCode ??
        'ru';
    String label(Map rule) =>
        '${locale == 'kk' ? rule['labelKk'] ?? rule['labelRu'] : rule['labelRu'] ?? rule['tier']}'
            .tr();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ваш прогресс'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Оплачено за текущий месяц: {amount} ₸'
              .tr(params: {'amount': _amount(spent)})),
          const SizedBox(height: 8),
          if (next != null)
            Text('До следующего статуса осталось: {amount} ₸'.tr(params: {
              'amount': _amount((_number(next['minMonthlySpent']) - spent)
                  .clamp(0, double.infinity))
            })),
          if (next == null && rules.isNotEmpty)
            Text('Вы достигли максимального статуса.'.tr()),
          const SizedBox(height: 16),
          Text('Все статусы'.tr(),
              style: Theme.of(context).textTheme.titleMedium),
          if (rules.isEmpty)
            Text('Условия статусов ещё не загружены. Обновите профиль.'.tr()),
          for (final rule in rules)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(label(rule),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                            if ('${rule['tier']}' == current)
                              const Icon(Icons.check_circle,
                                  color: Colors.green)
                          ]),
                          const SizedBox(height: 6),
                          Text('Расходы за месяц: от {amount} ₸'.tr(params: {
                            'amount': _amount(_number(rule['minMonthlySpent']))
                          })),
                          if (rule['maxMonthlySpent'] != null)
                            Text('Следующий уровень — с {amount} ₸'.tr(params: {
                              'amount':
                                  _amount(_number(rule['maxMonthlySpent']))
                            })),
                          Text('Скидка: {percent}%'.tr(params: {
                            'percent': _amount(_number(rule['discountPercent']))
                          })),
                          if ('${rule['tier']}' == current)
                            Text('Ваш текущий статус'.tr()),
                        ]))),
          const SizedBox(height: 12),
          Text(
              'Учитываются подтверждённые оплаты за текущий календарный месяц по времени Казахстана, включая оплату бонусами. Неоплаченные и возвращённые платежи не учитываются. В новом месяце сумма рассчитывается заново. Приглашённые клиенты не влияют на статус.'
                  .tr()),
        ]);
  }

  static num _number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  static String _amount(num value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
}
