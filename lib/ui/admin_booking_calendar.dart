import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../utils/admin_calendar_data.dart';
import '../utils/cleaning_time_range.dart';
import '../utils/user_error_message.dart';

typedef AdminCalendarLoader = Future<Map<String, dynamic>> Function(
    String from, String to);

class AdminBookingCalendar extends StatefulWidget {
  const AdminBookingCalendar(
      {super.key, required this.onOpenOrder, this.load, this.initialDay});
  final Future<void> Function(Map<String, dynamic>) onOpenOrder;
  final AdminCalendarLoader? load;
  final DateTime? initialDay;
  @override
  State<AdminBookingCalendar> createState() => _AdminBookingCalendarState();
}

class _AdminBookingCalendarState extends State<AdminBookingCalendar> {
  static const green = Color(0xFF16745C),
      ink = Color(0xFF18372E),
      muted = Color(0xFF687A74);
  static const monthNames = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь'
  ];
  static const monthDays = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря'
  ];
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _daySection = GlobalKey();
  late DateTime _month, _selected;
  AdminCalendarSnapshot? _snapshot;
  Timer? _timer;
  bool _loading = true,
      _filters = false,
      _onlyBooked = false,
      _cancelled = false;
  String? _cleanerId, _error, _opening;
  int _request = 0;
  String get _day => adminCalendarDay(_selected);

  @override
  void initState() {
    super.initState();
    final today = widget.initialDay ??
        DateTime.now().toUtc().add(const Duration(hours: 5));
    _selected = DateTime(today.year, today.month, today.day);
    _month = DateTime(today.year, today.month);
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading) _reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    final from = adminCalendarDay(_month),
        to = adminCalendarDay(DateTime(_month.year, _month.month + 1, 0));
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.load?.call(from, to) ??
          BackendApiService.instance
              .getMap('/admin/calendar', query: {'from': from, 'to': to}));
      if (!mounted || request != _request) return;
      final snapshot = AdminCalendarSnapshot(data);
      setState(() {
        _snapshot = snapshot;
        if (_cleanerId != null &&
            !snapshot.cleaners.any((c) => c['id'] == _cleanerId))
          _cleanerId = null;
      });
    } catch (error) {
      if (mounted && request == _request)
        setState(() => _error = UserErrorMessage.message(error));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selected = DateTime(
          _month.year,
          _month.month,
          math.min(
              _selected.day, DateTime(_month.year, _month.month + 1, 0).day));
      _snapshot = null;
    });
    _reload();
  }

  void _today() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final reload = now.year != _month.year || now.month != _month.month;
    setState(() {
      _selected = DateTime(now.year, now.month, now.day);
      _month = DateTime(now.year, now.month);
      if (reload) _snapshot = null;
    });
    if (reload) _reload();
  }

  Future<void> _open(Map<String, dynamic> order) async {
    if (_opening != null) return;
    setState(() => _opening = '${order['id']}');
    try {
      await widget.onOpenOrder(order);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(UserErrorMessage.message(error))));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  bool _matches(Map<String, dynamic> order) {
    final query = _search.text.toLowerCase().trim();
    if (query.isEmpty) return true;
    return [
      order['numeric_id'],
      order['customer_name'],
      order['customer_phone'],
      order['city'],
      order['street'],
      order['house'],
      order['apartment'],
      order['package_name_ru']
    ].join(' ').toLowerCase().contains(query);
  }

  List<Map<String, dynamic>> _ordersOn(String day) {
    final snapshot = _snapshot;
    if (snapshot == null) return [];
    final staffOrders = _cleanerId == null
        ? null
        : snapshot
            .forCleaner(_cleanerId!, day, includeCancelled: _cancelled)
            .map((v) => v.id)
            .toSet();
    return snapshot
        .ordersOn(day, includeCancelled: _cancelled)
        .where((o) =>
            _matches(o) &&
            (staffOrders == null || staffOrders.contains('${o['id']}')))
        .toList();
  }

  String _area(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  String _address(Map<String, dynamic> order) => [
        order['street'],
        order['house'],
        if (order['apartment'] != null) 'кв. ${order['apartment']}'
      ].where((v) => v != null && '$v'.isNotEmpty).join(', ');
  String _time(Map<String, dynamic> order) {
    String clock(Object? value) =>
        RegExp(r'^([0-2]\d:[0-5]\d)').firstMatch('$value')?.group(1) ?? '';
    final start = clock(order['start_time']), end = clock(order['end_time']);
    return start.isEmpty
        ? 'Время не указано'
        : cleaningTimeRange(start, end,
            date: '${order['service_date'] ?? order['scheduled_date']}',
            durationMinutes: order['estimated_duration_minutes']);
  }

  String _dateTitle(DateTime date) =>
      '${date.day} ${monthDays[date.month - 1]} ${date.year}';
  Color _statusColor(AdminCalendarVisit visit) => switch (visit.status) {
        'cancelled' => const Color(0xFF8C9793),
        'completed' => green,
        'in_progress' => const Color(0xFFD56E28),
        'offered' || 'reserved' => const Color(0xFFB78415),
        _ => const Color(0xFF477CBA)
      };
  String _statusTitle(AdminCalendarVisit visit) {
    if (calendarCancelled(visit.parentStatus)) return 'Отменён';
    if (visit.status == 'completed')
      return visit.parentStatus == 'completed' ? 'Завершён' : 'Часть завершена';
    if (visit.parentStatus == 'pending_payment') return 'Ожидает оплаты';
    return switch (visit.status) {
      'in_progress' => 'В работе',
      'reserved' => 'Резерв команды',
      'offered' => 'Ожидает принятия',
      _ => visit.parentStatus == 'pending_assignment' ||
              visit.parentStatus == 'waiting_cleaner'
          ? 'Ждём всю команду'
          : 'Подтверждён'
    };
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final orders = _ordersOn(_day);
    final selectedVisits = snapshot?.visits
            .where((v) =>
                v.appearsOn(_day) &&
                (_cleanerId == null || v.cleanerId == _cleanerId) &&
                !calendarCancelled(v.parentStatus) &&
                _matches(v.order))
            .toList() ??
        [];
    final area = _cleanerId == null
        ? orders
            .where((o) =>
                !calendarCancelled(o['status']) &&
                AdminCalendarVisit(o, const {}).day == _day)
            .fold<double>(0, (n, o) => n + calendarNumber(o['area']).toDouble())
        : snapshot?.dailyArea(_cleanerId!, _day) ?? 0;
    final cleaners = snapshot?.cleaners
            .where((c) => _cleanerId == null || c['id'] == _cleanerId)
            .where((c) {
          final visits = snapshot
              .forCleaner('${c['id']}', _day, includeCancelled: _cancelled)
              .where((v) => _matches(v.order));
          return (!_onlyBooked || visits.isNotEmpty) &&
              (_search.text.trim().isEmpty || visits.isNotEmpty);
        }).toList() ??
        [];
    final unassigned = snapshot
            ?.unassignedOn(_day)
            .where(_matches)
            .where((o) =>
                _cleanerId == null ||
                selectedVisits.any((v) => v.id == '${o['id']}'))
            .toList() ??
        [];
    final filterCount = (_cleanerId == null ? 0 : 1) +
        (_onlyBooked ? 1 : 0) +
        (_cancelled ? 1 : 0) +
        (_search.text.isEmpty ? 0 : 1);
    return ListView(
        controller: _scroll,
        cacheExtent: 1800,
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const LinearProgressIndicator(minHeight: 2, color: green),
          if (_error != null)
            Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E6),
                    borderRadius: BorderRadius.circular(12)),
                child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      Text(
                          '${snapshot == null ? 'Не удалось загрузить календарь' : 'Не удалось обновить. Показаны предыдущие данные'}. $_error'),
                      TextButton(
                          onPressed: _reload, child: const Text('Повторить'))
                    ])),
          _panel(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LayoutBuilder(
                builder: (context, box) => Wrap(
                        spacing: 8,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                              tooltip: 'Предыдущий месяц',
                              onPressed: () => _changeMonth(-1),
                              icon: const Icon(Icons.chevron_left)),
                          Text('${monthNames[_month.month - 1]} ${_month.year}',
                              style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: ink)),
                          IconButton(
                              tooltip: 'Следующий месяц',
                              onPressed: () => _changeMonth(1),
                              icon: const Icon(Icons.chevron_right)),
                          TextButton(
                              onPressed: _today, child: const Text('Сегодня')),
                          IconButton(
                              tooltip: 'Обновить календарь',
                              onPressed: _loading ? null : _reload,
                              icon: const Icon(Icons.refresh)),
                          TextButton.icon(
                              onPressed: () =>
                                  setState(() => _filters = !_filters),
                              icon: Icon(_filters
                                  ? Icons.filter_list_off
                                  : Icons.filter_list),
                              label: Text(filterCount == 0
                                  ? 'Фильтры'
                                  : 'Фильтры · $filterCount')),
                        ])),
            if (_filters) ...[
              const Divider(height: 24),
              TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Клиент, адрес, телефон или номер заказа',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  initialValue: _cleanerId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Клинер', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('Все клинеры')),
                    for (final cleaner
                        in snapshot?.cleaners ?? <Map<String, dynamic>>[])
                      DropdownMenuItem(
                          value: '${cleaner['id']}',
                          child: Text(
                              '${cleaner['full_name'] ?? cleaner['phone'] ?? 'Клинер'}'))
                  ],
                  onChanged: (value) =>
                      setState(() => _cleanerId = value == '' ? null : value)),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _check('Только с записями', _onlyBooked,
                    (v) => setState(() => _onlyBooked = v)),
                _check('Показать отменённые', _cancelled,
                    (v) => setState(() => _cancelled = v)),
                TextButton(
                    onPressed: () => setState(() {
                          _cleanerId = null;
                          _onlyBooked = false;
                          _cancelled = false;
                          _search.clear();
                        }),
                    child: const Text('Сбросить'))
              ]),
            ],
            const SizedBox(height: 14),
            _monthGrid(),
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 6, children: [
              _legend('Есть записи', green),
              _legend('Выбранный день', const Color(0xFF1D5845)),
              _legend('Без записей', const Color(0xFFDCE6E1))
            ]),
          ])),
          const SizedBox(height: 18),
          Column(
              key: _daySection,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(_dateTitle(_selected),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: ink)),
                      TextButton.icon(
                          onPressed: () => _scroll.animateTo(0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut),
                          icon: const Icon(Icons.calendar_month_outlined,
                              size: 17),
                          label: const Text('Другая дата')),
                    ]),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  _metric('Заказов', '${orders.length}',
                      Icons.receipt_long_outlined),
                  _metric(
                      'Клинеров с записями',
                      '${selectedVisits.map((v) => v.cleanerId).toSet().length}',
                      Icons.people_outline),
                  _metric('Площадь', '${_area(area)} м²', Icons.square_foot),
                  if (unassigned.isNotEmpty)
                    _metric('Требуют назначения', '${unassigned.length}',
                        Icons.person_search_outlined,
                        warning: true)
                ]),
              ]),
          const SizedBox(height: 14),
          if (snapshot == null && _loading)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: green))),
          if (snapshot != null && cleaners.isEmpty)
            _panel(const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Нет клинеров по выбранным условиям. Измените фильтры или выберите другой день.',
                    style: TextStyle(color: muted)))),
          if (snapshot != null)
            LayoutBuilder(builder: (context, box) {
              final columns = box.maxWidth >= 820 ? 2 : 1;
              final width = (box.maxWidth - 14 * (columns - 1)) / columns;
              return Wrap(spacing: 14, runSpacing: 14, children: [
                for (final cleaner in cleaners)
                  SizedBox(width: width, child: _cleanerCard(snapshot, cleaner))
              ]);
            }),
          if (unassigned.isNotEmpty) ...[
            const SizedBox(height: 18),
            _panel(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Нужно назначить исполнителей',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF925B09))),
                  const SizedBox(height: 6),
                  const Text('Эти заказы пока не обеспечены полной командой.',
                      style: TextStyle(color: muted)),
                  for (final order in unassigned)
                    _unassignedRow(snapshot!, order)
                ]),
                tint: const Color(0xFFFFFBEE))
          ],
          const SizedBox(height: 14),
          const Text(
              'Норма — 220 м², максимум — 250 м² на клинера в день. Площадь командной уборки учитывается по долям. Возможность нового заказа зависит также от его длительности и утверждённого графика.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.5)),
          if (snapshot != null) ...[
            const SizedBox(height: 6),
            Text(
                'Данные обновляются каждые 30 секунд · ${_updatedLabel(snapshot)}',
                style: const TextStyle(fontSize: 11, color: muted))
          ],
        ]);
  }

  Widget _monthGrid() {
    final first = DateTime(_month.year, _month.month),
        offset = first.weekday - 1,
        days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((offset + days + 6) ~/ 7) * 7;
    return Column(children: [
      Row(children: [
        for (final label in ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'])
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                      child: Text(label,
                          style: const TextStyle(
                              color: muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)))))
      ]),
      LayoutBuilder(
          builder: (context, box) => Wrap(children: [
                for (var cell = 0; cell < cells; cell++)
                  SizedBox(
                      width: box.maxWidth / 7,
                      child: cell < offset || cell >= offset + days
                          ? const SizedBox(height: 76)
                          : _dayCell(DateTime(
                              _month.year, _month.month, cell - offset + 1)))
              ])),
    ]);
  }

  Widget _dayCell(DateTime day) {
    final key = adminCalendarDay(day),
        chosen = key == _day,
        orders = _ordersOn(key);
    final booked = orders.any((o) => !calendarCancelled(o['status']));
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final today = key == adminCalendarDay(now);
    final area = _cleanerId == null
        ? orders
            .where((o) =>
                !calendarCancelled(o['status']) &&
                AdminCalendarVisit(o, const {}).day == key)
            .fold<double>(
                0, (sum, o) => sum + calendarNumber(o['area']).toDouble())
        : _snapshot?.dailyArea(_cleanerId!, key) ?? 0;
    return Semantics(
        button: true,
        selected: chosen,
        label:
            '${_dateTitle(day)}, заказов ${orders.length}, ${_area(area)} квадратных метров',
        child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
                color: chosen
                    ? const Color(0xFF1D5845)
                    : booked
                        ? const Color(0xFFE9F5EF)
                        : const Color(0xFFF6F8F7),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                    key: ValueKey('calendar-day-$key'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selected = day);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final target = _daySection.currentContext;
                        if (target != null)
                          Scrollable.ensureVisible(target,
                              duration: const Duration(milliseconds: 250),
                              alignment: 0.05);
                      });
                    },
                    child: Container(
                        height: 72,
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 2),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: today
                                ? Border.all(
                                    color: chosen ? Colors.white : green,
                                    width: 1.5)
                                : null),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${day.day}',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: chosen ? Colors.white : ink)),
                              if (orders.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text('${orders.length} зак.',
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: chosen ? Colors.white : green)),
                                Text('${_area(area)} м²',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: chosen
                                            ? const Color(0xFFD2E8DF)
                                            : muted))
                              ] else
                                const SizedBox(height: 24)
                            ]))))));
  }

  Widget _cleanerCard(
      AdminCalendarSnapshot snapshot, Map<String, dynamic> cleaner) {
    final id = '${cleaner['id']}',
        all = snapshot.forCleaner(id, _day, includeCancelled: _cancelled),
        visits = all.where((v) => _matches(v.order)).toList();
    final shift = snapshot.workingDay(id, _day),
        approved = snapshot.approvedWeek(id, _day);
    final area = snapshot.dailyArea(id, _day),
        over = area > snapshot.maximum,
        near = area >= snapshot.norm;
    final name = '${cleaner['full_name'] ?? cleaner['phone'] ?? 'Клинер'}';
    final eligible = cleaner['status'] == 'approved' &&
        cleaner['verification_status'] == 'approved';
    final unknown = all.any((v) => v.occupiesTime && v.duration <= 0);
    final free = shift == null || unknown || !eligible
        ? <({int start, int end})>[]
        : calendarFreeIntervals(shift, all, _day);
    final outsideShift = all.any((visit) =>
        visit.occupiesTime &&
        visit.day == _day &&
        (shift == null ||
            visit.start < calendarClockMinutes(shift['start_time']) ||
            visit.start > calendarClockMinutes(shift['end_time']) ||
            visit.start + visit.duration >
                calendarClockMinutes(shift['end_time']) + 120));
    var conflict = false;
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        if (all[i].occupiesTime &&
            all[j].occupiesTime &&
            all[i].startOn(_day) < all[j].endOn(_day) &&
            all[j].startOn(_day) < all[i].endOn(_day)) conflict = true;
      }
    }
    return Container(
        key: ValueKey('calendar-cleaner-$id'),
        child: _panel(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
                backgroundColor: shift != null
                    ? const Color(0xFFE4F2EC)
                    : const Color(0xFFF0F2F1),
                foregroundColor: green,
                child: Text(
                    name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: ink)),
                  if (cleaner['phone'] != null)
                    Text('${cleaner['phone']}',
                        style: const TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 5),
                  Text(
                      !eligible
                          ? 'Нет допуска к работе'
                          : shift == null
                              ? (approved ? 'Выходной' : 'График не утверждён')
                              : 'Работает ${shift['start_time']}–${shift['end_time']}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: shift == null ? muted : green))
                ])),
            Text('${all.length} зак.',
                style: const TextStyle(color: muted, fontSize: 12))
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: Text('${_area(area)} м²',
                    style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: over ? const Color(0xFFC44242) : ink))),
            Text('из ${_area(snapshot.maximum)} м²',
                style: const TextStyle(fontSize: 12, color: muted))
          ]),
          const SizedBox(height: 6),
          ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                  value: (area / snapshot.maximum).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFEAF0ED),
                  color: over
                      ? const Color(0xFFC44242)
                      : near
                          ? const Color(0xFFCB942F)
                          : green)),
          const SizedBox(height: 6),
          Text(
              over
                  ? 'Превышен дневной лимит'
                  : area >= snapshot.maximum
                      ? 'Дневной лимит выбран'
                      : 'Норма ${_area(snapshot.norm)} м² · Остаток ${_area(math.max(0, snapshot.maximum - area))} м²',
              style: TextStyle(
                  fontSize: 11, color: over ? const Color(0xFFC44242) : muted)),
          const SizedBox(height: 14),
          _timeline(all, shift),
          if (unknown) ...[
            const SizedBox(height: 8),
            const Text(
                'Есть запись без времени — откройте заказ и проверьте расписание.',
                style: TextStyle(fontSize: 12, color: Color(0xFFC44242)))
          ],
          if (outsideShift) ...[
            const SizedBox(height: 8),
            const Text(
                'Есть запись вне утверждённого графика — проверьте назначение.',
                style: TextStyle(fontSize: 12, color: Color(0xFFAD6B18)))
          ],
          if (conflict) ...[
            const SizedBox(height: 8),
            const Text('Есть пересечение записей — проверьте назначения.',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFC44242),
                    fontWeight: FontWeight.w700))
          ],
          if (free.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                'Без записей: ${free.map((i) => '${calendarClockLabel(i.start)}–${calendarClockLabel(i.end)}').join(' · ')}',
                style: const TextStyle(fontSize: 12, color: green, height: 1.5))
          ],
          const SizedBox(height: 10),
          if (visits.isEmpty)
            Text(all.isEmpty ? 'Записей нет' : 'Нет заказов по поиску',
                style: const TextStyle(color: muted, fontSize: 13)),
          for (final visit in visits) _visitRow(visit),
        ])));
  }

  Widget _timeline(
      List<AdminCalendarVisit> visits, Map<String, dynamic>? shift) {
    var begin = 480, end = 1200;
    if (shift != null) {
      begin = math.min(begin, calendarClockMinutes(shift['start_time']));
      end = math.max(
          end, math.min(1440, calendarClockMinutes(shift['end_time']) + 120));
    }
    for (final visit in visits) {
      begin = math.min(begin, math.max(0, visit.startOn(_day)));
      end = math.max(end, math.min(1440, visit.endOn(_day)));
    }
    begin = (begin ~/ 120) * 120;
    end = math.min(1440, ((end + 119) ~/ 120) * 120);
    final span = math.max(60, end - begin),
        lanes = <int>[],
        placed = <({AdminCalendarVisit visit, int lane, int start, int end})>[];
    for (final visit in visits) {
      final start = math.max(begin, visit.startOn(_day)),
          finish = math.min(end, visit.endOn(_day));
      if (finish <= start) continue;
      var lane = lanes.indexWhere((until) => until <= start);
      if (lane < 0) {
        lane = lanes.length;
        lanes.add(finish);
      } else {
        lanes[lane] = finish;
      }
      placed.add((visit: visit, lane: lane, start: start, end: finish));
    }
    final height = math.max(1, lanes.length) * 22.0;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      return Column(children: [
        SizedBox(
            height: 18,
            child: Stack(children: [
              for (var hour = begin;
                  hour <= end;
                  hour += span > 720 ? 240 : 120)
                Positioned(
                    left: ((hour - begin) / span * width - 14)
                        .clamp(0, math.max(0, width - 29)),
                    child: Text(
                        hour == 1440 ? '24:00' : calendarClockLabel(hour),
                        style: const TextStyle(fontSize: 9, color: muted)))
            ])),
        Container(
            height: height,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
                color: const Color(0xFFF1F4F2),
                borderRadius: BorderRadius.circular(6)),
            child: Stack(children: [
              if (shift != null)
                Positioned(
                    left: ((calendarClockMinutes(shift['start_time']) - begin) /
                            span *
                            width)
                        .clamp(0, width),
                    width: ((calendarClockMinutes(shift['end_time']) -
                                calendarClockMinutes(shift['start_time'])) /
                            span *
                            width)
                        .clamp(0, width),
                    top: 0,
                    bottom: 0,
                    child: Container(color: const Color(0xFFE2F0E8))),
              for (final item in placed)
                Positioned(
                    left: (item.start - begin) / span * width,
                    width: math.max(5, (item.end - item.start) / span * width),
                    top: item.lane * 22 + 2,
                    height: 18,
                    child: Tooltip(
                        message:
                            '${item.visit.order['customer_name'] ?? 'Клиент'} · ${_statusTitle(item.visit)} · ${_area(item.visit.area)} м²',
                        child: Material(
                            color: _statusColor(item.visit),
                            borderRadius: BorderRadius.circular(4),
                            child: InkWell(
                                onTap: _opening == null
                                    ? () => _open(item.visit.order)
                                    : null,
                                child: const SizedBox.expand()))))
            ]))
      ]);
    });
  }

  Widget _visitRow(AdminCalendarVisit visit) {
    final order = visit.order,
        color = _statusColor(visit),
        crew = calendarNumber(order['required_cleaners'] ?? 1).toInt();
    final time = _time(order);
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
            color: color.withValues(alpha: 0.065),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
                key: ValueKey('calendar-order-${visit.id}-${visit.cleanerId}'),
                borderRadius: BorderRadius.circular(12),
                onTap: _opening == null ? () => _open(order) : null,
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                              spacing: 10,
                              runSpacing: 5,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(time,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: ink)),
                                Text('${_area(visit.area)} м²',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: color)),
                                if (crew > 1)
                                  Text('Команда · $crew чел.',
                                      style: const TextStyle(
                                          fontSize: 11, color: muted))
                              ]),
                          const SizedBox(height: 5),
                          Text(
                              '${order['customer_name'] ?? 'Клиент'} · №${order['numeric_id'] ?? order['id']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                  fontSize: 13)),
                          if (_address(order).isNotEmpty)
                            Text(_address(order),
                                style:
                                    const TextStyle(fontSize: 12, color: muted),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 5),
                          Wrap(spacing: 10, runSpacing: 4, children: [
                            Text(_statusTitle(visit),
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                            if (visit.day != _day)
                              Text('Начало ${visit.day}',
                                  style: const TextStyle(
                                      fontSize: 11, color: muted)),
                            if (order['customer_phone'] != null)
                              Text('${order['customer_phone']}',
                                  style: const TextStyle(
                                      fontSize: 11, color: muted))
                          ])
                        ])))));
  }

  Widget _unassignedRow(
      AdminCalendarSnapshot snapshot, Map<String, dynamic> order) {
    final assigned =
            snapshot.visits.where((v) => v.id == '${order['id']}').length,
        required = calendarNumber(order['required_cleaners'] ?? 1).toInt();
    final offers = AdminCalendarSnapshot.maps(order['offers']);
    return ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: _opening == null ? () => _open(order) : null,
        leading:
            const Icon(Icons.person_search_outlined, color: Color(0xFFAE7920)),
        title: Text(
            '${order['customer_name'] ?? 'Клиент'} · ${_area(calendarNumber(order['area']))} м²',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
            '${_time(order)} · Назначено $assigned из $required\n${_address(order)}${offers.isEmpty ? '' : '\nПредложено: ${offers.map((o) => o['name'] ?? 'Клинер').join(', ')}'}',
            style: const TextStyle(fontSize: 12, height: 1.5)),
        trailing: const Icon(Icons.chevron_right));
  }

  String _updatedLabel(AdminCalendarSnapshot snapshot) {
    final date = DateTime.tryParse('${snapshot.raw['updatedAt']}')
        ?.toUtc()
        .add(const Duration(hours: 5));
    return date == null
        ? ''
        : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} по Астане';
  }

  Widget _panel(Widget child, {Color tint = Colors.white}) => Material(
        color: tint,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE1E9E4))),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
  Widget _metric(String label, String value, IconData icon,
          {bool warning = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color:
                  warning ? const Color(0xFFFFF4D7) : const Color(0xFFEEF6F2),
              borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 18, color: warning ? const Color(0xFFAA7410) : green),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: warning ? const Color(0xFF925B09) : ink)),
              Text(label, style: const TextStyle(fontSize: 10, color: muted))
            ])
          ]));
  Widget _legend(String label, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: muted))
      ]);
  Widget _check(String label, bool value, ValueChanged<bool> changed) =>
      InkWell(
          onTap: () => changed(!value),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: value, onChanged: (v) => changed(v ?? false)),
            Text(label, style: const TextStyle(fontSize: 12))
          ]));
}
