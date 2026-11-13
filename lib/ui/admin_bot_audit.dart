import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../localization/translation_controller.dart';
import '../utils/admin_date_time.dart';

typedef BotAuditLoader = Future<List<Map<String, dynamic>>> Function(
    Map<String, String?> query);
typedef BotAuditDetailsLoader = Future<Map<String, dynamic>> Function(
    String id);

class AdminBotAudit extends StatefulWidget {
  const AdminBotAudit({
    super.key,
    this.search = '',
    this.loader,
    this.detailsLoader,
  });
  final String search;
  final BotAuditLoader? loader;
  final BotAuditDetailsLoader? detailsLoader;
  @override
  State<AdminBotAudit> createState() => _AdminBotAuditState();
}

class _AdminBotAuditState extends State<AdminBotAudit> {
  static const _pageSize = 30;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _failed = false, _hasMore = false;
  int _offset = 0, _generation = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminBotAudit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.search != oldWidget.search) {
      _timer?.cancel();
      _generation++;
      _timer = Timer(const Duration(milliseconds: 250), () => _load(offset: 0));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    super.dispose();
  }

  Future<void> _load({int? offset}) async {
    final generation = ++_generation, next = offset ?? _offset;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final query = <String, String?>{
        'search': widget.search.trim(),
        'limit': '$_pageSize',
        'offset': '$next',
      };
      final rows = await (widget.loader?.call(query) ??
          BackendApiService.instance.getList(
            '/admin/bot-actions',
            query: query,
          ));
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = rows;
        _offset = next;
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  void _open(Map<String, dynamic> row) {
    showDialog<void>(
      context: context,
      builder: (_) => _BotActionDetails(
        id: '${row['id']}',
        title: '${row['title'] ?? 'Действие бота'}',
        loader: widget.detailsLoader,
      ),
    );
  }

  Widget _record(Map<String, dynamic> row) {
    final customer = _map(row['customer']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Бот MooonAI'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Chip(label: Text('${row['resultLabel'] ?? 'Выполнено'}')),
                Text(formatAdminDateTime(row['createdAt'])),
              ],
            ),
            Text(
              '${row['title'] ?? 'Действие бота'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              customer.isEmpty
                  ? 'Общее действие, без привязки к клиенту.'.tr()
                  : '${'Клиент'.tr()}: ${customer['name'] ?? customer['id']}',
            ),
            if (customer['phone'] != null)
              SelectableText('${customer['phone']}'),
            if (row['amount'] != null)
              Text('${'Сумма'.tr()}: ${row['amount']} ₸'),
            if (row['errorMessage'] != null) Text('${row['errorMessage']}'),
            if (row['errorCode'] != null)
              Text('${'Код ошибки'.tr()}: ${row['errorCode']}'),
            TextButton.icon(
              onPressed: () => _open(row),
              icon: const Icon(Icons.open_in_new),
              label: Text('Открыть'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : () => _load(offset: 0),
              icon: const Icon(Icons.refresh),
              label: Text('Обновить'.tr()),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            Column(
              children: [
                Text('Не удалось загрузить журнал бота.'.tr()),
                TextButton(onPressed: _load, child: Text('Повторить'.tr())),
              ],
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Действий бота пока нет.'.tr()),
            )
          else
            ..._rows.map(_record),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _loading || _offset == 0
                    ? null
                    : () => _load(
                          offset:
                              (_offset - _pageSize).clamp(0, _offset).toInt(),
                        ),
                child: Text('Назад'.tr()),
              ),
              Text('${'Страница'.tr()} ${_offset ~/ _pageSize + 1}'),
              TextButton(
                onPressed: _loading || _failed || !_hasMore
                    ? null
                    : () => _load(offset: _offset + _pageSize),
                child: Text('Далее'.tr()),
              ),
            ],
          ),
        ],
      );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _status(dynamic value) {
  const labels = {
    'paid': 'Оплачен',
    'pending': 'Ожидает оплаты',
    'invoice_requested': 'Счёт запрошен',
    'pending_payment': 'Ожидает оплаты',
    'active': 'Активен',
    'rejected': 'Отклонён',
    'cancelled': 'Отменён',
    'refunded': 'Возвращён',
    'pending_assignment': 'Ищем уборщицу',
    'waiting_cleaner': 'Ищем уборщицу',
    'assigned': 'Исполнитель назначен',
    'start_pending': 'Ожидает подтверждения начала',
    'completion_pending': 'Ожидает подтверждения завершения',
    'finish_pending': 'Ожидает подтверждения завершения',
    'draft': 'Черновик',
    'frozen': 'Заморожен',
    'cancelled_by_customer': 'Отменён клиентом',
    'in_progress': 'Уборка идёт',
    'completed': 'Завершён',
    'expired': 'Срок истёк',
    'kaspi': 'Kaspi.kz',
    'bcc': 'Банк BCC',
    'bonus': 'Бонусы',
    'manual': 'Вручную',
  };
  return (labels['$value'] ?? 'Не указан').tr();
}

class _BotActionDetails extends StatefulWidget {
  const _BotActionDetails({required this.id, required this.title, this.loader});
  final String id, title;
  final BotAuditDetailsLoader? loader;
  @override
  State<_BotActionDetails> createState() => _BotActionDetailsState();
}

class _BotActionDetailsState extends State<_BotActionDetails> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() =>
      widget.loader?.call(widget.id) ??
      BackendApiService.instance.getMap('/admin/bot-actions/${widget.id}');
  Widget _line(String title, dynamic value) => value == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SelectableText('${title.tr()}: $value'),
        );
  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.tr(),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            ...children,
          ],
        ),
      );
  Widget _payment(String title, Map<String, dynamic> p) => p.isEmpty
      ? const SizedBox.shrink()
      : _section(title, [
          _line('Номер платежа', '${p['id']}'),
          _line(
            'Сумма к оплате',
            p['amount'] == null ? null : '${p['amount']} ₸',
          ),
          _line(
            'Бонусами',
            p['bonus_amount'] == null ? null : '${p['bonus_amount']} ₸',
          ),
          _line('Статус', _status(p['status'])),
          _line('Способ оплаты', _status(p['provider'])),
          if (p['paid_at'] != null)
            _line('Оплачен', formatAdminDateTime(p['paid_at'])),
        ]);
  Widget _content(Map<String, dynamic> data) {
    final event = _map(data['event']),
        customer = _map(data['customer']),
        order = _map(data['order']),
        address = _map(data['address']),
        cleaner = _map(data['cleaner']),
        purchase = _map(data['package']),
        contextData = _map(data['context']),
        snapshot = _map(data['snapshot']),
        quote = _map(snapshot['quote']);
    final contextLabels = {
      'date': 'Выбранная дата',
      'startTime': 'Выбранное начало',
      'area': 'Площадь, м²',
      'cleaningsPerMonth': 'Уборок в месяц',
      'packageId': 'Тариф',
      'customerPackageId': 'Пакет клиента',
      'addressId': 'Адрес клиента',
      'paymentId': 'Платёж',
      'orderId': 'Заказ',
      'scheduledAt': 'Время проверки площади',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Действие бота', [
          _line('Действие', event['title']),
          _line('Когда', formatAdminDateTime(event['createdAt'])),
          _line('Результат', event['resultLabel']),
          _line('Причина', event['errorMessage']),
          _line('Код ошибки', event['errorCode']),
          _line('Номер запроса', event['requestId']),
        ]),
        if (customer.isNotEmpty)
          _section('Клиент', [
            _line('Имя', customer['name']),
            _line('Телефон', customer['phone']),
            _line('Номер клиента', customer['id']),
          ])
        else
          Text('Это действие не было связано с конкретным клиентом.'.tr()),
        if (quote.isNotEmpty)
          _section('Расчёт стоимости', [
            _line(
              'Рассчитанная сумма',
              quote['monthlyPrice'] == null
                  ? null
                  : '${quote['monthlyPrice']} ₸',
            ),
            _line('Количество уборок', quote['cleaningCount']),
            _line('Площадь, м²', quote['area']),
          ]),
        if (contextData.isNotEmpty)
          _section(
            'Что запросил бот',
            contextLabels.entries
                .where((e) => contextData[e.key] != null)
                .map((e) => _line(e.value, contextData[e.key]))
                .toList(),
          ),
        if (purchase.isNotEmpty)
          _section('Пакет клиента', [
            _line('Название', purchase['name']),
            _line('Номер пакета', purchase['id']),
            _line('Всего уборок', purchase['totalCleanings']),
            _line('Доступно сейчас', purchase['availableCleanings']),
            _line('Текущий статус', _status(purchase['status'])),
          ]),
        if (order.isNotEmpty)
          _section('Связанный заказ', [
            _line('Номер заказа', order['numeric_id'] ?? order['id']),
            _line('Дата уборки', formatAdminDateTime(order['scheduled_date'])),
            _line('Начало уборки', order['start_time']),
            _line('Окончание уборки', order['end_time']),
            _line('Текущий статус', _status(order['status'])),
            _line(
              'Текущее назначение',
              cleaner['name'] ?? 'Исполнитель не назначен'.tr(),
            ),
            _line('Телефон исполнителя', cleaner['phone']),
            _line(
              'Допуслуги',
              order['addon_amount'] == null
                  ? null
                  : '${order['addon_amount']} ₸',
            ),
          ]),
        if (address.isNotEmpty)
          _section('Адрес уборки', [
            _line(
              'Адрес',
              [
                address['city'],
                address['settlement'],
                address['street'],
                address['house'],
                if (address['apartment'] != null)
                  '${'Квартира'.tr()} ${address['apartment']}',
              ].where((v) => v != null && '$v'.isNotEmpty).join(', '),
            ),
            _line('Площадь, м²', address['verified_area'] ?? address['area']),
          ]),
        _payment('Связанный платёж', _map(data['payment'])),
        _payment('Платёж за пакет', _map(data['packagePayment'])),
        if (_map(snapshot['payment']).isNotEmpty)
          _section('На момент действия бота', [
            _line(
                'Статус оплаты', _status(_map(snapshot['payment'])['status'])),
            _line(
                'Сумма',
                _map(snapshot['payment'])['amount'] == null
                    ? null
                    : '${_map(snapshot['payment'])['amount']} ₸'),
          ]),
        if ((data['addons'] as List? ?? []).isNotEmpty)
          _section(
              'Дополнительные услуги',
              (data['addons'] as List).map((item) {
                final a = _map(item);
                return _line(
                    '${a['name']} × ${a['quantity']}',
                    a['paid_separately'] == true
                        ? 'Оплачивается отдельно специалистам'.tr()
                        : '${a['price']} ₸');
              }).toList()),
        if ((data['requestedAddons'] as List? ?? []).isNotEmpty)
          _section(
              'Что выбрал бот',
              (data['requestedAddons'] as List).map((item) {
                final a = _map(item);
                return _line('${a['name']}', a['quantity']);
              }).toList()),
        if (data['note'] != null) Text('${data['note']}'),
        if (data['detailsAvailable'] != true)
          Text(
            'Подробности этой старой операции не сохранились. Сумму или клиента восстановить достоверно нельзя.'
                .tr(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 720,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              if (snapshot.hasError)
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Не удалось загрузить подробности.'.tr()),
                    TextButton(
                      onPressed: () => setState(() => _future = _fetch()),
                      child: Text('Повторить'.tr()),
                    ),
                  ],
                );
              return SingleChildScrollView(
                  child: _content(snapshot.data ?? {}));
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть'.tr()),
          ),
        ],
      );
}
