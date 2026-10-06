import 'package:flutter/material.dart';

import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class TrainingOrderScreen extends StatefulWidget {
  const TrainingOrderScreen({super.key});

  @override
  State<TrainingOrderScreen> createState() => _TrainingOrderScreenState();
}

class _TrainingOrderScreenState extends State<TrainingOrderScreen> {
  int _step = 0;
  String? _package;
  String? _date;
  String? _time;
  final _addons = <String>{};

  static const _packages = ['Разовый пакет', '4 раза в месяц', '8 раз в месяц'];
  static const _dates = ['2 сентября', '3 сентября', '4 сентября'];
  static const _times = ['10:00 - 13:10', '14:00 - 17:10', '18:00 - 21:10'];
  static const _addonItems = ['Мытье окон', 'Чистка духовки', 'Санузел'];

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _package != null;
      case 1:
        return _date != null;
      case 2:
        return _time != null;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      '1. Выберите пакет',
      '2. Выберите дату',
      '3. Выберите время',
      '4. Добавьте допуслуги',
      '5. Проверьте оплату',
      'Тестовый заказ готов',
    ];

    return DomlyShell(
      bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 0),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  domlyTopIconButton(
                    icon: Icons.arrow_back,
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      if (navigator.canPop()) {
                        navigator.pop(false);
                      } else {
                        navigator.pushNamedAndRemoveUntil(
                          '/client/home',
                          (_) => false,
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Обучение заказу'.tr(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: DomlyColors.foreground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: (_step + 1) / titles.length,
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                color: DomlyColors.buttonPrimary,
                backgroundColor: DomlyColors.border,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: DomlyColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          titles[_step],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hintForStep(),
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: DomlyColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _stepBody(),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DomlyPrimaryButton(
                label:
                    _step == titles.length - 1 ? 'Завершить обучение' : 'Далее',
                icon: _step == titles.length - 1
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded,
                onPressed: !_canContinue
                    ? null
                    : () {
                        if (_step == titles.length - 1) {
                          final navigator = Navigator.of(context);
                          if (navigator.canPop()) {
                            navigator.pop(true);
                          } else {
                            navigator.pushNamedAndRemoveUntil(
                              '/client/home',
                              (_) => false,
                            );
                          }
                        } else {
                          setState(() => _step += 1);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hintForStep() {
    switch (_step) {
      case 0:
        return 'Нажмите на пакет. В реальном заказе сумма считается по площади из профиля.';
      case 1:
        return 'Выберите доступную дату. До запуска активны только разрешенные даты.';
      case 2:
        return 'Выберите свободное окно. Система учитывает длительность уборки и допы.';
      case 3:
        return 'Допуслуги можно не выбирать. Здесь показано, как добавить их к уборке.';
      case 4:
        return 'Здесь клиент выбирает способ оплаты. Это демо, счет не создается.';
      default:
        return 'Тестовая уборка не ушла уборщицам и не записалась в базу.';
    }
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _choiceList(_packages, _package, (value) {
          setState(() => _package = value);
        });
      case 1:
        return _choiceList(_dates, _date, (value) {
          setState(() => _date = value);
        }, icon: Icons.calendar_month_outlined);
      case 2:
        return _choiceList(_times, _time, (value) {
          setState(() => _time = value);
        }, icon: Icons.schedule_outlined);
      case 3:
        return Column(
          children: _addonItems.map((item) {
            final selected = _addons.contains(item);
            return _choiceTile(
              label: item,
              selected: selected,
              icon: Icons.add_circle_outline,
              onTap: () => setState(() {
                selected ? _addons.remove(item) : _addons.add(item);
              }),
            );
          }).toList(),
        );
      case 4:
        return Column(
          children: [
            _summaryRow('Пакет', _package ?? 'Не выбран'),
            _summaryRow('Дата', _date ?? 'Не выбрана'),
            _summaryRow('Время', _time ?? 'Не выбрано'),
            _summaryRow(
              'Допы',
              _addons.isEmpty ? 'Без допуслуг' : _addons.join(', '),
            ),
            const SizedBox(height: 12),
            _choiceTile(
              label: 'KASPI.KZ',
              selected: true,
              icon: Icons.receipt_long_outlined,
              onTap: () {},
            ),
            _choiceTile(
              label: 'Онлайн-платеж',
              selected: false,
              icon: Icons.credit_card_outlined,
              onTap: () {},
            ),
            _choiceTile(
              label: 'Оплатить бонусами',
              selected: false,
              icon: Icons.stars_outlined,
              onTap: () {},
            ),
          ],
        );
      default:
        return const Icon(
          Icons.check_circle_rounded,
          color: DomlyColors.primary,
          size: 92,
        );
    }
  }

  Widget _choiceList(
    List<String> values,
    String? selected,
    ValueChanged<String> onTap, {
    IconData icon = Icons.inventory_2_outlined,
  }) {
    return Column(
      children: values
          .map(
            (value) => _choiceTile(
              label: value,
              selected: value == selected,
              icon: icon,
              onTap: () => onTap(value),
            ),
          )
          .toList(),
    );
  }

  Widget _choiceTile({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                selected ? const Color(0xFFFFF1EA) : DomlyColors.backgroundSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? DomlyColors.buttonPrimary : DomlyColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color:
                      selected ? DomlyColors.buttonPrimary : DomlyColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color:
                        selected ? DomlyColors.foreground : DomlyColors.muted,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? DomlyColors.primary : DomlyColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(
                color: DomlyColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DomlyColors.foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
