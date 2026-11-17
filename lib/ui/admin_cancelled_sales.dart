import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/domly_ui.dart' show domlyDateText;
import 'package:url_launcher/url_launcher.dart';
import '../services/backend_api_service.dart';
import '../localization/translation_controller.dart';
import '../utils/admin_date_time.dart';
import '../utils/order_display.dart';

typedef CancellationLoader = Future<Map<String, dynamic>> Function(
    Map<String, String?> query);

class AdminCancelledSales extends StatefulWidget {
  const AdminCancelledSales({
    super.key,
    this.search = '',
    this.dateFrom,
    this.dateTo,
    this.sort = 'desc',
    this.loader,
  });
  final String search, sort;
  final DateTime? dateFrom, dateTo;
  final CancellationLoader? loader;
  @override
  State<AdminCancelledSales> createState() => _AdminCancelledSalesState();
}

class _AdminCancelledSalesState extends State<AdminCancelledSales> {
  List<Map<String, dynamic>> _rows = [];
  int _offset = 0, _total = 0, _generation = 0;
  bool _loading = false, _failed = false;
  String _kind = 'all';
  Timer? _poll, _debounce;
  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_loading) _load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant AdminCancelledSales oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.search != oldWidget.search ||
        widget.dateFrom != oldWidget.dateFrom ||
        widget.dateTo != oldWidget.dateTo ||
        widget.sort != oldWidget.sort) {
      _generation++;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        _offset = 0;
        _load();
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      if (!silent) _failed = false;
    });
    try {
      final query = <String, String?>{
        'search': widget.search.trim(),
        'kind': _kind,
        'offset': '$_offset',
        'limit': '30',
        'sort': widget.sort,
        'dateFrom': widget.dateFrom?.toUtc().toIso8601String(),
        'dateTo': widget.dateTo == null ? null : DateTime(widget.dateTo!.year, widget.dateTo!.month, widget.dateTo!.day + 1).subtract(const Duration(milliseconds: 1)).toUtc().toIso8601String(),
      };
      final data = await (widget.loader?.call(query) ??
          BackendApiService.instance.getMap(
            '/admin/cancelled-sales',
            query: query,
          ));
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _failed = true;
          _loading = false;
        });
    }
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  String _text(dynamic v) => v == null || '$v'.isEmpty ? '—' : '$v';
  String _money(dynamic v) {
    final n = num.tryParse('$v') ?? 0;
    return '${n == n.roundToDouble() ? n.toInt() : n} ₸';
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse('$v');
    return d == null ? '—' : domlyDateText(d);
  }

  Widget _line(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SelectableText('${label.tr()}: ${_text(value)}'),
      );
  Future<void> _copy(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Телефон скопирован'.tr())));
  }

  String _packageStatus(dynamic value) =>
      ({
        'active': 'Активен'.tr(),
        'pending_payment': 'Ожидает оплаты'.tr(),
        'cancelled': 'Отменён'.tr(),
        'expired': 'Срок истёк'.tr(),
        'frozen': 'Заморожен'.tr(),
      })['$value'] ??
      _text(value);
  Widget _card(Map<String, dynamic> row) {
    final address = _map(row['address']), effects = _map(row['effects']);
    final phone = '${row['customer_phone'] ?? ''}',
        digits = phone.replaceAll(RegExp(r'\D'), '');
    final packageAddons =
        (row['package_addons'] as List? ?? []).map(_map).toList();
    final addons = (row['addons'] as List? ?? []).map(_map).toList();
    final orders = (row['package_orders'] as List? ?? []).map(_map).toList();
    final payments = (row['payments'] as List? ?? []).map(_map).toList();
    return Card(
      key: ValueKey('${row['kind']}:${row['id']}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  row['kind'] == 'payment'
                      ? '${'Отменённый счёт'.tr()} №${row['payment_number'] ?? row['id']}'
                      : '${'Отменённый заказ'.tr()} №${row['order_number'] ?? row['id']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(formatAdminDateTime(row['cancelled_at'])),
                if (row['created_by'] == 'bot')
                  Chip(label: Text('Оформил бот MonAI'.tr())),
              ],
            ),
            _line('Клиент', row['customer_name']),
            _line('Телефон клиента', phone),
            _line('Пакет', row['package_name']),
            _line(
              row['kind'] == 'payment' ? 'Сумма счёта' : 'Стоимость заказа',
              row['amount'] == null ? '—' : _money(row['amount']),
            ),
            _line(
              'Адрес',
              [
                address['city'],
                address['settlement'],
                address['street'],
                address['house'],
                if (address['apartment'] != null)
                  '${'Кв.'.tr()} ${address['apartment']}',
              ].where((v) => v != null && '$v'.isNotEmpty).join(', '),
            ),
            if (effects['scope'] == 'addons')
              Text(
                'Отменены допуслуги. Оплаченная уборка сохранена.'.tr(),
                style: const TextStyle(color: Colors.green),
              ),
            if (effects['retainedReason'] == 'other_payment_exists')
              Text(
                'Есть другая попытка оплаты. Пакет или заказ сохранён.'.tr(),
              ),
            if (effects['requiresReview'] == true)
              Text(
                'Требуется проверка: уборка уже начата или завершена.'.tr(),
                style: const TextStyle(color: Colors.deepOrange),
              ),
            Wrap(
              spacing: 12,
              children: [
                if (phone.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _copy(phone),
                    icon: const Icon(Icons.copy),
                    label: Text('Скопировать телефон'.tr()),
                  ),
                if (digits.length >= 10)
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:+$digits')),
                    icon: const Icon(Icons.call_outlined),
                    label: Text('Позвонить'.tr()),
                  ),
                if (digits.length >= 10)
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://wa.me/$digits'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text('Открыть WhatsApp'.tr()),
                  ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Вся информация'.tr()),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _line('Email', row['customer_email']),
                _line('Источник отмены', row['cancellation_source']),
                _line('Причина', row['reason']),
                _line('Номер плательщика Kaspi', row['invoice_phone']),
                _line('Способ оплаты', row['provider']),
                _line('Создан', formatAdminDateTime(row['payment_created_at'])),
                _line('Отменён', formatAdminDateTime(row['cancelled_at'])),
                _line('Бонусы в счёте', _money(row['bonus_amount'])),
                _line('Бонусы возвращены', _money(effects['bonusReturned'])),
                _line('Уборок в пакете', row['total_cleanings']),
                _line('Месяцев', row['months']),
                _line('Статус пакета', _packageStatus(row['package_status'])),
                _line(
                  'Площадь',
                  address['area'] == null ? '—' : '${address['area']} м²',
                ),
                _line(
                  'Подтверждённая площадь',
                  address['verified_area'] == null
                      ? '—'
                      : '${address['verified_area']} м²',
                ),
                _line('Подъезд', address['entrance']),
                _line('Этаж', address['floor']),
                _line('Домофон', address['intercom']),
                _line('Комментарий к адресу', address['access_comment']),
                if (row['order_id'] != null) ...[
                  _line('Номер заказа', row['order_number']),
                  _line('Дата уборки', _date(row['scheduled_date'])),
                  _line(
                    'Время уборки',
                    '${row['start_time'] ?? '—'} – ${row['end_time'] ?? '—'}',
                  ),
                  _line(
                    'Статус заказа',
                    orderStatusLabel('${row['order_status']}'),
                  ),
                  _line('Уборщица', row['cleaner_name']),
                  _line('Телефон уборщицы', row['cleaner_phone']),
                ],
                for (final a in addons)
                  _line(
                    'Допуслуга',
                    '${a['title']} · ${a['quantity']} × ${_money(a['price'])} · ${paymentStatusLabel('${a['status']}')}${a['paidSeparately'] == true ? ' · ${'Отдельная оплата'.tr()}' : ''}',
                  ),
                for (final a in packageAddons)
                  _line(
                    'Допуслуги пакета',
                    '${a['title'] ?? a['title_ru'] ?? a['name'] ?? a['id']} · ${a['quantity'] ?? 1} · ${_money(a['total'] ?? a['price'])}',
                  ),
                for (final o in orders)
                  _line(
                    'Уборка по пакету',
                    '№${o['number']} · ${_date(o['date'])} ${o['startTime'] ?? ''} · ${orderStatusLabel('${o['status']}')}',
                  ),
                for (final p in payments)
                  _line(
                    'Связанный платёж',
                    '№${p['number']} · ${_money(p['amount'])} · ${paymentStatusLabel('${p['status']}')}',
                  ),
                _line('ID платежа / записи', row['id']),
                _line('ID клиента', row['customer_id']),
                _line(
                  'ID покупки пакета',
                  row['customer_package_id'] ?? row['package_purchase_id'],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ExpansionTile(
            title: Text('Фильтры'.tr()),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final k in {
                    'all': 'Все',
                    'payment': 'Счета',
                    'order': 'Заказы',
                  }.entries)
                    ChoiceChip(
                      label: Text(k.value.tr()),
                      selected: _kind == k.key,
                      onSelected: (_) {
                        setState(() {
                          _kind = k.key;
                          _offset = 0;
                        });
                        _load();
                      },
                    ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${'Всего'.tr()}: $_total'),
                const Spacer(),
                IconButton(
                  tooltip: 'Обновить'.tr(),
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_failed)
            Text('Не удалось загрузить отменённые счета и заказы.'.tr()),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                      (_loading
                              ? 'Загрузка...'
                              : 'Отменённых счетов и заказов нет.')
                          .tr(),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _rows.map(_card).toList(),
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _loading || _offset == 0
                    ? null
                    : () {
                        _offset = (_offset - 30).clamp(0, _total).toInt();
                        _load();
                      },
                child: Text('Назад'.tr()),
              ),
              Text(
                '${_rows.isEmpty ? 0 : _offset + 1}–${_offset + _rows.length} / $_total',
              ),
              TextButton(
                onPressed: _loading || _offset + _rows.length >= _total
                    ? null
                    : () {
                        _offset += 30;
                        _load();
                      },
                child: Text('Далее'.tr()),
              ),
            ],
          ),
        ],
      );
}
