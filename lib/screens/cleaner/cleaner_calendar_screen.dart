import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerCalendarScreen extends StatefulWidget {
  const CleanerCalendarScreen({super.key});

  @override
  State<CleanerCalendarScreen> createState() => _CleanerCalendarScreenState();
}

class _CleanerCalendarScreenState extends State<CleanerCalendarScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now();
  final _data = FirestoreDataService.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.cleanerScheduleSlotsStream(),
      builder: (context, snap) {
        final slots = snap.data ?? <Map<String, dynamic>>[];
        final selected = slots.where((s) {
          final date = _toDate(s['scheduledFor'] ?? s['date']);
          final status = (s['status'] ?? '').toString().toLowerCase();
          return date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day &&
              status != 'completed' &&
              status != 'cancelled' &&
              status != 'canceled';
        }).toList();
        selected.sort(
          (a, b) => _toDate(
            a['scheduledFor'] ?? a['date'],
          ).compareTo(_toDate(b['scheduledFor'] ?? b['date'])),
        );

        return DomlyShell(
          bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 1),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DomlyHeader(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        domlyTopIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Календарь'.tr(),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'График уборок по дням'.tr(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xCCFFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.calendar_today,
                          color: Color(0x99FFFFFF),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      children: [
                        DomlyCard(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  10,
                                ),
                                child: Row(
                                  children: [
                                    _monthButton(Icons.chevron_left, () {
                                      setState(() {
                                        _selectedMonth = DateTime(
                                          _selectedMonth.year,
                                          _selectedMonth.month - 1,
                                        );
                                      });
                                    }),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _monthLabel(_selectedMonth),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: DomlyColors.foreground,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _monthButton(Icons.chevron_right, () {
                                      setState(() {
                                        _selectedMonth = DateTime(
                                          _selectedMonth.year,
                                          _selectedMonth.month + 1,
                                        );
                                      });
                                    }),
                                  ],
                                ),
                              ),
                              Row(
                                children: _weekdays
                                    .map(
                                      (day) => Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            day,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: DomlyColors.muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 6),
                              ..._buildCalendarRows(slots),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_selectedDate.day} ${_monthNameGenitive(_selectedDate.month)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: DomlyColors.foreground,
                                ),
                              ),
                            ),
                            if (selected.isNotEmpty)
                              Text(
                                '${selected.length} уборок'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: DomlyColors.muted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<Map<String, dynamic>>(
                          future: _data.calculateDailySchedule(
                            date: _selectedDate,
                          ),
                          builder: (context, scheduleSnap) {
                            final summary = Map<String, dynamic>.from(
                              scheduleSnap.data?['summary'] as Map? ?? const {},
                            );
                            if (summary.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DomlyCard(
                                color: DomlyColors.backgroundSoft,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.schedule_outlined,
                                        color: DomlyColors.buttonPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Занято ${summary['occupiedHours'] ?? 0} ч из ${summary['limitHours'] ?? 8.5} ч',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Площадь: ${summary['totalArea'] ?? 0} м² из ${summary['limitArea'] ?? 220} м²',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: DomlyColors.muted,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Остаток: ${summary['remainingMinutes'] ?? 0} мин • ${summary['remainingArea'] ?? 0} м² • Доп. услуг: ${summary['totalAddonCount'] ?? 0}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: DomlyColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (summary['overbooked'] == true) ...[
                                      const SizedBox(width: 10),
                                      const DomlyStatusChip(
                                        label: 'Перегруз',
                                        color: DomlyColors.danger,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        if (selected.isEmpty)
                          const DomlyEmptyStateCard(
                            title: 'Нет запланированных уборок',
                            subtitle:
                                'Когда появятся назначения на выбранную дату, они будут показаны здесь.',
                            icon: Icons.event_busy_outlined,
                          )
                        else
                          ...selected.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DomlyCard(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            DomlyColors.primary,
                                            DomlyColors.accent,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        (item['time'] ?? '—')
                                            .toString()
                                            .split(' ')
                                            .first,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${(item['time'] ?? '—').toString()} · ${((item['residentialComplex'] ?? item['address'] ?? 'Адрес будет уточнен').toString())}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        DomlyColors.foreground,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Icon(
                                                Icons.chevron_right,
                                                color: DomlyColors.muted,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${item['area'] ?? 0} м² · ${(item['customerName'] ?? item['client'] ?? 'Клиент').toString()}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: DomlyColors.muted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _infoChip(
                                                '${item['totalDurationMinutes'] ?? item['estimatedDurationMinutes'] ?? 0} мин',
                                              ),
                                              _infoChip(
                                                'Допы: ${item['addonCount'] ?? 0}',
                                              ),
                                              _infoChip(
                                                'Дорога: ${item['travelTimeMinutes'] ?? 15} мин',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (selected.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: DomlyCard(
                              color: DomlyColors.backgroundSoft,
                              border: Border.all(
                                color: DomlyColors.buttonPrimary.withValues(
                                  alpha: 0.10,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    color: DomlyColors.buttonPrimary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Итого за день'.tr(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${selected.length} заказ(ов)'.tr(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _monthButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: DomlyColors.backgroundSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: DomlyColors.foreground),
        ),
      ),
    );
  }

  List<Widget> _buildCalendarRows(List<Map<String, dynamic>> slots) {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final daysInMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;
    final offset = (firstDay.weekday + 6) % 7;
    final cells = <Widget>[];

    for (var i = 0; i < offset; i++) {
      cells.add(const SizedBox(height: 44));
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final hasOrders = slots.any((slot) {
        final slotDate = _toDate(slot['scheduledFor'] ?? slot['date']);
        final status = (slot['status'] ?? '').toString().toLowerCase();
        return slotDate.year == date.year &&
            slotDate.month == date.month &&
            slotDate.day == date.day &&
            status != 'completed' &&
            status != 'cancelled' &&
            status != 'canceled';
      });
      final isSelected =
          _selectedDate.year == date.year &&
          _selectedDate.month == date.month &&
          _selectedDate.day == date.day;
      final isToday =
          DateTime.now().year == date.year &&
          DateTime.now().month == date.month &&
          DateTime.now().day == date.day;

      cells.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDate = date),
          child: Container(
            height: 44,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [DomlyColors.primary, DomlyColors.accent],
                    )
                  : null,
              color: isSelected
                  ? null
                  : isToday
                  ? DomlyColors.backgroundSoft
                  : hasOrders
                  ? DomlyColors.accent.withValues(alpha: 0.15)
                  : DomlyColors.backgroundSoft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: isToday && !isSelected
                  ? Border.all(color: DomlyColors.buttonPrimary, width: 1.4)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : DomlyColors.foreground,
                  ),
                ),
                if (hasOrders)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : DomlyColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: List.generate(7, (index) {
            final cellIndex = i + index;
            return Expanded(
              child: cellIndex < cells.length
                  ? cells[cellIndex]
                  : const SizedBox(height: 44),
            );
          }),
        ),
      );
    }
    return rows;
  }

  DateTime _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  String _monthLabel(DateTime month) {
    return '${_monthName(month.month)} ${month.year}';
  }

  String _monthName(int month) {
    const months = [
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
      'Декабрь',
    ];
    return months[month - 1];
  }

  String _monthNameGenitive(int month) {
    const months = [
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
      'декабря',
    ];
    return months[month - 1];
  }

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DomlyColors.foreground,
        ),
      ),
    );
  }
}
