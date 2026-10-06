import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerEarningsScreen extends StatefulWidget {
  const CleanerEarningsScreen({super.key});

  @override
  State<CleanerEarningsScreen> createState() => _CleanerEarningsScreenState();
}

class _CleanerEarningsScreenState extends State<CleanerEarningsScreen> {
  _IncomePeriod _period = _IncomePeriod.month;
  bool _cashoutSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: data.cleanerProfileStream(),
      builder: (context, profileSnap) {
        final profile = profileSnap.data ?? <String, dynamic>{};
        final today = (profile['todayEarnings'] ?? 0) as num;
        final week =
            (profile['weeklyEarnings'] ?? profile['weekEarnings'] ?? 0) as num;
        final month = (profile['monthlyEarnings'] ?? 0) as num;
        final dailyIncome = (profile['dailyIncome'] ?? 13500) as num;
        final totalEarnedProfile = (profile['totalEarned'] ?? 0) as num;
        final totalWithdrawnProfile = (profile['totalWithdrawn'] ?? 0) as num;
        final walletBalance = (profile['currentWalletBalance'] ?? 0) as num;
        final availableWeeklyCashoutRaw =
            (profile['availableWeeklyCashoutAmount'] ?? 0) as num;
        final availableFullCashoutRaw =
            (profile['availableFullCashoutAmount'] ?? 0) as num;
        final availableWithdrawal =
            (profile['availableWithdrawalAmount'] ?? 0) as num;
        final availableFullCashout = availableFullCashoutRaw > 0
            ? availableFullCashoutRaw
            : availableWithdrawal;
        final availableWeeklyCashout = availableWeeklyCashoutRaw > 0
            ? availableWeeklyCashoutRaw
            : (availableFullCashout > 0
                  ? (availableFullCashout.toDouble() * 0.3).round()
                  : 0);
        final lockedBonus = (profile['lockedBonusAmount'] ?? 0) as num;
        final unlockedBonus = (profile['unlockedBonusAmount'] ?? 0) as num;
        final totalBonusAwarded = (profile['totalBonusAwarded'] ?? 0) as num;
        final totalArea = (profile['totalCleanedArea'] ?? 0) as num;
        final jobsCount = (profile['jobsCount'] ?? 0) as num;
        final level =
            (profile['cleanerStatusLabel'] ??
                    (jobsCount >= 20 ? 'Специалист' : 'Новичок'))
                .toString();
        final progressText = (profile['cleanerStatusProgressText'] ?? '')
            .toString();
        final nextLevel = (profile['nextCleanerStatus'] ?? '').toString();
        final statusProgress =
            ((profile['cleanerStatusProgress'] as num?)?.toDouble() ?? 0).clamp(
              0.0,
              1.0,
            );

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: data.cleanerOrdersStream(),
          builder: (context, ordersSnap) {
            final orders = ordersSnap.data ?? const <Map<String, dynamic>>[];
            final completedOrders =
                orders
                    .where(
                      (order) =>
                          (order['status'] ?? '').toString() == 'completed',
                    )
                    .toList()
                  ..sort((a, b) => _timestampOf(b).compareTo(_timestampOf(a)));

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: data.cleanerPayoutsStream(),
              builder: (context, payoutsSnap) {
                final payouts =
                    payoutsSnap.data ?? const <Map<String, dynamic>>[];
                final filteredOrders = completedOrders
                    .where((order) => _matchesPeriod(order, _period))
                    .toList();
                final filteredPayouts = payouts
                    .where((payout) => _matchesPeriod(payout, _period))
                    .toList();
                final settledPayouts = filteredPayouts.where((payout) {
                  final status = (payout['status'] ?? '')
                      .toString()
                      .toLowerCase();
                  return status == 'completed' ||
                      status == 'paid' ||
                      status == 'approved' ||
                      status == 'settled' ||
                      status == 'success' ||
                      status == 'succeeded';
                }).toList();
                final settledAllPayouts = payouts.where((payout) {
                  final status = (payout['status'] ?? '')
                      .toString()
                      .toLowerCase();
                  return status == 'completed' ||
                      status == 'paid' ||
                      status == 'approved' ||
                      status == 'settled' ||
                      status == 'success' ||
                      status == 'succeeded';
                }).toList();
                final totalWithdrawnLive = settledAllPayouts.fold<num>(
                  0,
                  (total, payout) =>
                      total + ((payout['net'] ?? payout['amount'] ?? 0) as num),
                );
                final displayWalletBalance =
                    totalWithdrawnLive > 0 || totalWithdrawnProfile > 0
                    ? (totalEarnedProfile - totalWithdrawnLive).clamp(
                        0,
                        1 << 31,
                      )
                    : walletBalance;

                final periodIncome = filteredOrders.fold<num>(
                  0,
                  (total, order) => total + _orderPrice(order),
                );
                final periodAddonIncome = filteredOrders.fold<num>(
                  0,
                  (total, order) => total + _addonIncome(order),
                );
                final periodGrossWithdrawals = filteredPayouts.fold<num>(
                  0,
                  (total, payout) =>
                      total +
                      ((payout['gross'] ?? payout['amount'] ?? 0) as num),
                );
                final periodNetWithdrawals = settledPayouts.fold<num>(
                  0,
                  (total, payout) =>
                      total + ((payout['net'] ?? payout['amount'] ?? 0) as num),
                );
                final periodTaxes = settledPayouts.fold<num>(
                  0,
                  (total, payout) => total + ((payout['tax'] ?? 0) as num),
                );
                final transactionItems = _buildTransactions(
                  filteredOrders,
                  filteredPayouts,
                );

                return DomlyShell(
                  bottomNavigationBar: const DomlyCleanerBottomNav(
                    currentIndex: 4,
                  ),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              DomlyHeader(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  10,
                                  20,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    domlyTopIconButton(
                                      icon: Icons.arrow_back,
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons
                                                .account_balance_wallet_outlined,
                                            size: 40,
                                            color: Colors.white,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Кошелёк'.tr(),
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'Баланс, начисления и выводы'.tr(),
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
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  18,
                                ),
                                child: Column(
                                  children: [
                                    DomlyCard(
                                      padding: const EdgeInsets.all(6),
                                      color: DomlyColors.buttonPrimary,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Текущий баланс'.tr(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${displayWalletBalance.toInt()} ₸',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _walletMetric(
                                                  'Заработано',
                                                  '${totalEarnedProfile.toInt()} ₸',
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _walletMetric(
                                                  'Выведено',
                                                  '${totalWithdrawnLive.toInt()} ₸',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          _walletMetric(
                                            'Можно вывести сейчас',
                                            '${availableWithdrawal.toInt()} ₸',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _amountCard(
                                            'Сегодня',
                                            today,
                                            Icons.today_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _amountCard(
                                            'Неделя',
                                            week,
                                            Icons.date_range_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _amountCard(
                                            'Месяц',
                                            month,
                                            Icons.calendar_month_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _breakdownCard(
                                            'Ставка за рабочий день',
                                            '${dailyIncome.toInt()} ₸',
                                            Icons.payments_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _breakdownCard(
                                            'Убрано всего',
                                            '${totalArea.toInt()} м²',
                                            Icons.square_foot_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (totalBonusAwarded > 0 ||
                                        unlockedBonus > 0 ||
                                        lockedBonus > 0)
                                      DomlyCard(
                                        padding: const EdgeInsets.all(6),
                                        color: DomlyColors.accent,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.card_giftcard_outlined,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Бонусы'.tr(),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _bonusMetric(
                                                    'Доступно сейчас',
                                                    '${unlockedBonus.toInt()} ₸',
                                                    Icons.check_circle_outline,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _bonusMetric(
                                                    'Будет через 7 дней',
                                                    '${lockedBonus.toInt()} ₸',
                                                    Icons.lock_clock_outlined,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Всего заработано бонусов'
                                                          .tr(),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    '${totalBonusAwarded.toInt()} ₸',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    DomlyCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Вывод средств'.tr(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _summaryRow(
                                            'Можно вывести на этой неделе',
                                            '${availableWeeklyCashout.toInt()} ₸',
                                          ),
                                          _summaryRow(
                                            'Можно вывести полностью',
                                            '${availableFullCashout.toInt()} ₸',
                                          ),
                                          if (lockedBonus > 0)
                                            _summaryRow(
                                              'Бонусы доступны через 7 дней',
                                              '${lockedBonus.toInt()} ₸',
                                            ),
                                          const SizedBox(height: 6),
                                          Column(
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: DomlySecondaryButton(
                                                  label: 'Вывести 30%',
                                                  onPressed:
                                                      _cashoutSubmitting ||
                                                          availableWeeklyCashout <=
                                                              0
                                                      ? null
                                                      : () => _requestCashout(
                                                          'partial',
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                width: double.infinity,
                                                child: DomlyPrimaryButton(
                                                  label: 'Вывести все',
                                                  onPressed:
                                                      _cashoutSubmitting ||
                                                          availableFullCashout <=
                                                              0
                                                      ? null
                                                      : () => _requestCashout(
                                                          'full',
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    DomlyCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Период'.tr(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: _IncomePeriod.values.map((
                                              period,
                                            ) {
                                              final selected =
                                                  _period == period;
                                              return ChoiceChip(
                                                label: Text(period.label),
                                                selected: selected,
                                                onSelected: (_) => setState(
                                                  () => _period = period,
                                                ),
                                                selectedColor: DomlyColors
                                                    .primary
                                                    .withValues(alpha: 0.12),
                                                labelStyle: TextStyle(
                                                  fontSize: 12,
                                                  color: selected
                                                      ? DomlyColors.primary
                                                      : DomlyColors.foreground,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _breakdownCard(
                                            'Доход за ${_period.label.toLowerCase()}',
                                            '${periodIncome.toInt()} ₸',
                                            Icons.cleaning_services_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _breakdownCard(
                                            'Доп. услуги',
                                            '${periodAddonIncome.toInt()} ₸',
                                            Icons.auto_awesome_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _breakdownCard(
                                            'Выведено',
                                            '${periodNetWithdrawals.toInt()} ₸',
                                            Icons.download_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _breakdownCard(
                                            'Удержано',
                                            '${periodTaxes.toInt()} ₸',
                                            Icons.receipt_long_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (progressText.isNotEmpty ||
                                        nextLevel.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      DomlyCard(
                                        padding: const EdgeInsets.all(8),
                                        color: DomlyColors.accent,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.workspace_premium,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    level,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.20,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: FractionallySizedBox(
                                                widthFactor: statusProgress,
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              nextLevel.isNotEmpty
                                                  ? progressText
                                                  : 'Максимальный уровень достигнут.',
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    DomlyCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'История операций'.tr(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          if (transactionItems.isEmpty)
                                            Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                              child: Text(
                                                'За выбранный период операций нет'
                                                    .tr(),
                                                style: TextStyle(
                                                  color: DomlyColors.muted,
                                                ),
                                              ),
                                            )
                                          else
                                            ...transactionItems.map(
                                              _transactionTile,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (filteredPayouts.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      DomlyCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Сводка выплат'.tr(),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _summaryRow(
                                              'Начислено к выплате',
                                              '${periodGrossWithdrawals.toInt()} ₸',
                                            ),
                                            _summaryRow(
                                              'Выведено на счет',
                                              '${periodNetWithdrawals.toInt()} ₸',
                                            ),
                                            _summaryRow(
                                              'Налог / удержание',
                                              '${periodTaxes.toInt()} ₸',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
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

  Widget _amountCard(String title, num amount, IconData icon) {
    return DomlyCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Icon(icon, color: DomlyColors.buttonPrimary),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            '${amount.toInt()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const Text(
            '₸',
            style: TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _walletMetric(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bonusMetric(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard(String title, String value, IconData icon) {
    return DomlyCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DomlyColors.buttonPrimary),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: DomlyColors.muted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionTile(_WalletTransaction item) {
    final isWithdrawal = item.type == _WalletTransactionType.withdrawal;
    final color = isWithdrawal ? DomlyColors.danger : DomlyColors.primary;
    final icon = isWithdrawal
        ? Icons.download_outlined
        : Icons.cleaning_services_outlined;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DomlyColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${isWithdrawal ? '-' : '+'}${item.amount.toInt()} ₸',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  List<_WalletTransaction> _buildTransactions(
    List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> payouts,
  ) {
    final items = <_WalletTransaction>[
      ...orders.map(
        (order) => _WalletTransaction(
          type: _WalletTransactionType.earning,
          amount: _orderPrice(order),
          date: _timestampOf(order),
          title: (order['package'] ?? 'Уборка').toString(),
          subtitle: _orderSubtitle(order),
        ),
      ),
      ...payouts.map(
        (payout) => _WalletTransaction(
          type: _WalletTransactionType.withdrawal,
          amount: (payout['net'] ?? payout['amount'] ?? 0) as num,
          date: _timestampOf(payout),
          title: 'Вывод средств',
          subtitle: _payoutSubtitle(payout),
        ),
      ),
    ];
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  bool _matchesPeriod(Map<String, dynamic> item, _IncomePeriod period) {
    final date = _timestampOf(item);
    final now = DateTime.now();
    switch (period) {
      case _IncomePeriod.day:
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      case _IncomePeriod.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeek = DateTime(start.year, start.month, start.day);
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        return !date.isBefore(startOfWeek) && date.isBefore(endOfWeek);
      case _IncomePeriod.month:
        return date.year == now.year && date.month == now.month;
    }
  }

  DateTime _timestampOf(Map<String, dynamic> item) {
    final timestamp = item['createdAt'] ?? item['completedAt'] ?? item['date'];
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is DateTime) {
      return timestamp;
    }
    if (timestamp is String && timestamp.isNotEmpty) {
      return DateTime.tryParse(timestamp) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  num _orderPrice(Map<String, dynamic> order) {
    return (order['price'] ?? 0) as num;
  }

  num _addonIncome(Map<String, dynamic> order) {
    if (order['addonTotalPrice'] is num) {
      return order['addonTotalPrice'] as num;
    }
    if (order['addonsPrice'] is num) {
      return order['addonsPrice'] as num;
    }
    final addons = order['addons'];
    if (addons is List) {
      return addons.length * 3000;
    }
    return 0;
  }

  String _orderSubtitle(Map<String, dynamic> order) {
    final date = _formatDate(_timestampOf(order));
    final address = (order['address'] ?? '').toString();
    if (address.isEmpty) {
      return date;
    }
    return '$date • $address';
  }

  String _payoutSubtitle(Map<String, dynamic> payout) {
    final date = _formatDate(_timestampOf(payout));
    final weekId = (payout['weekId'] ?? '').toString();
    if (weekId.isEmpty) {
      return date;
    }
    return '$date • $weekId';
  }

  String _formatDate(DateTime date) {
    return domlyDateText(date);
  }

  Future<void> _requestCashout(String payoutType) async {
    setState(() => _cashoutSubmitting = true);
    try {
      await FirestoreDataService.instance.requestCleanerCashout(
        payoutType: payoutType,
      );
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Запрос отправлен',
        subtitle: payoutType == 'full'
            ? 'Оформлен полный вывод средств.'
            : 'Оформлен вывод 30% от баланса.',
        type: DomlySnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() => _cashoutSubmitting = false);
      }
    }
  }
}

enum _IncomePeriod {
  day('День'),
  week('Неделя'),
  month('Месяц');

  const _IncomePeriod(this.label);

  final String label;
}

enum _WalletTransactionType { earning, withdrawal }

class _WalletTransaction {
  const _WalletTransaction({
    required this.type,
    required this.amount,
    required this.date,
    required this.title,
    required this.subtitle,
  });

  final _WalletTransactionType type;
  final num amount;
  final DateTime date;
  final String title;
  final String subtitle;
}
