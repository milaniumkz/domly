import 'package:flutter/material.dart';

import '../../ui/domly_ui.dart';
import 'legal_document_screen.dart';
import '../../localization/translation_controller.dart';

Future<bool> showPurchaseTermsDialog(
  BuildContext context, {
  String? packageName,
}) async {
  var acceptedConditions = false;
  var acceptedOffer = false;

  final validityText = _packageValidityText(packageName);

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canProceed = acceptedConditions && acceptedOffer;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Подтверждение заказа'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DomlyColors.foreground,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    packageName == null || packageName.isEmpty
                        ? 'Перед отправкой заявки нужно согласиться с условиями и офертой.'
                        : 'Перед отправкой заявки по пакету "$packageName" нужно согласиться с условиями и офертой.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Checkbox 1: Conditions
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DomlyColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DomlyColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Условия уборки'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Что входит в стандартную уборку:'.tr()),
                        const SizedBox(height: 6),
                        Text('• сухая и влажная уборка полов'.tr()),
                        Text('• протирка пыли с доступных поверхностей'.tr()),
                        Text('• уборка кухни снаружи доступных поверхностей'
                            .tr()),
                        Text('• уборка санузла и ванной комнаты'.tr()),
                        Text('• вынос бытового мусора'.tr()),
                        const SizedBox(height: 10),
                        Text(
                          'Важно:'.tr(),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• доп. услуги оплачиваются отдельно, если не включены в пакет;'
                              .tr(),
                        ),
                        Text('• срок действия пакета — $validityText;'.tr()),
                        Text(
                          '• бесплатная отмена — за 12 часов до визита;'.tr(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ограничение ответственности:'.tr(),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Сервис не несет ответственность за кражу ценностей, оставленных без надлежащего хранения.'
                              .tr(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: acceptedConditions,
                              onChanged: (value) {
                                setState(
                                    () => acceptedConditions = value ?? false);
                              },
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'Я соглашаюсь с условиями уборки'.tr(),
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Checkbox 2: Offer agreement
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DomlyColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DomlyColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Договор оферты'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Для продолжения необходимо подписать договор оферты. Вы можете скачать и ознакомиться с документом.'
                              .tr(),
                        ),
                        const SizedBox(height: 10),
                        DomlySecondaryButton(
                          label: 'Открыть договор',
                          icon: Icons.description_outlined,
                          onPressed: () => Navigator.of(context)
                              .pushNamed(LegalDocumentScreen.offerRoute),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: acceptedOffer,
                              onChanged: (value) {
                                setState(() => acceptedOffer = value ?? false);
                              },
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'Я подписываю договор оферты'.tr(),
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: DomlySecondaryButton(
                        label: 'Отмена',
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DomlyPrimaryButton(
                        label: 'Продолжить',
                        onPressed: canProceed
                            ? () => Navigator.pop(context, true)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );

  return result == true;
}

String _packageValidityText(String? packageName) {
  final normalized = (packageName ?? '').trim().toLowerCase();
  if (normalized.contains('квартал')) {
    return '3 месяца';
  }
  if (normalized.contains('ген') || normalized.contains('ремонт')) {
    return 'до выполнения одной уборки';
  }
  if (normalized.contains('2 раза') ||
      normalized.contains('4 раза') ||
      normalized.contains('8 раз')) {
    return '1 месяц';
  }
  return 'по условиям выбранного пакета';
}
