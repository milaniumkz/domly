import 'dart:async';

import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerChecklistScreen extends StatefulWidget {
  const CleanerChecklistScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<CleanerChecklistScreen> createState() => _CleanerChecklistScreenState();
}

class _CleanerChecklistScreenState extends State<CleanerChecklistScreen> {
  final _noteController = TextEditingController();
  final _data = FirestoreDataService.instance;
  final _config = AppConfigService.instance;
  final Set<String> _completed = <String>{};
  final Set<String> _addons = <String>{};
  List<String> _orderedAddons = const <String>[];
  List<Map<String, dynamic>> _orderedAddonsDetailed =
      const <Map<String, dynamic>>[];
  StreamSubscription<Map<String, dynamic>?>? _checklistSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _templateSubscription;
  List<Map<String, dynamic>> _templateGroups = AppConfigService
      .defaultCleanerChecklistTemplates
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  bool _saving = false;
  bool _hasLocalChanges = false;
  bool _hydratedChecklist = false;
  bool _applyingChecklist = false;

  @override
  void initState() {
    super.initState();
    _noteController.addListener(() {
      if (!_applyingChecklist) {
        _hasLocalChanges = true;
      }
    });
    final orderId = widget.orderId.trim();
    if (orderId.isNotEmpty) {
      _checklistSubscription = _data
          .cleanerChecklistStream(orderId)
          .listen(_applySavedChecklist);
    }
    _templateSubscription = _config.cleanerChecklistTemplatesStream().listen((
      groups,
    ) {
      if (!mounted) return;
      setState(() {
        _templateGroups = groups
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _checklistSubscription?.cancel();
    _templateSubscription?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _applySavedChecklist(Map<String, dynamic>? checklist) {
    if (!mounted || checklist == null) {
      return;
    }
    if (_hydratedChecklist && _hasLocalChanges) {
      return;
    }
    final completed = ((checklist['completedTasks'] ?? const []) as List)
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    final addons = ((checklist['addons'] ?? const []) as List)
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    final note = (checklist['note'] ?? '').toString();
    setState(() {
      _completed
        ..clear()
        ..addAll(completed);
      _addons
        ..clear()
        ..addAll(addons);
      _applyingChecklist = true;
      if (_noteController.text != note) {
        _noteController.text = note;
      }
      _applyingChecklist = false;
      _hydratedChecklist = true;
      _hasLocalChanges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orderId.trim().isEmpty) {
      return _buildChecklistPicker();
    }
    return DomlyShell(
      child: SafeArea(
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
                          'Чек-лист уборки'.tr(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Отметьте выполненные базовые задачи и дополнительные услуги.'
                              .tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.cleanerScheduleSlotsStream(),
                builder: (context, slotsSnapshot) {
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _data.cleanerOrdersStream(),
                    builder: (context, ordersSnapshot) {
                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _data.cleanerPaidAddonRequestsForSlotStream(
                          widget.orderId,
                        ),
                        builder: (context, addonRequestsSnapshot) {
                          return StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _data.customerPackagesStream(),
                            builder: (context, packagesSnapshot) {
                              final assignments = _mergeAssignments(
                                slotsSnapshot.data ??
                                    const <Map<String, dynamic>>[],
                                ordersSnapshot.data ??
                                    const <Map<String, dynamic>>[],
                              );
                              final order = _mergePaidAddonRequestsIntoOrder(
                                _findOrderData(assignments),
                                addonRequestsSnapshot.data ??
                                    const <Map<String, dynamic>>[],
                              );
                              final orderedAddons = _addonLabels(order);
                              final baseTasks = _baseTasksForOrder(
                                order,
                                packagesSnapshot.data ??
                                    const <Map<String, dynamic>>[],
                              );
                              _orderedAddons = orderedAddons;
                              _orderedAddonsDetailed = _addonDetails(order);

                              return ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  24,
                                ),
                                children: [
                                  _baseTasksCard(order, baseTasks),
                                  const SizedBox(height: 14),
                                  if (orderedAddons.isNotEmpty) ...[
                                    _orderedAddonsCard(orderedAddons),
                                    const SizedBox(height: 14),
                                  ],
                                  _proposeAddonsCard(order),
                                  const SizedBox(height: 14),
                                  DomlyCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Комментарий'.tr(),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: DomlyColors.foreground,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: _noteController,
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Комментарий по уборке или инциденту',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 96),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: DomlyStickyActionBar(
                  child: DomlyPrimaryButton(
                    label: _saving ? 'Сохраняем...' : 'Сохранить чек-лист',
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _findOrderData(List<Map<String, dynamic>> orders) {
    for (final order in orders) {
      final ids = [
        order['id'],
        order['scheduleSlotId'],
        order['slotId'],
        order['sourceOrderId'],
        order['customerOrderId'],
        order['orderId'],
      ].map((value) => (value ?? '').toString().trim()).toSet();
      if (ids.contains(widget.orderId)) {
        return order;
      }
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _mergePaidAddonRequestsIntoOrder(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> paidRequests,
  ) {
    if (paidRequests.isEmpty) {
      return order;
    }
    final merged = Map<String, dynamic>.from(order);
    if ((merged['id'] ?? '').toString().trim().isEmpty) {
      merged['id'] = widget.orderId.trim();
    }

    final detailed = <Map<String, dynamic>>[..._addonDetails(merged)];
    final labels = <String>[..._addonLabels(merged)];

    void addDetailed(Object? value) {
      if (value is! List) return;
      for (final item in value) {
        if (item is Map) {
          final mapped = Map<String, dynamic>.from(item);
          final key = _addonIdentity(mapped);
          if (key.isEmpty ||
              detailed.any((existing) => _addonIdentity(existing) == key)) {
            continue;
          }
          detailed.add(mapped);
          final label = _addonLabel(mapped);
          if (label.isNotEmpty && !labels.contains(label)) {
            labels.add(label);
          }
        } else {
          final label = item.toString().trim();
          if (label.isNotEmpty && !labels.contains(label)) {
            labels.add(label);
          }
        }
      }
    }

    for (final request in paidRequests) {
      addDetailed(request['addonsDetailed']);
      addDetailed(request['separatePaymentAddons']);
      final simple = request['addons'];
      if (simple is List) {
        for (final item in simple) {
          final label = item is Map
              ? _addonLabel(item)
              : item.toString().trim();
          if (label.isNotEmpty && !labels.contains(label)) {
            labels.add(label);
          }
        }
      }
    }

    merged['addonsDetailed'] = detailed;
    merged['addons'] = labels;
    return merged;
  }

  List<Map<String, dynamic>> _mergeAssignments(
    List<Map<String, dynamic>> slots,
    List<Map<String, dynamic>> orders,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    void add(Map<String, dynamic> item) {
      final key = _slotTargetId(item);
      if (key.isEmpty) return;
      final existing = merged[key];
      merged[key] = {if (existing != null) ...existing, ...item};
    }

    for (final order in orders) {
      add(order);
    }
    for (final slot in slots) {
      add(slot);
    }
    return merged.values.toList();
  }

  Widget _buildChecklistPicker() {
    return DomlyShell(
      bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 2),
      child: SafeArea(
        child: Column(
          children: [
            DomlyHeader(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                children: [
                  domlyTopIconButton(
                    icon: Icons.arrow_back,
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacementNamed(
                          context,
                          '/cleaner/orders',
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Выберите уборку'.tr(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.cleanerScheduleSlotsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          DomlyColors.buttonPrimary,
                        ),
                      ),
                    );
                  }
                  final active =
                      (snapshot.data ?? const <Map<String, dynamic>>[]).where((
                          slot,
                        ) {
                          final status = (slot['status'] ?? '')
                              .toString()
                              .toLowerCase();
                          return status != 'completed' &&
                              status != 'canceled' &&
                              status != 'cancelled';
                        }).toList()
                        ..sort((a, b) => _slotDate(a).compareTo(_slotDate(b)));

                  if (active.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: DomlyEmptyStateCard(
                          title: 'Активных уборок нет',
                          subtitle:
                              'Когда у вас появится назначенная уборка, чек-лист можно будет открыть отсюда.',
                          icon: Icons.checklist_outlined,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: active.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final slot = active[index];
                      final slotId = _slotTargetId(slot);
                      return DomlyCard(
                        padding: const EdgeInsets.all(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: slotId.isEmpty
                              ? null
                              : () {
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/cleaner/checklist',
                                    arguments: {'orderId': slotId},
                                  );
                                },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _slotTitle(slot),
                                style: const TextStyle(
                                  color: DomlyColors.foreground,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                (slot['address'] ?? 'Адрес не указан')
                                    .toString(),
                                style: const TextStyle(
                                  color: DomlyColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Открыть чек-лист'.tr(),
                                    style: TextStyle(
                                      color: DomlyColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.chevron_right,
                                    color: DomlyColors.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _slotTargetId(Map<String, dynamic> slot) {
    for (final key in ['scheduleSlotId', 'slotId', 'id', 'customerOrderId']) {
      final value = (slot[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return '';
  }

  DateTime _slotDate(Map<String, dynamic> slot) {
    final value =
        slot['scheduledFor'] ?? slot['date'] ?? slot['scheduledDateKey'];
    if (value is DateTime) return value;
    if (value is Timestamp) {
      return value.toDate();
    }
    final parsed = DateTime.tryParse((value ?? '').toString());
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _slotTitle(Map<String, dynamic> slot) {
    final date = _slotDate(slot);
    final dateText = date.millisecondsSinceEpoch == 0
        ? 'Дата не указана'
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final time = (slot['time'] ?? 'Время не указано').toString();
    return '$dateText · $time';
  }

  List<Map<String, dynamic>> _addonDetails(Map<String, dynamic> data) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    void append(Object? value) {
      if (value is! List) return;
      for (final item in value) {
        if (item is Map) {
          final mapped = Map<String, dynamic>.from(item);
          final identity = [
            mapped['key'],
            mapped['label'],
            mapped['title'],
            mapped['name'],
            mapped['quantity'],
            mapped['separatePayment'],
            mapped['separate'],
          ].map((part) => (part ?? '').toString()).join('|');
          if (!_isStandardCleaningTask(_addonLabel(mapped)) &&
              seen.add(identity)) {
            result.add(mapped);
          }
        }
      }
    }

    append(data['addonsDetailed']);
    append(data['separatePaymentAddons']);
    return result;
  }

  String _addonIdentity(Map<dynamic, dynamic> mapped) {
    return [
      mapped['key'],
      mapped['label'],
      mapped['title'],
      mapped['name'],
      mapped['quantity'],
      mapped['separatePayment'],
      mapped['separate'],
    ].map((part) => (part ?? '').toString().trim()).join('|');
  }

  String _addonLabel(Map<dynamic, dynamic> item) {
    var text =
        (item['label'] ??
                item['title'] ??
                item['name'] ??
                item['optionLabel'] ??
                item['key'] ??
                '')
            .toString()
            .trim();
    if (text.isEmpty) return '';
    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
    if (qty > 1 && !text.contains('×')) {
      text = '$text × $qty';
    }
    final separate =
        item['separatePayment'] == true || item['separate'] == true;
    if (separate && !text.contains('отдельно')) {
      text = '$text · оплата отдельно';
    }
    return text;
  }

  List<String> _addonLabels(Map<String, dynamic> data) {
    final labels = <String>[];
    void addLabel(Object? value, {Object? quantity, bool separate = false}) {
      var text = (value ?? '').toString().trim();
      if (text.isEmpty) return;
      final qty = (quantity as num?)?.toInt() ?? 1;
      if (qty > 1 && !text.contains('×')) {
        text = '$text × $qty';
      }
      if (separate && !text.contains('отдельно')) {
        text = '$text · оплата отдельно';
      }
      if (_isStandardCleaningTask(text)) {
        return;
      }
      if (!labels.contains(text)) {
        labels.add(text);
      }
    }

    void addDetailed(Object? value) {
      if (value is! List) return;
      for (final item in value) {
        if (item is Map) {
          addLabel(
            item['label'] ??
                item['title'] ??
                item['name'] ??
                item['optionLabel'] ??
                item['key'],
            quantity: item['quantity'],
            separate:
                item['separatePayment'] == true || item['separate'] == true,
          );
        } else {
          addLabel(item);
        }
      }
    }

    addDetailed(data['addonsDetailed']);
    addDetailed(data['separatePaymentAddons']);

    final simple = data['addons'];
    if (simple is List) {
      for (final item in simple) {
        if (item is Map) {
          addLabel(
            item['label'] ?? item['title'] ?? item['name'] ?? item['key'],
            quantity: item['quantity'],
          );
        } else {
          addLabel(item);
        }
      }
    }
    return labels;
  }

  bool _isStandardCleaningTask(String value) {
    final text = value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
        .trim();
    const standardTasks = {
      'протереть пыль',
      'пропылесосить',
      'вымыть пол',
      'помыть пол',
      'очистить кухню',
      'убрать кухню',
      'очистить санузел',
      'убрать санузел',
      'поддерживающая уборка',
      'стоимость зависит от площади квартиры',
    };
    return standardTasks.contains(text);
  }

  Widget _orderedAddonsCard(List<String> orderedAddons) {
    return DomlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Доп. услуги из заказа'.tr(),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Отметьте выполненные доп. услуги по этому заказу.'.tr(),
            style: TextStyle(fontSize: 13, color: DomlyColors.muted),
          ),
          const SizedBox(height: 12),
          ...orderedAddons.map(
            (addon) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _addonTile(addon, 'Заказано клиентом'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proposeAddonsCard(Map<String, dynamic> order) {
    return DomlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Предложить доп. услуги'.tr(),
            style: TextStyle(
              color: DomlyColors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Выберите допы, которые клиент должен согласовать и оплатить.'.tr(),
            style: TextStyle(color: DomlyColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: DomlySecondaryButton(
              label: 'Выбрать допы для клиента',
              onPressed: () => _showAddonRequestSheet(order),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseTasksCard(Map<String, dynamic> order, List<String> tasks) {
    final packageName = (order['package'] ?? order['packageName'] ?? '')
        .toString()
        .trim();
    return DomlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Основные позиции уборки'.tr(),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (packageName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Пакет: $packageName'.tr(),
              style: const TextStyle(fontSize: 13, color: DomlyColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _baseTile(task),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _baseTasksForOrder(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> packages,
  ) {
    final package = _packageForOrder(order, packages);
    final packageTasks = <String>[
      if (package != null) ..._extractPackageChecklistItems(package),
      ..._extractPackageChecklistItems(order),
    ];
    final result = <String>[];
    void add(String value) {
      final text = value.trim();
      if (text.isEmpty || _isPackageMetaText(text)) {
        return;
      }
      if (!result.any((item) => item.toLowerCase() == text.toLowerCase())) {
        result.add(text);
      }
    }

    for (final task in packageTasks) {
      add(task);
    }
    if (result.isEmpty) {
      for (final task in _baseTemplateTasks()) {
        add(task);
      }
    }
    return result.isEmpty
        ? const [
            'Протереть пыль',
            'Пропылесосить',
            'Вымыть пол',
            'Очистить кухню',
            'Очистить санузел',
          ]
        : result;
  }

  Map<String, dynamic>? _packageForOrder(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> packages,
  ) {
    final packageId = (order['packageId'] ?? order['package_id'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final packageName = (order['package'] ?? order['packageName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    for (final package in packages) {
      final id = (package['id'] ?? package['key'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final name = (package['name'] ?? package['title'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (packageId.isNotEmpty && id == packageId) {
        return package;
      }
      if (packageName.isNotEmpty && name == packageName) {
        return package;
      }
    }
    return null;
  }

  List<String> _extractPackageChecklistItems(Map<String, dynamic> data) {
    final result = <String>[];
    void append(Object? value) {
      if (value is List) {
        for (final item in value) {
          append(item);
        }
        return;
      }
      if (value is Map) {
        append(
          value['label'] ??
              value['title'] ??
              value['name'] ??
              value['text'] ??
              value['description'],
        );
        return;
      }
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        result.add(text);
      }
    }

    for (final key in const [
      'checklistItems',
      'checklist',
      'standardTasks',
      'standardServices',
      'includedServices',
      'included',
      'includes',
      'services',
      'features',
      'whatIncluded',
      'whatIncludes',
      'items',
    ]) {
      append(data[key]);
    }
    return result;
  }

  List<String> _baseTemplateTasks() {
    for (final group in _templateGroups) {
      final key = (group['key'] ?? '').toString();
      if (key != 'base_tasks') {
        continue;
      }
      return ((group['items'] ?? const []) as List)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  bool _isPackageMetaText(String value) {
    final text = value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
        .trim();
    return text.contains('стоимость зависит') ||
        text.contains('площад') ||
        text.contains('цена') ||
        text.contains('скидк') ||
        text.contains('оплата отдельно');
  }

  Widget _baseTile(String task) {
    return CheckboxListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      tileColor: DomlyColors.backgroundSoft,
      value: _completed.contains(task),
      onChanged: (value) {
        setState(() {
          _hasLocalChanges = true;
          if (value == true) {
            _completed.add(task);
          } else {
            _completed.remove(task);
          }
        });
      },
      title: Text(task),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _addonTile(String task, String description) {
    return CheckboxListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      tileColor: DomlyColors.backgroundSoft,
      value: _addons.contains(task),
      onChanged: (value) {
        setState(() {
          _hasLocalChanges = true;
          if (value == true) {
            _addons.add(task);
          } else {
            _addons.remove(task);
          }
        });
      },
      title: Text(task),
      subtitle: Text(
        description.isEmpty
            ? 'Отметьте, если предложено или выполнено'
            : description,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Future<void> _showAddonRequestSheet(Map<String, dynamic> order) async {
    final slotId = _slotTargetId(order).isNotEmpty
        ? _slotTargetId(order)
        : widget.orderId.trim();
    if (slotId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не удалось открыть допы',
        subtitle: 'Не найден ID текущей уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }

    final groups = await _config.getAddonGroupConfigs();
    if (!mounted) return;

    final quantities = <String, int>{};
    final labels = <String, String>{};
    final supportsQuantity = <String, bool>{};
    final separatePayment = <String, bool>{};
    for (final group in groups) {
      final items = ((group['items'] ?? const []) as List).whereType<Map>();
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw);
        final key = (item['key'] ?? '').toString();
        if (key.isEmpty || item['isActive'] == false) continue;
        labels[key] = (item['label'] ?? key).toString();
        supportsQuantity[key] = item['supportsQuantity'] == true;
        separatePayment[key] = item['separatePayment'] == true;
      }
    }

    final noteController = TextEditingController();
    var submitting = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selected = quantities.entries
                .where((entry) => entry.value > 0)
                .map(
                  (entry) => <String, dynamic>{
                    'key': entry.key,
                    'label': labels[entry.key] ?? entry.key,
                    'quantity': entry.value,
                    'separate': separatePayment[entry.key] == true,
                    'separatePayment': separatePayment[entry.key] == true,
                  },
                )
                .toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.88,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
                          children: [
                            Text(
                              'Допы для согласования'.tr(),
                              style: TextStyle(
                                color: DomlyColors.foreground,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Клиент увидит запрос. После оплаты и подтверждения админом допы появятся в списке работ.'
                                  .tr(),
                              style: TextStyle(
                                color: DomlyColors.muted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...groups.map((group) {
                              final items =
                                  ((group['items'] ?? const []) as List)
                                      .whereType<Map>()
                                      .where(
                                        (item) => (item['key'] ?? '')
                                            .toString()
                                            .isNotEmpty,
                                      )
                                      .where(
                                        (item) => item['isActive'] != false,
                                      )
                                      .toList();
                              if (items.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: DomlyCard(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (group['label'] ??
                                                group['key'] ??
                                                'Допы')
                                            .toString(),
                                        style: const TextStyle(
                                          color: DomlyColors.foreground,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...items.map((raw) {
                                        final item = Map<String, dynamic>.from(
                                          raw,
                                        );
                                        final key = (item['key'] ?? '')
                                            .toString();
                                        final quantity = quantities[key] ?? 0;
                                        final hasQuantity =
                                            supportsQuantity[key] == true;
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      labels[key] ?? key,
                                                      style: const TextStyle(
                                                        color: DomlyColors
                                                            .foreground,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (separatePayment[key] ==
                                                        true)
                                                      Text(
                                                        'Оплата отдельно'.tr(),
                                                        style: TextStyle(
                                                          color:
                                                              DomlyColors.muted,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              if (hasQuantity) ...[
                                                IconButton(
                                                  onPressed: quantity <= 0
                                                      ? null
                                                      : () => setModalState(() {
                                                          quantities[key] =
                                                              quantity - 1;
                                                        }),
                                                  icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                  ),
                                                ),
                                                Text('$quantity'),
                                                IconButton(
                                                  onPressed: () =>
                                                      setModalState(() {
                                                        quantities[key] =
                                                            quantity + 1;
                                                      }),
                                                  icon: const Icon(
                                                    Icons.add_circle_outline,
                                                  ),
                                                ),
                                              ] else
                                                Switch(
                                                  value: quantity > 0,
                                                  onChanged: (value) =>
                                                      setModalState(() {
                                                        quantities[key] = value
                                                            ? 1
                                                            : 0;
                                                      }),
                                                ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            TextField(
                              controller: noteController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Комментарий клиенту',
                                hintText:
                                    'Например: холодильник сильно загрязнен',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 18,
                              color: Color(0x1A000000),
                              offset: Offset(0, -6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DomlyPrimaryButton(
                              label: 'Отправить клиенту',
                              isLoading: submitting,
                              onPressed: selected.isEmpty || submitting
                                  ? null
                                  : () async {
                                      setModalState(() => submitting = true);
                                      try {
                                        await _data.submitCleanerAddonRequest(
                                          slotId: slotId,
                                          addonsDetailed: selected,
                                          note: noteController.text.trim(),
                                        );
                                        if (!mounted || !sheetContext.mounted) {
                                          return;
                                        }
                                        Navigator.pop(sheetContext);
                                        showDomlySnackBar(
                                          this.context,
                                          title: 'Допы отправлены клиенту',
                                          subtitle:
                                              'Они появятся в чек-листе после согласования и оплаты.',
                                          type: DomlySnackBarType.success,
                                        );
                                      } catch (error) {
                                        setModalState(() => submitting = false);
                                        if (!mounted) return;
                                        showDomlySnackBar(
                                          this.context,
                                          title: 'Не удалось отправить допы',
                                          subtitle: '$error',
                                          type: DomlySnackBarType.error,
                                        );
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    noteController.dispose();
  }

  Future<void> _save() async {
    try {
      setState(() => _saving = true);
      await _data.saveCleanerChecklist(
        orderId: widget.orderId,
        completedTasks: _completed.toList(),
        addons: _addons.toList(),
        orderedAddons: _orderedAddons,
        addonsDetailed: _orderedAddonsDetailed,
        note: _noteController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Чек-лист сохранен',
        type: DomlySnackBarType.success,
      );
      _hasLocalChanges = false;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDomlySnackBar(
        context,
        title: 'Не удалось сохранить чек-лист',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }
}
