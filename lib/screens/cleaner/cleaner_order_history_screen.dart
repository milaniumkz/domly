import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/order_display.dart';
import '../../localization/translation_controller.dart';

enum _OrderPeriod { week, month, year }

class CleanerOrderHistoryScreen extends StatefulWidget {
  const CleanerOrderHistoryScreen({super.key});

  @override
  State<CleanerOrderHistoryScreen> createState() =>
      _CleanerOrderHistoryScreenState();
}

class _CleanerOrderHistoryScreenState extends State<CleanerOrderHistoryScreen> {
  final _data = FirestoreDataService.instance;
  _OrderPeriod _period = _OrderPeriod.month;

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 4),
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            _periodSelector(),
            Expanded(child: _orderList()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return DomlyHeader(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
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
                  'История заказов'.tr(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Сводка по выполненным уборкам за период.'.tr(),
                  style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          for (final p in _OrderPeriod.values) ...[
            Expanded(child: _periodChip(p)),
            if (p != _OrderPeriod.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _periodChip(_OrderPeriod period) {
    final selected = period == _period;
    final labels = {
      _OrderPeriod.week: 'Неделя',
      _OrderPeriod.month: 'Месяц',
      _OrderPeriod.year: 'Год',
    };
    return Material(
      color: selected ? DomlyColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _period = period),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Text(
            labels[period]!,
            style: TextStyle(
              color: selected ? Colors.white : DomlyColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.cleanerOrdersStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: DomlyEmptyStateCard(
                icon: Icons.history,
                title: 'Не удалось загрузить историю',
                subtitle: 'Обновите экран и попробуйте снова.',
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(
                  DomlyColors.buttonPrimary,
                ),
              ),
            ),
          );
        }
        final allOrders = snap.data ?? [];
        final completedOrders = allOrders.where((order) {
          final status = (order['orderStatus'] ?? order['status'] ?? '')
              .toString();
          return status == 'completed';
        }).toList();
        final filtered = _filterByPeriod(completedOrders);
        filtered.sort((a, b) {
          final da = _orderDate(b);
          final db_ = _orderDate(a);
          return da.compareTo(db_);
        });

        if (filtered.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: DomlyEmptyStateCard(
                icon: Icons.history,
                title: 'Нет заказов за выбранный период',
                subtitle: 'Выберите другой период или проверьте позже.',
              ),
            ),
          );
        }

        final summary = _computeSummary(filtered);
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            _summaryCard(summary, filtered.length),
            const SizedBox(height: 16),
            ...filtered.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _orderCard(o),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _filterByPeriod(
    List<Map<String, dynamic>> orders,
  ) {
    final now = DateTime.now();
    DateTime cutoff;
    switch (_period) {
      case _OrderPeriod.week:
        cutoff = now.subtract(const Duration(days: 7));
        break;
      case _OrderPeriod.month:
        cutoff = DateTime(now.year, now.month, 1);
        break;
      case _OrderPeriod.year:
        cutoff = DateTime(now.year, 1, 1);
        break;
    }
    return orders.where((o) {
      final d = _orderDate(o);
      return d.isAfter(cutoff) || d.isAtSameMomentAs(cutoff);
    }).toList();
  }

  Map<String, dynamic> _computeSummary(List<Map<String, dynamic>> orders) {
    int totalArea = 0;
    int totalDurationMinutes = 0;
    int totalAddons = 0;
    for (final o in orders) {
      totalArea += ((o['area'] ?? 0) as num).toInt();
      totalDurationMinutes +=
          ((o['totalDurationMinutes'] ?? o['estimatedDurationMinutes'] ?? 0)
                  as num)
              .toInt();
      totalAddons += ((o['addonCount'] ?? 0) as num).toInt();
    }
    return {
      'totalArea': totalArea,
      'totalDurationMinutes': totalDurationMinutes,
      'totalAddons': totalAddons,
    };
  }

  Widget _summaryCard(Map<String, dynamic> summary, int count) {
    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _miniMetric('$count', 'Заказов')),
              const SizedBox(width: 12),
              Expanded(
                child: _miniMetric('${summary['totalArea']} м²', 'Площадь'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _miniMetric('${summary['totalDurationMinutes'] ?? 0} мин', 'Время'),
        ],
      ),
    );
  }

  Widget _miniMetric(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: DomlyColors.muted),
        ),
      ],
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status = (order['orderStatus'] ?? order['status'] ?? '').toString();
    final date = _orderDate(order);
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
    final addons = _formatAddons(order);
    final durationMinutes =
        ((order['totalDurationMinutes'] ??
                    order['estimatedDurationMinutes'] ??
                    0)
                as num)
            .toInt();
    final addonCount = ((order['addonCount'] ?? 0) as num).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusLabel(status),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DomlyColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DomlyColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(order['area'] ?? 0)} м² · $durationMinutes мин',
                      style: const TextStyle(
                        fontSize: 13,
                        color: DomlyColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((order['address'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              (order['address'] ?? '—').toString(),
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
          ],
          if (addons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              addons,
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
          ],
          if (addonCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [if (addonCount > 0) _infoChip('Допов: $addonCount')],
            ),
          ],
        ],
      ),
    );
  }

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

  String _formatAddons(Map<String, dynamic> order) {
    final addons = order['addons'];
    if (addons is List && addons.isNotEmpty) {
      return addons.map((e) => e.toString()).join(', ');
    }
    final addonsDetailed = order['addonsDetailed'];
    if (addonsDetailed is List && addonsDetailed.isNotEmpty) {
      return addonsDetailed
          .map((e) => (e['label'] ?? e['key'] ?? '').toString())
          .join(', ');
    }
    return '';
  }

  DateTime _orderDate(Map<String, dynamic> order) {
    final value =
        order['completedAt'] ??
        order['date'] ??
        order['scheduledFor'] ??
        order['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Завершено';
      case 'canceled':
      case 'cancelled':
        return 'Отменено';
      case 'disputed':
        return 'Спор';
      case 'pending_assignment':
        return 'Ожидание';
      case 'assigned':
        return 'Подтверждено';
      case 'in_progress':
        return 'В процессе';
      default:
        return orderStatusLabel(status);
    }
  }
}
