import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../utils/admin_calendar_data.dart';
import '../utils/working_schedule.dart';
import '../utils/user_error_message.dart';

class AdminWeeklyWorkload extends StatefulWidget {
  const AdminWeeklyWorkload({
    super.key,
    this.search = '',
    this.revision = 0,
    this.load,
    this.initialDay,
    this.onOpenOrder,
  });
  final String search;
  final int revision;
  final Future<Map<String, dynamic>> Function(String, String)? load;
  final DateTime? initialDay;
  final Future<void> Function(Map<String, dynamic>)? onOpenOrder;
  @override
  State<AdminWeeklyWorkload> createState() => _AdminWeeklyWorkloadState();
}

class _AdminWeeklyWorkloadState extends State<AdminWeeklyWorkload> {
  late DateTime _monday;
  AdminCalendarSnapshot? _data;
  String? _error;
  bool _loading = true;
  int _request = 0;
  Timer? _timer;
  DateTime _weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  @override
  void initState() {
    super.initState();
    _monday = _weekStart(
      widget.initialDay ?? DateTime.now().toUtc().add(const Duration(hours: 5)),
    );
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading) _reload();
    });
  }

  @override
  void didUpdateWidget(covariant AdminWeeklyWorkload oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = adminCalendarDay(_monday),
          to = adminCalendarDay(_monday.add(const Duration(days: 6)));
      final raw = await (widget.load?.call(from, to) ??
          BackendApiService.instance.getMap(
            '/admin/calendar',
            query: {'from': from, 'to': to},
          ));
      if (mounted && request == _request)
        setState(() => _data = AdminCalendarSnapshot(raw));
    } catch (e) {
      if (mounted && request == _request)
        setState(() => _error = UserErrorMessage.message(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _move(int weeks) {
    setState(() {
      _monday = _monday.add(Duration(days: weeks * 7));
      _data = null;
    });
    _reload();
  }

  Widget _day(Map<String, dynamic> cleaner, int offset) {
    final date = _monday.add(Duration(days: offset)),
        id = '${cleaner['id']}',
        snapshot = _data!;
    final day = adminCalendarDay(date),
        shift = snapshot.workingDay(id, adminCalendarDay(date));
    final visits = snapshot.forCleaner(id, day),
        approved = snapshot.approvedWeek(id, day);
    final free = shift == null
        ? <({int start, int end})>[]
        : calendarFreeIntervals(shift, visits, day);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            shift == null ? const Color(0xFFF3F4F6) : const Color(0xFFEDF8F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workScheduleDateLabel(day),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            shift != null
                ? 'Смена: ${shift['start_time']}–${shift['end_time']}'
                : approved
                    ? 'Выходной'
                    : 'График не утверждён',
          ),
          if (visits.isEmpty)
            const Text(
              'Заказов нет',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          for (final v in visits)
            InkWell(
              onTap: widget.onOpenOrder == null
                  ? null
                  : () => widget.onOpenOrder!(v.order),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${calendarClockLabel(v.startOn(day))}–${calendarClockLabel(v.endOn(day))} · ${v.area.toStringAsFixed(1)} м² · ${v.status == 'completed' ? 'завершено' : v.status == 'in_progress' ? 'в работе' : 'занято'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF155E75),
                  ),
                ),
              ),
            ),
          if (snapshot.dailyArea(id, day) >= snapshot.maximum)
            const Text('Лимит площади исчерпан — новые заказы недоступны',
                style: TextStyle(
                    color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
          for (var i = 1; i < visits.length; i++)
            if (day.compareTo('2026-12-01') >= 0 &&
                visits[i].startOn(day) - visits[i - 1].endOn(day) < 90)
              const Text('Между соседними заказами меньше 90 минут',
                  style: TextStyle(
                      color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
          if (shift != null)
            Text(
              'Свободное время по графику: ${free.isEmpty ? 'нет' : free.map((f) => '${calendarClockLabel(f.start)}–${calendarClockLabel(f.end)}').join(', ')}',
              style: const TextStyle(fontSize: 12),
            ),
          Text(
            'Площадь за день: ${snapshot.dailyArea(id, day).toStringAsFixed(1)} / ${snapshot.maximum.toStringAsFixed(0)} м²',
            style: const TextStyle(fontSize: 12),
          ),
          if (day.compareTo('2026-12-01') >= 0)
            const Text(
              'Между заказами — минимум 90 минут',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.search.trim().toLowerCase();
    final cleaners = _data?.cleaners
            .where(
              (c) =>
                  query.isEmpty ||
                  '${c['full_name']} ${c['phone']}'.toLowerCase().contains(
                        query,
                      ),
            )
            .toList() ??
        <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'График и занятость на неделю',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Предыдущая неделя',
              onPressed: () => _move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${adminCalendarDay(_monday)} — ${adminCalendarDay(_monday.add(const Duration(days: 6)))}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'Следующая неделя',
              onPressed: () => _move(1),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () {
                setState(
                  () => _monday = _weekStart(
                    DateTime.now().toUtc().add(const Duration(hours: 5)),
                  ),
                );
                _reload();
              },
              child: const Text('Текущая неделя'),
            ),
            IconButton(
              tooltip: 'Обновить график',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          TextButton(onPressed: _reload, child: Text(_error!)),
        if (!_loading && cleaners.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Уборщицы не найдены'),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final width =
                box.maxWidth >= 800 ? (box.maxWidth - 12) / 2 : box.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final cleaner in cleaners)
                  SizedBox(
                    width: width,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${cleaner['full_name'] ?? 'Уборщица'}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('${cleaner['phone'] ?? ''}'),
                            for (var i = 0; i < 7; i++) _day(cleaner, i),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
