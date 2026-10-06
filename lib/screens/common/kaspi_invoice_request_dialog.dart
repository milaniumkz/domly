import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/translation_controller.dart';
import '../../ui/domly_ui.dart';

enum DomlyPaymentMethod {
  kaspi,
  online,
  bonus,
}

class KaspiInvoiceRequestResult {
  const KaspiInvoiceRequestResult({
    required this.phone,
    required this.useBonus,
  });

  final String phone;
  final bool useBonus;
}

class DomlyPaymentSelection {
  const DomlyPaymentSelection({
    required this.method,
    required this.useBonus,
  });

  final DomlyPaymentMethod method;
  final bool useBonus;
}

Future<String?> showKaspiInvoiceRequestDialog(BuildContext context) async {
  final result = await showKaspiInvoiceRequestOptionsDialog(context);
  return result?.phone;
}

Future<DomlyPaymentMethod?> showPaymentMethodDialog(
  BuildContext context,
) async {
  final result = await showPaymentMethodOptionsDialog(context);
  return result?.method;
}

Future<DomlyPaymentSelection?> showPaymentMethodOptionsDialog(
  BuildContext context, {
  int bonusBalance = 0,
  int maxBonusToSpend = 0,
  int paymentAmount = 0,
}) {
  final availableBonus =
      bonusBalance.clamp(0, maxBonusToSpend).clamp(0, paymentAmount).toInt();
  final canPayFullyWithBonus =
      paymentAmount > 0 && availableBonus >= paymentAmount;
  var useBonus = false;
  return showDialog<DomlyPaymentSelection>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return StatefulBuilder(builder: (context, setState) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required DomlyPaymentMethod method,
        }) {
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(dialogContext).pop(
              DomlyPaymentSelection(method: method, useBonus: useBonus),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: DomlyColors.border),
                color: DomlyColors.card,
              ),
              child: Row(
                children: [
                  Icon(icon, color: DomlyColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title.tr(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle.tr(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: DomlyColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: DomlyColors.muted),
                ],
              ),
            ),
          );
        }

        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Выберите способ оплаты'.tr(),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: DomlyColors.foreground,
                ),
              ),
              if (availableBonus > 0) ...[
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => useBonus = !useBonus),
                  child: Row(
                    children: [
                      Checkbox(
                        value: useBonus,
                        onChanged: (value) {
                          setState(() => useBonus = value ?? false);
                        },
                        activeColor: DomlyColors.primary,
                      ),
                      Expanded(
                        child: Text(
                          'Оплатить бонусами: доступно $availableBonus ₸'.tr(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DomlyColors.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (canPayFullyWithBonus) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: DomlyPrimaryButton(
                    label: 'Оплатить бонусами',
                    icon: Icons.card_giftcard,
                    onPressed: useBonus
                        ? () => Navigator.of(dialogContext).pop(
                              const DomlyPaymentSelection(
                                method: DomlyPaymentMethod.bonus,
                                useBonus: true,
                              ),
                            )
                        : null,
                  ),
                ),
                if (!useBonus) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Чтобы оплатить бонусами, сначала поставьте галочку.'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              option(
                icon: Icons.credit_card,
                title: 'Онлайн-платёж',
                subtitle: 'Оплата картой внутри приложения',
                method: DomlyPaymentMethod.online,
              ),
              const SizedBox(height: 10),
              option(
                icon: Icons.phone_iphone,
                title: 'Kaspi.kz',
                subtitle: 'Выставить счёт по номеру телефона',
                method: DomlyPaymentMethod.kaspi,
              ),
            ],
          ),
        );
      });
    },
  );
}

Future<KaspiInvoiceRequestResult?> showKaspiInvoiceRequestOptionsDialog(
  BuildContext context, {
  int bonusBalance = 0,
  int maxBonusToSpend = 0,
  int paymentAmount = 0,
  bool initialUseBonus = false,
}) async {
  final controller = TextEditingController(text: '+7 ');
  String? errorText;
  final availableBonus =
      bonusBalance.clamp(0, maxBonusToSpend).clamp(0, paymentAmount).toInt();
  bool useBonus = initialUseBonus && availableBonus > 0;

  return showDialog<KaspiInvoiceRequestResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          String normalizePhone(String value) {
            final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
            if (digits.length == 11 && digits.startsWith('8')) {
              return '7${digits.substring(1)}';
            }
            if (digits.length == 11 && digits.startsWith('7')) {
              return digits;
            }
            if (digits.length == 10) {
              return '7$digits';
            }
            return '';
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Введите номер KASPI.KZ'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DomlyColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'На этот номер будет выставлен счёт на оплату.'.tr(),
                  ),
                  if (paymentAmount > 0) ...[
                    const SizedBox(height: 10),
                    Builder(builder: (_) {
                      final bonusAmount =
                          useBonus ? availableBonus.clamp(0, paymentAmount) : 0;
                      final payable =
                          (paymentAmount - bonusAmount).clamp(0, paymentAmount);
                      final bonusText =
                          bonusAmount > 0 ? ' · бонусами $bonusAmount ₸' : '';
                      return Text(
                        'Сумма счёта: $payable ₸$bonusText'.tr(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DomlyColors.foreground,
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+()\-\s]'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Номер телефона'.tr(),
                      hintText: '+7 777 000 00 00'.tr(),
                      errorText: errorText,
                    ),
                  ),
                  if (availableBonus > 0) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => useBonus = !useBonus),
                      child: Row(
                        children: [
                          Checkbox(
                            value: useBonus,
                            onChanged: (value) {
                              setState(() => useBonus = value ?? false);
                            },
                            activeColor: DomlyColors.primary,
                          ),
                          Expanded(
                            child: Text(
                              'Оплатить бонусами: доступно $availableBonus ₸'
                                  .tr(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: DomlyColors.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stackVertically = constraints.maxWidth < 320;
                      final secondaryButton = SizedBox(
                        width: stackVertically ? double.infinity : 132,
                        child: DomlySecondaryButton(
                          label: 'Отмена'.tr(),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      );
                      final primaryButton = SizedBox(
                        width: stackVertically ? double.infinity : 156,
                        child: DomlyPrimaryButton(
                          label: 'Выставить счёт',
                          onPressed: () {
                            final normalized = normalizePhone(controller.text);
                            if (normalized.isEmpty) {
                              setState(() {
                                errorText = 'Введите номер полностью'.tr();
                              });
                              return;
                            }
                            Navigator.of(dialogContext).pop(
                              KaspiInvoiceRequestResult(
                                phone: normalized,
                                useBonus: useBonus,
                              ),
                            );
                          },
                        ),
                      );

                      return Wrap(
                        alignment: WrapAlignment.end,
                        runAlignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [secondaryButton, primaryButton],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
