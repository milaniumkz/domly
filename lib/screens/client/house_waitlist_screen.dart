import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class HouseWaitlistScreen extends StatefulWidget {
  const HouseWaitlistScreen({
    super.key,
    required this.houseId,
  });

  final String houseId;

  @override
  State<HouseWaitlistScreen> createState() => _HouseWaitlistScreenState();
}

class _HouseWaitlistScreenState extends State<HouseWaitlistScreen> {
  final _data = FirestoreDataService.instance;
  bool _joining = false;
  bool _inviting = false;
  late Future<Map<String, dynamic>?> _statsFuture;
  late Future<Map<String, dynamic>> _referralFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    _referralFuture = _loadReferralData();
  }

  Future<Map<String, dynamic>?> _loadStats() {
    return _data.getHouseStats(houseId: widget.houseId);
  }

  Future<Map<String, dynamic>> _loadReferralData() async {
    final results = await Future.wait([
      _data.ensureReferralLink(),
      _data.getReferralStats(),
    ]);
    final link = Map<String, dynamic>.from(results[0] as Map);
    final stats = Map<String, dynamic>.from(results[1] as Map);
    return {
      'referralCode': (link['referralCode'] ?? '').toString().trim(),
      'referralLink': (link['referralLink'] ?? '').toString().trim(),
      'invited': (stats['invited'] as num?)?.toInt() ?? 0,
      'registered': (stats['registered'] as num?)?.toInt() ?? 0,
      'paid': (stats['paid'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> _refreshStats() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _statsFuture = _loadStats();
      _referralFuture = _loadReferralData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _statsFuture,
      builder: (context, statsSnap) {
        if (statsSnap.hasError) {
          return const DomlyShell(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Не удалось загрузить данные по дому',
                    subtitle: 'Обновите экран и попробуйте снова.',
                    icon: Icons.error_outline,
                  ),
                ),
              ),
            ),
          );
        }
        if (statsSnap.connectionState == ConnectionState.waiting &&
            !statsSnap.hasData) {
          return const DomlyShell(
            child: SafeArea(
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        DomlyColors.buttonPrimary),
                  ),
                ),
              ),
            ),
          );
        }
        final stats = statsSnap.data ?? const <String, dynamic>{};
        final house =
            Map<String, dynamic>.from(stats['house'] as Map? ?? const {});
        final threshold = (house['threshold'] as num?)?.toInt() ?? 20;
        final current = (house['current_users'] as num?)?.toInt() ?? 0;
        final progress = (stats['progress'] as num?)?.toDouble() ?? 0;
        final remaining = (stats['remaining'] as num?)?.toInt() ?? 0;
        final status = (house['status'] ?? 'INACTIVE').toString().toUpperCase();
        final activationText = (stats['activationText'] ?? '').toString();
        final popularPackage = (stats['popularPackage'] ?? '—').toString();
        final houseAddress = (house['address'] ?? widget.houseId).toString();

        return DomlyShell(
          bottomNavigationBar: DomlyStickyActionBar(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DomlyPrimaryButton(
                  label: 'Оставить заявку',
                  onPressed: _joining
                      ? null
                      : () {
                          if (status == 'ACTIVE') {
                            showDomlySnackBar(
                              context,
                              title: 'Дом уже активен',
                              subtitle:
                                  'Можно сразу выбрать пакет и заказать уборку.',
                              type: DomlySnackBarType.info,
                            );
                            return;
                          }
                          _joinWaitlist();
                        },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DomlySecondaryButton(
                        label: 'Пригласить соседей',
                        onPressed: _inviting ? null : _inviteNeighbors,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DomlySecondaryButton(
                        label: 'Карта покрытия',
                        onPressed: () =>
                            Navigator.pushNamed(context, '/map/clusters'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: DomlyHeader(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
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
                                'Подключение дома'.tr(),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                activationText.isEmpty
                                    ? 'Мы скоро стартуем в вашем доме. Пока набираем необходимое количество квартир.'
                                    : activationText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xCCFFFFFF),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 156),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      DomlyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ваш дом в очереди'.tr(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              houseAddress,
                              style: const TextStyle(
                                fontSize: 12,
                                color: DomlyColors.muted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DomlyStatusChip(
                              label: status == 'ACTIVE'
                                  ? 'Активен'
                                  : status == 'IN_PROGRESS'
                                      ? 'Подключается'
                                      : 'Ожидает запуска',
                              color: status == 'ACTIVE'
                                  ? DomlyColors.primary
                                  : const Color(0xFFFF9800),
                            ),
                            const SizedBox(height: 14),
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: DomlyColors.backgroundSoft,
                              color: DomlyColors.buttonPrimary,
                            ),
                            const SizedBox(height: 10),
                            _statRow('Подано заявок', '$current из $threshold'),
                            const SizedBox(height: 12),
                            Text(
                              remaining > 0
                                  ? 'Нужно еще $remaining соседей'
                                  : 'Дом готов к запуску',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DomlyColors.foreground,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'До запуска осталось совсем немного'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: DomlyColors.muted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
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
                                    'Популярный пакет'.tr(),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    popularPackage,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: DomlyColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _referralFuture,
                        builder: (context, referralSnap) {
                          final referral =
                              referralSnap.data ?? const <String, dynamic>{};
                          final invited =
                              (referral['invited'] as num?)?.toInt() ?? 0;
                          final registered =
                              (referral['registered'] as num?)?.toInt() ?? 0;
                          final paid = (referral['paid'] as num?)?.toInt() ?? 0;
                          final referralCode =
                              (referral['referralCode'] ?? '').toString();
                          return DomlyCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Приглашенные соседи'.tr(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Поделитесь ссылкой на веб-версию DOMLY. После регистрации и оплаты соседей прогресс обновится здесь.'
                                      .tr(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DomlyColors.muted,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _statRow('Приглашено вами', '$invited'),
                                const SizedBox(height: 10),
                                _statRow('Зарегистрировались', '$registered'),
                                const SizedBox(height: 10),
                                _statRow('Оплатили пакет', '$paid'),
                                if (referralCode.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: DomlyColors.backgroundSoft,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: DomlyColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      'Ваш код: $referralCode'.tr(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
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

  Widget _statRow(String label, String value, {bool mutedValue = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: DomlyColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: mutedValue ? DomlyColors.muted : DomlyColors.foreground,
          ),
        ),
      ],
    );
  }

  Future<void> _joinWaitlist() async {
    setState(() => _joining = true);
    try {
      await _data.joinWaitlist(houseId: widget.houseId);
      await _refreshStats();
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Заявка отправлена',
        subtitle: 'Дом добавлен в очередь на подключение.',
        type: DomlySnackBarType.success,
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _inviteNeighbors() async {
    setState(() => _inviting = true);
    try {
      final invite = await _data.ensureReferralLink();
      final referralCode = (invite['referralCode'] ?? '').toString().trim();
      final referralLink = (invite['referralLink'] ?? '').toString().trim();
      final shareText = StringBuffer('Подключай DOMLY в наш дом. ')
        ..write('Открой веб-версию приложения: $referralLink');
      if (referralCode.isNotEmpty) {
        shareText.write(' Используй мой код: $referralCode');
      }
      await Share.share(
        shareText.toString(),
        subject: 'Приглашение в DOMLY',
      );
      await _refreshStats();
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }
}
