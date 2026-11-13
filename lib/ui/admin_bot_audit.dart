import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../localization/translation_controller.dart';
import '../utils/admin_date_time.dart';

typedef BotAuditLoader = Future<List<Map<String, dynamic>>> Function(Map<String, String?> query);

class AdminBotAudit extends StatefulWidget {
  const AdminBotAudit({super.key, this.search = '', this.loader});
  final String search;
  final BotAuditLoader? loader;
  @override
  State<AdminBotAudit> createState() => _AdminBotAuditState();
}

class _AdminBotAuditState extends State<AdminBotAudit> {
  static const _pageSize = 30;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _failed = false, _hasMore = false;
  int _offset = 0, _generation = 0;
  Timer? _searchTimer;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant AdminBotAudit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.search != oldWidget.search) {
      _searchTimer?.cancel();
      _generation++;
      _searchTimer = Timer(const Duration(milliseconds: 250), () => _load(offset: 0));
    }
  }

  Future<void> _load({int? offset}) async {
    final generation = ++_generation;
    final nextOffset = offset ?? _offset;
    setState(() { _loading = true; _failed = false; });
    try {
      final query = <String, String?>{
        'search': widget.search.trim().isEmpty ? 'MooonAI' : widget.search.trim(),
        'limit': '$_pageSize', 'offset': '$nextOffset',
      };
      final rows = await (widget.loader?.call(query) ??
        BackendApiService.instance.getList('/admin/audit', query: query));
      if (!mounted || generation != _generation) return;
      setState(() { _rows = rows.where((row) => row['payload'] is Map && row['payload']['actorKind'] == 'bot').toList(); _hasMore = rows.length == _pageSize; _offset = nextOffset; _loading = false; });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  void dispose() { _searchTimer?.cancel(); _generation++; super.dispose(); }

  String _operation(String action) {
    final key = action.replaceFirst('bot.moon-ai.', '');
    final labels = <String, String>{
      'package_purchase': 'Оформление пакета и счёта'.tr(),
      'payment_verify': 'Проверка оплаты'.tr(),
      'order_create': 'Бронирование уборки'.tr(),
      'available_slots': 'Проверка свободного времени'.tr(),
      'customer': 'Проверка клиента'.tr(),
      'quote': 'Расчёт стоимости'.tr(),
      'catalog': 'Просмотр тарифов'.tr(),
      'area.confirmed_by_bot': 'Подтверждение площади'.tr(),
      'quality_check.visit_requested_by_bot': 'Запись на проверку площади'.tr(),
      'payment.webhook.moon_ai_kaspi': 'Подтверждение от платёжного сервиса'.tr(),
    };
    return labels[key] ?? action;
  }

  Widget _record(Map<String, dynamic> row) {
    final payload = row['payload'] is Map ? Map<String, dynamic>.from(row['payload'] as Map) : <String, dynamic>{};
    final failed = payload['result'] == 'error';
    final result = failed ? 'Ошибка'.tr() : payload['replay'] == true ? 'Повтор запроса'.tr() : 'Выполнено'.tr();
    final client = row['customer_name'] ?? payload['customerId'] ?? '—';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Бот MooonAI'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
            Chip(label: Text(result), avatar: Icon(failed ? Icons.error_outline : Icons.check_circle_outline, size: 18)),
            Text(formatAdminDateTime(row['created_at'])),
          ]),
          Text(_operation((row['action'] ?? '').toString()), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SelectableText('${'Клиент'.tr()}: $client'),
          if (row['customer_phone'] != null) SelectableText(row['customer_phone'].toString()),
          if (payload['code'] != null) Text('${'Код ошибки'.tr()}: ${payload['code']}'),
          if (payload['requestId'] != null) SelectableText('${'Запрос'.tr()}: ${payload['requestId']}'),
          SelectableText('${row['entity_type'] ?? ''}: ${row['entity_id'] ?? ''}'),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: _loading ? null : () => _load(offset: 0),
        icon: const Icon(Icons.refresh), label: Text('Обновить'.tr()))),
      if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_failed) Column(children: [
        Text('Не удалось загрузить журнал бота.'.tr()),
        TextButton(onPressed: () => _load(), child: Text('Повторить'.tr())),
      ])
      else if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('Действий бота пока нет.'.tr()))
      else ..._rows.map(_record),
      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton(onPressed: _loading || _offset == 0 ? null : () => _load(offset: (_offset - _pageSize).clamp(0, _offset).toInt()),
          child: Text('Назад'.tr())),
        Text('${'Страница'.tr()} ${_offset ~/ _pageSize + 1}'),
        TextButton(onPressed: _loading || _failed || !_hasMore ? null : () => _load(offset: _offset + _pageSize),
          child: Text('Далее'.tr())),
      ]),
    ]);
  }
}
