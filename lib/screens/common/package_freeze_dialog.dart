import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../localization/translation_controller.dart';
import '../../utils/user_error_message.dart';

class PackageFreezeDialog extends StatefulWidget {
  const PackageFreezeDialog({super.key, required this.onSubmit});
  final Future<void> Function(int days) onSubmit;
  @override
  State<PackageFreezeDialog> createState() => _PackageFreezeDialogState();
}

class _PackageFreezeDialogState extends State<PackageFreezeDialog> {
  final _days = TextEditingController(text: '7');
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _days.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_busy) return;
    final days = int.tryParse(_days.text);
    if (days == null || days < 1) {
      setState(() => _error = 'Укажите срок заморозки.'.tr());
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.onSubmit(days);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = UserErrorMessage.message(error); });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Заморозить пакет'.tr()),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Срок действия пакета будет продлён на выбранное число дней.'.tr()),
        const SizedBox(height: 16),
        TextField(controller: _days, enabled: !_busy, autofocus: true,
          keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: 'Количество дней'.tr(), errorText: _error, errorMaxLines: 4)),
      ])),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text('Отмена'.tr())),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy
          ? const SizedBox(width: 20,height: 20,child: CircularProgressIndicator(strokeWidth: 2))
          : Text('Заморозить'.tr())),
      ],
    ),
  );
}
