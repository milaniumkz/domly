import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import 'cleaner_service_area_notice.dart';
import '../../localization/translation_controller.dart';

class CleanerDashboardScreen extends StatefulWidget {
  const CleanerDashboardScreen({super.key});

  @override
  State<CleanerDashboardScreen> createState() => _CleanerDashboardScreenState();
}

class _CleanerDashboardScreenState extends State<CleanerDashboardScreen> {
  final _data = FirestoreDataService.instance;
  late final Stream<Map<String, dynamic>?> _profileStream;
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  late final Stream<List<Map<String, dynamic>>> _payoutsStream;
  late final Stream<List<Map<String, dynamic>>> _scheduleSlotsStream;
  late final Stream<List<Map<String, dynamic>>> _videosStream;
  late final Stream<List<Map<String, dynamic>>> _videoViewsStream;

  @override
  void initState() {
    super.initState();
    _profileStream = _data.cleanerProfileStream();
    _ordersStream = _data.cleanerOrdersStream();
    _payoutsStream = _data.cleanerPayoutsStream();
    _scheduleSlotsStream = _data.cleanerScheduleSlotsStream();
    _videosStream = _data.cleanerVideosStream();
    _videoViewsStream = _data.userVideoViewsStream();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileStream,
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 0),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Не удалось загрузить профиль',
                    subtitle: 'Обновите экран и попробуйте снова.',
                    icon: Icons.error_outline,
                  ),
                ),
              ),
            ),
          );
        }
        final profile = profileSnap.data ?? <String, dynamic>{};
        final name = (profile['name'] ?? 'Исполнитель').toString();
        final monthlyEarnings = (profile['monthlyEarnings'] ?? 0).toString();
        final currentBalance = ((profile['currentWalletBalance'] ?? 0) as num)
            .toInt();
        final totalWithdrawn = ((profile['totalWithdrawn'] ?? 0) as num)
            .toInt();
        final availableWithdrawal =
            ((profile['availableWithdrawalAmount'] ?? 0) as num).toInt();
        final statusLabel =
            (profile['cleanerStatusLabel'] ??
                    _levelLabel((profile['jobsCount'] ?? 0) as num))
                .toString();
        final statusProgressText = (profile['cleanerStatusProgressText'] ?? '')
            .toString();
        final statusProgress =
            ((profile['cleanerStatusProgress'] as num?)?.toDouble() ?? 0).clamp(
              0.0,
              1.0,
            );
        final hasServiceAreas = cleanerHasServiceAreas(profile);

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _ordersStream,
          builder: (context, ordersSnap) {
            if (ordersSnap.hasError) {
              return const DomlyShell(
                bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 0),
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
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _payoutsStream,
              builder: (context, payoutsSnap) {
                if (payoutsSnap.hasError) {
                  return const DomlyShell(
                    bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 0),
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: DomlyEmptyStateCard(
                            title: 'Не удалось загрузить выплаты',
                            subtitle: 'Обновите экран и попробуйте снова.',
                            icon: Icons.error_outline,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _scheduleSlotsStream,
                  builder: (context, shiftsSnap) {
                    if (shiftsSnap.hasError) {
                      return const DomlyShell(
                        bottomNavigationBar: DomlyCleanerBottomNav(
                          currentIndex: 0,
                        ),
                        child: SafeArea(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: DomlyEmptyStateCard(
                                title: 'Не удалось загрузить расписание',
                                subtitle: 'Обновите экран и попробуйте снова.',
                                icon: Icons.error_outline,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    if (profileSnap.connectionState ==
                            ConnectionState.waiting &&
                        !profileSnap.hasData &&
                        ordersSnap.connectionState == ConnectionState.waiting &&
                        !ordersSnap.hasData &&
                        payoutsSnap.connectionState ==
                            ConnectionState.waiting &&
                        !payoutsSnap.hasData &&
                        shiftsSnap.connectionState == ConnectionState.waiting &&
                        !shiftsSnap.hasData) {
                      return const DomlyShell(
                        bottomNavigationBar: DomlyCleanerBottomNav(
                          currentIndex: 0,
                        ),
                        child: SafeArea(
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                DomlyColors.buttonPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final allSlots =
                        shiftsSnap.data ?? <Map<String, dynamic>>[];
                    final payouts =
                        payoutsSnap.data ?? <Map<String, dynamic>>[];
                    final pendingWithdrawal = payouts
                        .where((payout) {
                          final status = (payout['status'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase();
                          return status == 'pending' ||
                              status == 'requested' ||
                              status == 'processing' ||
                              status == 'in_review';
                        })
                        .fold<int>(
                          0,
                          (total, payout) =>
                              total +
                              ((payout['net'] ?? payout['amount'] ?? 0) as num)
                                  .toInt(),
                        );
                    final displayedBalance =
                        (currentBalance - pendingWithdrawal).clamp(0, 1 << 31);
                    final today = DateTime.now();
                    final startToday = DateTime(
                      today.year,
                      today.month,
                      today.day,
                    );
                    final startTomorrow = startToday.add(
                      const Duration(days: 1),
                    );
                    final startDayAfterTomorrow = startTomorrow.add(
                      const Duration(days: 1),
                    );
                    final futureJobs =
                        allSlots.where((slot) {
                          final date = _slotDate(slot);
                          final normalizedDate = DateTime(
                            date.year,
                            date.month,
                            date.day,
                          );
                          final status = (slot['status'] ?? '')
                              .toString()
                              .toLowerCase();
                          return !normalizedDate.isBefore(startToday) &&
                              status != 'completed' &&
                              status != 'cancelled' &&
                              status != 'canceled';
                        }).toList()..sort(
                          (a, b) => _slotDate(a).compareTo(_slotDate(b)),
                        );
                    final jobs = futureJobs.where((slot) {
                      final date = _slotDate(slot);
                      final normalizedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                      );
                      return normalizedDate == startToday;
                    }).toList();
                    final tomorrowJobs = futureJobs.where((slot) {
                      final date = _slotDate(slot);
                      final normalizedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                      );
                      return normalizedDate == startTomorrow;
                    }).toList();
                    final upcomingJobs = futureJobs
                        .where((slot) {
                          final date = _slotDate(slot);
                          final normalizedDate = DateTime(
                            date.year,
                            date.month,
                            date.day,
                          );
                          return !normalizedDate.isBefore(
                            startDayAfterTomorrow,
                          );
                        })
                        .take(6)
                        .toList();

                    return DomlyShell(
                      bottomNavigationBar: const DomlyCleanerBottomNav(
                        currentIndex: 0,
                      ),
                      child: SafeArea(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(
                                  child: DomlyHeader(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      14,
                                      20,
                                      48,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Добро пожаловать'.tr(),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xCCFFFFFF),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: DomlyStatusChip(
                                                          label: statusLabel,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons.star,
                                                            size: 16,
                                                            color: Colors.white,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '${profile['rating'] ?? 0}',
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  if (statusProgressText
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      statusProgressText,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xD9FFFFFF,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                      child: LinearProgressIndicator(
                                                        minHeight: 6,
                                                        value: statusProgress,
                                                        backgroundColor:
                                                            const Color(
                                                              0x33FFFFFF,
                                                            ),
                                                        valueColor:
                                                            const AlwaysStoppedAnimation<
                                                              Color
                                                            >(Colors.white),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _trainingActionButton(),
                                                const SizedBox(width: 8),
                                                _notificationsActionButton(),
                                                const SizedBox(width: 8),
                                                domlyTopIconButton(
                                                  icon: Icons.person_outline,
                                                  onPressed: () =>
                                                      Navigator.pushNamed(
                                                        context,
                                                        '/cleaner/profile',
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Transform.translate(
                                          offset: const Offset(0, 28),
                                          child: GestureDetector(
                                            onTap: () => Navigator.pushNamed(
                                              context,
                                              '/cleaner/earnings',
                                            ),
                                            child: DomlyCard(
                                              padding: const EdgeInsets.all(6),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'Заработок сегодня'
                                                                  .tr(),
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    DomlyColors
                                                                        .muted,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              '${profile['todayEarnings'] ?? 0} ₸',
                                                              style: const TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    DomlyColors
                                                                        .primary,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              'Баланс: ${displayedBalance.toInt()} ₸'
                                                                  .tr(),
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: DomlyColors
                                                                    .foreground,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 3,
                                                            ),
                                                            Text(
                                                              'Выведено: $totalWithdrawn ₸'
                                                                  .tr(),
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    DomlyColors
                                                                        .muted,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 3,
                                                            ),
                                                            Text(
                                                              'Доступно к выводу: $availableWithdrawal ₸'
                                                                  .tr(),
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    DomlyColors
                                                                        .muted,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const DomlyIconBadge(
                                                        icon: Icons
                                                            .payments_outlined,
                                                        size: 44,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: _summaryMetric(
                                                          'Уборок сегодня',
                                                          '${jobs.length}',
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: _summaryMetric(
                                                          'За месяц',
                                                          '$monthlyEarnings ₸',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 36),
                                ),
                                if (!hasServiceAreas)
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      14,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: CleanerServiceAreaNotice(
                                        onPressed: () => Navigator.pushNamed(
                                          context,
                                          '/cleaner/profile',
                                        ),
                                      ),
                                    ),
                                  ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _actionCard(
                                            title: 'График',
                                            subtitle:
                                                '${profile['weekOrders'] ?? jobs.length} на неделе',
                                            icon: Icons.calendar_today_outlined,
                                            onTap: () => Navigator.pushNamed(
                                              context,
                                              '/cleaner/calendar',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _actionCard(
                                            title: 'Доход',
                                            subtitle:
                                                '${profile['monthlyEarnings'] ?? 0} ₸/мес',
                                            icon: Icons.trending_up,
                                            reverse: true,
                                            onTap: () => Navigator.pushNamed(
                                              context,
                                              '/cleaner/earnings',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 14),
                                ),
                                const SliverPadding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  sliver: SliverToBoxAdapter(
                                    child: DomlySectionTitle(
                                      title: 'Ближайшие планы уборок',
                                    ),
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 6),
                                ),
                                if (jobs.isNotEmpty)
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: _planGroupTitle(
                                        'Сегодня',
                                        '${jobs.length}',
                                      ),
                                    ),
                                  ),
                                if (jobs.isNotEmpty)
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      20,
                                      0,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _jobCard(jobs[index]),
                                        ),
                                        childCount: jobs.length,
                                      ),
                                    ),
                                  ),
                                if (tomorrowJobs.isNotEmpty)
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: _planGroupTitle(
                                        'Завтра',
                                        '${tomorrowJobs.length}',
                                      ),
                                    ),
                                  ),
                                if (tomorrowJobs.isNotEmpty)
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      20,
                                      0,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _jobCard(tomorrowJobs[index]),
                                        ),
                                        childCount: tomorrowJobs.length,
                                      ),
                                    ),
                                  ),
                                if (upcomingJobs.isNotEmpty)
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: _planGroupTitle(
                                        'Далее',
                                        '${upcomingJobs.length}',
                                      ),
                                    ),
                                  ),
                                if (upcomingJobs.isNotEmpty)
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      20,
                                      0,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _jobCard(upcomingJobs[index]),
                                        ),
                                        childCount: upcomingJobs.length,
                                      ),
                                    ),
                                  ),
                                if (futureJobs.isEmpty)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 20,
                                      ),
                                      child: DomlyEmptyStateCard(
                                        title: 'Планы уборок пока пусты',
                                        subtitle:
                                            'Когда появятся новые назначения на сегодня или ближайшие дни, они будут показаны здесь.',
                                        icon: Icons.event_available_outlined,
                                      ),
                                    ),
                                  ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 100),
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
  }

  Widget _summaryMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
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

  Widget _planGroupTitle(String title, String count) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DomlyColors.foreground,
              ),
            ),
          ),
          Text(
            '$count уборок'.tr(),
            style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool reverse = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: DomlyCard(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DomlyIconBadge(
              icon: icon,
              colors: reverse
                  ? const [DomlyColors.accent, DomlyColors.primary]
                  : const [DomlyColors.primary, DomlyColors.accent],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DomlyColors.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> job) {
    final orderId =
        (job['scheduleSlotId'] ??
                job['slotId'] ??
                job['id'] ??
                job['sourceOrderId'] ??
                job['customerOrderId'])
            .toString();
    final chatId = (job['chatId'] ?? orderId).toString();

    return DomlyCard(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_slotDateLabel(job)} · ${(job['time'] ?? '—').toString()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _jobMetaChip(
                  '${job['totalDurationMinutes'] ?? job['estimatedDurationMinutes'] ?? '—'} мин',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _jobMetaChip(
                  'Дорога ${job['travelTimeMinutes'] ?? 15} мин',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _jobMetaChip('Допы ${job['addonCount'] ?? 0}')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            (job['customerName'] ?? job['client'] ?? 'Клиент').toString(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (job['address'] ?? '').toString(),
            style: const TextStyle(color: DomlyColors.muted),
          ),
          if (((job['area'] ?? 0) as num).toInt() > 0)
            Text(
              'Площадь: ${((job['area'] ?? 0) as num).toInt()} м²',
              style: const TextStyle(color: DomlyColors.muted),
            ),
          if (_shouldShowResidentialComplex(
            (job['address'] ?? '').toString(),
            (job['residentialComplex'] ?? '').toString(),
          ))
            Text(
              _formatResidentialComplex(
                (job['residentialComplex'] ?? '').toString(),
              ),
              style: const TextStyle(color: DomlyColors.muted),
            ),
          if ((job['customerPhone'] ?? '').toString().isNotEmpty)
            Text(
              'Телефон: ${(job['customerPhone'] ?? '').toString()}',
              style: const TextStyle(color: DomlyColors.muted),
            ),
          if ((job['entrance'] ?? '').toString().isNotEmpty ||
              (job['apartment'] ?? '').toString().isNotEmpty)
            Text(
              'Подъезд: ${(job['entrance'] ?? '—')} • Квартира: ${(job['apartment'] ?? '—')}',
              style: const TextStyle(color: DomlyColors.muted),
            ),
          const SizedBox(height: 4),
          Text(
            (job['package'] ?? '').toString(),
            style: const TextStyle(color: DomlyColors.muted),
          ),
          const SizedBox(height: 6),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DomlySecondaryButton(
                      label: 'Чат',
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
                    child: DomlySecondaryButton(
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
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: DomlyPrimaryButton(
                  label: 'Фотоотчет',
                  onPressed: () => _startJob(job),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jobMetaChip(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DomlyColors.foreground,
        ),
      ),
    );
  }

  Future<void> _startJob(Map<String, dynamic> job) async {
    final orderId = _statusTargetId(job);
    if (orderId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не удалось открыть фотоотчет',
        subtitle: 'Не найден ID уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    final status = (job['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'in_progress') {
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

  String _statusTargetId(Map<String, dynamic> job) {
    for (final key in ['scheduleSlotId', 'slotId']) {
      final value = (job[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    final scopeType = (job['scopeType'] ?? '').toString();
    final looksLikeScheduleSlot =
        scopeType == 'schedule_slot' ||
        job.containsKey('scheduledDateKey') ||
        job.containsKey('scheduledFor');
    if (looksLikeScheduleSlot) {
      final value = (job['id'] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    for (final key in ['sourceOrderId', 'customerOrderId', 'orderId', 'id']) {
      final value = (job[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return '';
  }

  DateTime _slotDate(Map<String, dynamic> slot) {
    final value = slot['scheduledFor'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse('${slot['scheduledDateKey'] ?? ''}') ??
        DateTime.now();
  }

  String _slotDateLabel(Map<String, dynamic> slot) {
    final date = _slotDate(slot);
    const months = <String>[
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _levelLabel(num jobsCount) {
    if (jobsCount >= 50) {
      return 'Топ';
    }
    if (jobsCount >= 20) {
      return 'Специалист';
    }
    return 'Новичок';
  }

  Widget _trainingActionButton() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _videosStream,
      builder: (context, videosSnap) {
        final videos = videosSnap.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _videoViewsStream,
          builder: (context, viewsSnap) {
            final viewedIds = (viewsSnap.data ?? const <Map<String, dynamic>>[])
                .where((view) => (view['completed'] ?? false) == true)
                .map((view) => (view['videoId'] ?? '').toString())
                .toSet();
            final unseenCount = videos
                .where((video) => !viewedIds.contains(video['id']))
                .length;
            return domlyTopBadgeIconButton(
              icon: Icons.ondemand_video_outlined,
              badgeCount: unseenCount,
              onPressed: () =>
                  Navigator.pushNamed(context, '/cleaner/training'),
            );
          },
        );
      },
    );
  }

  Widget _notificationsActionButton() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.userNotificationsStream(),
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
