import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../services/firestore_data_service.dart';
import '../utils/user_error_message.dart';
import '../utils/working_schedule.dart';

class AdminWorkSchedules extends StatefulWidget {
  const AdminWorkSchedules({super.key, this.search = ''});
  final String search;
  @override
  State<AdminWorkSchedules> createState() => _AdminWorkSchedulesState();
}

class _AdminWorkSchedulesState extends State<AdminWorkSchedules> {
  final _data = FirestoreDataService.instance;
  String _status = 'pending';
  late Stream<List<Map<String, dynamic>>> _stream;
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    _stream = _data.adminWorkingSchedulesStream(status: _status);
  }

  Future<void> _review(Map<String, dynamic> row, String decision) async {
    final id = '${row['id']}';
    if (_busy.contains(id)) return;
    var comment = '';
    if (decision == 'rejected') {
      final controller = TextEditingController();
      final value = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text('Отклонить график?'.tr()),
                  content: TextField(
                      controller: controller,
                      maxLength: 2000,
                      maxLines: 3,
                      decoration:
                          InputDecoration(labelText: 'Причина отказа'.tr())),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Отмена'.tr())),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Отклонить'.tr())),
                  ]));
      comment = controller.text.trim();
      controller.dispose();
      if (value != true || !mounted) return;
    }
    setState(() => _busy.add(id));
    try {
      await _data.reviewWorkingSchedule(id, decision, comment);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(UserErrorMessage.message(error))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
              initialValue: _status,
              items: [
                for (final entry in const {
                  'pending': 'На одобрении',
                  'approved': 'Одобрен',
                  'rejected': 'Отклонён',
                  'all': 'Все заявки'
                }.entries)
                  DropdownMenuItem(
                      value: entry.key, child: Text(entry.value.tr()))
              ],
              onChanged: (value) => setState(() {
                    _status = value ?? 'pending';
                    _stream = _data.adminWorkingSchedulesStream(
                        status: _status == 'all' ? null : _status);
                  }))),
      Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(
                      child: Text(UserErrorMessage.message(snapshot.error)));
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final query = widget.search.trim().toLowerCase();
                final rows = snapshot.data!
                    .where((r) =>
                        query.isEmpty ||
                        '${r['cleaner_name']} ${r['cleaner_phone']} ${r['week_start']}'
                            .toLowerCase()
                            .contains(query))
                    .toList();
                if (rows.isEmpty)
                  return Center(child: Text('Заявок на график пока нет'.tr()));
                return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index], id = '${row['id']}';
                      final days =
                          (row['days'] as List? ?? const []).whereType<Map>();
                      return Card(
                          child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${row['cleaner_name'] ?? 'Уборщица'} · ${row['cleaner_phone'] ?? ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text(
                                        workScheduleDateLabel(row['week_start'])
                                            .tr()),
                                    Text(workScheduleStatus(row['status']).tr(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    for (final day in days)
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: Text(
                                              '${workScheduleDateLabel(day['date']).tr()}: ${day['working'] == true ? '${day['startTime']} – ${day['endTime']}' : 'Выходной'.tr()}')),
                                    if ('${row['review_comment'] ?? ''}'
                                        .isNotEmpty)
                                      Text('${row['review_comment']}'),
                                    if (row['status'] == 'pending')
                                      Wrap(spacing: 12, children: [
                                        FilledButton(
                                            onPressed: _busy.contains(id)
                                                ? null
                                                : () =>
                                                    _review(row, 'approved'),
                                            child:
                                                Text('Одобрить график'.tr())),
                                        TextButton(
                                            onPressed: _busy.contains(id)
                                                ? null
                                                : () =>
                                                    _review(row, 'rejected'),
                                            child: Text('Отклонить'.tr())),
                                      ]),
                                  ])));
                    });
              })),
    ]);
  }
}
