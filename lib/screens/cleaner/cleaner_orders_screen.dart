import 'dart:async';

import 'package:flutter/material.dart';
import '../../utils/backend_compat.dart';

import '../../services/call_service.dart';
import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/order_display.dart';
import 'cleaner_service_area_notice.dart';
import '../../localization/translation_controller.dart';

class CleanerOrdersScreen extends StatefulWidget {
  const CleanerOrdersScreen({super.key});

  @override
  State<CleanerOrdersScreen> createState() => _CleanerOrdersScreenState();
}

class _CleanerOrdersScreenState extends State<CleanerOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _data = FirestoreDataService.instance;
  late final Stream<Map<String, dynamic>?> _profileStream;
  late final Stream<List<Map<String, dynamic>>> _scheduleSlotsStream;
  late final Stream<List<Map<String, dynamic>>> _offersStream;
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  late final Stream<List<Map<String, dynamic>>> _notificationsStream;
  late final Stream<List<Map<String, dynamic>>> _chatSummariesStream;
  bool _initialTabApplied = false;
  final Set<String> _acceptingOfferIds = <String>{};
  final Set<String> _rejectingOfferIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _profileStream = _data.cleanerProfileStream().asBroadcastStream();
    _scheduleSlotsStream = _data.cleanerScheduleSlotsStream();
    _offersStream = _data.cleanerOrderOffersStream().asBroadcastStream();
    _ordersStream = _data.cleanerOrdersStream();
    _notificationsStream = _data.userNotificationsStream();
    _chatSummariesStream = _data.userChatSummariesStream();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    if (rawTab == 'completed' || rawTab == 'history' || rawTab == 'done') {
      _tabController.index = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileStream,
      initialData: const <String, dynamic>{},
      builder: (context, profileSnap) {
        final profile = profileSnap.data ?? const <String, dynamic>{};
        final hasServiceAreas = profileSnap.hasError
            ? true
            : cleanerHasServiceAreas(profile);
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _scheduleSlotsStream,
          initialData: const <Map<String, dynamic>>[],
          builder: (context, snap) {
            if (snap.hasError) {
              return const DomlyShell(
                bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 2),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: DomlyEmptyStateCard(
                        title: 'Не удалось загрузить заказы',
                        subtitle: 'Обновите экран и попробуйте снова.',
                        icon: Icons.error_outline,
                      ),
                    ),
                  ),
                ),
              );
            }
            final activeSlots = snap.data ?? <Map<String, dynamic>>[];
            final active = activeSlots.where((e) {
              return _isActiveAssignment(e);
            }).toList();

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _offersStream,
              initialData: const <Map<String, dynamic>>[],
              builder: (context, offerSnap) {
                final offers = offerSnap.hasError
                    ? const <Map<String, dynamic>>[]
                    : offerSnap.data ?? <Map<String, dynamic>>[];
                final activeOffers = offers.where((offer) {
                  try {
                    return _offerSecondsLeft(offer) > 0;
                  } catch (_) {
                    return false;
                  }
                }).toList();
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _ordersStream,
                  initialData: const <Map<String, dynamic>>[],
                  builder: (context, doneSnap) {
                    if (doneSnap.hasError) {
                      return const DomlyShell(
                        bottomNavigationBar: DomlyCleanerBottomNav(
                          currentIndex: 2,
                        ),
                        child: SafeArea(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: DomlyEmptyStateCard(
                                title: 'Не удалось загрузить историю заказов',
                                subtitle: 'Обновите экран и попробуйте снова.',
                                icon: Icons.error_outline,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final cleanerOrders =
                        doneSnap.data ?? <Map<String, dynamic>>[];
                    final done = cleanerOrders
                        .where(
                          (e) => (e['status'] ?? '').toString() == 'completed',
                        )
                        .toList();
                    final activeCleanerOrders = cleanerOrders
                        .where((e) => _isActiveAssignment(e))
                        .toList();
                    final activeAssignments = _mergeActiveAssignments(
                      active,
                      activeCleanerOrders,
                    );

                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _chatSummariesStream,
                      initialData: const <Map<String, dynamic>>[],
                      builder: (context, chatSnap) {
                        final chatSummaries = chatSnap.hasError
                            ? const <Map<String, dynamic>>[]
                            : chatSnap.data ?? const <Map<String, dynamic>>[];
                        return DomlyShell(
                          bottomNavigationBar: const DomlyCleanerBottomNav(
                            currentIndex: 2,
                          ),
                          child: SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 430,
                                ),
                                child: Column(
                                  children: [
                                    DomlyHeader(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        6,
                                        20,
                                        10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          domlyTopIconButton(
                                            icon: Icons.arrow_back,
                                            onPressed: () =>
                                                Navigator.pop(context),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Мои заказы'.tr(),
                                                  style: TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Активные предложения и уборки'
                                                      .tr(),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xCCFFFFFF),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _notificationsActionButton(),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        2,
                                        20,
                                        0,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: DomlyColors.border,
                                          ),
                                        ),
                                        child: TabBar(
                                          controller: _tabController,
                                          indicator: BoxDecoration(
                                            color: DomlyColors.buttonPrimary,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          dividerColor: Colors.transparent,
                                          labelColor: Colors.white,
                                          unselectedLabelColor:
                                              DomlyColors.muted,
                                          tabs: const [
                                            Tab(text: 'Активные'),
                                            Tab(text: 'Завершенные'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Expanded(
                                      child: TabBarView(
                                        controller: _tabController,
                                        children: [
                                          _activeTab(
                                            offers: activeOffers,
                                            slots: activeAssignments,
                                            chatSummaries: chatSummaries,
                                            hasServiceAreas: hasServiceAreas,
                                          ),
                                          _list(done),
                                        ],
                                      ),
                                    ),
                                  ],
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
          },
        );
      },
    );
  }

  Widget _activeTab({
    required List<Map<String, dynamic>> offers,
    required List<Map<String, dynamic>> slots,
    required List<Map<String, dynamic>> chatSummaries,
    required bool hasServiceAreas,
  }) {
    if (!hasServiceAreas && offers.isEmpty && active.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          CleanerServiceAreaNotice(
            onPressed: () => Navigator.pushNamed(context, '/cleaner/profile'),
          ),
        ],
      );
    }
    if (offers.isEmpty && slots.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: DomlyEmptyStateCard(
            title: 'Нет активных заказов',
            subtitle:
                'Новые предложения и подтвержденные уборки появятся здесь.',
            icon: Icons.event_busy_outlined,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        if (!hasServiceAreas) ...[
          const SizedBox(height: 4),
          CleanerServiceAreaNotice(
            onPressed: () => Navigator.pushNamed(context, '/cleaner/profile'),
          ),
          const SizedBox(height: 8),
        ],
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Новые предложения'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 8),
          for (final offer in offers) ...[
            _offerCard(offer),
            const SizedBox(height: 8),
          ],
        ],
        if (slots.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Подтвержденные визиты'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 8),
          for (final slot in slots) ...[
            _slotCard(slot, chatSummaries: chatSummaries),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _list(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: DomlyEmptyStateCard(
            title: 'История пока пуста',
            subtitle:
                'После завершения уборок здесь появятся предыдущие заказы.',
            icon: Icons.history_toggle_off,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      itemCount: list.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 4.0),
        child: _card(list[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString();
    final displayId = orderDisplayId(order);
    final area = _intValue(order['area']);
    final customerPhone = _customerPhone(order);
    final rawDate = order['date'] is Timestamp
        ? (order['date'] as Timestamp).toDate()
        : null;
    final dateLabel = rawDate != null
        ? domlyDateText(rawDate)
        : (order['dateText'] ?? order['date'] ?? '—').toString();
    return DomlyCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _color(status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _text(status),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 2),
          Text('Заказ: $displayId'.tr()),
          Text('Дата: $dateLabel'.tr()),
          Text('Время: ${(order['time'] ?? '—')}'),
          if ((order['estimatedDurationMinutes'] ??
                      order['totalDurationMinutes'])
                  .toString()
                  .isNotEmpty &&
              '${order['estimatedDurationMinutes'] ?? order['totalDurationMinutes']}' !=
                  'null')
            Text(
              'Длительность: ${(order['estimatedDurationMinutes'] ?? order['totalDurationMinutes'] ?? '—')} мин',
            ),
          Text('Клиент: ${(order['customerName'] ?? order['client'] ?? '—')}'),
          Text(
            'Телефон клиента: ${customerPhone.isEmpty ? '.tr()—' : customerPhone}',
          ),
          Text('Адрес: ${(order['address'] ?? '—')}'),
          if (area > 0) Text('Площадь: $area м²'.tr()),
          if (_shouldShowResidentialComplex(
            (order['address'] ?? '').toString(),
            (order['residentialComplex'] ?? '').toString(),
          ))
            Text(
              _formatResidentialComplex(
                (order['residentialComplex'] ?? '—').toString(),
              ),
            ),
          if ((order['entrance'] ?? '').toString().isNotEmpty ||
              (order['apartment'] ?? '').toString().isNotEmpty)
            Text(
              'Подъезд: ${(order['entrance'] ?? '—')} • Квартира: ${(order['apartment'] ?? '—')}',
            ),
          if ((order['accessMethod'] ?? '').toString().isNotEmpty)
            Text('Доступ: ${(order['accessMethod'] ?? '—')}'),
          Text('Пакет: ${(order['package'] ?? '—')}'),
          if (status != 'completed') ...[
            const SizedBox(height: 2),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        label: 'Звонок',
                        onPressed: customerPhone.isEmpty
                            ? null
                            : () => _callCustomer(customerPhone),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        label: 'Чат',
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/chat',
                            arguments: {
                              'orderId':
                                  order['chatId'] ??
                                  order['scheduleSlotId'] ??
                                  order['slotId'] ??
                                  order['customerOrderId'] ??
                                  order['id'],
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        label: 'Чек-лист',
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/cleaner/checklist',
                            arguments: {
                              'orderId':
                                  order['scheduleSlotId'] ??
                                  order['slotId'] ??
                                  order['id'] ??
                                  order['customerOrderId'],
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (status == 'in_progress') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: DomlySecondaryButton(
                      label: 'Предложить допы',
                      onPressed: () => _showAddonRequestSheet(order),
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  child: DomlyPrimaryButton(
                    label: _primaryActionLabel(status),
                    onPressed: _primaryActionEnabled(status)
                        ? () => _handlePrimaryAction(order)
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _notificationsActionButton() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _notificationsStream,
      initialData: const <Map<String, dynamic>>[],
      builder: (context, notificationsSnap) {
        final unreadCount = (notificationsSnap.data ?? const [])
            .where((item) => item['read'] != true)
            .length;
        return domlyTopBadgeIconButton(
          icon: Icons.notifications_none,
          badgeCount: unreadCount,
          onPressed: () => Navigator.pushNamed(context, '/notifications'),
        );
      },
    );
  }

  String _formatAddonLabels(Map<String, dynamic> data) {
    final labels = <String>[];
    void addLabel(Object? value) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty &&
          !_isStandardCleaningTask(text) &&
          !labels.contains(text)) {
        labels.add(text);
      }
    }

    final detailed = data['addonsDetailed'];
    if (detailed is List) {
      for (final item in detailed) {
        if (item is Map) {
          final label =
              item['label'] ??
              item['title'] ??
              item['name'] ??
              item['optionLabel'] ??
              item['key'];
          addLabel(label);
        } else {
          addLabel(item);
        }
      }
    }

    final separate = data['separatePaymentAddons'];
    if (separate is List) {
      for (final item in separate) {
        if (item is Map) {
          addLabel(
            item['label'] ?? item['title'] ?? item['name'] ?? item['key'],
          );
        } else {
          addLabel(item);
        }
      }
    }

    final simple = data['addons'];
    if (simple is List) {
      for (final item in simple) {
        if (item is Map) {
          addLabel(
            item['label'] ?? item['title'] ?? item['name'] ?? item['key'],
          );
        } else {
          addLabel(item);
        }
      }
    }
    return labels.join(', ');
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

  Widget _offerCard(Map<String, dynamic> offer) {
    final offerId = (offer['id'] ?? '').toString();
    final remainingSeconds = _offerSecondsLeft(offer);
    final addonLabels = _formatAddonLabels(offer);
    final estimatedMinutes = _intValue(offer['estimatedDurationMinutes']);
    final travelMinutes = _intValue(offer['travelMinutes']);
    final area = _intValue(offer['area'] ?? offer['areaSqm']);
    final dateLabel = _offerDateText(offer);
    final isAccepting = _acceptingOfferIds.contains(offerId);
    final isRejecting = _rejectingOfferIds.contains(offerId);
    final canRespond = remainingSeconds > 0 && !isAccepting && !isRejecting;

    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA500),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Предложение'.tr(),
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const Spacer(),
              _offerCountdown(offer),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            (offer['address'] ?? 'Адрес уточняется').toString(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text('Дата уборки: $dateLabel'.tr()),
          Text('Время начала: ${(offer['time'] ?? '—')}'),
          if (area > 0) Text('Площадь: $area м²'.tr()),
          if (estimatedMinutes > 0)
            Text('Примерная длительность: $estimatedMinutes мин'.tr()),
          if (travelMinutes > 0) Text('Доезд: $travelMinutes мин'.tr()),
          if (addonLabels.isNotEmpty) Text('Доп. услуги: $addonLabels'.tr()),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DomlySecondaryButton(
                  onPressed: canRespond
                      ? () => _handleRejectOffer(offerId)
                      : null,
                  label: isRejecting ? 'Отклоняем...' : 'Отказаться',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DomlyPrimaryButton(
                  label: isAccepting ? 'Принимаем...' : 'Принять',
                  onPressed: canRespond
                      ? () => _handleAcceptOffer(offerId)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slotCard(
    Map<String, dynamic> slot, {
    required List<Map<String, dynamic>> chatSummaries,
  }) {
    final status = (slot['status'] ?? '').toString();
    final area = _intValue(slot['area']);
    final addonLabels = _formatAddonLabels(slot);
    final canCancelAssignment = _canCleanerCancelAssignment(slot);
    final orderId =
        (slot['scheduleSlotId'] ??
                slot['slotId'] ??
                slot['id'] ??
                slot['sourceOrderId'] ??
                slot['customerOrderId'])
            .toString();
    final chatId = (slot['chatId'] ?? orderId).toString();
    final chatUnread = _chatUnreadCount(chatSummaries, chatId);
    final displayId = orderDisplayId(slot);
    final customerPhone = _customerPhone(slot);
    return DomlyCard(
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _color(status == 'assigned' ? 'confirmed' : status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status == 'assigned' ? 'Запланировано' : _text(status),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 2),
          Text('Заказ: $displayId'.tr()),
          Text('Дата: ${_slotDateText(slot)}'.tr()),
          Text('Время уборки: ${(slot['time'] ?? '—')}'),
          Text(
            'Длительность: ${(slot['totalDurationMinutes'] ?? slot['estimatedDurationMinutes'] ?? '—')} мин',
          ),
          Text('Клиент: ${(slot['customerName'] ?? '—')}'),
          if (customerPhone.isNotEmpty) Text('Телефон: $customerPhone'.tr()),
          Text('Адрес: ${(slot['address'] ?? '—')}'),
          if (area > 0) Text('Площадь: $area м²'.tr()),
          if (_shouldShowResidentialComplex(
            (slot['address'] ?? '').toString(),
            (slot['residentialComplex'] ?? '').toString(),
          ))
            Text(
              _formatResidentialComplex(
                (slot['residentialComplex'] ?? '—').toString(),
              ),
            ),
          if ((slot['entrance'] ?? '').toString().isNotEmpty ||
              (slot['apartment'] ?? '').toString().isNotEmpty)
            Text(
              'Подъезд: ${(slot['entrance'] ?? '—')} • Квартира: ${(slot['apartment'] ?? '—')}',
            ),
          if ((slot['accessMethod'] ?? '').toString().isNotEmpty)
            Text('Доступ: ${(slot['accessMethod'] ?? '—')}'),
          Text('Пакет: ${(slot['package'] ?? '—')}'),
          if (addonLabels.isNotEmpty) Text('Доп. услуги: $addonLabels'.tr()),
          const SizedBox(height: 10),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: 'Звонок',
                      onPressed: customerPhone.isEmpty
                          ? null
                          : () => _callCustomer(customerPhone),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _actionButton(
                      label: chatUnread > 0 ? 'Чат ($chatUnread)' : 'Чат',
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/chat',
                          arguments: {'orderId': chatId},
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _actionButton(
                      label: 'Чек-лист',
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/cleaner/checklist',
                          arguments: {'orderId': orderId},
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (status == 'in_progress') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: DomlySecondaryButton(
                    label: 'Предложить допы',
                    onPressed: () => _showAddonRequestSheet(slot),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              if (canCancelAssignment) ...[
                SizedBox(
                  width: double.infinity,
                  child: DomlySecondaryButton(
                    label: 'Отменить заказ',
                    foregroundColor: DomlyColors.danger,
                    onPressed: () => _handleCancelAssignment(slot),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: DomlyPrimaryButton(
                  label: _primaryActionLabel(status),
                  onPressed: _primaryActionEnabled(status)
                      ? () => _handlePrimaryAction(slot)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddonRequestSheet(Map<String, dynamic> order) async {
    final slotId = _statusTargetId(order);
    if (slotId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не удалось открыть допы',
        subtitle: 'Не найден ID текущей уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    final groups = await AppConfigService.instance.getAddonGroupConfigs();
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
                              'Предложить доп. услуги'.tr(),
                              style: TextStyle(
                                color: DomlyColors.foreground,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Клиент получит согласование. После оплаты и подтверждения админом допы добавятся в заказ.'
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
                                          title: 'Предложение отправлено',
                                          subtitle:
                                              'Клиент получит запрос на согласование.',
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

  Color _color(String status) {
    switch (status) {
      case 'confirmed':
      case 'assigned':
      case 'in_progress':
      case 'start_pending':
        return DomlyColors.primary;
      case 'pending':
      case 'pending_assignment':
        return const Color(0xFFFFA500);
      case 'canceled':
      case 'cancelled':
        return DomlyColors.danger;
      case 'completed':
        return const Color(0xFF22C55E);
      default:
        return DomlyColors.muted;
    }
  }

  String _customerPhone(Map<String, dynamic> data) {
    for (final key in [
      'customerPhone',
      'clientPhone',
      'phone',
      'customer_phone',
      'client_phone',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null' && value != '—') {
        return value;
      }
    }
    final customer = data['customer'];
    if (customer is Map) {
      final value = (customer['phone'] ?? customer['customerPhone'] ?? '')
          .toString();
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  Future<void> _callCustomer(String phone) async {
    final launched = await CallService.callPhone(phone);
    if (launched || !mounted) {
      return;
    }
    showDomlySnackBar(
      context,
      title: 'Не удалось открыть звонок',
      subtitle: 'Проверьте, что на устройстве доступно приложение телефона.',
      type: DomlySnackBarType.error,
    );
  }

  String _text(String status) {
    switch (status) {
      case 'confirmed':
      case 'assigned':
        return 'Подтверждено';
      case 'start_pending':
        return 'Ждём клиента';
      case 'offer_pending':
      case 'scheduled_pending_confirmation':
        return 'Предложение активно';
      case 'scheduled_confirmed':
        return 'Запланировано';
      case 'reassignment_needed':
        return 'Нужно переназначение';
      case 'pending':
      case 'pending_assignment':
        return 'Ожидание';
      case 'in_progress':
        return 'В процессе';
      case 'canceled':
      case 'cancelled':
        return 'Отменено';
      case 'completed':
        return 'Завершено';
      default:
        return orderStatusLabel(status);
    }
  }

  Future<void> _handlePrimaryAction(Map<String, dynamic> order) async {
    final status = (order['status'] ?? '').toString().toLowerCase();
    final orderId = _statusTargetId(order);
    if (orderId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не удалось открыть заказ',
        subtitle: 'Не найден ID уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }

    if (status == 'pending') {
      await _data.advanceOrderStatus(orderId: orderId, toStatus: 'assigned');
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Заказ принят',
        subtitle: 'Теперь он появится в активной работе.',
        type: DomlySnackBarType.success,
      );
      return;
    }

    if (status == 'confirmed' || status == 'assigned') {
      try {
        await _data.advanceOrderStatus(
          orderId: orderId,
          toStatus: 'in_progress',
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showDomlySnackBar(
          context,
          title: 'Не удалось начать уборку',
          subtitle: '$error',
          type: DomlySnackBarType.error,
        );
        return;
      }
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Запрос отправлен клиенту',
        subtitle:
            'Фотоотчёт и завершение будут доступны после подтверждения старта.',
        type: DomlySnackBarType.info,
      );
      return;
    }
    if (status == 'start_pending') {
      showDomlySnackBar(
        context,
        title: 'Ждём подтверждение клиента',
        subtitle: 'Завершить уборку можно только после ответа "Да".',
        type: DomlySnackBarType.info,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.pushNamed(
      context,
      '/photo-report',
      arguments: {'orderId': orderId},
    );
  }

  String _primaryActionLabel(String status) {
    switch (status) {
      case 'confirmed':
      case 'assigned':
        return 'Начать';
      case 'start_pending':
        return 'Ждём клиента';
      case 'in_progress':
        return 'Продолжить';
      default:
        return 'Принять';
    }
  }

  bool _primaryActionEnabled(String status) {
    return status != 'start_pending';
  }

  bool _canCleanerCancelAssignment(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'assigned' && status != 'confirmed') {
      return false;
    }
    final start = _slotStartDateTime(slot);
    return start.difference(DateTime.now()) >= const Duration(hours: 12);
  }

  DateTime _slotStartDateTime(Map<String, dynamic> slot) {
    final date = _slotDate(slot);
    final match = RegExp(
      r'(\d{1,2}):(\d{2})',
    ).firstMatch((slot['time'] ?? '').toString());
    final hour = int.tryParse(match?.group(1) ?? '') ?? date.hour;
    final minute = int.tryParse(match?.group(2) ?? '') ?? date.minute;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Future<void> _handleCancelAssignment(Map<String, dynamic> slot) async {
    final orderId = _statusTargetId(slot);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Отменить заказ?'.tr()),
        content: Text(
          'Заказ уйдет другим уборщицам с той же датой и временем. Отменить можно только за 12 часов до начала.'
              .tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Назад'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Отменить заказ'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _data.advanceOrderStatus(orderId: orderId, toStatus: 'canceled');
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Заказ отменен',
        subtitle: 'Мы отправили его другим уборщицам на это же время.',
        type: DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отменить заказ',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  String _statusTargetId(Map<String, dynamic> order) {
    for (final key in ['scheduleSlotId', 'slotId']) {
      final value = (order[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    final scopeType = (order['scopeType'] ?? '').toString();
    final looksLikeScheduleSlot =
        scopeType == 'schedule_slot' ||
        order.containsKey('scheduledDateKey') ||
        order.containsKey('scheduledFor');
    if (looksLikeScheduleSlot) {
      final value = (order['id'] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    for (final key in ['sourceOrderId', 'customerOrderId', 'orderId', 'id']) {
      final value = (order[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return '';
  }

  Future<void> _handleAcceptOffer(String offerId) async {
    if (_acceptingOfferIds.contains(offerId)) {
      return;
    }
    setState(() => _acceptingOfferIds.add(offerId));
    try {
      await _data.acceptOrderOffer(offerId: offerId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось принять заказ',
        subtitle: _friendlyError(error),
        type: DomlySnackBarType.error,
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _acceptingOfferIds.remove(offerId));
      }
    }
    if (!mounted) {
      return;
    }
    showDomlySnackBar(
      context,
      title: 'Заказ принят',
      subtitle: 'Предложение закреплено за вами.',
      type: DomlySnackBarType.success,
    );
  }

  Future<void> _handleRejectOffer(String offerId) async {
    if (_rejectingOfferIds.contains(offerId)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Отклонить заказ?'.tr()),
        content: Text('Вы точно хотите отклонить этот заказ?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Назад'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Да, отклонить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _rejectingOfferIds.add(offerId));
    try {
      await _data.rejectOrderOffer(offerId: offerId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отклонить заказ',
        subtitle: _friendlyError(error),
        type: DomlySnackBarType.error,
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _rejectingOfferIds.remove(offerId));
      }
    }
    if (!mounted) {
      return;
    }
    showDomlySnackBar(
      context,
      title: 'Отказ отправлен',
      subtitle: 'Предложение снято из вашего списка.',
      type: DomlySnackBarType.info,
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('unauthenticated') ||
        text.contains('Authentication required') ||
        text.contains('Нужна авторизация')) {
      return 'Сессия устарела. Выйдите и войдите снова.';
    }
    if (text.contains('resource-exhausted') ||
        text.contains('RESOURCE_EXHAUSTED')) {
      return 'Сервис временно перегружен. Попробуйте еще раз через минуту.';
    }
    if (text.contains('permission-denied')) {
      return 'Нет доступа к этому заказу.';
    }
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 120
        ? '${firstLine.substring(0, 120)}...'
        : firstLine;
  }

  bool _isTerminalAssignment(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString().toLowerCase();
    return status == 'completed' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  bool _isActiveAssignment(Map<String, dynamic> item) {
    if (_isTerminalAssignment(item)) {
      return false;
    }
    final endAt = _assignmentEndAt(item);
    if (endAt == null) {
      return true;
    }
    return endAt.isAfter(DateTime.now());
  }

  DateTime? _assignmentEndAt(Map<String, dynamic> item) {
    final startAt = _assignmentStartAt(item);
    if (startAt == null) {
      return null;
    }
    final timeText = (item['time'] ?? '').toString();
    final endFromRange = _timeRangeEndAt(startAt, timeText);
    if (endFromRange != null) {
      return endFromRange;
    }
    final duration = _intValue(
      item['totalDurationMinutes'] ?? item['estimatedDurationMinutes'],
    );
    if (duration > 0) {
      return startAt.add(Duration(minutes: duration));
    }
    return DateTime(startAt.year, startAt.month, startAt.day, 23, 59, 59);
  }

  DateTime? _assignmentStartAt(Map<String, dynamic> item) {
    final value = item['scheduledFor'] ?? item['date'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    final dateKey = (item['scheduledDateKey'] ?? '').toString().trim();
    if (dateKey.isNotEmpty) {
      return DateTime.tryParse(dateKey);
    }
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  DateTime? _timeRangeEndAt(DateTime date, String value) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})\s*[-–—]\s*(\d{1,2}):(\d{2})',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final hour = int.tryParse(match.group(3) ?? '');
    final minute = int.tryParse(match.group(4) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  List<Map<String, dynamic>> _mergeActiveAssignments(
    List<Map<String, dynamic>> scheduleSlots,
    List<Map<String, dynamic>> cleanerOrders,
  ) {
    final mergedByKey = <String, Map<String, dynamic>>{};
    final keyAliases = <String, String>{};
    final unkeyed = <Map<String, dynamic>>[];

    void putAssignment(Map<String, dynamic> item, {required bool preferred}) {
      final keys = _assignmentKeys(item);
      if (keys.isEmpty) {
        unkeyed.add(item);
        return;
      }
      var canonical = keys
          .map((key) => keyAliases[key])
          .firstWhere((key) => key != null, orElse: () => null);
      canonical ??= keys.first;
      for (final key in keys) {
        keyAliases[key] = canonical;
      }
      final existing = mergedByKey[canonical];
      if (preferred || existing == null) {
        final merged = existing == null
            ? item
            : {
                ...existing,
                ...item,
                if (existing.containsKey('addons'))
                  'addons': existing['addons'],
                if (existing.containsKey('addonsDetailed'))
                  'addonsDetailed': existing['addonsDetailed'],
                if (existing.containsKey('separatePaymentAddons'))
                  'separatePaymentAddons': existing['separatePaymentAddons'],
                if (existing.containsKey('addonCount'))
                  'addonCount': existing['addonCount'],
                if (existing.containsKey('addonTotalPrice'))
                  'addonTotalPrice': existing['addonTotalPrice'],
                if (existing.containsKey('addonsSeparatePaymentTotal'))
                  'addonsSeparatePaymentTotal':
                      existing['addonsSeparatePaymentTotal'],
              };
        mergedByKey[canonical] = merged;
      }
    }

    for (final item in scheduleSlots) {
      putAssignment(item, preferred: false);
    }
    for (final item in cleanerOrders) {
      putAssignment(item, preferred: true);
    }
    final merged = <Map<String, dynamic>>[...mergedByKey.values, ...unkeyed]
      ..sort((a, b) => _slotDate(a).compareTo(_slotDate(b)));
    return merged;
  }

  List<String> _assignmentKeys(Map<String, dynamic> item) {
    final keys = <String>[];
    for (final field in const ['scheduleSlotId', 'slotId', 'id']) {
      final value = (item[field] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null' && !keys.contains(value)) {
        keys.add(value);
      }
    }
    return keys;
  }

  int _intValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final normalized = value.replaceAll(RegExp(r'[^0-9,.-]'), '');
      return double.tryParse(normalized.replaceAll(',', '.'))?.round() ?? 0;
    }
    return 0;
  }

  int _chatUnreadCount(
    List<Map<String, dynamic>> chatSummaries,
    String chatId,
  ) {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return 0;
    }
    for (final item in chatSummaries) {
      final orderId = (item['orderId'] ?? item['chatId'] ?? item['id'] ?? '')
          .toString()
          .trim();
      if (orderId == normalizedChatId) {
        return _intValue(item['unreadCount']);
      }
    }
    return 0;
  }

  DateTime _slotDate(Map<String, dynamic> slot) {
    final value = slot['scheduledFor'] ?? slot['date'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse('${slot['scheduledDateKey'] ?? ''}') ??
        DateTime.now();
  }

  String _offerDateText(Map<String, dynamic> offer) {
    final explicit = (offer['dateText'] ?? '').toString().trim();
    if (explicit.isNotEmpty && explicit != 'null') {
      final parsed = DateTime.tryParse(explicit);
      return parsed == null ? explicit : domlyDateText(parsed);
    }
    final rawDate = offer['scheduledFor'] ?? offer['date'];
    if (rawDate is Timestamp) {
      return domlyDateText(rawDate.toDate());
    }
    if (rawDate is DateTime) {
      return domlyDateText(rawDate);
    }
    final dateKey = (offer['scheduledDateKey'] ?? '').toString().trim();
    if (dateKey.isNotEmpty) {
      final parsed = DateTime.tryParse(dateKey);
      return parsed == null ? dateKey : domlyDateText(parsed);
    }
    final parsed = DateTime.tryParse(rawDate?.toString() ?? '');
    return parsed == null ? 'Дата уточняется' : domlyDateText(parsed);
  }

  String _slotDateText(Map<String, dynamic> slot) {
    final date = _slotDate(slot);
    return '${date.day}.${date.month}.${date.year} ${(slot['time'] ?? '10:00 - 13:00')}';
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 148),
      child: DomlySecondaryButton(onPressed: onPressed, label: label),
    );
  }

  Widget _offerCountdown(Map<String, dynamic> offer) {
    final secondsLeft = _offerSecondsLeft(offer);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: secondsLeft.toDouble(), end: 0),
      duration: Duration(seconds: secondsLeft),
      builder: (context, value, _) {
        final wholeSeconds = value.ceil().clamp(0, 7200);
        final minutes = wholeSeconds ~/ 60;
        final seconds = wholeSeconds % 60;
        return Text(
          wholeSeconds > 0
              ? 'Осталось ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
              : 'Время ответа истекло',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: wholeSeconds > 0
                ? DomlyColors.buttonPrimary
                : DomlyColors.danger,
          ),
        );
      },
    );
  }

  int _offerSecondsLeft(Map<String, dynamic> offer) {
    final expiresAt = _toDateTime(offer['expiresAt']);
    return expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 7200);
  }
}

String _formatResidentialComplex(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final normalized = trimmed.toLowerCase();
  if (normalized.startsWith('жк')) {
    return trimmed;
  }
  return 'ЖК: $trimmed';
}

bool _shouldShowResidentialComplex(String address, String complex) {
  final complexTrimmed = complex.trim();
  if (complexTrimmed.isEmpty) {
    return false;
  }
  final addressNormalized = address.trim().toLowerCase();
  final complexNormalized = complexTrimmed.toLowerCase();
  return !addressNormalized.contains(complexNormalized);
}

DateTime _toDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse('${value ?? ''}') ?? DateTime.now();
}
