import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../services/firestore_data_service.dart';
import '../utils/user_error_message.dart';
import '../utils/working_schedule.dart';

class CleanerWorkScheduleButton extends StatelessWidget {
  const CleanerWorkScheduleButton({super.key});
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        leading: const Icon(Icons.edit_calendar),
        title: Text('Настроить режим работы'.tr()),
        subtitle: Text('Текущая и следующая недели'.tr()),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => const CleanerWorkScheduleSheet()),
      ));
}

class CleanerWorkScheduleSheet extends StatefulWidget {
  const CleanerWorkScheduleSheet({super.key});
  @override
  State<CleanerWorkScheduleSheet> createState() =>
      _CleanerWorkScheduleSheetState();
}

class _CleanerWorkScheduleSheetState extends State<CleanerWorkScheduleSheet> {
  final _data = FirestoreDataService.instance;
  Map<String, dynamic>? _snapshot;
  Object? _error;
  String? _week, _requestKey;
  final _drafts = <String, List<Map<String, dynamic>>>{};
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _data.cleanerWorkingSchedule();
      if (!mounted) return;
      setState(() {
        _snapshot = value;
        _error = null;
        if(![value['currentWeekStart'],value['nextWeekStart']].contains(_week))_week=value['nextWeekStart']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Map? _request(String week) => (_snapshot?['requests'] as List? ?? const [])
      .whereType<Map>()
      .where((r) => workScheduleDay(r['week_start']) == week)
      .firstOrNull;
  List<Map<String, dynamic>> _days(String week) => _drafts.putIfAbsent(
      week,
      () =>
          workScheduleDays(week, _request(week)?['days'] as List? ?? const []));
  Future<void> _time(Map<String, dynamic> day, String field) async {
    final parts = '${day[field]}'.split(':');
    final value = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: int.tryParse(parts.first) ?? 8,
            minute: int.tryParse(parts.last) ?? 0),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (value != null && mounted)
      setState(() {
        day[field] =
            '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
        _requestKey = null;
      });
  }

  Future<void> _save() async {
    if (_week == null || _saving) return;
    setState(() => _saving = true);
    try {
      _requestKey ??= 'work-$_week-${DateTime.now().microsecondsSinceEpoch}';
      await _data.submitWorkingSchedule({
        'weekStart': _week,
        'days': _days(_week!),
        'clientRequestId': _requestKey
      });
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('График отправлен на одобрение'.tr())));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(UserErrorMessage.message(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    return SafeArea(
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .85,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: _error != null
                    ? Column(children: [
                        Text(UserErrorMessage.message(_error)),
                        TextButton(
                            onPressed: _load,
                            child: Text('Попробовать снова'.tr()))
                      ])
                    : _snapshot == null || _week == null
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                Text('Режим работы'.tr(),
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                    initialValue: _week,
                                    items: [
                                      DropdownMenuItem(
                                          value:
                                              '${_snapshot!['currentWeekStart']}',
                                          child: Text('Текущая неделя'.tr())),
                                      DropdownMenuItem(
                                          value:
                                              '${_snapshot!['nextWeekStart']}',
                                          child: Text('Следующая неделя'.tr())),
                                    ],
                                    onChanged: _saving
                                        ? null
                                        : (value) => setState(() {
                                              _week = value;
                                              _requestKey = null;
                                            })),
                                const SizedBox(height: 8),
                                Text(
                                    workScheduleStatus(
                                            _request(_week!)?['status'])
                                        .tr(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                if ('${_request(_week!)?['review_comment'] ?? ''}'
                                    .isNotEmpty)
                                  Text(
                                      '${_request(_week!)?['review_comment']}'),
                                Text(
                                    'Каждая неделя отправляется на одобрение отдельно. До одобрения новые заказы по этому графику не поступают.'
                                        .tr()),
                                const SizedBox(height: 8),
                                Text(
                                    'Проверяется только начало уборки. Последнее начало для клиента — 18:00.'
                                        .tr()),
                                Expanded(
                                    child: ListView(
                                        children: _days(_week!).map((day) {
                                  final past = '${day['date']}'
                                          .compareTo('${_snapshot!['today']}') <
                                      0;
                                  return Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SwitchListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    title: Text(
                                                        workScheduleDateLabel(
                                                                day['date'])
                                                            .tr()),
                                                    subtitle: Text(
                                                        (day['working'] == true
                                                                ? 'Рабочий день'
                                                                : 'Выходной')
                                                            .tr()),
                                                    value:
                                                        day['working'] == true,
                                                    onChanged: past || _saving
                                                        ? null
                                                        : (value) =>
                                                            setState(() {
                                                              day['working'] =
                                                                  value;
                                                              _requestKey =
                                                                  null;
                                                            })),
                                                if (day['working'] == true)
                                                  Row(children: [
                                                    Text('С'.tr()),
                                                    TextButton(
                                                        onPressed: past ||
                                                                _saving
                                                            ? null
                                                            : () => _time(day,
                                                                'startTime'),
                                                        child: Text(
                                                            '${day['startTime']}')),
                                                    Text('До'.tr()),
                                                    TextButton(
                                                        onPressed: past ||
                                                                _saving
                                                            ? null
                                                            : () => _time(
                                                                day, 'endTime'),
                                                        child: Text(
                                                            '${day['endTime']}')),
                                                  ]),
                                              ])));
                                }).toList())),
                                FilledButton(
                                    onPressed: _saving ? null : _save,
                                    child: Text((_saving
                                            ? 'Отправляем...'
                                            : 'Отправить эту неделю на одобрение')
                                        .tr())),
                              ]))));
  }
}
