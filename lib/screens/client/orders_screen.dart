import 'dart:async';

import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../app/debug_session.dart';
import '../../services/app_config_service.dart';
import '../../services/call_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/payment_link_service.dart';
import '../common/kaspi_invoice_request_dialog.dart';
import '../../ui/domly_ui.dart';
import '../../ui/info_dialog.dart';
import '../../utils/bonus_policy_utils.dart';
import '../../utils/order_display.dart';
import '../../utils/user_error_message.dart';
import '../../localization/translation_controller.dart';

class _OrderAddonItemDef {
  const _OrderAddonItemDef({
    required this.key,
    required this.label,
    this.supportsQuantity = false,
    this.note,
    this.shortInfo,
    this.fullInfo,
    this.features = const <String>[],
    this.separatePayment = false,
    this.durationMinutes = 15,
  });

  final String key;
  final String label;
  final bool supportsQuantity;
  final String? note;
  final String? shortInfo;
  final String? fullInfo;
  final List<String> features;
  final bool separatePayment;
  final int durationMinutes;

  String? get infoText => shortInfo ?? note;
}

class _OrderAddonGroupDef {
  const _OrderAddonGroupDef({required this.label, required this.items});

  final String label;
  final List<_OrderAddonItemDef> items;
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  static const _fallbackAddonGroups = <_OrderAddonGroupDef>[
    _OrderAddonGroupDef(
      label: 'Окна и стекла',
      items: [
        _OrderAddonItemDef(
          key: 'window_standard',
          label: 'Мытье окон стандарт',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'window_panorama',
          label: 'Панорама',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'window_mosquito',
          label: 'Мытье москитных сеток',
          supportsQuantity: true,
        ),
      ],
    ),
    _OrderAddonGroupDef(
      label: 'Балкон',
      items: [
        _OrderAddonItemDef(
          key: 'balcony_window_standard',
          label: 'Мытье окон стандарт',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'balcony_panorama',
          label: 'Панорама',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'balcony_balcony',
          label: 'Балкон',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'balcony_loggia',
          label: 'Лоджия',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'balcony_terrace',
          label: 'Терасса',
          supportsQuantity: true,
        ),
      ],
    ),
    _OrderAddonGroupDef(
      label: 'Кухня',
      items: [
        _OrderAddonItemDef(key: 'kitchen_oven', label: 'Чистка духовки внутри'),
        _OrderAddonItemDef(
          key: 'kitchen_hood',
          label: 'Чистка вытяжки и фильтров',
        ),
        _OrderAddonItemDef(
          key: 'kitchen_fridge',
          label: 'Мытье холодильника внутри',
        ),
        _OrderAddonItemDef(
          key: 'kitchen_facades',
          label: 'Мытье фасадов кухонного гарнитура',
        ),
        _OrderAddonItemDef(
          key: 'kitchen_full_set',
          label: 'Полное мытье кухонного гарнитура',
        ),
        _OrderAddonItemDef(
          key: 'kitchen_stove',
          label: 'Чистка плит и варочных панелей',
        ),
        _OrderAddonItemDef(
          key: 'kitchen_microwave',
          label: 'Чистка микроволновки',
        ),
        _OrderAddonItemDef(key: 'kitchen_apron', label: 'Мытье фартука'),
        _OrderAddonItemDef(
          key: 'kitchen_dishes_hand',
          label: 'Мытье посуды вручную',
        ),
        _OrderAddonItemDef(
          key: 'kitchen_dishwasher_loading',
          label: 'Загрузка посуды в посудомойку',
        ),
      ],
    ),
    _OrderAddonGroupDef(
      label: 'Санузлы',
      items: [
        _OrderAddonItemDef(key: 'bath_tile_walls', label: 'Стены кафель'),
        _OrderAddonItemDef(
          key: 'bath_glass_walls',
          label: 'Стеклянные стены душа и ванны',
        ),
        _OrderAddonItemDef(
          key: 'bath_washer_wipe',
          label: 'Протирка стиральной машины',
        ),
      ],
    ),
    _OrderAddonGroupDef(
      label: 'Комфорт и текстиль',
      items: [
        _OrderAddonItemDef(
          key: 'textile_bed_linen_ironing',
          label: 'Глажка постельного белья',
        ),
        _OrderAddonItemDef(
          key: 'textile_clothes_ironing',
          label: 'Глажка одежды',
        ),
        _OrderAddonItemDef(
          key: 'textile_curtains_ironing',
          label: 'Глажка штор',
        ),
        _OrderAddonItemDef(
          key: 'textile_bed_change',
          label: 'Замена постельного белья и заправка кроватей',
        ),
      ],
    ),
    _OrderAddonGroupDef(
      label: 'Труднодоступные зоны',
      items: [
        _OrderAddonItemDef(
          key: 'hard_chandelier_standard',
          label: 'Чистка люстр стандартная',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'hard_chandelier_complex',
          label: 'Чистка люстр сложная',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'hard_chandelier_super',
          label: 'Чистка люстр супер сложная',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'hard_lamps',
          label: 'Светильники и плафоны',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'hard_upper_shelves',
          label: 'Чистка верхних полок, антресолей и шкафов',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(key: 'hard_baseboards', label: 'Чистка плинтусов'),
        _OrderAddonItemDef(
          key: 'hard_doors',
          label: 'Мытье дверей',
          supportsQuantity: true,
        ),
        _OrderAddonItemDef(
          key: 'hard_cobweb',
          label: 'Удаление паутины и пыли в труднодоступных местах',
        ),
      ],
    ),
    _OrderAddonGroupDef(
      label: 'Мебель и поверхности',
      items: [
        _OrderAddonItemDef(
          key: 'furniture_sofa',
          label: 'Химчистка диванов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
        _OrderAddonItemDef(
          key: 'furniture_mattress',
          label: 'Химчистка матрасов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
        _OrderAddonItemDef(
          key: 'carpet_cleaning',
          label: 'Химчистка ковров и паласов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
      ],
    ),
  ];

  late TabController _tabController;
  final _data = FirestoreDataService.instance;
  final Map<String, int> _addonUnitPrices = <String, int>{};
  final Map<String, bool> _addonSeparatePayment = <String, bool>{};
  StreamSubscription<List<Map<String, dynamic>>>? _addonGroupsSubscription;
  List<_OrderAddonGroupDef> _addonGroups = List<_OrderAddonGroupDef>.from(
    _fallbackAddonGroups,
  );
  final Set<String> _locallyCancelledSlotIds = <String>{};
  final Set<String> _locallyCancelledOrderIds = <String>{};
  bool _initialTabApplied = false;
  bool _pendingEditHandled = false;
  String? _pendingEditSlotId;
  bool _pendingFocusHandled = false;
  String? _pendingFocusOrderId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _addonGroupsSubscription = AppConfigService.instance
        .addonGroupConfigsStream()
        .listen((groups) {
          if (!mounted) return;
          setState(() {
            _addonGroups = _mapAddonGroupConfigs(groups);
          });
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyDebugRescheduleIfNeeded();
    });
  }

  @override
  void dispose() {
    _addonGroupsSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  List<_OrderAddonGroupDef> _mapAddonGroupConfigs(
    List<Map<String, dynamic>> groups,
  ) {
    _addonUnitPrices.clear();
    _addonSeparatePayment.clear();
    for (final group in _fallbackAddonGroups) {
      for (final item in group.items) {
        if (item.separatePayment) {
          _addonSeparatePayment[item.key] = true;
        }
      }
    }
    if (groups.isEmpty) {
      return List<_OrderAddonGroupDef>.from(_fallbackAddonGroups);
    }
    final mapped = groups
        .map((group) {
          final items = ((group['items'] ?? const []) as List)
              .whereType<Map>()
              .map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem);
                final key = (item['key'] ?? '').toString();
                final price = (item['price'] as num?)?.toInt() ?? 0;
                if (key.isNotEmpty) {
                  _addonUnitPrices[key] = price;
                  _addonSeparatePayment[key] =
                      item['separatePayment'] == true ||
                      item['separate'] == true;
                }
                return _OrderAddonItemDef(
                  key: key,
                  label: (item['label'] ?? key).toString(),
                  supportsQuantity: item['supportsQuantity'] == true,
                  note: (item['note'] ?? '').toString().trim().isEmpty
                      ? null
                      : (item['note'] ?? '').toString(),
                  shortInfo:
                      (item['shortInfo'] ??
                              item['description'] ??
                              item['note'] ??
                              item['hint'] ??
                              item['prompt'] ??
                              item['note'] ??
                              item['hint'] ??
                              item['prompt'] ??
                              '')
                          .toString()
                          .trim()
                          .isEmpty
                      ? null
                      : (item['shortInfo'] ??
                                item['description'] ??
                                item['note'] ??
                                item['hint'] ??
                                item['prompt'])
                            .toString(),
                  fullInfo:
                      (item['fullInfo'] ?? item['longDescription'] ?? '')
                          .toString()
                          .trim()
                          .isEmpty
                      ? null
                      : (item['fullInfo'] ?? item['longDescription'])
                            .toString(),
                  features: item['features'] is List
                      ? (item['features'] as List)
                            .map((value) => value.toString())
                            .where((value) => value.trim().isNotEmpty)
                            .toList()
                      : const <String>[],
                  durationMinutes:
                      (item['durationMinutes'] as num?)?.toInt() ?? 15,
                );
              })
              .where((item) => item.key.isNotEmpty)
              .toList();
          return _OrderAddonGroupDef(
            label: (group['label'] ?? group['key'] ?? 'Доп. услуги').toString(),
            items: items,
          );
        })
        .where((group) => group.items.isNotEmpty)
        .toList();
    return mapped.isEmpty
        ? List<_OrderAddonGroupDef>.from(_fallbackAddonGroups)
        : mapped;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialTabApplied) {
      return;
    }
    _initialTabApplied = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) {
      return;
    }
    final rawTab = args['initialTab']?.toString().trim().toLowerCase();
    if (rawTab == 'history' || rawTab == 'completed') {
      _tabController.index = 1;
    }
    final editSlotId = args['editSlotId']?.toString().trim();
    if (editSlotId != null && editSlotId.isNotEmpty) {
      _pendingEditSlotId = editSlotId;
      _tabController.index = 0;
    }
    final focusOrderId = (args['focusOrderId'] ?? args['orderId'])
        ?.toString()
        .trim();
    if (focusOrderId != null && focusOrderId.isNotEmpty) {
      _pendingFocusOrderId = focusOrderId;
      _tabController.index = 0;
    }
  }

  Future<void> _applyDebugRescheduleIfNeeded() async {
    if (!mounted || DebugSession.uid != 'customer_demo') {
      return;
    }
    final slotId = DebugSession.value('debug_reschedule_slot_id');
    final dateValue = DebugSession.value('debug_reschedule_date');
    final timeValue = DebugSession.value('debug_reschedule_time');
    if (slotId == null ||
        slotId.isEmpty ||
        dateValue == null ||
        dateValue.isEmpty ||
        timeValue == null ||
        timeValue.isEmpty) {
      return;
    }
    final date = DateTime.tryParse(dateValue);
    if (date == null) {
      return;
    }
    try {
      await _data.updateScheduledCleaning(
        slotId: slotId,
        date: date,
        time: timeValue,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Silent in debug-only QA hook.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.customerScheduleSlotsStream(),
      initialData: const <Map<String, dynamic>>[],
      builder: (context, slotsSnap) {
        final slots = slotsSnap.data ?? <Map<String, dynamic>>[];
        final active = slots.where((slot) {
          final slotId = (slot['id'] ?? slot['slotId'] ?? '').toString();
          if (slotId.isNotEmpty && _locallyCancelledSlotIds.contains(slotId)) {
            return false;
          }
          final status = (slot['status'] ?? '').toString().toLowerCase();
          return status != 'completed' &&
              status != 'canceled' &&
              status != 'cancelled';
        }).toList()..sort((a, b) => _slotDate(a).compareTo(_slotDate(b)));
        _openPendingEditIfNeeded(active);

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.customerOrdersStream(),
          initialData: const <Map<String, dynamic>>[],
          builder: (context, ordersSnap) {
            final allOrders = ordersSnap.data ?? <Map<String, dynamic>>[];
            final scheduledOrderIds = slots
                .map(
                  (slot) =>
                      (slot['sourceOrderId'] ??
                              slot['customerOrderId'] ??
                              slot['orderId'])
                          .toString(),
                )
                .where((id) => id.isNotEmpty)
                .toSet();
            final scheduledSubscriptionIds = slots
                .map((slot) => (slot['subscriptionId'] ?? '').toString())
                .where((id) => id.isNotEmpty)
                .toSet();
            final loadingSlots =
                slotsSnap.connectionState == ConnectionState.waiting &&
                !slotsSnap.hasData &&
                !slotsSnap.hasError;
            final loadingOrders =
                ordersSnap.connectionState == ConnectionState.waiting &&
                !ordersSnap.hasData &&
                !ordersSnap.hasError;
            final pendingOrders = allOrders.where((order) {
              final status = (order['status'] ?? '').toString().toLowerCase();
              final orderId = (order['id'] ?? order['orderId'] ?? '')
                  .toString();
              if (orderId.isNotEmpty &&
                  _locallyCancelledOrderIds.contains(orderId)) {
                return false;
              }
              final orderSubscriptionId = (order['subscriptionId'] ?? '')
                  .toString();
              return status != 'completed' &&
                  status != 'canceled' &&
                  status != 'cancelled' &&
                  status != 'merged' &&
                  !scheduledOrderIds.contains(orderId) &&
                  (orderSubscriptionId.isEmpty ||
                      !scheduledSubscriptionIds.contains(orderSubscriptionId));
            }).toList()..sort((a, b) => _orderDate(a).compareTo(_orderDate(b)));
            final visiblePendingOrders = _hidePaidPackageOrdersAwaitingSchedule(
              pendingOrders,
            );
            _openFocusedOrderIfNeeded(
              activeSlots: active,
              pendingOrders: visiblePendingOrders,
            );
            final history = _historyOrdersFromSources(
              orders: allOrders,
              slots: slots,
            );

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _data.customerAddonRequestsStream(),
              initialData: const <Map<String, dynamic>>[],
              builder: (context, addonSnap) {
                final addonRequests = (addonSnap.data ?? const [])
                    .where(
                      (item) =>
                          (item['status'] ?? '').toString() ==
                          'pending_customer',
                    )
                    .toList();
                return DomlyShell(
                  bottomNavigationBar: const DomlyClientBottomNav(
                    currentIndex: 1,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, _) {
                            final showActive = _tabController.index == 0;
                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                15,
                                0,
                                15,
                                112,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _OrdersFigmaHeader(
                                    subtitle: showActive
                                        ? 'Активные и ожидающие уборки'
                                        : 'История завершенных уборок',
                                  ),
                                  if (showActive) ...[
                                    const SizedBox(height: 20),
                                  ] else
                                    const SizedBox(height: 35),
                                  _OrdersSegmentedTabs(
                                    activeIndex: _tabController.index,
                                    onTap: (index) {
                                      setState(
                                        () => _tabController.index = index,
                                      );
                                    },
                                  ),
                                  SizedBox(height: showActive ? 20 : 34),
                                  if (showActive) ...[
                                    ...addonRequests.map(
                                      (request) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _buildAddonRequestCard(request),
                                      ),
                                    ),
                                    _buildFigmaActiveContent(
                                      slots: active,
                                      pendingOrders: visiblePendingOrders,
                                      loading: loadingSlots || loadingOrders,
                                      hasError:
                                          slotsSnap.hasError ||
                                          ordersSnap.hasError,
                                    ),
                                  ] else
                                    _buildFigmaHistoryContent(
                                      orders: history,
                                      loading: loadingSlots || loadingOrders,
                                      hasError:
                                          slotsSnap.hasError ||
                                          ordersSnap.hasError,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openPendingEditIfNeeded(List<Map<String, dynamic>> activeSlots) {
    final slotId = _pendingEditSlotId;
    if (_pendingEditHandled || slotId == null || slotId.isEmpty) {
      return;
    }
    Map<String, dynamic>? target;
    for (final slot in activeSlots) {
      final ids = [
        slot['id'],
        slot['slotId'],
        slot['scheduleSlotId'],
        slot['chatId'],
        slot['sourceOrderId'],
        slot['orderId'],
        slot['customerOrderId'],
      ].map((value) => (value ?? '').toString().trim());
      if (ids.contains(slotId)) {
        target = slot;
        break;
      }
    }
    if (target == null) {
      return;
    }
    _pendingEditHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _editScheduledCleaning(target!);
    });
  }

  void _openFocusedOrderIfNeeded({
    required List<Map<String, dynamic>> activeSlots,
    required List<Map<String, dynamic>> pendingOrders,
  }) {
    final focusId = _pendingFocusOrderId;
    if (_pendingFocusHandled || focusId == null || focusId.isEmpty) {
      return;
    }
    for (final slot in activeSlots) {
      if (_orderIdentityValues(slot).contains(focusId)) {
        _pendingFocusHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showFigmaSlotActions(slot);
          }
        });
        return;
      }
    }
    for (final order in pendingOrders) {
      if (_orderIdentityValues(order).contains(focusId)) {
        _pendingFocusHandled = true;
        return;
      }
    }
  }

  Set<String> _orderIdentityValues(Map<String, dynamic> item) {
    return {
          item['id'],
          item['slotId'],
          item['scheduleSlotId'],
          item['chatId'],
          item['sourceOrderId'],
          item['customerOrderId'],
          item['orderId'],
          item['paymentId'],
        }
        .map((value) => (value ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Widget _buildFigmaActiveContent({
    required List<Map<String, dynamic>> slots,
    required List<Map<String, dynamic>> pendingOrders,
    required bool loading,
    required bool hasError,
  }) {
    if (hasError) {
      return const _OrdersFigmaMessageCard(
        title: 'Не удалось загрузить заказы',
        subtitle: 'Проверьте подключение и попробуйте открыть экран позже.',
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 42),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF439F73),
            ),
          ),
        ),
      );
    }
    if (slots.isEmpty && pendingOrders.isEmpty) {
      return const _OrdersFigmaMessageCard(
        title: 'Пока нет заказов',
        subtitle: 'Когда вы оформите уборку, она появится здесь.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 31),
                child: Text(
                  'Последние заказы'.tr(),
                  style: TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 30 / 22,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _tabController.animateTo(1),
              child: Padding(
                padding: EdgeInsets.only(right: 22),
                child: Text(
                  'Все'.tr(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Color(0xFF439F73),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 22 / 16,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...slots.map(
          (slot) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _buildFigmaSlotCard(slot),
          ),
        ),
        ...pendingOrders.map(
          (order) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _buildFigmaPendingOrderCard(order),
          ),
        ),
      ],
    );
  }

  Widget _buildAddonRequestCard(Map<String, dynamic> request) {
    final labels = _formatAddonRequestLabels(request);
    final amount = ((request['amount'] ?? 0) as num?)?.toInt() ?? 0;
    final cleanerName = (request['cleanerName'] ?? 'Уборщица').toString();
    final note = (request['note'] ?? '').toString().trim();
    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Согласование доп. услуг'.tr(),
            style: TextStyle(
              color: DomlyColors.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$cleanerName предложила добавить: $labels'.tr(),
            style: const TextStyle(
              color: DomlyColors.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(
                color: DomlyColors.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${amount.toString()} ₸',
            style: const TextStyle(
              color: DomlyColors.foreground,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DomlySecondaryButton(
                  label: 'Отклонить',
                  onPressed: () => _rejectAddonRequest(request),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DomlyPrimaryButton(
                  label: 'Согласовать',
                  onPressed: () => _approveAddonRequest(request),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatAddonRequestLabels(Map<String, dynamic> request) {
    final labels = <String>[];
    final detailed = request['addonsDetailed'];
    if (detailed is List) {
      for (final item in detailed) {
        if (item is Map) {
          final label = (item['label'] ?? item['key'] ?? '').toString();
          final quantity = ((item['quantity'] ?? 1) as num?)?.toInt() ?? 1;
          if (label.trim().isNotEmpty) {
            labels.add(quantity > 1 ? '$label × $quantity' : label);
          }
        }
      }
    }
    final simple = request['addons'];
    if (labels.isEmpty && simple is List) {
      labels.addAll(simple.map((item) => item.toString()));
    }
    return labels.where((item) => item.trim().isNotEmpty).join(', ');
  }

  Future<void> _approveAddonRequest(Map<String, dynamic> request) async {
    final requestId = (request['id'] ?? '').toString();
    if (requestId.isEmpty) return;
    final amount =
        ((request['amount'] ?? request['price'] ?? 0) as num?)?.toInt() ?? 0;
    final profile = await _data.customerProfileStream().first;
    if (!mounted) return;
    final bonusBalance = (profile?['bonusPoints'] as num?)?.toInt() ?? 0;
    final bonusLimit = addonBonusSpendLimit(
      amount,
      await AppConfigService.instance.promotionsStream().first,
    );
    if (!mounted) return;
    final paymentSelection = await showPaymentMethodOptionsDialog(
      context,
      bonusBalance: bonusBalance,
      maxBonusToSpend: bonusLimit,
      paymentAmount: amount,
    );
    if (!mounted || paymentSelection == null) return;
    String? kaspiPhone;
    var selectedBonusToSpend =
        paymentSelection.method == DomlyPaymentMethod.bonus
        ? amount
        : paymentSelection.useBonus
        ? bonusBalance.clamp(0, bonusLimit).clamp(0, amount).toInt()
        : 0;
    if (paymentSelection.method == DomlyPaymentMethod.kaspi) {
      final paymentRequest = await showKaspiInvoiceRequestOptionsDialog(
        context,
        bonusBalance: bonusBalance,
        maxBonusToSpend: bonusLimit,
        paymentAmount: amount,
        initialUseBonus: selectedBonusToSpend > 0,
      );
      if (!mounted || paymentRequest == null) return;
      kaspiPhone = paymentRequest.phone;
      selectedBonusToSpend = paymentRequest.useBonus
          ? bonusBalance.clamp(0, bonusLimit).clamp(0, amount).toInt()
          : 0;
    }
    try {
      final result = await PaymentLinkService.runBlocking(
        context,
        task: () => _data.approveCleanerAddonRequest(
          requestId: requestId,
          kaspiPhone: kaspiPhone,
          paymentMethod: paymentSelection.method.name,
          bonusToSpend: selectedBonusToSpend,
        ),
        message: 'Отправляем согласование...',
      );
      if (!mounted) return;
      if (paymentSelection.method == DomlyPaymentMethod.online) {
        final paymentId = (result['paymentId'] ?? '').toString();
        if (paymentId.isNotEmpty) {
          final paymentSession = await PaymentLinkService.runBlocking(
            context,
            task: () => _data.createBccPaymentSession(orderId: paymentId),
            message: 'Открываем онлайн-оплату...',
          );
          if (!mounted) return;
          Navigator.pushNamed(
            context,
            '/client/online-payment',
            arguments: paymentSession,
          );
          return;
        }
      }
      showDomlySnackBar(
        context,
        title: 'Согласование отправлено',
        subtitle:
            'Менеджер подтвердит оплату, после этого допы добавятся в уборку.',
        type: DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось согласовать допы',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  Future<void> _rejectAddonRequest(Map<String, dynamic> request) async {
    final requestId = (request['id'] ?? '').toString();
    if (requestId.isEmpty) return;
    try {
      await _data.rejectCleanerAddonRequest(requestId: requestId);
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Доп. услуги отклонены',
        subtitle: 'Уборщица увидит отказ.',
        type: DomlySnackBarType.info,
      );
    } catch (error) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось отклонить допы',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  Widget _buildFigmaHistoryContent({
    required List<Map<String, dynamic>> orders,
    required bool loading,
    required bool hasError,
  }) {
    if (hasError) {
      return const _OrdersFigmaMessageCard(
        title: 'Не удалось загрузить историю',
        subtitle: 'Попробуйте обновить экран позже.',
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 42),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF439F73),
            ),
          ),
        ),
      );
    }
    if (orders.isEmpty) {
      return const _OrdersFigmaMessageCard(
        title: 'История пока пуста',
        subtitle: 'Завершенные уборки появятся здесь.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...orders.map(
          (order) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _buildFigmaHistoryOrderCard(order),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _historyOrdersFromSources({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> slots,
  }) {
    final completedSlots = slots
        .where((slot) {
          final status = (slot['status'] ?? '').toString().toLowerCase();
          final orderStatus = (slot['orderStatus'] ?? '')
              .toString()
              .toLowerCase();
          return status == 'completed' || orderStatus == 'completed';
        })
        .map((slot) {
          final slotId = _cleanString(slot['id'] ?? slot['slotId']);
          final sourceOrderId = _cleanString(
            slot['sourceOrderId'] ?? slot['customerOrderId'] ?? slot['orderId'],
          );
          return {
            ...slot,
            'id': sourceOrderId.isNotEmpty ? sourceOrderId : slotId,
            'slotId': slotId,
            'status': 'completed',
            'date':
                slot['scheduledFor'] ??
                slot['date'] ??
                slot['scheduledDateKey'],
            'cleanerName': _slotCleanerDisplayName(slot),
          };
        })
        .toList();

    final scheduledOrderIds = completedSlots
        .map((slot) => _cleanString(slot['id']))
        .where((id) => id.isNotEmpty)
        .toSet();
    final completedOrders = orders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      final orderStatus = (order['orderStatus'] ?? '').toString().toLowerCase();
      if (status != 'completed' && orderStatus != 'completed') {
        return false;
      }
      final orderId = _cleanString(order['id'] ?? order['orderId']);
      return !scheduledOrderIds.contains(orderId);
    }).toList();

    final history = <Map<String, dynamic>>[
      ...completedSlots,
      ...completedOrders,
    ]..sort((a, b) => _orderDate(b).compareTo(_orderDate(a)));
    return history;
  }

  String _cleanString(Object? value) {
    final text = (value ?? '').toString().trim();
    return text == 'null' ? '' : text;
  }

  Widget _buildFigmaSlotCard(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString();
    final cleaner = _slotCleanerDisplayName(slot);
    final address =
        (slot['address'] ?? slot['residentialComplex'] ?? 'Адрес будет уточнен')
            .toString();
    final area = (slot['area'] ?? slot['apartmentArea'] ?? '100').toString();
    final price = (slot['price'] ?? slot['amount'] ?? slot['total'] ?? 0);
    final canCancel = _canCancelSlot(status);
    final canEdit = _canEditSlot(status);
    final awaitingStartConfirmation = _isAwaitingStartConfirmation(slot);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _showFigmaSlotActions(slot),
      child: Container(
        padding: const EdgeInsets.fromLTRB(27, 19, 15, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDEECE3)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    domlyDateText(_slotDate(slot)),
                    style: const TextStyle(
                      color: Color(0xFF2B4338),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 30 / 22,
                    ),
                  ),
                ),
                _OrdersStatusPill(
                  text: status == 'assigned'
                      ? 'Подтверждено'
                      : _statusText(status),
                  color: _statusColor(status),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    (slot['time'] ?? '10:00 - 12:36').toString(),
                    style: const TextStyle(
                      color: Color(0xFF658170),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 20 / 15,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 48),
                  child: Text(
                    '$area м²'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF658170),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 22 / 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _OrdersAvatar(name: cleaner),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cleaner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF2B4338),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 24 / 18,
                        ),
                      ),
                      Text(
                        address.isEmpty ? 'Адрес будет уточнен' : address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF658170),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 18 / 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (price > 0) ...[
                  Text(
                    '$price ₸',
                    style: const TextStyle(
                      color: Color(0xFFCF7548),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 27 / 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF658170),
                  size: 24,
                ),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canCancel)
                    _SlotActionChip(
                      label: 'Отменить',
                      danger: true,
                      onTap: () => _cancelSlot(slot),
                    ),
                  _SlotActionChip(
                    label: _isActiveCleaningStatus(status)
                        ? 'Добавить допы'
                        : 'Редактировать заказ',
                    onTap: () => _editScheduledCleaning(slot),
                  ),
                ],
              ),
            ],
            if (awaitingStartConfirmation) ...[
              const SizedBox(height: 14),
              _CleaningStartConfirmationPanel(
                rejected: slot['cleaningStartRejected'] == true,
                onConfirm: () => _confirmCleaningStart(slot, true),
                onReject: () => _confirmCleaningStart(slot, false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showFigmaSlotActions(Map<String, dynamic> slot) async {
    final status = (slot['status'] ?? '').toString();
    final orderId =
        (slot['chatId'] ??
                slot['scheduleSlotId'] ??
                slot['slotId'] ??
                slot['id'] ??
                slot['sourceOrderId'] ??
                slot['orderId'])
            .toString();
    final phone = (slot['cleanerPhone'] ?? '').toString();
    final cleanerId = (slot['cleanerId'] ?? '').toString().trim();
    final canOpenChat = orderId.isNotEmpty && cleanerId.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Действия по уборке'.tr(),
                      style: TextStyle(
                        color: Color(0xFF2B4338),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cancellationRuleText(slot),
                      style: const TextStyle(
                        color: Color(0xFF658170),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DomlySecondaryButton(
                            label: 'Звонок',
                            onPressed: phone.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    CallService.callPhone(phone);
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DomlyPrimaryButton(
                            label: 'Чат',
                            onPressed: !canOpenChat
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(
                                      this.context,
                                      '/chat',
                                      arguments: {'orderId': orderId},
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DomlySecondaryButton(
                      label: 'Жалоба',
                      onPressed: orderId.isEmpty
                          ? null
                          : () {
                              Navigator.pop(context);
                              Navigator.pushNamed(
                                this.context,
                                '/complaint',
                                arguments: {'orderId': orderId},
                              );
                            },
                    ),
                    const SizedBox(height: 10),
                    DomlySecondaryButton(
                      label: 'Чек-лист',
                      onPressed: orderId.isEmpty
                          ? null
                          : () {
                              Navigator.pop(context);
                              _showClientChecklist(slot);
                            },
                    ),
                    if (_canEditSlot(status)) ...[
                      const SizedBox(height: 10),
                      DomlySecondaryButton(
                        label: _isActiveCleaningStatus(status)
                            ? 'Добавить допы'
                            : 'Редактировать заказ',
                        onPressed: () {
                          Navigator.pop(context);
                          _editScheduledCleaning(slot);
                        },
                      ),
                    ],
                    if (_isAwaitingStartConfirmation(slot)) ...[
                      const SizedBox(height: 10),
                      _CleaningStartConfirmationPanel(
                        rejected: slot['cleaningStartRejected'] == true,
                        onConfirm: () {
                          Navigator.pop(context);
                          _confirmCleaningStart(slot, true);
                        },
                        onReject: () {
                          Navigator.pop(context);
                          _confirmCleaningStart(slot, false);
                        },
                      ),
                    ],
                    if (_canCancelSlot(status)) ...[
                      const SizedBox(height: 10),
                      DomlySecondaryButton(
                        label: 'Отменить уборку',
                        foregroundColor: DomlyColors.danger,
                        onPressed: () {
                          Navigator.pop(context);
                          _cancelSlot(slot);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _hidePaidPackageOrdersAwaitingSchedule(
    List<Map<String, dynamic>> orders,
  ) => orders.where((order) => !_isPaidPackageAwaitingSchedule(order)).toList();

  bool _isPaidPackageAwaitingSchedule(Map<String, dynamic> order) {
    final paymentStatus = (order['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final orderStatus = ((order['orderStatus'] ?? order['status']) ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    final isPaid =
        paymentStatus == 'paid' ||
        order['paidAt'] != null ||
        order['subscriptionStatus'] == 'active' ||
        (order['subscriptionId'] ?? '').toString().trim().isNotEmpty;
    final awaitsSchedule =
        orderStatus == 'pending_assignment' ||
        status == 'pending_assignment' ||
        status == 'pending';
    return isPaid && awaitsSchedule;
  }

  int _pendingOrderAmount(Map<String, dynamic> order) {
    for (final key in const [
      'amount',
      'price',
      'total',
      'monthlyPrice',
      'subtotal',
      'addonsBillableTotal',
    ]) {
      final value = order[key];
      if (value is num && value.toInt() > 0) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
    }
    return 0;
  }

  String _moneyText(int amount) {
    final raw = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return '${buffer.toString()} ₸';
  }

  String _pendingOrderTitle(Map<String, dynamic> order) {
    final packageName =
        (order['packageName'] ??
                order['package'] ??
                order['planName'] ??
                order['frequencyLabel'] ??
                '')
            .toString()
            .trim();
    if (packageName.isNotEmpty) {
      return packageName;
    }
    final packageId = (order['packageId'] ?? '').toString().toLowerCase();
    if (packageId == 'addons_only') {
      return 'Доп. услуги к уборке';
    }
    return 'Заказ DOMLY';
  }

  List<String> _pendingOrderAddonLines(Map<String, dynamic> order) {
    final raw = order['addonsDetailed'];
    final lines = <String>[];
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final label = (item['label'] ?? item['key'] ?? '').toString().trim();
        if (label.isEmpty || _isStandardCleaningTask(label)) {
          continue;
        }
        final quantity = ((item['quantity'] as num?)?.toInt() ?? 1)
            .clamp(1, 999)
            .toInt();
        final price = (item['price'] as num?)?.toInt() ?? 0;
        final total = price * quantity;
        final qtyText = quantity > 1 ? ' × $quantity' : '';
        final priceText = total > 0 ? ' — ${_moneyText(total)}' : '';
        lines.add('$label$qtyText$priceText');
      }
    }
    if (lines.isEmpty && order['addons'] is List) {
      lines.addAll(
        (order['addons'] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty && !_isStandardCleaningTask(item)),
      );
    }
    return lines;
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

  Widget _pendingPaymentInfo(Map<String, dynamic> order) {
    final amount = _pendingOrderAmount(order);
    final addonLines = _pendingOrderAddonLines(order);
    final kaspiPhone =
        (order['kaspiPhone'] ?? order['phone'] ?? order['customerPhone'] ?? '')
            .toString()
            .trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Что оплачивается'.tr(),
                  style: TextStyle(
                    color: Color(0xFF658170),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 16 / 12,
                  ),
                ),
              ),
              if (amount > 0)
                Text(
                  _moneyText(amount),
                  style: const TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 22 / 18,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _pendingOrderTitle(order),
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 18 / 14,
            ),
          ),
          if (addonLines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...addonLines
                .take(4)
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xFF658170),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 16 / 12,
                      ),
                    ),
                  ),
                ),
          ],
          if (kaspiPhone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Kaspi: $kaspiPhone',
              style: const TextStyle(
                color: Color(0xFFCF7548),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 16 / 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFigmaPendingOrderCard(Map<String, dynamic> order) {
    final paymentStatus = (order['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final orderStatus = ((order['orderStatus'] ?? order['status']) ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final status = paymentStatus.isNotEmpty ? paymentStatus : orderStatus;
    final isInvoiceRequested = status == 'invoice_requested';
    final isPaidAwaitingAssignment =
        paymentStatus == 'paid' && orderStatus == 'pending_assignment';
    final isCombinedPaidPackages = order['combinedPaidPackages'] == true;
    final combinedPackageCount =
        (order['combinedPackageCount'] as num?)?.toInt() ?? 1;
    final canCancelPendingOrder = paymentStatus != 'paid';
    final orderId = (order['id'] ?? order['orderId'] ?? '').toString().trim();
    final subscriptionId = (order['subscriptionId'] ?? '').toString().trim();
    final schedulingSubscriptionId = subscriptionId.isNotEmpty
        ? subscriptionId
        : orderId;
    final title = isPaidAwaitingAssignment
        ? 'Выберите\nвремя'
        : isInvoiceRequested
        ? 'Ожидает\nоплаты'
        : 'Ожидает\nподтверждения';
    final subtitle = isPaidAwaitingAssignment
        ? isCombinedPaidPackages && combinedPackageCount > 1
              ? 'Оплата подтверждена. Все купленные пакеты объединены здесь. Выберите даты и время уборок.'
              : 'Оплата подтверждена. Выберите удобную дату и время уборки.'
        : isInvoiceRequested
        ? 'Счет уже выставлен. Вы можете оплатить его позже или отменить заказ.'
        : 'Заявка отправлена. Вы можете отменить заказ или оформить еще один.';
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 24 / 18,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF658170),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 18 / 13,
                  ),
                ),
              ),
              if (status == 'pending_payment' ||
                  status == 'invoice_requested' ||
                  status == 'initiated')
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Container(
                    width: 100,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8E7DD),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'KASPI.KZ',
                      style: TextStyle(
                        color: Color(0xFFDF0808),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 16 / 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (status == 'pending_payment' ||
              status == 'invoice_requested' ||
              status == 'initiated') ...[
            const SizedBox(height: 14),
            _pendingPaymentInfo(order),
          ],
          const SizedBox(height: 14),
          if (isPaidAwaitingAssignment && schedulingSubscriptionId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DomlyPrimaryButton(
                label: 'Выбрать дату и время',
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/client/package-calendar',
                    arguments: {'subscriptionId': schedulingSubscriptionId},
                  );
                },
              ),
            ),
          if (canCancelPendingOrder)
            OutlinedButton(
              onPressed: () => _cancelPendingOrder(order),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                side: const BorderSide(color: Color(0xFFE7B89C)),
                foregroundColor: const Color(0xFFC8794E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Отменить заказ'.tr(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFigmaHistoryOrderCard(Map<String, dynamic> order) {
    final cleaner =
        (order['cleanerName'] ??
                order['cleaner'] ??
                order['executorName'] ??
                'Исполнитель')
            .toString();
    final price = order['price'] ?? order['amount'] ?? order['total'] ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _showFigmaHistoryActions(order),
      child: Container(
        height: 130,
        padding: const EdgeInsets.fromLTRB(28, 25, 49, 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDEECE3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    domlyDateText(_orderDate(order)),
                    style: const TextStyle(
                      color: Color(0xFF2B4338),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 24 / 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Завершено'.tr(),
                    style: TextStyle(
                      color: Color(0xFF439F73),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 18 / 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Исполнитель: $cleaner'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF658170),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 18 / 13,
                    ),
                  ),
                ],
              ),
            ),
            if (price > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '$price ₸',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 24 / 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFigmaHistoryActions(Map<String, dynamic> order) async {
    final orderId = _cleanString(order['slotId'] ?? order['id']);
    if (orderId.isEmpty) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Завершенный заказ'.tr(),
                  style: TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Оставьте отзыв об уборке или сообщите о проблеме.'.tr(),
                  style: TextStyle(
                    color: DomlyColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                DomlyPrimaryButton(
                  label: 'Оставить отзыв',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(
                      this.context,
                      '/review',
                      arguments: {'orderId': orderId},
                    );
                  },
                ),
                const SizedBox(height: 10),
                DomlySecondaryButton(
                  label: 'Жалоба',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(
                      this.context,
                      '/complaint',
                      arguments: {'orderId': orderId},
                    );
                  },
                ),
                const SizedBox(height: 10),
                DomlySecondaryButton(
                  label: 'Чек-лист',
                  onPressed: () {
                    Navigator.pop(context);
                    _showClientChecklist(order);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showClientChecklist(Map<String, dynamic> order) async {
    final orderIds = _orderIdentityValues(order);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.86,
            ),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: AppConfigService.instance
                  .cleanerChecklistTemplatesStream(),
              builder: (context, templatesSnapshot) {
                final templates =
                    templatesSnapshot.data ??
                    AppConfigService.defaultCleanerChecklistTemplates;
                return StreamBuilder<Map<String, dynamic>?>(
                  stream: FirestoreDataService.instance
                      .cleanerChecklistForOrderIdsStream(orderIds),
                  builder: (context, checklistSnapshot) {
                    final checklist = checklistSnapshot.data;
                    return _buildClientChecklistSheet(
                      order: order,
                      templates: templates,
                      checklist: checklist,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildClientChecklistSheet({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> templates,
    required Map<String, dynamic>? checklist,
  }) {
    final completed = _stringSet(checklist?['completedTasks']);
    final addons = _stringSet(checklist?['addons']);
    final checklistOrderedAddons = _stringList(checklist?['orderedAddons']);
    final orderAddons = _pendingOrderAddonLines(order);
    final orderedAddons = checklistOrderedAddons.isNotEmpty
        ? checklistOrderedAddons
        : orderAddons;
    final checklistDetailedAddons = _mapList(checklist?['addonsDetailed']);
    final orderDetailedAddons = _mapList(order['addonsDetailed']);
    final detailedAddons = checklistDetailedAddons.isNotEmpty
        ? checklistDetailedAddons
        : orderDetailedAddons;
    final note = _cleanString(checklist?['note']);
    final hasChecklist = checklist != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Чек-лист уборки'.tr(),
                  style: TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: DomlyColors.muted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: hasChecklist
                      ? const Color(0xFFEFF9F2)
                      : const Color(0xFFFFF7EF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  hasChecklist
                      ? 'Уборщица отметила выполненные пункты. Клиенту отправлено уведомление.'
                      : 'Уборщица еще не отметила чек-лист. Ниже показано, что входит в уборку.',
                  style: TextStyle(
                    color: hasChecklist
                        ? const Color(0xFF2F8F4E)
                        : DomlyColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              for (final group in templates.where(
                (group) => !_isAddonChecklistGroup(group),
              )) ...[
                _buildChecklistGroup(group, completed, addons),
                const SizedBox(height: 12),
              ],
              if (orderedAddons.isNotEmpty || detailedAddons.isNotEmpty) ...[
                _buildOrderedAddonsBlock(orderedAddons, detailedAddons, addons),
                const SizedBox(height: 12),
              ],
              if (note.isNotEmpty)
                _buildInfoBlock(title: 'Комментарий уборщицы', body: note),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistGroup(
    Map<String, dynamic> group,
    Set<String> completed,
    Set<String> addons,
  ) {
    final title = _cleanString(group['title']).isEmpty
        ? 'Раздел чек-листа'
        : _cleanString(group['title']);
    final description = _cleanString(group['description']);
    final items = _stringList(group['items']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                color: DomlyColors.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final item in items)
            _buildChecklistItem(
              item,
              completed.contains(item) || addons.contains(item),
            ),
        ],
      ),
    );
  }

  bool _isAddonChecklistGroup(Map<String, dynamic> group) {
    final key = _cleanString(group['key']).toLowerCase();
    final title = _cleanString(group['title']).toLowerCase();
    return key != 'base_tasks' &&
        (key.contains('addon') ||
            title.contains('доп') ||
            title.contains('additional'));
  }

  Widget _buildChecklistItem(String title, bool checked) {
    return AbsorbPointer(
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        tileColor: DomlyColors.backgroundSoft,
        value: checked,
        onChanged: (_) {},
        activeColor: const Color(0xFF43A866),
        checkColor: Colors.white,
        title: Text(
          title,
          style: TextStyle(
            color: checked ? const Color(0xFF2B4338) : DomlyColors.foreground,
            fontSize: 14,
            height: 1.3,
            fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          checked ? 'Отмечено уборщицей' : 'Не отмечено',
          style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildOrderedAddonsBlock(
    List<String> orderedAddons,
    List<Map<String, dynamic>> detailedAddons,
    Set<String> completedAddons,
  ) {
    final detailedLabels = detailedAddons
        .map(
          (item) =>
              _cleanString(item['name'] ?? item['title'] ?? item['label']),
        )
        .where((item) => item.isNotEmpty && !_isStandardCleaningTask(item))
        .toList();
    final items = <String>{
      ...orderedAddons.where((item) => !_isStandardCleaningTask(item)),
      ...detailedLabels,
    }.toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Купленные допы'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Видно, какие доп. услуги уборщица отметила выполненными.'.tr(),
            style: TextStyle(
              color: DomlyColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'Дополнительных услуг нет.'.tr(),
              style: TextStyle(color: DomlyColors.muted, fontSize: 13),
            )
          else
            ...items.map(
              (item) =>
                  _buildChecklistItem(item, completedAddons.contains(item)),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock({required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: DomlyColors.foreground,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Set<String> _stringSet(Object? value) => _stringList(value).toSet();

  List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => _cleanString(item))
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final single = _cleanString(value);
    return single.isEmpty ? const <String>[] : <String>[single];
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! Iterable) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'assigned':
      case 'accepted':
      case 'scheduled_confirmed':
      case 'start_pending':
        return DomlyColors.primary;
      case 'pending':
      case 'pending_assignment':
        return const Color(0xFFFF9800);
      case 'invoice_requested':
      case 'initiated':
        return const Color(0xFF8A6F00);
      case 'failed':
      case 'canceled':
      case 'cancelled':
        return DomlyColors.danger;
      case 'completed':
        return const Color(0xFF22C55E);
      default:
        return DomlyColors.muted;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'confirmed':
      case 'assigned':
      case 'accepted':
      case 'scheduled_confirmed':
        return 'Подтверждено';
      case 'start_pending':
        return 'Подтвердите старт';
      case 'pending':
      case 'pending_assignment':
        return 'Ожидание';
      case 'invoice_requested':
        return 'Счёт на KASPI.KZ';
      case 'initiated':
        return 'Нужен номер KASPI.KZ';
      case 'failed':
        return 'Ошибка оплаты';
      case 'canceled':
      case 'cancelled':
        return 'Отменено';
      case 'completed':
        return 'Завершено';
      default:
        return orderStatusLabel(status);
    }
  }

  String _slotCleanerDisplayName(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final cleanerName = (slot['cleanerName'] ?? '').toString().trim();
    final assignmentStatus = (slot['assignmentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isConfirmed =
        status == 'assigned' ||
        status == 'confirmed' ||
        status == 'in_progress' ||
        status == 'completed' ||
        assignmentStatus == 'accepted' ||
        assignmentStatus == 'scheduled_confirmed' ||
        assignmentStatus == 'assigned';
    if (isConfirmed && cleanerName.isNotEmpty) {
      return cleanerName;
    }
    final hasActiveOffer =
        (slot['currentOfferId'] ?? '').toString().trim().isNotEmpty ||
        assignmentStatus == 'offer_pending' ||
        assignmentStatus == 'scheduled_pending_confirmation';
    return hasActiveOffer ? 'Ждем ответ уборщицы' : 'Ищем уборщицу';
  }

  bool _canCancelSlot(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending_assignment' ||
        normalized == 'assigned' ||
        normalized == 'confirmed';
  }

  bool _canEditSlot(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending_assignment' ||
        normalized == 'assigned' ||
        normalized == 'confirmed' ||
        _isActiveCleaningStatus(normalized);
  }

  bool _isActiveCleaningStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'in_progress' ||
        normalized == 'started' ||
        normalized == 'cleaning';
  }

  bool _isAwaitingStartConfirmation(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? slot['orderStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return status == 'start_pending' &&
        slot['startRequiresCustomerConfirmation'] == true &&
        slot['cleaningStartConfirmed'] != true;
  }

  Future<void> _confirmCleaningStart(
    Map<String, dynamic> slot,
    bool confirmed,
  ) async {
    final approved = await _confirmCleaningStartAnswer(confirmed);
    if (!mounted || approved != true) {
      return;
    }
    final orderId =
        (slot['scheduleSlotId'] ??
                slot['slotId'] ??
                slot['id'] ??
                slot['sourceOrderId'] ??
                slot['customerOrderId'] ??
                slot['orderId'])
            .toString()
            .trim();
    if (orderId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не найден заказ',
        subtitle: 'Обновите экран и попробуйте снова.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    try {
      await _data.confirmCleaningStart(orderId: orderId, confirmed: confirmed);
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: confirmed ? 'Старт подтверждён' : 'Ответ отправлен',
        subtitle: confirmed
            ? 'Уборщица может продолжать выполнение заказа.'
            : 'Уборщица не сможет завершить заказ без вашего подтверждения.',
        type: confirmed ? DomlySnackBarType.success : DomlySnackBarType.info,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отправить ответ',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  Future<bool?> _confirmCleaningStartAnswer(bool confirmed) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          confirmed
              ? 'Вы уверены, что уборщица начала уборку?'
              : 'Вы уверены, что уборщица не начала уборку?',
        ),
        content: Text(
          confirmed
              ? 'После подтверждения уборщица сможет продолжить и завершить заказ.'
              : 'После ответа “Нет” уборщица не сможет завершить заказ без повторного подтверждения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Отмена'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Подтвердить'.tr()),
          ),
        ],
      ),
    );
  }

  String _cancellationRuleText(Map<String, dynamic> slot) {
    return 'Если передумали или ошиблись со временем, отмените уборку. Она вернется в доступные, и можно будет выбрать новую дату.';
  }

  Future<void> _cancelSlot(Map<String, dynamic> slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.82,
            maxWidth: 420,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Отменить уборку?'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Вы действительно хотите отменить эту уборку?\n\nПосле отмены она вернется в доступные уборки пакета, и вы сможете выбрать другую дату и время.'
                      .tr(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: DomlyColors.foreground,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 150,
                      child: DomlySecondaryButton(
                        label: 'Нет',
                        onPressed: () => Navigator.pop(dialogContext, false),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: DomlyPrimaryButton(
                        label: 'Да, отменить',
                        onPressed: () => Navigator.pop(dialogContext, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) {
      return;
    }

    final slotId = (slot['id'] ?? '').toString().trim();
    if (slotId.isEmpty) {
      return;
    }
    setState(() => _locallyCancelledSlotIds.add(slotId));
    try {
      final result = await _data.cancelScheduleSlot(slotId: slotId);
      if (!mounted) {
        return;
      }
      final penaltyApplied = result['penaltyApplied'] == true;
      showDomlySnackBar(
        context,
        title: 'Уборка отменена',
        subtitle: penaltyApplied
            ? 'Уборка списана по правилам отмены.'
            : 'Уборка вернулась в доступные.',
        type: penaltyApplied
            ? DomlySnackBarType.info
            : DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _locallyCancelledSlotIds.remove(slotId));
      showDomlySnackBar(
        context,
        title: 'Не удалось отменить уборку',
        subtitle: _friendlyError(error),
        type: DomlySnackBarType.error,
      );
    }
  }

  String _friendlyError(Object error) {
    if (UserErrorMessage.isAuthError(error)) {
      return UserErrorMessage.message(error);
    }
    final text = error.toString();
    if (text.contains('resource-exhausted') ||
        text.contains('RESOURCE_EXHAUSTED')) {
      return 'Сервис временно перегружен. Попробуйте еще раз через минуту.';
    }
    if (text.contains('unauthenticated') ||
        text.contains('Authentication required') ||
        text.contains('Нужна авторизация')) {
      return 'Сессия устарела. Выйдите и войдите снова.';
    }
    if (text.contains('permission-denied')) {
      return 'Нет доступа к этому заказу.';
    }
    return UserErrorMessage.message(
      error,
      fallback: 'Попробуйте обновить экран и повторить действие.',
    );
  }

  Future<void> _cancelPendingOrder(Map<String, dynamic> order) async {
    final orderId = _pendingOrderId(order);
    if (orderId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не удалось отменить заказ',
        subtitle: 'У заказа нет номера для отмены. Обновите экран.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Отменить заказ?'.tr()),
        content: Text(
          'Заявка на счет будет отменена. При необходимости вы сможете оформить новый заказ сразу после этого.'
              .tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Нет'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Да, отменить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _locallyCancelledOrderIds.add(orderId));
    try {
      await _data.cancelPendingOrder(orderId: orderId);
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Заказ отменен',
        subtitle: 'Вы можете сразу оформить новый заказ.',
        type: DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _locallyCancelledOrderIds.remove(orderId));
      showDomlySnackBar(
        context,
        title: 'Не удалось отменить заказ',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  String _pendingOrderId(Map<String, dynamic> order) {
    for (final key in const [
      'orderId',
      'customerOrderId',
      'sourceOrderId',
      'paymentId',
      'id',
    ]) {
      final value = (order[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  Future<void> _editScheduledCleaning(Map<String, dynamic> slot) async {
    final subscriptionId = (slot['subscriptionId'] ?? '').toString();
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final addonsOnly = _isActiveCleaningStatus(status);
    DateTime? selectedDate;
    String? selectedTime;
    final addonQuantities = _loadAddonQuantities(slot);
    final relatedAddonRequests = await _customerAddonRequestsForSlot(slot);
    if (!mounted) {
      return;
    }
    final expandedAddonGroups = <String>{};
    final initialMonth = _slotDate(slot).isBefore(DateTime.now())
        ? DateTime.now()
        : _slotDate(slot);
    var visibleMonth = DateTime(initialMonth.year, initialMonth.month, 1);
    var datesRequested = false;
    var loadingDates = false;
    var loadingSlots = false;
    var availableDates = <Map<String, dynamic>>[];
    var availableSlots = <Map<String, dynamic>>[];
    var showDatePicker = true;
    final currentDate = _slotDate(slot);
    final currentTime = (slot['time'] ?? '').toString().trim();
    DomlyPaymentMethod? paymentMethod;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<Map<String, dynamic>> editableDatesForMonth(
              List<Map<String, dynamic>> serverDates,
            ) {
              final today = DateTime.now();
              final firstAllowed = DateTime(today.year, today.month, today.day);
              final monthStart = DateTime(
                visibleMonth.year,
                visibleMonth.month,
                1,
              );
              final monthEnd = DateTime(
                visibleMonth.year,
                visibleMonth.month + 1,
                0,
              );
              final byKey = <String, Map<String, dynamic>>{};
              for (final item in serverDates) {
                final dateKey = (item['date'] ?? '').toString();
                final parsed = DateTime.tryParse(dateKey);
                if (parsed == null) {
                  continue;
                }
                final normalized = DateTime(
                  parsed.year,
                  parsed.month,
                  parsed.day,
                );
                if (normalized.isBefore(firstAllowed)) {
                  continue;
                }
                byKey[dateKey] = item;
              }
              for (
                var cursor = monthStart;
                !cursor.isAfter(monthEnd);
                cursor = cursor.add(const Duration(days: 1))
              ) {
                if (cursor.isBefore(firstAllowed)) {
                  continue;
                }
                final dateKey =
                    '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';
                byKey.putIfAbsent(dateKey, () => {'date': dateKey});
              }
              final dates = byKey.values.toList()
                ..sort(
                  (a, b) => (a['date'] ?? '').toString().compareTo(
                    (b['date'] ?? '').toString(),
                  ),
                );
              return dates;
            }

            Future<void> loadDates() async {
              if (subscriptionId.isEmpty) {
                return;
              }
              setModalState(() {
                loadingDates = true;
                availableDates = <Map<String, dynamic>>[];
                availableSlots = <Map<String, dynamic>>[];
                selectedTime = null;
                showDatePicker = true;
              });
              final result = await _data.getAvailableDates(
                subscriptionId: subscriptionId,
                month: visibleMonth,
              );
              final dates = (result['dates'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              if (!context.mounted) {
                return;
              }
              setModalState(() {
                availableDates = editableDatesForMonth(dates);
                final currentKey =
                    '${currentDate.year.toString().padLeft(4, '0')}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
                if (selectedDate == null &&
                    availableDates.any(
                      (item) => (item['date'] ?? '').toString() == currentKey,
                    )) {
                  selectedDate = currentDate;
                }
                loadingDates = false;
              });
            }

            Future<void> loadSlots(DateTime date) async {
              if (subscriptionId.isEmpty) {
                return;
              }
              setModalState(() {
                loadingSlots = true;
                selectedDate = date;
                selectedTime = null;
                availableSlots = <Map<String, dynamic>>[];
                showDatePicker = false;
              });
              final result = await _data.getAvailableSlots(
                subscriptionId: subscriptionId,
                date: date,
              );
              final slots = (result['slots'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              if (!context.mounted) {
                return;
              }
              setModalState(() {
                availableSlots = slots;
                loadingSlots = false;
              });
            }

            if (!addonsOnly && !datesRequested) {
              datesRequested = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  loadDates();
                }
              });
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            addonsOnly ? 'Добавить допы' : 'Изменить уборку',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      addonsOnly
                          ? 'Уборка уже идет. Можно добавить доп. услуги, уборщица увидит обновление в заказе и чек-листе.'
                          : 'Можно изменить дату, указать любое будущее время и добавить доп. услуги к этой уборке.',
                      style: const TextStyle(color: DomlyColors.muted),
                    ),
                    if (_addonQuantitiesSummary(
                      addonQuantities,
                    ).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSelectedAddonsPreview(
                        title: 'Уже выбрано в заказе',
                        lines: _addonQuantitiesSummary(addonQuantities),
                      ),
                    ],
                    if (relatedAddonRequests.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSelectedAddonsPreview(
                        title: 'Ожидает оплаты или подтверждения',
                        lines: relatedAddonRequests
                            .map(_addonRequestPreviewLine)
                            .where((line) => line.isNotEmpty)
                            .toList(),
                      ),
                    ],
                    if (!addonsOnly) ...[
                      const SizedBox(height: 18),
                      Text(
                        selectedDate == null
                            ? 'Выберите новую дату'
                            : 'Дата: ${domlyDateText(selectedDate!)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (showDatePicker) ...[
                        if (loadingDates)
                          const Center(child: CircularProgressIndicator())
                        else if (availableDates.isEmpty)
                          Text(
                            'Нет дат для выбранного месяца'.tr(),
                            style: TextStyle(color: DomlyColors.muted),
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: DomlyColors.backgroundSoft,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: AbsorbPointer(
                              absorbing: loadingSlots,
                              child: Localizations.override(
                                context: context,
                                locale: const Locale('ru'),
                                child: CalendarDatePicker(
                                  key: ValueKey(
                                    '${visibleMonth.year}-${visibleMonth.month}-${selectedDate?.toIso8601String() ?? ''}',
                                  ),
                                  initialDate: selectedDate ?? initialMonth,
                                  firstDate: DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                    DateTime.now().day,
                                  ),
                                  lastDate: DateTime(DateTime.now().year + 1),
                                  currentDate: DateTime.now(),
                                  onDateChanged: (date) => loadSlots(date),
                                  onDisplayedMonthChanged: (month) {
                                    final normalized = DateTime(
                                      month.year,
                                      month.month,
                                      1,
                                    );
                                    if (normalized.year == visibleMonth.year &&
                                        normalized.month ==
                                            visibleMonth.month) {
                                      return;
                                    }
                                    setModalState(() {
                                      visibleMonth = normalized;
                                      selectedDate = null;
                                      selectedTime = null;
                                      availableSlots = <Map<String, dynamic>>[];
                                    });
                                    loadDates();
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (selectedDate != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Время на ${domlyDateText(selectedDate!)}'.tr(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  showDatePicker = true;
                                  selectedTime = null;
                                });
                              },
                              child: Text('Изменить дату'.tr()),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (loadingSlots)
                          const Center(child: CircularProgressIndicator())
                        else if (availableSlots.isEmpty)
                          Text(
                            'На выбранную дату свободных окон нет. Выберите другую дату.'
                                .tr(),
                            style: TextStyle(color: DomlyColors.muted),
                          )
                        else
                          ...availableSlots.map((item) {
                            final time = (item['time'] ?? '').toString();
                            final isSelected = selectedTime == time;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: isSelected
                                    ? DomlyColors.buttonSoft
                                    : DomlyColors.backgroundSoft,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    setModalState(() {
                                      selectedTime = time;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            time,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Text(
                                            'Выбрано'.tr(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: DomlyColors.buttonPrimary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                      if (selectedTime != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Новое время: $selectedTime'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DomlyColors.foreground,
                          ),
                        ),
                      ] else if (currentTime.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Текущее время: $currentTime'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DomlyColors.muted,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Дополнительные\nуслуги'.tr(),
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: DomlyColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ..._addonGroups.map(
                      (group) => _buildAddonEditorGroup(
                        group,
                        addonQuantities,
                        expandedAddonGroups.contains(group.label),
                        () {
                          setModalState(() {
                            if (expandedAddonGroups.contains(group.label)) {
                              expandedAddonGroups.remove(group.label);
                            } else {
                              expandedAddonGroups.add(group.label);
                            }
                          });
                        },
                        (item, next) {
                          setModalState(() {
                            if (next <= 0) {
                              addonQuantities.remove(item.key);
                            } else {
                              addonQuantities[item.key] = next;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    DomlyPrimaryButton(
                      label: addonsOnly
                          ? 'Заказать допы'
                          : 'Сохранить изменения',
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final previousAddonQuantities = _loadAddonQuantities(slot);
      final nextAddonsDetailed = await _selectedAddonsDetailed(addonQuantities);
      final deltaAddonsDetailed = _deltaAddonsDetailed(
        previousQuantities: previousAddonQuantities,
        nextAddonsDetailed: nextAddonsDetailed,
      );
      if (!mounted) {
        return;
      }

      await PaymentLinkService.runBlocking(
        context,
        task: () => _data.updateScheduledCleaning(
          slotId: slot['id'].toString(),
          date: addonsOnly ? null : selectedDate,
          time: addonsOnly ? null : selectedTime,
          addonsDetailed: nextAddonsDetailed,
        ),
        message: addonsOnly ? 'Добавляем допы...' : 'Сохраняем изменения...',
      );
      if (!mounted) {
        return;
      }

      final billableAddonTotal = _billableAddonTotal(deltaAddonsDetailed);
      if (billableAddonTotal > 0) {
        final profile = await _data.customerProfileStream().first;
        if (!mounted) {
          return;
        }
        final bonusBalance = (profile?['bonusPoints'] as num?)?.toInt() ?? 0;
        final bonusLimit = addonBonusSpendLimit(
          billableAddonTotal,
          await AppConfigService.instance.promotionsStream().first,
        );
        if (!mounted) {
          return;
        }
        final paymentSelection = await showPaymentMethodOptionsDialog(
          context,
          bonusBalance: bonusBalance,
          maxBonusToSpend: bonusLimit,
          paymentAmount: billableAddonTotal,
        );
        if (!mounted) {
          return;
        }
        if (paymentSelection == null) {
          showDomlySnackBar(
            context,
            title: 'Изменения сохранены',
            subtitle:
                'Чтобы оплатить новые допуслуги, выберите способ оплаты позже из истории платежей.',
            type: DomlySnackBarType.info,
          );
          setState(() {});
          return;
        }
        paymentMethod = paymentSelection.method;
        var selectedBonusToSpend =
            paymentSelection.method == DomlyPaymentMethod.bonus
            ? billableAddonTotal
            : paymentSelection.useBonus
            ? bonusBalance
                  .clamp(0, bonusLimit)
                  .clamp(0, billableAddonTotal)
                  .toInt()
            : 0;
        String? kaspiPhone;
        if (selectedBonusToSpend >= billableAddonTotal) {
          paymentMethod = DomlyPaymentMethod.bonus;
          kaspiPhone = null;
        }
        if (paymentMethod == DomlyPaymentMethod.kaspi &&
            selectedBonusToSpend < billableAddonTotal) {
          final paymentRequest = await showKaspiInvoiceRequestOptionsDialog(
            context,
            bonusBalance: bonusBalance,
            maxBonusToSpend: bonusLimit,
            paymentAmount: billableAddonTotal,
            initialUseBonus: selectedBonusToSpend > 0,
          );
          if (!mounted) {
            return;
          }
          if (paymentRequest == null) {
            showDomlySnackBar(
              context,
              title: 'Изменения сохранены',
              subtitle:
                  'Чтобы оплатить новые допуслуги, отправьте номер KASPI.KZ позже из истории платежей.',
              type: DomlySnackBarType.info,
            );
            setState(() {});
            return;
          }
          kaspiPhone = paymentRequest.phone;
          selectedBonusToSpend = paymentRequest.useBonus
              ? bonusBalance
                    .clamp(0, bonusLimit)
                    .clamp(0, billableAddonTotal)
                    .toInt()
              : 0;
        }

        final bookingDate = selectedDate ?? _slotDate(slot);
        final bookingTime = selectedTime ?? (slot['time'] ?? '').toString();
        final created = await PaymentLinkService.runBlocking(
          context,
          task: () => _data.createOrderAndInvoice(
            amount: billableAddonTotal,
            customerId: _data.currentUserId,
            packageName:
                'Доп. услуги к ${(slot['package'] ?? 'уборке').toString()}',
            packageId: 'addons_only',
            pricingMode: 'addons_only',
            cleaningsPerMonth: 1,
            accessMethod: 'Я дома',
            addons: deltaAddonsDetailed
                .map((item) => (item['label'] ?? '').toString())
                .where((item) => item.isNotEmpty)
                .toList(),
            addonsDetailed: deltaAddonsDetailed,
            frequencyLabel:
                'Изменение уборки: ${domlyDateText(bookingDate)} · $bookingTime',
            rooms: 0,
            bathrooms: 0,
            area: ((slot['area'] as num?)?.toInt() ?? 0),
            address: (slot['address'] ?? '').toString(),
            residentialComplex: (slot['residentialComplex'] ?? '').toString(),
            entrance: (slot['entrance'] ?? '').toString(),
            apartment: (slot['apartment'] ?? '').toString(),
            houseId: (slot['houseId'] ?? '').toString(),
            slotId: (slot['id'] ?? slot['slotId'] ?? '').toString(),
            sourceOrderId:
                (slot['sourceOrderId'] ?? slot['customerOrderId'] ?? '')
                    .toString(),
            subscriptionId: (slot['subscriptionId'] ?? '').toString(),
            bonusToSpend: selectedBonusToSpend,
          ),
          message: 'Создаем заявку на оплату допуслуг...',
        );
        final createdLocally = created['localFallback'] == true;
        if (createdLocally) {
          if (!mounted) {
            return;
          }
          showDomlySnackBar(
            context,
            title: 'Оформление временно недоступно',
            subtitle:
                'Сервер не принял заявку на оплату допуслуг. Попробуйте позже.',
            type: DomlySnackBarType.error,
          );
          return;
        }

        final orderId = created['orderId']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          if (!mounted) {
            return;
          }
          if (paymentMethod == DomlyPaymentMethod.online) {
            final paymentSession = await PaymentLinkService.runBlocking(
              context,
              task: () => _data.createBccPaymentSession(orderId: orderId),
              message: 'Открываем онлайн-оплату...',
            );
            if (!mounted) {
              return;
            }
            Navigator.pushNamed(
              context,
              '/client/online-payment',
              arguments: paymentSession,
            );
            return;
          }
          if (paymentMethod == DomlyPaymentMethod.kaspi) {
            final invoiceResult = await PaymentLinkService.runBlocking(
              context,
              task: () => _data.submitKaspiInvoiceRequest(
                orderId: orderId,
                kaspiPhone: kaspiPhone!,
              ),
              message: 'Отправляем заявку на счёт...',
            );
            final invoiceSentLocally = invoiceResult['localFallback'] == true;
            if (invoiceSentLocally) {
              if (!mounted) {
                return;
              }
              showDomlySnackBar(
                context,
                title: 'Оформление временно недоступно',
                subtitle:
                    'Сервер не принял заявку на счёт за допуслуги. Попробуйте позже.',
                type: DomlySnackBarType.error,
              );
              return;
            }
          }
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {});
      showDomlySnackBar(
        context,
        title: addonsOnly ? 'Допы добавлены' : 'Уборка обновлена',
        subtitle: addonsOnly
            ? (billableAddonTotal > 0
                  ? paymentMethod == DomlyPaymentMethod.bonus
                        ? 'Доп. услуги оплачены бонусами и добавлены в текущую уборку.'
                        : 'Доп. услуги добавлены в текущую уборку. Счёт будет выставлен на Kaspi.'
                  : 'Доп. услуги обновлены в текущей уборке.')
            : (billableAddonTotal > 0
                  ? paymentMethod == DomlyPaymentMethod.bonus
                        ? 'Новые допуслуги оплачены бонусами и сохранены.'
                        : 'Новые дата, время и допуслуги сохранены. Счёт будет выставлен на Kaspi.'
                  : 'Новые дата, время и допуслуги сохранены.'),
        type: DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось изменить уборку',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  DateTime _slotDate(Map<String, dynamic> slot) {
    final value =
        slot['scheduledFor'] ?? slot['date'] ?? slot['scheduledDateKey'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
      }
    }
    return DateTime.now();
  }

  DateTime _orderDate(Map<String, dynamic> order) {
    final value =
        order['completedAt'] ??
        order['scheduledFor'] ??
        order['date'] ??
        order['createdAt'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  Future<List<Map<String, dynamic>>> _customerAddonRequestsForSlot(
    Map<String, dynamic> slot,
  ) async {
    final ids = <String>{
      for (final key in const [
        'id',
        'slotId',
        'scheduleSlotId',
        'sourceOrderId',
        'customerOrderId',
        'orderId',
      ])
        (slot[key] ?? '').toString().trim(),
    }..removeWhere((item) => item.isEmpty);
    if (ids.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final requests = await _data.customerAddonRequestsStream().first;
    final hiddenStatuses = {
      'rejected_by_customer',
      'cancelled',
      'canceled',
      'merged',
      'paid',
      'completed',
    };
    return requests.where((request) {
      final status = (request['status'] ?? '').toString().trim().toLowerCase();
      if (hiddenStatuses.contains(status)) {
        return false;
      }
      for (final key in const [
        'slotId',
        'scheduleSlotId',
        'sourceOrderId',
        'customerOrderId',
        'orderId',
      ]) {
        if (ids.contains((request[key] ?? '').toString().trim())) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  List<String> _addonQuantitiesSummary(Map<String, int> quantities) {
    if (quantities.isEmpty) {
      return const <String>[];
    }
    final labels = <String, String>{};
    final durations = <String, int>{};
    for (final group in _addonGroups) {
      for (final item in group.items) {
        labels[item.key] = item.label;
        durations[item.key] = item.durationMinutes;
      }
    }
    return quantities.entries.where((entry) => entry.value > 0).map((entry) {
      final label = labels[entry.key] ?? entry.key;
      return entry.value > 1 ? '$label × ${entry.value}' : label;
    }).toList();
  }

  String _addonRequestPreviewLine(Map<String, dynamic> request) {
    final addons = (request['addonsDetailed'] as List? ?? const [])
        .whereType<Map>()
        .map((item) {
          final label = (item['label'] ?? item['key'] ?? '').toString();
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          return quantity > 1 ? '$label × $quantity' : label;
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (addons.isEmpty) {
      return '';
    }
    final amount = (request['amount'] as num?)?.toInt() ?? 0;
    final status = (request['paymentStatus'] ?? request['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final statusText = status == 'paid' || status == 'payment_confirmed'
        ? 'оплачено'
        : 'ожидает оплаты';
    return '${addons.join(', ')} · $statusText${amount > 0 ? ' · ${_moneyText(amount)}' : ''}';
  }

  Widget _buildSelectedAddonsPreview({
    required String title,
    required List<String> lines,
  }) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: DomlyColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, int> _loadAddonQuantities(Map<String, dynamic> slot) {
    final values = <String, int>{};
    final detailed = (slot['addonsDetailed'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    for (final raw in detailed) {
      final key = raw['key']?.toString() ?? '';
      final quantity = (raw['quantity'] as num?)?.toInt() ?? 0;
      if (key.isNotEmpty && quantity > 0) {
        values[key] = quantity;
      }
    }
    return values;
  }

  int _selectedCountForGroup(
    _OrderAddonGroupDef group,
    Map<String, int> addonQuantities,
  ) {
    return group.items.fold<int>(
      0,
      (total, item) => total + (addonQuantities[item.key] ?? 0),
    );
  }

  Widget _buildAddonEditorGroup(
    _OrderAddonGroupDef group,
    Map<String, int> addonQuantities,
    bool expanded,
    VoidCallback onToggle,
    void Function(_OrderAddonItemDef item, int quantity) onItemChanged,
  ) {
    final selectedCount = _selectedCountForGroup(group, addonQuantities);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: DomlyColors.foreground,
                        ),
                      ),
                    ),
                    if (selectedCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        height: 22,
                        constraints: const BoxConstraints(minWidth: 22),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: DomlyColors.buttonPrimary.withValues(
                            alpha: .12,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$selectedCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 24,
                      color: DomlyColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: group.items
                    .map(
                      (item) => _buildAddonEditorRow(
                        item,
                        addonQuantities,
                        (next) => onItemChanged(item, next),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddonEditorRow(
    _OrderAddonItemDef item,
    Map<String, int> addonQuantities,
    ValueChanged<int> onChanged,
  ) {
    final quantity = addonQuantities[item.key] ?? 0;
    final unitPrice = _addonUnitPrices[item.key] ?? 0;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            child: Material(
              color: DomlyColors.backgroundSoft,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _showAddonInfo(item, unitPrice: unitPrice),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: DomlyColors.buttonPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: DomlyColors.foreground,
                  ),
                ),
                if (item.separatePayment) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Оплачивается отдельно при оценке специалиста'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: DomlyColors.buttonPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else if (item.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.note!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (item.supportsQuantity)
            Container(
              decoration: BoxDecoration(
                color: DomlyColors.backgroundSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: quantity <= 0
                        ? null
                        : () => onChanged(quantity - 1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: DomlyColors.foreground,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onChanged(quantity + 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: 104,
              child: DomlySecondaryButton(
                label: quantity > 0 ? 'Убрать' : 'Добавить',
                onPressed: () => onChanged(quantity > 0 ? 0 : 1),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddonInfo(
    _OrderAddonItemDef item, {
    required int unitPrice,
  }) async {
    final infoConfig = await AppConfigService.instance.getInfoContent(item.key);
    if (!mounted) {
      return;
    }
    final fallbackInfo = {
      'title': item.label,
      'shortInfo': item.infoText ?? 'Информация по услуге пока не заполнена.',
      'description': item.infoText ?? 'Информация по услуге пока не заполнена.',
      'fullInfo': item.fullInfo ?? '',
      'longDescription': item.fullInfo ?? '',
      'features': item.features,
      'price': unitPrice > 0 ? unitPrice : null,
    };
    await InfoDialog.showFromConfig(
      context,
      config: infoConfig != null && infoConfig.isNotEmpty
          ? {...fallbackInfo, ...infoConfig}
          : fallbackInfo,
    );
  }

  Future<List<Map<String, dynamic>>> _selectedAddonsDetailed(
    Map<String, int> addonQuantities,
  ) async {
    final labels = <String, String>{};
    final durations = <String, int>{};
    for (final group in _addonGroups) {
      for (final item in group.items) {
        labels[item.key] = item.label;
        durations[item.key] = item.durationMinutes;
      }
    }
    final selected = addonQuantities.entries
        .where((entry) => entry.value > 0)
        .map(
          (entry) => <String, dynamic>{
            'key': entry.key,
            'label': labels[entry.key] ?? entry.key,
            'quantity': entry.value,
          },
        )
        .toList();
    if (selected.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final enriched = await Future.wait(
      selected.map((item) async {
        final key = (item['key'] ?? '').toString();
        final config = key.isEmpty
            ? null
            : await AppConfigService.instance.getAddonConfig(key);
        final separatePayment =
            _addonSeparatePayment[key] ?? config?['separatePayment'] == true;
        return <String, dynamic>{
          ...item,
          'price':
              _addonUnitPrices[key] ?? (config?['price'] as num?)?.toInt() ?? 0,
          'durationMinutes':
              (durations[key] ??
                  (config?['durationMinutes'] as num?)?.toInt() ??
                  15) *
              ((item['quantity'] as num?)?.toInt() ?? 1),
          'separatePayment': separatePayment,
          'separate': separatePayment,
        };
      }),
    );
    return enriched;
  }

  List<Map<String, dynamic>> _deltaAddonsDetailed({
    required Map<String, int> previousQuantities,
    required List<Map<String, dynamic>> nextAddonsDetailed,
  }) {
    final delta = <Map<String, dynamic>>[];
    for (final item in nextAddonsDetailed) {
      final key = (item['key'] ?? '').toString();
      if (key.isEmpty) {
        continue;
      }
      final nextQuantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final previousQuantity = previousQuantities[key] ?? 0;
      final addedQuantity = nextQuantity - previousQuantity;
      if (addedQuantity <= 0) {
        continue;
      }
      delta.add({...item, 'quantity': addedQuantity});
    }
    return delta;
  }

  int _billableAddonTotal(List<Map<String, dynamic>> items) {
    return items.fold<int>(0, (total, raw) {
      final quantity = (raw['quantity'] as num?)?.toInt() ?? 0;
      final price = (raw['price'] as num?)?.toInt() ?? 0;
      if (raw['separatePayment'] == true) {
        return total;
      }
      return total + (quantity * price);
    });
  }
}

class _OrdersFigmaHeader extends StatelessWidget {
  const _OrdersFigmaHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF439F73), Color(0xFF80D4B0)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -17,
            top: -22,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -49,
            bottom: -75,
            child: Container(
              width: 138,
              height: 138,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 20,
            child: Material(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.maybePop(context),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.arrow_back,
                    color: Color(0xFF2E7D5B),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 52,
            top: 17,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Заказы'.tr(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFEDFAF2),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersSegmentedTabs extends StatelessWidget {
  const _OrdersSegmentedTabs({required this.activeIndex, required this.onTap});

  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: activeIndex == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
              width: 166,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFDEECE3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _OrdersTabButton(
                label: 'Активные',
                selected: activeIndex == 0,
                onTap: () => onTap(0),
              ),
              _OrdersTabButton(
                label: 'История',
                selected: activeIndex == 1,
                onTap: () => onTap(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersTabButton extends StatelessWidget {
  const _OrdersTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF2B4338)
                  : const Color(0xFF658170),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 18 / 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdersStatusPill extends StatelessWidget {
  const _OrdersStatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 16 / 12,
        ),
      ),
    );
  }
}

class _SlotActionChip extends StatelessWidget {
  const _SlotActionChip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? DomlyColors.danger : const Color(0xFFC8794E);
    return Material(
      color: danger ? const Color(0xFFFFF2F1) : const Color(0xFFF8E7DD),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38, minWidth: 94),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CleaningStartConfirmationPanel extends StatelessWidget {
  const _CleaningStartConfirmationPanel({
    required this.onConfirm,
    required this.onReject,
    this.rejected = false,
  });

  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAF6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rejected
                ? 'Вы не подтвердили старт уборки'
                : 'Уборщица начала уборку?',
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Подтвердите, что уборщица уже приступила к работе. Без ответа она не сможет завершить заказ.'
                .tr(),
            style: TextStyle(
              color: Color(0xFF658170),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DomlyPrimaryButton(label: 'Да', onPressed: onConfirm),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DomlySecondaryButton(
                  label: 'Нет',
                  foregroundColor: DomlyColors.danger,
                  onPressed: onReject,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersAvatar extends StatelessWidget {
  const _OrdersAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'A' : name.trim().characters.first;
    return Container(
      width: 55,
      height: 55,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFCF7548), Color(0xFFEEB09B)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(
        initial.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 27 / 20,
        ),
      ),
    );
  }
}

class _OrdersFigmaMessageCard extends StatelessWidget {
  const _OrdersFigmaMessageCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF658170),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 18 / 13,
            ),
          ),
        ],
      ),
    );
  }
}
