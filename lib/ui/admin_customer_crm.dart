import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../utils/admin_customer_data.dart';
import '../utils/admin_date_time.dart';
import '../utils/user_error_message.dart';
import '../localization/translation_controller.dart';

typedef CrmRequest = Future<Map<String, dynamic>> Function(String method,
    String path, Map<String, dynamic>? body, Map<String, String?>? query);
const crmStageLabels = {
  'new': 'Новый',
  'working': 'В работе',
  'purchased': 'Купил',
  'refused': 'Отказался',
  'processed': 'Отработан'
};

Future<Map<String, dynamic>> _request(String method, String path,
    Map<String, dynamic>? body, Map<String, String?>? query) {
  final api = BackendApiService.instance;
  if (method == 'POST') return api.postMap(path, body: body);
  if (method == 'PATCH') return api.patchMap(path, body: body);
  return api.getMap(path, query: query);
}

class AdminCustomerCrm extends StatefulWidget {
  const AdminCustomerCrm(
      {super.key,
      this.search = '',
      this.sort = 'newest',
      this.legacyStatus = 'Все',
      this.dateFrom,
      this.dateTo,
      this.filtersExpanded = false,
      this.cardBuilder,
      this.onExport,
      this.request});
  final String search, sort, legacyStatus;
  final DateTime? dateFrom, dateTo;
  final bool filtersExpanded;
  final Widget Function(BuildContext, Map<String, dynamic>, int)? cardBuilder;
  final Future<void> Function(List<Map<String, dynamic>>)? onExport;
  final CrmRequest? request;
  @override
  State<AdminCustomerCrm> createState() => _AdminCustomerCrmState();
}

class _AdminCustomerCrmState extends State<AdminCustomerCrm> {
  final _city = TextEditingController(),
      _house = TextEditingController(),
      _min = TextEditingController(),
      _max = TextEditingController();
  String _stage = 'all',
      _purchase = 'all',
      _account = 'all',
      _area = 'all',
      _notes = 'all',
      _profile = 'all',
      _sort = 'newest';
  List<Map<String, dynamic>> _rows = [];
  int _offset = 0, _total = 0, _generation = 0;
  bool _loading = false, _failed = false, _exporting = false;
  String? _saving;
  Timer? _poll, _debounce;
  CrmRequest get _call => widget.request ?? _request;
  void _preset() {
    _profile = 'all';
    _area = 'all';
    _account = 'all';
    if (widget.legacyStatus == 'Удалён с оплатами')
      _account = 'deleted_paid';
    else if (widget.legacyStatus == 'Удалён')
      _account = 'deleted';
    else if (widget.legacyStatus == 'Без адреса')
      _area = 'missing';
    else if (widget.legacyStatus == 'Заполнен')
      _profile = 'filled';
    else if (widget.legacyStatus == 'Новый') _profile = 'new';
  }

  @override
  void initState() {
    super.initState();
    _sort = widget.sort;
    _preset();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_loading) _load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant AdminCustomerCrm old) {
    super.didUpdateWidget(old);
    if (widget.search != old.search ||
        widget.sort != old.sort ||
        widget.dateFrom != old.dateFrom ||
        widget.dateTo != old.dateTo ||
        widget.legacyStatus != old.legacyStatus) {
      if (widget.sort != old.sort) _sort = widget.sort;
      if (widget.legacyStatus != old.legacyStatus) _preset();
      _changed();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _generation++;
    for (final c in [_city, _house, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String?> _query() => {
        'search': widget.search.trim(),
        'stage': _stage,
        'purchase': _purchase,
        'account': _account,
        'area': _area,
        'notes': _notes,
        'profile': _profile,
        'sort': _sort,
        'city': _city.text.trim(),
        'house': _house.text.trim(),
        'paidMin': _min.text.trim(),
        'paidMax': _max.text.trim(),
        'dateFrom': widget.dateFrom?.toUtc().toIso8601String(),
        'dateTo': widget.dateTo == null
            ? null
            : DateTime(widget.dateTo!.year, widget.dateTo!.month,
                    widget.dateTo!.day + 1)
                .subtract(const Duration(milliseconds: 1))
                .toUtc()
                .toIso8601String(),
        'limit': '30',
        'offset': '$_offset'
      };
  void _changed() {
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _offset = 0;
      _load();
    });
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      if (!silent) _failed = false;
    });
    try {
      final data = await _call('GET', '/admin/customer-crm', null, _query());
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _failed = true;
          _loading = false;
        });
    }
  }

  Future<void> _stageChanged(Map<String, dynamic> row, String stage) async {
    setState(() => _saving = '${row['id']}');
    try {
      await _call('PATCH', '/admin/customer-crm/${row['id']}',
          {'stage': stage, 'revision': row['crm_revision'] ?? 0}, null);
      if (mounted) await _load(silent: true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(UserErrorMessage.message(e))));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  void _openNotes(Map<String, dynamic> row) {
    showDialog<void>(
        context: context,
        builder: (_) => _CrmNotes(
            customer: row,
            request: _call,
            onChanged: () {
              if (mounted) _load(silent: true);
            }));
  }

  void _reset() {
    setState(() {
      _stage = 'all';
      _purchase = 'all';
      _account = 'all';
      _area = 'all';
      _notes = 'all';
      _profile = 'all';
      _sort = widget.sort;
      for (final c in [_city, _house, _min, _max]) {
        c.clear();
      }
    });
    _changed();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final query = _query(), rows = <String, Map<String, dynamic>>{};
    try {
      for (var offset = 0;; offset += 200) {
        final data = await _call('GET', '/admin/customer-crm', null,
            {...query, 'offset': '$offset', 'limit': '200'});
        final page = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final row in page) {
          rows['${row['id']}'] = mapAdminCustomer(row);
        }
        if (page.length < 200) break;
      }
      await widget.onExport?.call(rows.values.toList());
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(UserErrorMessage.message(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _select(String label, String value, Map<String, String> options,
          void Function(String) change) =>
      SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
              initialValue: value,
              key: ValueKey('$label:$value'),
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: label.tr(), border: const OutlineInputBorder()),
              items: options.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value.tr())))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => change(v));
                  _changed();
                }
              }));
  Widget _field(String label, TextEditingController c, {bool number = false}) =>
      SizedBox(
          width: 220,
          child: TextField(
              controller: c,
              keyboardType: number ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                  labelText: label.tr(), border: const OutlineInputBorder()),
              onChanged: (_) => _changed()));
  Widget _card(Map<String, dynamic> row, int index) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.cardBuilder != null)
              widget.cardBuilder!(context, mapAdminCustomer(row), index)
            else
              ListTile(
                  title: Text('${row['full_name'] ?? 'Клиент'}'),
                  subtitle: SelectableText('${row['phone'] ?? ''}')),
            const SizedBox(height: 8),
            Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String>(
                          initialValue: '${row['crm_stage'] ?? 'new'}',
                          key: ValueKey('${row['id']}:${row['crm_stage']}'),
                          isExpanded: true,
                          decoration: InputDecoration(
                              labelText: 'Этап работы'.tr(),
                              border: const OutlineInputBorder()),
                          items: crmStageLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value.tr())))
                              .toList(),
                          onChanged: _saving == '${row['id']}'
                              ? null
                              : (v) {
                                  if (v != null) _stageChanged(row, v);
                                })),
                  TextButton.icon(
                      onPressed: () => _openNotes(row),
                      icon: const Icon(Icons.note_alt_outlined),
                      label: Text(
                          '${'Заметки'.tr()} (${row['notes_count'] ?? 0})'))
                ]),
            if (row['latest_note'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SelectableText('${row['latest_note']}')),
            if (row['crm_updated_at'] != null)
              Text(
                  '${'Последнее изменение CRM'.tr()}: ${formatAdminDateTime(row['crm_updated_at'])}'),
          ])));
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${'Найдено клиентов'.tr()}: $_total'),
                  Text('Период — дата регистрации'.tr()),
                  if (widget.onExport != null)
                    OutlinedButton.icon(
                        onPressed: _exporting ? null : _export,
                        icon: const Icon(Icons.download_outlined),
                        label: Text('Экспорт CSV'.tr())),
                  IconButton(
                      tooltip: 'Обновить'.tr(),
                      onPressed: _loading ? null : () => _load(),
                      icon: const Icon(Icons.refresh))
                ])),
        if (widget.filtersExpanded)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .25),
            child: SingleChildScrollView(primary: false, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 10, runSpacing: 12, children: [
                _select(
                    'Заполненность профиля',
                    _profile,
                    {'all': 'Все', 'filled': 'Заполнен', 'new': 'Без имени'},
                    (v) => _profile = v),
                _select('Этап работы', _stage,
                    {'all': 'Все', ...crmStageLabels}, (v) => _stage = v),
                _select(
                    'Оплаты и покупки',
                    _purchase,
                    {
                      'all': 'Все',
                      'paid': 'Оплатили',
                      'never_paid': 'Не оплачивали',
                      'pending': 'Ожидают оплаты',
                      'cancelled': 'Отменяли счета',
                      'none': 'Без покупок и заявок'
                    },
                    (v) => _purchase = v),
                _select(
                    'Аккаунт',
                    _account,
                    {
                      'all': 'Все',
                      'active': 'Действующий',
                      'blocked': 'Заблокирован',
                      'deleted': 'Удалён',
                      'deleted_paid': 'Удалён с оплатами'
                    },
                    (v) => _account = v),
                _select(
                    'Площадь и адрес',
                    _area,
                    {
                      'all': 'Все',
                      'verified': 'Площадь подтверждена',
                      'unverified': 'Площадь не подтверждена',
                      'missing': 'Без адреса'
                    },
                    (v) => _area = v),
                _select(
                    'Заметки',
                    _notes,
                    {
                      'all': 'Все',
                      'with': 'Есть заметки',
                      'without': 'Нет заметок'
                    },
                    (v) => _notes = v),
                _select(
                    'Сортировка',
                    _sort,
                    {
                      'newest': 'Сначала новые',
                      'oldest': 'Сначала старые',
                      'name': 'По имени',
                      'spent': 'Больше оплат',
                      'activity': 'Последние изменения CRM'
                    },
                    (v) => _sort = v),
                _field('Город', _city),
                _field('Улица и дом', _house),
                _field('Сумма оплат от', _min, number: true),
                _field('Сумма оплат до', _max, number: true),
                TextButton(
                    onPressed: _reset, child: Text('Сбросить фильтры'.tr())),
              ])))),
        if (_loading) const LinearProgressIndicator(),
        if (_failed)
          Text('Не удалось загрузить CRM. Проверьте фильтры и повторите.'.tr()),
        Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                        (_loading ? 'Загрузка...' : 'Клиенты не найдены.')
                            .tr()))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (context, i) =>
                        _card(_rows[i], _offset + i + 1))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(
              onPressed: _loading || _offset == 0
                  ? null
                  : () {
                      _offset = (_offset - 30).clamp(0, _total).toInt();
                      _load();
                    },
              child: Text('Назад'.tr())),
          Text(
              '${_rows.isEmpty ? 0 : _offset + 1}–${_offset + _rows.length} / $_total'),
          TextButton(
              onPressed: _loading || _offset + _rows.length >= _total
                  ? null
                  : () {
                      _offset += 30;
                      _load();
                    },
              child: Text('Далее'.tr()))
        ]),
      ]);
}

class _CrmNotes extends StatefulWidget {
  const _CrmNotes(
      {required this.customer, required this.request, required this.onChanged});
  final Map<String, dynamic> customer;
  final CrmRequest request;
  final VoidCallback onChanged;
  @override
  State<_CrmNotes> createState() => _CrmNotesState();
}

class _CrmNotesState extends State<_CrmNotes> {
  final _text = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  Map<String, dynamic>? _editing;
  int _total = 0;
  bool _loading = true, _saving = false;
  String? _error;
  String get _root => '/admin/customer-crm/${widget.customer['id']}/notes';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final data = await widget.request('GET', _root, null,
          {'limit': '50', 'offset': more ? '${_notes.length}' : '0'});
      if (!mounted) return;
      setState(() {
        final rows = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _notes = more ? [..._notes, ...rows] : rows;
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = UserErrorMessage.message(e);
        });
    }
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.request(
          _editing == null ? 'POST' : 'PATCH',
          _editing == null ? _root : '$_root/${_editing!['id']}',
          {
            'body': _text.text.trim(),
            if (_editing != null) 'revision': _editing!['revision']
          },
          null);
      if (!mounted) return;
      _text.clear();
      _editing = null;
      widget.onChanged();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = UserErrorMessage.message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 40, vertical: 12),
      child: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(context).height * .85,
          child: Padding(
              padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(
                              '${'Заметки клиента'.tr()}: ${widget.customer['full_name'] ?? widget.customer['phone'] ?? ''}',
                              maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close))
                    ]),
                    Text('Видны только администраторам'.tr()),
                    if (_error != null)
                      SelectableText(_error!,
                          style: const TextStyle(color: Colors.red)),
                    if (_loading) const LinearProgressIndicator(),
                    Expanded(
                        child: ListView(children: [
                      for (final note in _notes)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText('${note['body']}'),
                                      Text(
                                          '${note['author_name'] ?? 'Администратор'} · ${formatAdminDateTime(note['created_at'])}'),
                                      if ((note['revision'] as num? ?? 1) > 1)
                                        Text(
                                            '${'Изменена'.tr()}: ${formatAdminDateTime(note['updated_at'])}'),
                                      TextButton(
                                          onPressed: _saving
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _editing = note;
                                                    _text.text =
                                                        '${note['body']}';
                                                  });
                                                },
                                          child: Text('Редактировать'.tr()))
                                    ]))),
                      if (!_loading && _notes.isEmpty)
                        Text('Заметок пока нет.'.tr()),
                      if (_notes.length < _total)
                        TextButton(
                            onPressed:
                                _loading ? null : () => _load(more: true),
                            child: Text('Показать ещё'.tr()))
                    ])),
                    TextField(
                        controller: _text,
                        minLines: 2,
                        maxLines: 3,
                        maxLength: 10000,
                        enabled: !_saving,
                        decoration: InputDecoration(
                            labelText: (_editing == null
                                    ? 'Новая заметка'
                                    : 'Редактирование заметки')
                                .tr(),
                            border: const OutlineInputBorder())),
                    Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                      if (_editing != null)
                        TextButton(
                            onPressed: () {
                              setState(() {
                                _editing = null;
                                _text.clear();
                              });
                            },
                            child: Text('Отменить правку'.tr())),
                      FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text((_editing == null
                                  ? 'Добавить заметку'
                                  : 'Сохранить правку')
                              .tr()))
                    ]),
                  ]))));
}
