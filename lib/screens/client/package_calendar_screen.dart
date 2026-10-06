import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/launch_config.dart';
import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/payment_link_service.dart';
import '../../ui/info_dialog.dart';
import '../../ui/domly_ui.dart';
import '../../utils/bonus_policy_utils.dart';
import '../../utils/package_catalog_utils.dart';
import '../../utils/user_error_message.dart';
import '../common/kaspi_invoice_request_dialog.dart';
import '../../localization/translation_controller.dart';

class PackageCalendarScreen extends StatefulWidget {
  const PackageCalendarScreen({super.key, required this.subscriptionId});

  final String subscriptionId;

  @override
  State<PackageCalendarScreen> createState() => _PackageCalendarScreenState();
}

class _PackageCalendarScreenState extends State<PackageCalendarScreen> {
  final _data = FirestoreDataService.instance;
  final _scrollController = ScrollController();
  final _selectedBlockKey = GlobalKey();
  final Map<String, String> _selectedTimes = <String, String>{};
  final Map<String, List<Map<String, dynamic>>> _selectedAddonsByDate =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, List<Map<String, dynamic>>> _selectedNewAddonsByDate =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, List<Map<String, dynamic>>> _slotsCache =
      <String, List<Map<String, dynamic>>>{};
  DateTime _visibleMonth = DateTime(
    LaunchConfig.bookingFloor(DateTime.now()).year,
    LaunchConfig.bookingFloor(DateTime.now()).month,
  );
  Set<String> _availableDateKeys = <String>{};
  bool _loadingDates = false;
  String? _loadingSlotsDateKey;
  bool _submitting = false;
  int? _scheduledVisitsOverride;
  int? _pendingSelectionsOverride;
  StreamSubscription<List<Map<String, dynamic>>>? _slotsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _addonPricesSubscription;
  final Map<String, int> _addonUnitPrices = <String, int>{};
  List<Map<String, dynamic>> _liveSlots = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _slotsSubscription = _data.customerScheduleSlotsStream().listen((slots) {
      if (!mounted) {
        return;
      }
      setState(() {
        _liveSlots = List<Map<String, dynamic>>.from(slots);
      });
    });
    _addonPricesSubscription = AppConfigService.instance
        .addonGroupConfigsStream()
        .listen((groups) {
          if (!mounted) {
            return;
          }
          setState(() {
            _addonUnitPrices.clear();
            for (final group in groups) {
              final rawItems = group['items'];
              final items = rawItems is List ? rawItems : const [];
              for (final rawItem in items.whereType<Map>()) {
                final item = Map<String, dynamic>.from(rawItem);
                final key = (item['key'] ?? item['id'] ?? '').toString();
                final price = _priceFromAddonConfig(item);
                if (key.isNotEmpty) {
                  _addonUnitPrices[key] = price;
                }
              }
            }
          });
        });
    _loadAvailableDates();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _slotsSubscription?.cancel();
    _addonPricesSubscription?.cancel();
    super.dispose();
  }

  int _includedVisits(Map<String, dynamic>? subscription) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final currentPeriodIncluded =
        (subscription['currentPeriodIncludedVisits'] as num?)?.toInt();
    if (currentPeriodIncluded != null && currentPeriodIncluded > 0) {
      return currentPeriodIncluded;
    }
    return _monthlyIncludedVisits(subscription);
  }

  int _monthlyIncludedVisits(Map<String, dynamic> subscription) {
    final catalogVisits = PackageCatalogUtils.cleaningsPerMonth(subscription);
    final stored =
        (subscription['includedVisits'] as num?)?.toInt() ??
        (subscription['cleaningsPerMonth'] as num?)?.toInt() ??
        0;
    final label =
        '${subscription['frequencyLabel'] ?? ''} ${subscription['package'] ?? ''}'
            .toLowerCase();
    final billingPeriodMonths =
        (subscription['billingPeriodMonths'] as num?)?.toInt() ?? 1;
    var expected = catalogVisits;
    if (label.contains('8 раз') || label.contains('8/')) {
      expected = 8;
    } else if (label.contains('4 раза') || label.contains('4/')) {
      expected = 4;
    } else if (label.contains('2 раза') ||
        label.contains('два раза') ||
        label.contains('2/')) {
      expected = 2;
    }
    final monthlyFromStored = billingPeriodMonths > 1
        ? (stored / billingPeriodMonths).ceil()
        : stored;
    return expected > monthlyFromStored ? expected : monthlyFromStored;
  }

  int _storedCompletedVisits(Map<String, dynamic>? subscription) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final usedVisits = (subscription['usedVisits'] as num?)?.toInt();
    final completedVisits = (subscription['completedVisits'] as num?)?.toInt();
    return _maxInt(usedVisits ?? 0, completedVisits ?? 0);
  }

  int _storedScheduledVisits(Map<String, dynamic>? subscription) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final scheduledVisits = (subscription['scheduledVisits'] as num?)?.toInt();
    final selectedVisits = (subscription['selectedVisitsCount'] as num?)
        ?.toInt();
    return _maxInt(scheduledVisits ?? 0, selectedVisits ?? 0);
  }

  int _maxInt(int left, int right) => left >= right ? left : right;

  DateTime? _dateValue(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    try {
      final converted = (value as dynamic).toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {}
    return null;
  }

  ({DateTime start, DateTime end}) _currentPeriod(
    Map<String, dynamic> subscription,
  ) {
    final now = DateTime.now();
    final validFrom = DateUtils.dateOnly(
      _dateValue(subscription['validFrom']) ??
          _dateValue(subscription['createdAt']) ??
          now,
    );
    final validUntil = DateUtils.dateOnly(
      _dateValue(subscription['validUntil']) ??
          DateTime(validFrom.year, validFrom.month + 1, validFrom.day),
    );
    var start = validFrom;
    var next = DateTime(start.year, start.month + 1, start.day);
    final today = DateUtils.dateOnly(now);
    while (!next.isAfter(today) && next.isBefore(validUntil)) {
      start = next;
      next = DateTime(start.year, start.month + 1, start.day);
    }
    return (start: start, end: next.isBefore(validUntil) ? next : validUntil);
  }

  bool _slotInCurrentPeriod(
    Map<String, dynamic> slot,
    Map<String, dynamic> subscription,
  ) {
    final date = DateUtils.dateOnly(
      _dateValue(slot['scheduledFor']) ??
          _dateValue(slot['date']) ??
          _dateValue(slot['scheduledDateKey']) ??
          DateTime(2100),
    );
    final period = _currentPeriod(subscription);
    return !date.isBefore(period.start) && date.isBefore(period.end);
  }

  List<Map<String, dynamic>> _activePaidPackageSubscriptions(
    List<Map<String, dynamic>> subscriptions,
  ) {
    return subscriptions
        .where(
          (subscription) =>
              (subscription['status'] ?? '').toString().trim().toLowerCase() ==
                  'active' &&
              _isPaidSubscription(subscription) &&
              !_isAddonOnlySubscription(subscription) &&
              _includedVisits(subscription) > 0,
        )
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool _isAddonOnlySubscription(Map<String, dynamic> subscription) {
    final type =
        (subscription['type'] ??
                subscription['kind'] ??
                subscription['pricingMode'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final title =
        '${subscription['package'] ?? ''} ${subscription['frequencyLabel'] ?? ''}'
            .toLowerCase();
    return type.contains('addon') ||
        title.contains('доп. услуг') ||
        title.contains('доп услуги') ||
        title.contains('допуслуг') ||
        title.contains('изменение уборки');
  }

  List<Map<String, dynamic>> _subscriptionsForScheduling(
    List<Map<String, dynamic>> subscriptions,
  ) {
    final active = _activePaidPackageSubscriptions(
      subscriptions,
    ).where((item) => _availableSelectionsForSubscription(item) > 0).toList();
    active.sort((a, b) {
      final aCurrent = (a['id'] ?? '').toString() == widget.subscriptionId;
      final bCurrent = (b['id'] ?? '').toString() == widget.subscriptionId;
      if (aCurrent != bCurrent) {
        return aCurrent ? -1 : 1;
      }
      final aCreated = _subscriptionCreatedMillis(a);
      final bCreated = _subscriptionCreatedMillis(b);
      if (aCreated != bCreated) {
        return aCreated.compareTo(bCreated);
      }
      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });
    return active;
  }

  int _scheduledVisitsForSubscription(Map<String, dynamic>? subscription) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final id = (subscription['id'] ?? '').toString().trim();
    final sourceOrderId =
        (subscription['sourceOrderId'] ?? subscription['orderId'] ?? '')
            .toString()
            .trim();
    final live = _liveSlots.where((slot) {
      final slotSubscriptionId = (slot['subscriptionId'] ?? '').toString();
      final slotOrderId =
          (slot['sourceOrderId'] ??
                  slot['customerOrderId'] ??
                  slot['orderId'] ??
                  '')
              .toString();
      final belongs =
          (id.isNotEmpty && slotSubscriptionId == id) ||
          (sourceOrderId.isNotEmpty && slotOrderId == sourceOrderId);
      return belongs &&
          _slotInCurrentPeriod(slot, subscription) &&
          _isActiveScheduledSlot(slot);
    }).length;
    final storedCurrent = (subscription['currentPeriodScheduledVisits'] as num?)
        ?.toInt();
    return _maxInt(live, storedCurrent ?? _storedScheduledVisits(subscription));
  }

  int _usedVisitsForSubscription(Map<String, dynamic>? subscription) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final id = (subscription['id'] ?? '').toString().trim();
    final sourceOrderId =
        (subscription['sourceOrderId'] ?? subscription['orderId'] ?? '')
            .toString()
            .trim();
    final live = _liveSlots.where((slot) {
      final slotSubscriptionId = (slot['subscriptionId'] ?? '').toString();
      final slotOrderId =
          (slot['sourceOrderId'] ??
                  slot['customerOrderId'] ??
                  slot['orderId'] ??
                  '')
              .toString();
      final belongs =
          (id.isNotEmpty && slotSubscriptionId == id) ||
          (sourceOrderId.isNotEmpty && slotOrderId == sourceOrderId);
      if (!belongs) {
        return false;
      }
      final status = (slot['status'] ?? '').toString().trim().toLowerCase();
      final orderStatus = (slot['orderStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final completed = status == 'completed' || orderStatus == 'completed';
      final forfeited =
          (status == 'canceled' ||
              status == 'cancelled' ||
              orderStatus == 'canceled' ||
              orderStatus == 'cancelled') &&
          slot['cancellationPenaltyApplied'] == true;
      return _slotInCurrentPeriod(slot, subscription) &&
          (completed || forfeited);
    }).length;
    final stored =
        (subscription['currentPeriodUsedVisits'] as num?)?.toInt() ??
        (_storedCompletedVisits(subscription) +
            ((subscription['forfeitedVisits'] as num?)?.toInt() ?? 0));
    return _maxInt(live, stored);
  }

  int _availableSelectionsForSubscription(Map<String, dynamic>? subscription) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    return (_includedVisits(subscription) -
            _usedVisitsForSubscription(subscription) -
            _scheduledVisitsForSubscription(subscription))
        .clamp(0, 99)
        .toInt();
  }

  int _aggregateIncludedVisits(List<Map<String, dynamic>> subscriptions) {
    return _activePaidPackageSubscriptions(subscriptions).fold<int>(
      0,
      (total, subscription) => total + _includedVisits(subscription),
    );
  }

  int _aggregateUsedVisits(List<Map<String, dynamic>> subscriptions) {
    return _activePaidPackageSubscriptions(subscriptions).fold<int>(
      0,
      (total, subscription) => total + _usedVisitsForSubscription(subscription),
    );
  }

  int _aggregateScheduledVisits(List<Map<String, dynamic>> subscriptions) {
    return _activePaidPackageSubscriptions(subscriptions).fold<int>(
      0,
      (total, subscription) =>
          total + _scheduledVisitsForSubscription(subscription),
    );
  }

  int _aggregateAvailableSelections(List<Map<String, dynamic>> subscriptions) {
    return (_aggregateIncludedVisits(subscriptions) -
            _aggregateUsedVisits(subscriptions) -
            _aggregateScheduledVisits(subscriptions))
        .clamp(0, 99)
        .toInt();
  }

  int _subscriptionCreatedMillis(Map<String, dynamic> subscription) {
    final value = subscription['createdAt'] ?? subscription['updatedAt'];
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    final seconds = _timestampSeconds(value);
    if (seconds != null) {
      return seconds * 1000;
    }
    return 0;
  }

  int? _timestampSeconds(Object? value) {
    if (value == null) {
      return null;
    }
    try {
      final dynamic dynamicValue = value;
      final seconds = dynamicValue.seconds;
      if (seconds is int) {
        return seconds;
      }
      if (seconds is num) {
        return seconds.toInt();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _isPaidSubscription(Map<String, dynamic>? subscription) {
    if (subscription == null) {
      return false;
    }
    final paymentStatus =
        (subscription['paymentStatus'] ??
                subscription['paymentState'] ??
                subscription['statusPayment'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    if (paymentStatus.isEmpty) {
      return subscription['paid'] == true ||
          subscription['paidAt'] != null ||
          subscription['activatedAt'] != null ||
          subscription['subscriptionStatus'] == 'active' ||
          subscription['sourceOrderId'] != null;
    }
    return paymentStatus == 'paid' ||
        paymentStatus == 'payment_confirmed' ||
        paymentStatus == 'completed' ||
        paymentStatus == 'success' ||
        paymentStatus == 'succeeded';
  }

  bool _isActiveScheduledSlot(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final orderStatus = (slot['orderStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (status == 'canceled' ||
        status == 'cancelled' ||
        status == 'completed' ||
        orderStatus == 'canceled' ||
        orderStatus == 'cancelled' ||
        orderStatus == 'completed') {
      return false;
    }
    return status == 'pending_assignment' ||
        status == 'pending_payment' ||
        status == 'offered' ||
        status == 'assigned' ||
        status == 'in_progress' ||
        status == 'rescheduled' ||
        orderStatus == 'pending_assignment' ||
        orderStatus == 'pending_payment' ||
        orderStatus == 'assigned' ||
        orderStatus == 'in_progress';
  }

  Future<void> _loadAvailableDates() async {
    setState(() => _loadingDates = true);
    try {
      final result = await _data.getAvailableDates(
        subscriptionId: widget.subscriptionId,
        month: _visibleMonth,
      );
      final dates = (result['dates'] as List? ?? const [])
          .map((item) => (item as Map)['date']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .where((item) => !_isPastDateKey(item))
          .toSet();
      if (!mounted) {
        return;
      }
      setState(() {
        _availableDateKeys = dates;
        _removePastSelections();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось загрузить даты',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loadingDates = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.customerSubscriptionsStream(),
      builder: (context, snapshot) {
        final subscriptions = snapshot.data ?? <Map<String, dynamic>>[];
        final subscription = subscriptions
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (item) => item?['id'] == widget.subscriptionId,
              orElse: () => null,
            );
        final activePackageSubscriptions = _activePaidPackageSubscriptions(
          subscriptions,
        );

        if (subscription == null && activePackageSubscriptions.isEmpty) {
          return const DomlyShell(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (activePackageSubscriptions.isEmpty) {
          return const DomlyShell(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Ожидаем оплату',
                    subtitle:
                        'Выбор даты откроется после подтверждения оплаты администратором.',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ),
            ),
          );
        }

        final includedVisits = _aggregateIncludedVisits(
          activePackageSubscriptions,
        );
        final usedForAvailability = _aggregateUsedVisits(
          activePackageSubscriptions,
        );
        final actualScheduledVisits = _aggregateScheduledVisits(
          activePackageSubscriptions,
        );
        final scheduledVisits =
            _scheduledVisitsOverride ?? actualScheduledVisits;
        final serverPendingSelections = _aggregateAvailableSelections(
          activePackageSubscriptions,
        );
        final requiredSelections =
            _pendingSelectionsOverride ??
            (includedVisits - usedForAvailability - scheduledVisits)
                .clamp(0, 99)
                .toInt();
        final effectiveRequiredSelections =
            requiredSelections == 0 &&
                _data.isDebugCustomer &&
                _availableDateKeys.isNotEmpty
            ? 1
            : requiredSelections;
        _schedulePastSelectionCleanup();
        final selectedEntries =
            _selectedTimes.entries
                .where((entry) => !_isPastDateKey(entry.key))
                .toList()
              ..sort((a, b) => a.key.compareTo(b.key));
        final selectedAddonTotal = selectedEntries.fold<int>(0, (total, entry) {
          return total +
              _addonItemsAmount(
                _selectedNewAddonsByDate[entry.key] ??
                    const <Map<String, dynamic>>[],
              );
        });
        final remainingAfterSelection =
            (effectiveRequiredSelections - selectedEntries.length)
                .clamp(0, 99)
                .toInt();
        final calendarSubscription =
            subscription ?? activePackageSubscriptions.first;
        final area = (calendarSubscription['area'] ?? '—').toString();

        if (_scheduledVisitsOverride != null &&
            actualScheduledVisits >= _scheduledVisitsOverride! &&
            serverPendingSelections <= (_pendingSelectionsOverride ?? 99)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _scheduledVisitsOverride = null;
              _pendingSelectionsOverride = null;
            });
          });
        }

        return DomlyShell(
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: DomlyStickyActionBar(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selectedAddonTotal > 0) ...[
                          Text(
                            'Допы к оплате: ${_formatMoney(selectedAddonTotal)}'
                                .tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: DomlyColors.foreground,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        DomlyPrimaryButton(
                          label: _selectedTimes.length <= 1
                              ? 'Подтвердить выбранную дату'
                              : 'Подтвердить выбранные даты',
                          isLoading: _submitting,
                          onPressed:
                              _submitting ||
                                  effectiveRequiredSelections == 0 ||
                                  _selectedTimes.isEmpty ||
                                  _selectedTimes.length >
                                      effectiveRequiredSelections
                              ? null
                              : () => _submitSelections(_selectedTimes.entries),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const DomlyClientBottomNav(currentIndex: 2),
            ],
          ),
          child: SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: DomlyHeader(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                'Календарь уборок'.tr(),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                effectiveRequiredSelections == 0
                                    ? 'Все уборки уже выбраны'
                                    : _selectedTimes.isEmpty
                                    ? 'Можно подтверждать даты по одной или сразу несколько. Осталось выбрать: $effectiveRequiredSelections'
                                    : 'Выбрано ${_selectedTimes.length}. После сохранения останется: $remainingAfterSelection',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xE6FFFFFF),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Площадь: $area м² · Время выбирается после даты'
                                    .tr(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xCCFFFFFF),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _metricChip('Всего', '$includedVisits'),
                                  _metricChip(
                                    'Использовано',
                                    '$usedForAvailability',
                                  ),
                                  _metricChip('Выбрано', '$scheduledVisits'),
                                  _metricChip(
                                    'Доступно',
                                    '$effectiveRequiredSelections',
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      DomlyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Выберите даты'.tr(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (_loadingDates)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              Stack(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Text(
                                          _monthYearLabel(_visibleMonth),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: DomlyColors.muted,
                                          ),
                                        ),
                                      ),
                                      AbsorbPointer(
                                        absorbing: _loadingSlotsDateKey != null,
                                        child: Localizations.override(
                                          context: context,
                                          locale: const Locale('ru'),
                                          child: CalendarDatePicker(
                                            key: ValueKey(
                                              '${_visibleMonth.year}-${_visibleMonth.month}',
                                            ),
                                            initialDate: _initialCalendarDate(),
                                            firstDate:
                                                LaunchConfig.bookingFloor(
                                                  DateTime.now(),
                                                ),
                                            lastDate: DateTime(
                                              DateTime.now().year + 1,
                                            ),
                                            onDateChanged: (date) =>
                                                _handleDateTap(
                                                  date,
                                                  effectiveRequiredSelections,
                                                ),
                                            onDisplayedMonthChanged: (month) {
                                              final normalized = DateTime(
                                                month.year,
                                                month.month,
                                              );
                                              if (normalized.year ==
                                                      _visibleMonth.year &&
                                                  normalized.month ==
                                                      _visibleMonth.month) {
                                                return;
                                              }
                                              setState(() {
                                                _visibleMonth = normalized;
                                              });
                                              _loadAvailableDates();
                                            },
                                            currentDate: DateTime.now(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_loadingSlotsDateKey != null)
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.68,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(
                                                width: 28,
                                                height: 28,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.6,
                                                    ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'Подбираем слоты на ${_formatDateKey(_loadingSlotsDateKey!)}'
                                                    .tr(),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: DomlyColors.foreground,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 12),
                            Text(
                              'Можно выбрать сегодня и любой следующий день. После выбора времени система найдет свободную уборщицу по району и площади.'
                                  .tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: DomlyColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DomlyCard(
                        key: _selectedBlockKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Выбранные, но еще не подтвержденные уборки'.tr(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_selectedTimes.isEmpty)
                              Text(
                                'Пока ничего не выбрано'.tr(),
                                style: TextStyle(color: DomlyColors.muted),
                              )
                            else
                              ...selectedEntries.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: DomlyColors.backgroundSoft,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _formatDateKey(entry.key),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                entry.value,
                                                style: const TextStyle(
                                                  color: DomlyColors.muted,
                                                ),
                                              ),
                                              if (_allSelectedAddonsForDate(
                                                entry.key,
                                              ).isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Допы: ${_addonSummary(_allSelectedAddonsForDate(entry.key))}'
                                                      .tr(),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        DomlyColors.foreground,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          width: 132,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              DomlySecondaryButton(
                                                label: 'Подтвердить',
                                                onPressed: _submitting
                                                    ? null
                                                    : () => _submitSelections([
                                                        entry,
                                                      ]),
                                              ),
                                              const SizedBox(height: 6),
                                              DomlySecondaryButton(
                                                label: 'Допы',
                                                onPressed: _submitting
                                                    ? null
                                                    : () =>
                                                          _chooseAddonsForDate(
                                                            entry.key,
                                                          ),
                                              ),
                                              const SizedBox(height: 6),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: IconButton(
                                                  onPressed: _submitting
                                                      ? null
                                                      : () {
                                                          setState(() {
                                                            _selectedTimes
                                                                .remove(
                                                                  entry.key,
                                                                );
                                                            _selectedAddonsByDate
                                                                .remove(
                                                                  entry.key,
                                                                );
                                                            _selectedNewAddonsByDate
                                                                .remove(
                                                                  entry.key,
                                                                );
                                                          });
                                                        },
                                                  icon: const Icon(Icons.close),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _addonSummary(List<Map<String, dynamic>> items) {
    return items
        .map((item) {
          final label = (item['label'] ?? item['key'] ?? '').toString();
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          return quantity > 1 ? '$label × $quantity' : label;
        })
        .where((item) => item.isNotEmpty)
        .join(', ');
  }

  List<Map<String, dynamic>> _allSelectedAddonsForDate(String dateKey) {
    return <Map<String, dynamic>>[
      ...(_selectedAddonsByDate[dateKey] ?? const <Map<String, dynamic>>[]),
      ...(_selectedNewAddonsByDate[dateKey] ?? const <Map<String, dynamic>>[]),
    ];
  }

  Future<void> _chooseAddonsForDate(String dateKey) async {
    final subscriptions = await _data.customerSubscriptionsStream().first;
    final subscription = subscriptions.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == widget.subscriptionId,
      orElse: () => null,
    );
    if (subscription == null || !mounted) {
      return;
    }
    final paidAddons = await _availablePackageAddons(
      subscription,
      excludeDateKey: dateKey,
    );
    final addonGroups = _mapAddonGroupConfigs(
      await AppConfigService.instance.addonGroupConfigsStream().first,
    );
    if (!mounted) {
      return;
    }
    if (paidAddons.isEmpty && addonGroups.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Допы недоступны',
        subtitle: 'Каталог доп. услуг пока пуст.',
        type: DomlySnackBarType.info,
      );
      return;
    }
    final chosen = await _showAddonsBottomSheet(
      dateKey: dateKey,
      paidAddons: paidAddons,
      addonGroups: addonGroups,
      initialPaidSelection: _selectedAddonsByDate[dateKey] ?? const [],
      initialNewSelection: _selectedNewAddonsByDate[dateKey] ?? const [],
    );
    if (!mounted || chosen == null) {
      return;
    }
    final paid = chosen['paid'] ?? const <Map<String, dynamic>>[];
    final fresh = chosen['new'] ?? const <Map<String, dynamic>>[];
    setState(() {
      if (paid.isEmpty) {
        _selectedAddonsByDate.remove(dateKey);
      } else {
        _selectedAddonsByDate[dateKey] = paid;
      }
      if (fresh.isEmpty) {
        _selectedNewAddonsByDate.remove(dateKey);
      } else {
        _selectedNewAddonsByDate[dateKey] = fresh;
      }
    });
    _scrollToSelectedBlock();
  }

  void _scrollToSelectedBlock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final context = _selectedBlockKey.currentContext;
      if (context == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  Future<List<Map<String, dynamic>>> _availablePackageAddons(
    Map<String, dynamic> subscription, {
    String? excludeDateKey,
  }) async {
    final purchased = await _subscriptionPurchasedAddons(subscription);
    if (purchased.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final usedUnits = <String, int>{};

    void addUsed(List<Map<String, dynamic>> items) {
      for (final item in items) {
        final key = (item['key'] ?? item['label'] ?? '').toString();
        if (key.isEmpty) {
          continue;
        }
        usedUnits[key] =
            (usedUnits[key] ?? 0) +
            ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999).toInt();
      }
    }

    final slots = await _data.customerScheduleSlotsStream().first;
    for (final slot in slots) {
      if ((slot['subscriptionId'] ?? '').toString() != widget.subscriptionId) {
        continue;
      }
      if (!_isActiveScheduledSlot(slot)) {
        continue;
      }
      addUsed(_normalizedAddonItems(slot['addonsDetailed']));
    }
    for (final entry in _selectedAddonsByDate.entries) {
      if (entry.key == excludeDateKey) {
        continue;
      }
      addUsed(entry.value);
    }

    final result = <Map<String, dynamic>>[];
    for (final item in purchased) {
      final key = (item['key'] ?? item['label'] ?? '').toString();
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final remaining = quantity - (usedUnits[key] ?? 0);
      if (key.isEmpty || remaining <= 0) {
        continue;
      }
      result.add({
        ...item,
        'quantity': remaining,
        'purchasedQuantity': quantity,
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _subscriptionPurchasedAddons(
    Map<String, dynamic> subscription,
  ) async {
    return _data.subscriptionPurchasedAddons(subscription);
  }

  List<Map<String, dynamic>> _normalizedAddonItems(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) => (item['key'] ?? item['label'] ?? '').toString().isNotEmpty,
        )
        .map((item) {
          final quantity = ((item['quantity'] as num?)?.toInt() ?? 1)
              .clamp(1, 999)
              .toInt();
          return {...item, 'quantity': quantity};
        })
        .toList();
  }

  int _addonItemsAmount(List<Map<String, dynamic>> items) {
    return items.fold<int>(0, (total, item) {
      final price = _addonItemPrice(item);
      final quantity = ((item['quantity'] as num?)?.toInt() ?? 1)
          .clamp(1, 999)
          .toInt();
      return total + price * quantity;
    });
  }

  int _priceFromAddonConfig(Map<dynamic, dynamic> item) {
    for (final key in const ['price', 'unitPrice', 'amount', 'cost']) {
      final value = item[key];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return 0;
  }

  int _addonItemPrice(Map<String, dynamic> item) {
    final direct = _priceFromAddonConfig(item);
    if (direct > 0) {
      return direct;
    }
    final key = (item['key'] ?? item['label'] ?? '').toString();
    return _addonUnitPrices[key] ?? 0;
  }

  int _billableAddonItemsAmount(List<Map<String, dynamic>> items) {
    return items.fold<int>(0, (total, item) {
      if (item['separatePayment'] == true || item['separate'] == true) {
        return total;
      }
      final price = _addonItemPrice(item);
      final quantity = ((item['quantity'] as num?)?.toInt() ?? 1)
          .clamp(1, 999)
          .toInt();
      return total + price * quantity;
    });
  }

  bool _hasSeparateAddonItems(List<Map<String, dynamic>> items) {
    return items.any(
      (item) => item['separatePayment'] == true || item['separate'] == true,
    );
  }

  String _formatMoney(int amount) {
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

  Future<void> _showAddonInfo(_ScheduleAddonItemDef item) async {
    final infoConfig = await AppConfigService.instance.getInfoContent(item.key);
    if (!mounted) {
      return;
    }
    final fallbackInfo = {
      'title': item.label,
      'shortInfo': item.shortInfo ?? 'Информация по услуге пока не заполнена.',
      'description':
          item.shortInfo ?? 'Информация по услуге пока не заполнена.',
      'fullInfo': item.fullInfo ?? '',
      'longDescription': item.fullInfo ?? '',
      'features': item.features,
      'price': item.price > 0 ? item.price : null,
    };
    await InfoDialog.showFromConfig(
      context,
      config: infoConfig != null && infoConfig.isNotEmpty
          ? {...fallbackInfo, ...infoConfig}
          : fallbackInfo,
    );
  }

  List<_ScheduleAddonGroupDef> _mapAddonGroupConfigs(
    List<Map<String, dynamic>> groups,
  ) {
    return groups
        .map((group) {
          final items = ((group['items'] ?? const []) as List)
              .whereType<Map>()
              .map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem);
                final key = (item['key'] ?? '').toString();
                if (key.isEmpty || item['isActive'] == false) {
                  return null;
                }
                return _ScheduleAddonItemDef(
                  key: key,
                  label: (item['label'] ?? key).toString(),
                  supportsQuantity: item['supportsQuantity'] == true,
                  price: _addonItemPrice(item),
                  separatePayment:
                      item['separatePayment'] == true ||
                      item['separate'] == true,
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
                );
              })
              .whereType<_ScheduleAddonItemDef>()
              .toList();
          if (items.isEmpty) {
            return null;
          }
          return _ScheduleAddonGroupDef(
            label: (group['label'] ?? group['key'] ?? 'Доп. услуги').toString(),
            items: items,
          );
        })
        .whereType<_ScheduleAddonGroupDef>()
        .toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>?> _showAddonsBottomSheet({
    required String dateKey,
    required List<Map<String, dynamic>> paidAddons,
    required List<_ScheduleAddonGroupDef> addonGroups,
    required List<Map<String, dynamic>> initialPaidSelection,
    required List<Map<String, dynamic>> initialNewSelection,
  }) {
    final paidQuantities = <String, int>{};
    for (final item in initialPaidSelection) {
      final key = (item['key'] ?? item['label'] ?? '').toString();
      if (key.isNotEmpty) {
        paidQuantities[key] = (item['quantity'] as num?)?.toInt() ?? 1;
      }
    }
    final newQuantities = <String, int>{};
    for (final item in initialNewSelection) {
      final key = (item['key'] ?? item['label'] ?? '').toString();
      if (key.isNotEmpty) {
        newQuantities[key] = (item['quantity'] as num?)?.toInt() ?? 1;
      }
    }
    final expandedGroups = <String>{};
    return showModalBottomSheet<Map<String, List<Map<String, dynamic>>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<Map<String, dynamic>> buildPaidSelection() {
              return paidAddons
                  .map((item) {
                    final key = (item['key'] ?? item['label'] ?? '').toString();
                    final quantity = paidQuantities[key] ?? 0;
                    if (key.isEmpty || quantity <= 0) {
                      return null;
                    }
                    return <String, dynamic>{...item, 'quantity': quantity};
                  })
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }

            List<Map<String, dynamic>> buildNewSelection() {
              final result = <Map<String, dynamic>>[];
              for (final group in addonGroups) {
                for (final item in group.items) {
                  final quantity = newQuantities[item.key] ?? 0;
                  if (quantity <= 0) {
                    continue;
                  }
                  result.add({
                    'key': item.key,
                    'label': item.label,
                    'quantity': quantity,
                    'price': item.price,
                    'separatePayment': item.separatePayment,
                    'separate': item.separatePayment,
                    'purchaseType': 'new',
                  });
                }
              }
              return result;
            }

            final paidSelection = buildPaidSelection();
            final newSelection = buildNewSelection();
            final billableTotal = _billableAddonItemsAmount(newSelection);
            final allSelected = <Map<String, dynamic>>[
              ...paidSelection,
              ...newSelection,
            ];
            final selectedCount = allSelected.fold<int>(
              0,
              (total, item) =>
                  total +
                  (((item['quantity'] as num?)?.toInt() ?? 1)
                      .clamp(1, 999)
                      .toInt()),
            );
            final hasSeparatePayment = _hasSeparateAddonItems(newSelection);

            Widget quantityControls({
              required int quantity,
              required int? maxQuantity,
              required VoidCallback? onMinus,
              required VoidCallback? onPlus,
            }) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: quantity <= 0 ? null : onMinus,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: maxQuantity != null && quantity >= maxQuantity
                        ? null
                        : onPlus,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              );
            }

            return SafeArea(
              minimum: const EdgeInsets.only(bottom: 18),
              child: Container(
                margin: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: 22 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Допы на ${_formatDateKey(dateKey)}'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: DomlyColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Можно прикрепить уже оплаченные допы или докупить новые именно на эту уборку.'
                          .tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: DomlyColors.muted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (paidAddons.isNotEmpty) ...[
                            Text(
                              'Уже оплачено'.tr(),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: DomlyColors.foreground,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...paidAddons.map((item) {
                              final key = (item['key'] ?? item['label'] ?? '')
                                  .toString();
                              final label = (item['label'] ?? key).toString();
                              final maxQuantity =
                                  ((item['quantity'] as num?)?.toInt() ?? 1)
                                      .clamp(1, 999)
                                      .toInt();
                              final quantity = paidQuantities[key] ?? 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: DomlyColors.backgroundSoft,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: DomlyColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: DomlyColors.foreground,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Осталось: $maxQuantity'.tr(),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: DomlyColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    quantityControls(
                                      quantity: quantity,
                                      maxQuantity: maxQuantity,
                                      onMinus: () => setModalState(() {
                                        paidQuantities[key] = quantity - 1;
                                      }),
                                      onPlus: () => setModalState(() {
                                        paidQuantities[key] = quantity + 1;
                                      }),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],
                          if (addonGroups.isNotEmpty) ...[
                            Text(
                              'Докупить на эту уборку'.tr(),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: DomlyColors.foreground,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...addonGroups.map((group) {
                              final selectedCount = group.items.fold<int>(
                                0,
                                (total, item) =>
                                    total + (newQuantities[item.key] ?? 0),
                              );
                              final expanded = expandedGroups.contains(
                                group.label,
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: DomlyColors.backgroundSoft,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => setModalState(() {
                                        if (expanded) {
                                          expandedGroups.remove(group.label);
                                        } else {
                                          expandedGroups.add(group.label);
                                        }
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                group.label,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: DomlyColors.foreground,
                                                ),
                                              ),
                                            ),
                                            if (selectedCount > 0)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: DomlyColors
                                                      .buttonPrimary
                                                      .withValues(alpha: .12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text('$selectedCount'),
                                              ),
                                            Icon(
                                              expanded
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (expanded)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          0,
                                          10,
                                          10,
                                        ),
                                        child: Column(
                                          children: group.items.map((item) {
                                            final quantity =
                                                newQuantities[item.key] ?? 0;
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: DomlyColors.border,
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: 28,
                                                    child: Material(
                                                      color: DomlyColors
                                                          .backgroundSoft,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: InkWell(
                                                        onTap: () =>
                                                            _showAddonInfo(
                                                              item,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        child: const Padding(
                                                          padding:
                                                              EdgeInsets.all(6),
                                                          child: Icon(
                                                            Icons.info_outline,
                                                            size: 16,
                                                            color: DomlyColors
                                                                .buttonPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          item.label,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        Wrap(
                                                          spacing: 6,
                                                          runSpacing: 4,
                                                          crossAxisAlignment:
                                                              WrapCrossAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              item.price > 0
                                                                  ? item.supportsQuantity
                                                                        ? '${_formatMoney(item.price)} за 1 шт.'
                                                                        : _formatMoney(
                                                                            item.price,
                                                                          )
                                                                  : 'Цена уточняется',
                                                              style: const TextStyle(
                                                                fontSize: 13,
                                                                color: DomlyColors
                                                                    .foreground,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                            if (item
                                                                .separatePayment)
                                                              Text(
                                                                'оплачивается отдельно при оценке специалиста'
                                                                    .tr(),
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: DomlyColors
                                                                      .buttonPrimary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (item.supportsQuantity)
                                                    quantityControls(
                                                      quantity: quantity,
                                                      maxQuantity: null,
                                                      onMinus: () =>
                                                          setModalState(() {
                                                            newQuantities[item
                                                                    .key] =
                                                                quantity - 1;
                                                          }),
                                                      onPlus: () =>
                                                          setModalState(() {
                                                            newQuantities[item
                                                                    .key] =
                                                                quantity + 1;
                                                          }),
                                                    )
                                                  else
                                                    SizedBox(
                                                      width: 104,
                                                      child: DomlySecondaryButton(
                                                        label: quantity > 0
                                                            ? 'Убрать'
                                                            : 'Добавить',
                                                        onPressed: () =>
                                                            setModalState(() {
                                                              newQuantities[item
                                                                      .key] =
                                                                  quantity > 0
                                                                  ? 0
                                                                  : 1;
                                                            }),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: DomlyColors.backgroundSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: DomlyColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'К оплате'.tr(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: DomlyColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  selectedCount == 0
                                      ? 'Допы не выбраны'
                                      : 'Выбрано: $selectedCount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: DomlyColors.muted,
                                  ),
                                ),
                                if (hasSeparatePayment) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Часть услуг рассчитывается отдельно менеджером.'
                                        .tr(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: DomlyColors.muted,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatMoney(billableTotal),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: DomlyColors.foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DomlySecondaryButton(
                            label: 'Без допов',
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pop(const <String, List<Map<String, dynamic>>>{
                                'paid': <Map<String, dynamic>>[],
                                'new': <Map<String, dynamic>>[],
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DomlyPrimaryButton(
                            label: billableTotal > 0
                                ? 'Применить · ${_formatMoney(billableTotal)}'
                                : 'Применить',
                            onPressed: () {
                              final result =
                                  <String, List<Map<String, dynamic>>>{
                                    'paid': List<Map<String, dynamic>>.from(
                                      paidSelection,
                                    ),
                                    'new': List<Map<String, dynamic>>.from(
                                      newSelection,
                                    ),
                                  };
                              Navigator.of(context).pop(result);
                            },
                          ),
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
    );
  }

  Future<void> _handleDateTap(DateTime date, int requiredSelections) async {
    return _handleDateKeyTap(_toDateKey(date), requiredSelections);
  }

  Future<void> _handleDateKeyTap(String dateKey, int requiredSelections) async {
    if (_loadingSlotsDateKey != null) {
      return;
    }
    if (_isPastDateKey(dateKey)) {
      setState(() {
        _selectedTimes.remove(dateKey);
        _selectedAddonsByDate.remove(dateKey);
        _selectedNewAddonsByDate.remove(dateKey);
        _slotsCache.remove(dateKey);
      });
      showDomlySnackBar(
        context,
        title: 'Дата уже прошла',
        subtitle: 'Выберите сегодня или любой следующий день.',
        type: DomlySnackBarType.info,
      );
      return;
    }
    if (!_selectedTimes.containsKey(dateKey) &&
        _selectedTimes.length >= requiredSelections) {
      showDomlySnackBar(
        context,
        title: 'Достигнут лимит',
        subtitle: 'Можно выбрать не больше $requiredSelections дат за раз.',
        type: DomlySnackBarType.info,
      );
      return;
    }

    try {
      setState(() => _loadingSlotsDateKey = dateKey);
      final date = DateTime.tryParse(dateKey) ?? DateTime.now();
      final slots =
          _slotsCache[dateKey] ??
          await (() async {
            final result = await _data.getAvailableSlots(
              subscriptionId: widget.subscriptionId,
              date: date,
            );
            final parsed = (result['slots'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            _slotsCache[dateKey] = parsed;
            return parsed;
          })();
      if (!mounted) {
        return;
      }
      final selectedTime = await _showTimePickerBottomSheet(
        dateKey: dateKey,
        slots: slots,
      );
      if (!mounted || selectedTime == null) {
        return;
      }
      setState(() {
        _selectedTimes[dateKey] = selectedTime;
      });
      await _chooseAddonsForDate(dateKey);
      _scrollToSelectedBlock();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось загрузить слоты',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loadingSlotsDateKey = null);
      }
    }
  }

  Future<void> _submitSelections(
    Iterable<MapEntry<String, String>> entries,
  ) async {
    final entriesList = entries.toList();
    final pastDateKeys = entriesList
        .where((entry) => _isPastDateKey(entry.key))
        .map((entry) => entry.key)
        .toList();
    if (pastDateKeys.isNotEmpty) {
      setState(() {
        for (final dateKey in pastDateKeys) {
          _selectedTimes.remove(dateKey);
          _selectedAddonsByDate.remove(dateKey);
          _selectedNewAddonsByDate.remove(dateKey);
          _slotsCache.remove(dateKey);
        }
      });
      showDomlySnackBar(
        context,
        title: 'Дата уже прошла',
        subtitle: 'Мы убрали старую дату. Выберите сегодня или следующий день.',
        type: DomlySnackBarType.info,
      );
      return;
    }

    DomlyPaymentMethod? paymentMethod;
    String? kaspiPhone;
    var useBonusForNewAddons = false;
    var selectedBonusForNewAddons = 0;
    final hasBillableNewAddons = entriesList.any(
      (entry) =>
          (_selectedNewAddonsByDate[entry.key] ??
                  const <Map<String, dynamic>>[])
              .isNotEmpty,
    );
    if (hasBillableNewAddons) {
      final bonusBalance =
          ((await _data.customerProfileStream().first)?['bonusPoints'] as num?)
              ?.toInt() ??
          0;
      if (!mounted) {
        return;
      }
      final newAddonsAmount = entriesList.fold<int>(0, (total, entry) {
        return total +
            _addonItemsAmount(
              _selectedNewAddonsByDate[entry.key] ??
                  const <Map<String, dynamic>>[],
            );
      });
      final bonusLimit = addonBonusSpendLimit(
        newAddonsAmount,
        await AppConfigService.instance.promotionsStream().first,
      );
      if (!mounted) {
        return;
      }
      final paymentSelection = await showPaymentMethodOptionsDialog(
        context,
        bonusBalance: bonusBalance,
        maxBonusToSpend: bonusLimit,
        paymentAmount: newAddonsAmount,
      );
      if (!mounted) {
        return;
      }
      if (paymentSelection == null) {
        showDomlySnackBar(
          context,
          title: 'Оплата допуслуг не отправлена',
          subtitle: 'Выберите способ оплаты для новых допуслуг.',
          type: DomlySnackBarType.info,
        );
        return;
      }
      paymentMethod = paymentSelection.method;
      useBonusForNewAddons =
          paymentSelection.useBonus ||
          paymentSelection.method == DomlyPaymentMethod.bonus;
      selectedBonusForNewAddons =
          paymentSelection.method == DomlyPaymentMethod.bonus
          ? newAddonsAmount
          : paymentSelection.useBonus
          ? bonusBalance.clamp(0, bonusLimit).clamp(0, newAddonsAmount).toInt()
          : 0;
      if (selectedBonusForNewAddons >= newAddonsAmount) {
        paymentMethod = DomlyPaymentMethod.bonus;
        useBonusForNewAddons = true;
        kaspiPhone = null;
      }
      if (paymentMethod == DomlyPaymentMethod.kaspi &&
          selectedBonusForNewAddons < newAddonsAmount) {
        final paymentRequest = await showKaspiInvoiceRequestOptionsDialog(
          context,
          bonusBalance: bonusBalance,
          maxBonusToSpend: bonusLimit,
          paymentAmount: newAddonsAmount,
          initialUseBonus: useBonusForNewAddons,
        );
        if (!mounted) {
          return;
        }
        if (paymentRequest == null) {
          showDomlySnackBar(
            context,
            title: 'Оплата допуслуг не отправлена',
            subtitle: 'Для новых допуслуг нужен номер KASPI.KZ.',
            type: DomlySnackBarType.info,
          );
          return;
        }
        kaspiPhone = paymentRequest.phone;
        if (paymentRequest.useBonus) {
          useBonusForNewAddons = true;
          selectedBonusForNewAddons = bonusBalance
              .clamp(0, bonusLimit)
              .clamp(0, newAddonsAmount)
              .toInt();
        }
      }
    }

    var remainingBonusForNewAddons = selectedBonusForNewAddons;
    final selections =
        entriesList.map((entry) {
          final addonsDetailed =
              _selectedAddonsByDate[entry.key] ??
              const <Map<String, dynamic>>[];
          final newAddonsDetailed =
              _selectedNewAddonsByDate[entry.key] ??
              const <Map<String, dynamic>>[];
          final newAddonAmount = _addonItemsAmount(newAddonsDetailed);
          final bonusToSpend = useBonusForNewAddons
              ? remainingBonusForNewAddons.clamp(0, newAddonAmount).toInt()
              : 0;
          remainingBonusForNewAddons -= bonusToSpend;
          return {
            'date': entry.key,
            'time': entry.value,
            'addonsDetailed': addonsDetailed,
            'newAddonsDetailed': newAddonsDetailed,
            if (newAddonsDetailed.isNotEmpty) ...{
              if (kaspiPhone != null) 'kaspiPhone': kaspiPhone,
              'bonusToSpend': bonusToSpend,
            },
            'addons': addonsDetailed
                .map((item) => (item['label'] ?? item['key'] ?? '').toString())
                .where((item) => item.isNotEmpty)
                .toList(),
          };
        }).toList()..sort(
          (a, b) => (a['date'] ?? '').toString().compareTo(
            (b['date'] ?? '').toString(),
          ),
        );
    if (selections.isEmpty) {
      return;
    }

    final subscriptions = await _data.customerSubscriptionsStream().first;
    final activePackageSubscriptions = _activePaidPackageSubscriptions(
      subscriptions,
    );
    final packagesForScheduling = _subscriptionsForScheduling(
      activePackageSubscriptions,
    );
    if (!mounted) {
      return;
    }
    final actualScheduledVisits = _aggregateScheduledVisits(
      activePackageSubscriptions,
    );
    final pendingSelectionsBefore = _aggregateAvailableSelections(
      activePackageSubscriptions,
    );

    if (packagesForScheduling.isEmpty ||
        selections.length > pendingSelectionsBefore) {
      showDomlySnackBar(
        context,
        title: 'Нет доступных уборок',
        subtitle:
            'Доступный остаток изменился. Обновите экран и выберите даты снова.',
        type: DomlySnackBarType.error,
      );
      return;
    }

    final groupedSelections = <String, List<Map<String, dynamic>>>{};
    var packageIndex = 0;
    var remainingInPackage = _availableSelectionsForSubscription(
      packagesForScheduling.first,
    );
    for (final selection in selections) {
      while (remainingInPackage <= 0 &&
          packageIndex < packagesForScheduling.length - 1) {
        packageIndex += 1;
        remainingInPackage = _availableSelectionsForSubscription(
          packagesForScheduling[packageIndex],
        );
      }
      if (remainingInPackage <= 0) {
        break;
      }
      final subscriptionId = (packagesForScheduling[packageIndex]['id'] ?? '')
          .toString();
      if (subscriptionId.isEmpty) {
        continue;
      }
      groupedSelections
          .putIfAbsent(subscriptionId, () => <Map<String, dynamic>>[])
          .add(selection);
      remainingInPackage -= 1;
    }

    final distributedCount = groupedSelections.values.fold<int>(
      0,
      (sum, items) => sum + items.length,
    );
    if (distributedCount != selections.length) {
      showDomlySnackBar(
        context,
        title: 'Нет доступных уборок',
        subtitle:
            'Не удалось распределить выбранные даты по активным пакетам. Обновите экран.',
        type: DomlySnackBarType.error,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final addonPaymentIds = <String>[];
      for (final entry in groupedSelections.entries) {
        final result = await _data.bookSchedule(
          subscriptionId: entry.key,
          selections: entry.value,
        );
        addonPaymentIds.addAll(
          (result['addonPaymentIds'] as List? ?? const [])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty),
        );
      }
      if (paymentMethod == DomlyPaymentMethod.online &&
          addonPaymentIds.isNotEmpty) {
        if (!mounted) {
          return;
        }
        final paymentSession = await PaymentLinkService.runBlocking(
          context,
          task: () =>
              _data.createBccPaymentSession(orderId: addonPaymentIds.first),
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
      if (!mounted) {
        return;
      }
      setState(() {
        for (final selection in selections) {
          final dateKey = selection['date'];
          if (dateKey != null) {
            _selectedTimes.remove(dateKey);
            _selectedAddonsByDate.remove(dateKey);
            _selectedNewAddonsByDate.remove(dateKey);
            _slotsCache.remove(dateKey);
          }
        }
      });
      await _loadAvailableDates();
      final remainingSelections = (pendingSelectionsBefore - selections.length)
          .clamp(0, 99)
          .toInt();
      if (!mounted) {
        return;
      }
      setState(() {
        _scheduledVisitsOverride = actualScheduledVisits + selections.length;
        _pendingSelectionsOverride = remainingSelections;
      });
      showDomlySnackBar(
        context,
        title: remainingSelections > 0
            ? selections.length == 1
                  ? 'Дата сохранена'
                  : 'Даты сохранены'
            : 'Расписание сохранено',
        subtitle: remainingSelections > 0
            ? 'Можно выбрать и подтвердить ещё $remainingSelections.'
            : null,
        type: DomlySnackBarType.success,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/client/orders',
        (_) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось сохранить расписание',
        subtitle: _scheduleErrorText(error),
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _scheduleErrorText(Object error) {
    if (UserErrorMessage.isAuthError(error)) {
      return UserErrorMessage.message(error);
    }
    final text = error.toString();
    if (text.contains('Authentication required') ||
        text.contains('unauthenticated')) {
      return 'Сессия обновляется. Нажмите подтвердить еще раз.';
    }
    if (text.contains('Slot ') && text.contains(' is unavailable')) {
      return 'Это время уже недоступно. Обновите список и выберите другое время.';
    }
    if (text.contains('Cleaning can only be booked at least')) {
      return 'Выберите время, которое еще не прошло.';
    }
    if (text.contains('Cleaning cannot be booked in the past')) {
      return 'Дата уже прошла. Выберите сегодня или любой следующий день.';
    }
    return 'Проверьте выбранное время и попробуйте снова.';
  }

  void _schedulePastSelectionCleanup() {
    if (!_selectedTimes.keys.any(_isPastDateKey)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(_removePastSelections);
    });
  }

  void _removePastSelections() {
    final pastDateKeys = _selectedTimes.keys.where(_isPastDateKey).toList();
    for (final dateKey in pastDateKeys) {
      _selectedTimes.remove(dateKey);
      _selectedAddonsByDate.remove(dateKey);
      _selectedNewAddonsByDate.remove(dateKey);
      _slotsCache.remove(dateKey);
    }
  }

  bool _isPastDateKey(String dateKey) {
    final date = DateTime.tryParse(dateKey);
    if (date == null) {
      return false;
    }
    final today = DateTime.now();
    final todayStart = LaunchConfig.bookingFloor(today);
    final dateStart = DateTime(date.year, date.month, date.day);
    return dateStart.isBefore(todayStart);
  }

  DateTime _initialCalendarDate() {
    final floor = LaunchConfig.bookingFloor(DateTime.now());
    final visible = DateTime(_visibleMonth.year, _visibleMonth.month);
    return visible.isBefore(floor) ? floor : visible;
  }

  String _toDateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateKey(String dateKey) {
    final date = DateTime.tryParse(dateKey) ?? DateTime.now();
    return domlyDateText(date);
  }

  Future<String?> _showTimePickerBottomSheet({
    required String dateKey,
    required List<Map<String, dynamic>> slots,
  }) {
    final initiallySelected = _selectedTimes[dateKey];
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? pendingTime = initiallySelected;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1E9E4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Выберите время'.tr(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: DomlyColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateKey(dateKey),
                      style: const TextStyle(
                        fontSize: 13,
                        color: DomlyColors.muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (slots.isEmpty) ...[
                      Text(
                        'На выбранную дату свободных окон нет. Выберите другую дату.'
                            .tr(),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: slots.map((slot) {
                              final time = slot['time']?.toString() ?? '';
                              final selected = pendingTime == time;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: selected
                                      ? DomlyColors.buttonSoft
                                      : DomlyColors.backgroundSoft,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, time),
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
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: DomlyColors.foreground,
                                              ),
                                            ),
                                          ),
                                          if ((slot['availableCleaners'] ?? 0)
                                              is num)
                                            Text(
                                              '${slot['availableCleaners']} исполн.',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: DomlyColors.muted,
                                              ),
                                            ),
                                          if (selected) ...[
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.check_circle,
                                              color: DomlyColors.buttonPrimary,
                                              size: 20,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    DomlySecondaryButton(
                      label: 'Отмена',
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _monthYearLabel(DateTime date) {
    const months = <String>[
      'январь',
      'февраль',
      'март',
      'апрель',
      'май',
      'июнь',
      'июль',
      'август',
      'сентябрь',
      'октябрь',
      'ноябрь',
      'декабрь',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleAddonItemDef {
  const _ScheduleAddonItemDef({
    required this.key,
    required this.label,
    this.supportsQuantity = false,
    this.price = 0,
    this.separatePayment = false,
    this.shortInfo,
    this.fullInfo,
    this.features = const <String>[],
  });

  final String key;
  final String label;
  final bool supportsQuantity;
  final int price;
  final bool separatePayment;
  final String? shortInfo;
  final String? fullInfo;
  final List<String> features;
}

class _ScheduleAddonGroupDef {
  const _ScheduleAddonGroupDef({required this.label, required this.items});

  final String label;
  final List<_ScheduleAddonItemDef> items;
}
