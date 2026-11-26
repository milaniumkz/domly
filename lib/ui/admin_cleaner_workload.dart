import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../utils/admin_calendar_data.dart';
import '../utils/user_error_message.dart';

typedef CleanerWorkloadBuilder = Widget Function(
  BuildContext context,
  Map<String, Map<String, dynamic>> totals,
  Widget periodPicker,
);

class AdminCleanerWorkload extends StatefulWidget {
  const AdminCleanerWorkload({super.key, required this.builder, this.load});
  final Future<Map<String, dynamic>> Function(String from, String to)? load;
  final CleanerWorkloadBuilder builder;
  @override
  State<AdminCleanerWorkload> createState() => _AdminCleanerWorkloadState();
}

class _AdminCleanerWorkloadState extends State<AdminCleanerWorkload> {
  late DateTimeRange _period;
  Map<String, Map<String, dynamic>> _totals = {};
  bool _loading = true;
  String? _error;
  int _request = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final today = DateTime(now.year, now.month, now.day);
    _period = DateTimeRange(start: DateTime(now.year, now.month), end: today);
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading) _reload();
    });
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
      _totals = {};
    });
    try {
      final data = await (widget.load?.call(
              adminCalendarDay(_period.start), adminCalendarDay(_period.end)) ??
          BackendApiService.instance.getMap(
            '/admin/cleaner-workload',
            query: {
              'from': adminCalendarDay(_period.start),
              'to': adminCalendarDay(_period.end),
            },
          ));
      if (mounted && request == _request)
        setState(
          () => _totals = {
            for (final r in AdminCalendarSnapshot.maps(data['cleaners']))
              '${r['id']}': r,
          },
        );
    } catch (e) {
      if (mounted && request == _request)
        setState(() => _error = UserErrorMessage.message(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _period,
      helpText: 'Период выполненных уборок',
      saveText: 'Показать',
    );
    if (value != null && mounted) {
      setState(() => _period = value);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        _totals,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.date_range),
              label: Text(
                'Выполнено за период: ${adminCalendarDay(_period.start)} — ${adminCalendarDay(_period.end)}',
              ),
            ),
            const Text(
              'Площадь — по завершённым уборкам. Часы — по фактическим отметкам начала и окончания.',
              style: TextStyle(fontSize: 12),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: Text(_error!),
              ),
          ],
        ),
      );
}

String actualWorkLabel(Map<String, dynamic>? row) {
  if (row == null) return '—';
  final minutes = calendarNumber(row['actual_minutes']).round();
  return '${minutes ~/ 60} ч ${minutes % 60} мин';
}
