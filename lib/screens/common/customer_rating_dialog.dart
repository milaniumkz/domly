import 'package:flutter/material.dart';
import '../../ui/domly_ui.dart';

Future<bool> showCustomerRatingDialog(BuildContext context,
    {required Future<void> Function(int rating, String note) submit}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CustomerRatingDialog(submit: submit),
      ) ??
      false;
}

class _CustomerRatingDialog extends StatefulWidget {
  const _CustomerRatingDialog({required this.submit});
  final Future<void> Function(int rating, String note) submit;
  @override
  State<_CustomerRatingDialog> createState() => _CustomerRatingDialogState();
}

class _CustomerRatingDialogState extends State<_CustomerRatingDialog> {
  final _note = TextEditingController();
  int _rating = 5;
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.submit(_rating, _note.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showDomlySnackBar(context,
          title: 'Не удалось сохранить оценку',
          subtitle: '$error',
          type: DomlySnackBarType.error);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Оцените клиента'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Эта оценка будет влиять на рейтинг клиента.'.tr()),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed:
                        _submitting ? null : () => setState(() => _rating = i),
                    icon: Icon(i <= _rating ? Icons.star : Icons.star_border,
                        color: const Color(0xFFD06D45), size: 32),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: _note,
                  enabled: !_submitting,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Комментарий',
                      hintText: 'Например: всё было готово к уборке')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed:
                  _submitting ? null : () => Navigator.pop(context, false),
              child: Text('Позже'.tr())),
          FilledButton(
              onPressed: _submitting ? null : _save,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Сохранить'.tr())),
        ],
      );
}
