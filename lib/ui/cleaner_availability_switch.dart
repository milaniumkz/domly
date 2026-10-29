import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../utils/user_error_message.dart';

class CleanerAvailabilitySwitch extends StatefulWidget {
  const CleanerAvailabilitySwitch(
      {super.key, required this.online, required this.onChanged});
  final bool online;
  final Future<void> Function(bool) onChanged;
  @override
  State<CleanerAvailabilitySwitch> createState() =>
      _CleanerAvailabilitySwitchState();
}

class _CleanerAvailabilitySwitchState extends State<CleanerAvailabilitySwitch> {
  late bool _online = widget.online;
  bool _saving = false;

  @override
  void didUpdateWidget(CleanerAvailabilitySwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.online != widget.online) _online = widget.online;
  }

  Future<void> _change(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.onChanged(value);
      if (mounted) setState(() => _online = value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserErrorMessage.message(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: SwitchListTile.adaptive(
          title: Text((_online ? 'Онлайн' : 'Офлайн').tr()),
          subtitle: Text((_online
                  ? 'Новые заказы приходят, даже когда приложение свёрнуто.'
                  : 'Новые заказы не поступают. Принятые заказы остаются доступны.')
              .tr()),
          value: _online,
          onChanged: _saving ? null : _change,
          secondary: _saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_online ? Icons.wifi : Icons.wifi_off),
        ),
      );
}
