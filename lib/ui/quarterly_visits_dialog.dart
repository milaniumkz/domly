import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

Future<int?> showQuarterlyVisitsDialog(BuildContext context,
        {required int selectedVisits}) =>
    showDialog<int>(
        context: context,
        builder: (_) => QuarterlyVisitsDialog(selectedVisits: selectedVisits));

class QuarterlyVisitsDialog extends StatelessWidget {
  const QuarterlyVisitsDialog({super.key, required this.selectedVisits});
  final int selectedVisits;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Квартальный пакет'.tr(),
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Выберите количество уборок в месяц:'.tr(),
            style:
                TextStyle(fontSize: 13, height: 1.45, color: colors.onSurface)),
        const SizedBox(height: 12),
        for (final value in [2, 4, 8])
          ListTile(
            key: ValueKey('quarterly_visits_$value'),
            contentPadding: EdgeInsets.zero,
            title: Text(
                (value == 8
                        ? '{count} уборок в месяц'
                        : '{count} уборки в месяц')
                    .tr(params: {'count': '$value'}),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
            trailing: value == selectedVisits
                ? Icon(Icons.check, color: colors.primary)
                : null,
            onTap: () => Navigator.pop(context, value),
          ),
      ]),
    );
  }
}
