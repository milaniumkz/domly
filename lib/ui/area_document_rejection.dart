import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

Future<String?> showAreaDocumentRejection(BuildContext context,
        {bool alreadyApproved = false}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _RejectionDialog(alreadyApproved: alreadyApproved));

class _RejectionDialog extends StatefulWidget {
  const _RejectionDialog({required this.alreadyApproved});
  final bool alreadyApproved;
  @override
  State<_RejectionDialog> createState() => _RejectionDialogState();
}

class _RejectionDialogState extends State<_RejectionDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text('Отклонить документ'.tr()),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.alreadyApproved)
              Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                      'Подтверждение площади будет снято. Оплаты и бонусы требуют отдельного рассмотрения.'
                          .tr())),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                  labelText: 'Причина отклонения'.tr(),
                  hintText:
                      'Например: план нечитаемый, загрузите чёткое фото'.tr()),
            )
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена'.tr())),
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => FilledButton(
                    onPressed: value.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, value.text.trim()),
                    child: Text('Отклонить и уведомить'.tr()),
                  )),
        ],
      );
}
