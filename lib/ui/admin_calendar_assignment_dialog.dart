import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../utils/admin_calendar_data.dart';
import '../utils/user_error_message.dart';

class AdminCalendarAssignmentDialog extends StatefulWidget {
  const AdminCalendarAssignmentDialog(
      {super.key, required this.visit, required this.swap});
  final AdminCalendarVisit visit;
  final bool swap;
  @override
  State<AdminCalendarAssignmentDialog> createState() =>
      _AdminCalendarAssignmentDialogState();
}

class _AdminCalendarAssignmentDialogState
    extends State<AdminCalendarAssignmentDialog> {
  final _api = BackendApiService.instance;
  List<Map<String, dynamic>> _cleaners = [];
  List<AdminCalendarVisit> _visits = [];
  String? _cleaner, _order, _error;
  bool _loading = true, _saving = false;
  late String _day;
  @override
  void initState() {
    super.initState();
    _day = widget.visit.day;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cleaner = null;
      _order = null;
    });
    try {
      if (widget.swap) {
        final data = AdminCalendarSnapshot(await _api
            .getMap('/admin/calendar', query: {'from': _day, 'to': _day}));
        final now = DateTime.now();
        _visits = data.visits
            .where((v) =>
                v.id != widget.visit.id &&
                v.cleanerId != widget.visit.cleanerId &&
                ['assigned', 'pending_assignment', 'waiting_cleaner']
                    .contains(v.parentStatus) &&
                v.status == 'accepted' &&
                (DateTime.tryParse('${v.day}T${v.order['start_time']}+05:00')
                        ?.isAfter(now) ??
                    false))
            .toList();
        _cleaners = data.cleaners
            .where((c) =>
                c['status'] == 'approved' &&
                c['deleted_at'] == null &&
                c['verification_status'] == 'approved' &&
                _visits.any((v) => v.cleanerId == c['id']))
            .toList();
      } else {
        _cleaners = await _api.getList(
            '/admin/calendar/orders/${widget.visit.id}/transfer-candidates',
            query: {'fromCleanerId': widget.visit.cleanerId});
      }
    } catch (e) {
      _error = UserErrorMessage.message(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime.parse(_day)
                .isBefore(DateTime(now.year, now.month, now.day))
            ? DateTime(now.year, now.month, now.day)
            : DateTime.parse(_day),
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: DateTime(now.year + 2));
    if (date != null && mounted) {
      _day = adminCalendarDay(date);
      await _load();
    }
  }

  Future<void> _save() async {
    if (_saving || _cleaner == null || (widget.swap && _order == null)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final move = {
        'orderId': widget.visit.id,
        'fromCleanerId': widget.visit.cleanerId,
        'toCleanerId': _cleaner
      };
      await _api.postMap(
          widget.swap ? '/admin/calendar/swap' : '/admin/calendar/transfer',
          body: widget.swap
              ? {
                  'moves': [
                    move,
                    {
                      'orderId': _order,
                      'fromCleanerId': _cleaner,
                      'toCleanerId': widget.visit.cleanerId
                    }
                  ]
                }
              : move);
      _api.dataRevision.value++;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = UserErrorMessage.message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = _visits.where((v) => v.cleanerId == _cleaner).toList();
    return AlertDialog(
        title: Text(widget.swap ? 'Обменяться заказами' : 'Передать заказ'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(
                      'Заказ №${widget.visit.order['numeric_id'] ?? ''} · ${widget.visit.day} · ${widget.visit.order['start_time']}'),
                  const SizedBox(height: 12),
                  if (widget.swap)
                    OutlinedButton.icon(
                        onPressed: _saving || _loading ? null : _pickDay,
                        icon: const Icon(Icons.calendar_month),
                        label: Text('Дата второго заказа: $_day')),
                  if (_loading)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()))
                  else ...[
                    if (_cleaners.isEmpty)
                      Text(widget.swap
                          ? 'На выбранную дату нет других уборщиц с предстоящими заказами.'
                          : 'На это время нет доступных уборщиц. Выберите другую дату или время в заказе.'),
                    if (_cleaners.isNotEmpty)
                      DropdownButtonFormField<String>(
                          key: ValueKey('cleaner-$_day-${_cleaners.length}'),
                          initialValue: _cleaner,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Уборщица'),
                          items: [
                            for (final c in _cleaners)
                              DropdownMenuItem(
                                  value: '${c['id']}',
                                  child: Text(
                                      '${c['full_name'] ?? c['phone'] ?? 'Уборщица'}',
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: _saving
                              ? null
                              : (v) => setState(() {
                                    _cleaner = v;
                                    _order = null;
                                  })),
                    if (widget.swap && _cleaner != null)
                      DropdownButtonFormField<String>(
                          key: ValueKey('order-$_cleaner'),
                          initialValue: _order,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Заказ для обмена'),
                          items: [
                            for (final v in choices)
                              DropdownMenuItem(
                                  value: v.id,
                                  child: Text(
                                      '№${v.order['numeric_id']} · ${v.order['start_time']} · ${v.order['customer_name'] ?? ''}',
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _order = v)),
                    const SizedBox(height: 12),
                    const Text(
                        'Дата, время и стоимость заказов сохраняются. Доступность проверяется при подтверждении. Обе уборщицы получат уведомления.',
                        style: TextStyle(fontSize: 12)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    TextButton(
                        onPressed: _saving ? null : _load,
                        child: const Text('Обновить список'))
                  ]
                ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: _loading ||
                      _saving ||
                      _cleaner == null ||
                      (widget.swap && _order == null)
                  ? null
                  : _save,
              child: Text(_saving
                  ? 'Сохраняем…'
                  : widget.swap
                      ? 'Обменять'
                      : 'Передать'))
        ]);
  }
}
