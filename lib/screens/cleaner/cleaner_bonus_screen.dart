import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerBonusScreen extends StatefulWidget {
  const CleanerBonusScreen({super.key});

  @override
  State<CleanerBonusScreen> createState() => _CleanerBonusScreenState();
}

class _CleanerBonusScreenState extends State<CleanerBonusScreen> {
  final _data = FirestoreDataService.instance;
  final _config = AppConfigService.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _config.workerBonusConfigStream(),
      builder: (context, configSnap) {
        if (configSnap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: DomlyEmptyStateCard(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Не удалось загрузить бонусы',
                    subtitle: 'Обновите экран и попробуйте снова.',
                  ),
                ),
              ),
            ),
          );
        }
        final config = configSnap.data ?? const <String, dynamic>{};
        final bonusesVisible = _config.getBool(config, 'bonusesVisible', true);
        final title = _config.getString(config, 'title', 'Бонусы');
        final description = _config.getString(
          config,
          'description',
          'Ваши бонусы зависят от качества и количества выполненной работы',
        );

        return StreamBuilder<Map<String, dynamic>?>(
          stream: _data.cleanerProfileStream(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const DomlyShell(
                bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: DomlyEmptyStateCard(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Не удалось загрузить бонусы',
                        subtitle: 'Обновите экран и попробуйте снова.',
                      ),
                    ),
                  ),
                ),
              );
            }
            if (configSnap.connectionState == ConnectionState.waiting &&
                !configSnap.hasData &&
                snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const DomlyShell(
                bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
                child: SafeArea(
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(DomlyColors.primary),
                      ),
                    ),
                  ),
                ),
              );
            }
            final profile = snap.data ?? <String, dynamic>{};
            return DomlyShell(
              bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 4),
              child: SafeArea(
                child: Column(
                  children: [
                    _header(title),
                    Expanded(
                      child: bonusesVisible
                          ? ListView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              children: [
                                const SizedBox(height: 8),
                                _introCard(description),
                                const SizedBox(height: 16),
                                _balanceCard(profile),
                                const SizedBox(height: 16),
                                _bonusRulesCard(config),
                                const SizedBox(height: 16),
                                _careerBonusCard(profile),
                                const SizedBox(height: 16),
                                _nextBonusProgress(profile),
                                const SizedBox(height: 16),
                                _bonusLedgerCard(profile),
                                const SizedBox(height: 24),
                              ],
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              children: [
                                const SizedBox(height: 8),
                                DomlyEmptyStateCard(
                                  icon: Icons.visibility_off_outlined,
                                  title: 'Раздел временно скрыт',
                                  subtitle: description,
                                ),
                              ],
                            ),
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

  Widget _header(String title) {
    return DomlyHeader(
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
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Статусы, бонусы и правила начисления.'.tr(),
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
    );
  }

  Widget _introCard(String description) {
    return DomlyCard(
      padding: const EdgeInsets.all(16),
      color: DomlyColors.backgroundSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DomlyIconBadge(
            icon: Icons.workspace_premium_outlined,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: DomlyColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bonusRulesCard(Map<String, dynamic> config) {
    final reliableArea =
        _config.getInt(config, 'cleanerReliableAreaThreshold', 12000);
    final reliableBonus =
        _config.getInt(config, 'cleanerReliableBonusAmount', 100000);
    final expertArea =
        _config.getInt(config, 'cleanerExpertAreaThreshold', 30000);
    final expertBonus =
        _config.getInt(config, 'cleanerExpertBonusAmount', 200000);
    final legendArea =
        _config.getInt(config, 'cleanerLegendAreaThreshold', 65000);
    final legendBonus =
        _config.getInt(config, 'cleanerLegendBonusAmount', 500000);
    final weeklyAreaThreshold =
        _config.getInt(config, 'cleanerWeeklyAreaThreshold', 1300);
    final weeklyAreaBonus =
        _config.getInt(config, 'cleanerWeeklyAreaBonusAmount', 5000);
    final addonThreshold1 =
        _config.getInt(config, 'cleanerWeeklyAddonBonusThreshold1', 30000);
    final addonBonus1 =
        _config.getInt(config, 'cleanerWeeklyAddonBonusAmount1', 4000);
    final addonThreshold2 =
        _config.getInt(config, 'cleanerWeeklyAddonBonusThreshold2', 50000);
    final addonBonus2 =
        _config.getInt(config, 'cleanerWeeklyAddonBonusAmount2', 6000);

    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Условия бонусов и статусов'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          _ruleRow(
            Icons.workspace_premium_outlined,
            'Новичок',
            'Статус с момента регистрации.',
          ),
          const SizedBox(height: 10),
          _ruleRow(
            Icons.verified_user_outlined,
            'Надежная',
            'От $reliableArea м² • карьерный бонус $reliableBonus ₸',
          ),
          const SizedBox(height: 10),
          _ruleRow(
            Icons.auto_awesome_outlined,
            'Эксперт',
            'От $expertArea м² • карьерный бонус $expertBonus ₸',
          ),
          const SizedBox(height: 10),
          _ruleRow(
            Icons.emoji_events_outlined,
            'Легенда',
            'От $legendArea м² • карьерный бонус $legendBonus ₸',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: DomlyColors.border),
          ),
          _ruleRow(
            Icons.square_foot_outlined,
            'Еженедельный бонус',
            'От $weeklyAreaThreshold м² за неделю • +$weeklyAreaBonus ₸',
          ),
          const SizedBox(height: 10),
          _ruleRow(
            Icons.add_chart_outlined,
            'Доп. бонус',
            'Продажи доп. услуг от $addonThreshold1 ₸ за неделю • +$addonBonus1 ₸',
          ),
          const SizedBox(height: 10),
          _ruleRow(
            Icons.trending_up_outlined,
            'Доп. бонус 2',
            'Продажи доп. услуг от $addonThreshold2 ₸ за неделю • +$addonBonus2 ₸',
          ),
          const SizedBox(height: 12),
          Text(
            'Еженедельные бонусы становятся доступны к выводу через 7 календарных дней.'
                .tr(),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: DomlyColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(Map<String, dynamic> profile) {
    final unlocked = ((profile['unlockedBonusAmount'] as num?)?.toInt() ?? 0) +
        ((profile['manualBonusBalance'] as num?)?.toInt() ?? 0);
    final locked = (profile['lockedBonusAmount'] as num?)?.toInt() ?? 0;
    final totalBonusAwarded =
        (profile['totalBonusAwarded'] as num?)?.toInt() ?? 0;

    return DomlyCard(
      padding: const EdgeInsets.all(18),
      color: DomlyColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard_outlined, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Бонусный баланс'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$unlocked ₸',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            locked > 0
                ? 'Доступно к выводу через 7 дней'
                : 'Доступно к выводу сейчас',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          if (locked > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.lock_clock_outlined,
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  'Заблокировано: $locked ₸'.tr(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
          if (totalBonusAwarded > 0) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Всего начислено'.tr(),
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                Text(
                  '$totalBonusAwarded ₸',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _nextBonusProgress(Map<String, dynamic> profile) {
    final nextStatus = (profile['nextCleanerStatus'] ?? '').toString();
    final progressText =
        (profile['cleanerStatusProgressText'] ?? '').toString();
    final progress =
        ((profile['cleanerStatusProgress'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0);

    final weeklyArea =
        (profile['currentWeekCleanedArea'] as num?)?.toInt() ?? 0;
    const weeklyAreaTarget = 1300;
    final weeklyAreaProgress =
        min(weeklyArea / weeklyAreaTarget, 1.0).toDouble();

    final weekAddonSales =
        (profile['currentWeekAddonSales'] as num?)?.toInt() ?? 0;
    const addonTarget1 = 30000;
    const addonTarget2 = 50000;
    final addonProgress = min(weekAddonSales / addonTarget1, 1.0).toDouble();

    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прогресс до следующих бонусов'.tr(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DomlyColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          if (nextStatus.isNotEmpty) ...[
            _progressRow(
              'Карьерный: $nextStatus',
              progress,
              progressText,
            ),
            const SizedBox(height: 12),
          ],
          _progressRow(
            'Площадь за неделю',
            weeklyAreaProgress,
            '$weeklyArea / $weeklyAreaTarget м²',
          ),
          const SizedBox(height: 12),
          _progressRow(
            'Доп.услуги за неделю',
            addonProgress,
            '$weekAddonSales / $addonTarget1 ₸',
          ),
          if (addonProgress >= 1.0 && weekAddonSales < addonTarget2) ...[
            const SizedBox(height: 12),
            _progressRow(
              'Доп.услуги → 6 000 ₸',
              min(weekAddonSales / addonTarget2, 1.0).toDouble(),
              '$weekAddonSales / $addonTarget2 ₸',
            ),
          ],
        ],
      ),
    );
  }

  Widget _careerBonusCard(Map<String, dynamic> profile) {
    final nextStatus = (profile['nextCleanerStatus'] ?? '').toString();
    final remainingArea =
        ((profile['remainingAreaToNextStatus'] ?? 0) as num).toInt();
    final nextCareerBonus =
        ((profile['nextCareerBonusAmount'] ?? 0) as num).toInt();
    if (nextStatus.isEmpty || nextCareerBonus <= 0) {
      return const SizedBox.shrink();
    }
    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Следующий бонус'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$nextStatus • $nextCareerBonus ₸',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Осталось убрать $remainingArea м² до следующего статуса.'.tr(),
            style: const TextStyle(
              fontSize: 13,
              color: DomlyColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRow(String label, double progress, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: DomlyColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress,
            backgroundColor: DomlyColors.border,
            valueColor:
                const AlwaysStoppedAnimation<Color>(DomlyColors.buttonPrimary),
          ),
        ),
      ],
    );
  }

  Widget _ruleRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DomlyColors.backgroundSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: DomlyColors.buttonPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DomlyColors.foreground,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: DomlyColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bonusLedgerCard(Map<String, dynamic> profile) {
    final ledger = _parseBonusLedger(profile);
    if (ledger.isEmpty) {
      return const DomlyEmptyStateCard(
        icon: Icons.card_giftcard_outlined,
        title: 'История бонусов пуста',
        subtitle: 'Начисления и разблокировки появятся здесь.',
      );
    }

    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'История начислений'.tr(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DomlyColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          ...ledger.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ledgerEntry(entry),
              )),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _parseBonusLedger(Map<String, dynamic> profile) {
    final raw = profile['bonusLedger'];
    if (raw is! List) return [];
    return raw
        .map((e) => e as Map<String, dynamic>)
        .toList()
        .reversed
        .take(20)
        .toList();
  }

  Widget _ledgerEntry(Map<String, dynamic> entry) {
    final label = (entry['label'] ?? '').toString();
    final amount = ((entry['amount'] ?? 0) as num).toInt();
    final unlockAtMs = (entry['unlockAtMs'] as num?)?.toInt() ?? 0;
    final type = (entry['type'] ?? '').toString();

    final icon = _bonusTypeIcon(type);
    String statusText;
    Color statusColor;
    if (unlockAtMs == 0 ||
        unlockAtMs <= DateTime.now().millisecondsSinceEpoch) {
      statusText = 'Доступен';
      statusColor = const Color(0xFF22C55E);
    } else {
      final unlockDate = DateTime.fromMillisecondsSinceEpoch(unlockAtMs);
      final now = DateTime.now();
      final daysLeft = max(0, unlockDate.difference(now).inDays);
      statusText = 'Через $daysLeft дн.';
      statusColor = DomlyColors.muted;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DomlyColors.backgroundSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: DomlyColors.buttonPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                style: TextStyle(fontSize: 11, color: statusColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '+$amount ₸',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
      ],
    );
  }

  IconData _bonusTypeIcon(String type) {
    switch (type) {
      case 'career':
        return Icons.emoji_events;
      case 'weekly_area':
        return Icons.square_foot;
      case 'weekly_addons':
        return Icons.add_circle_outline;
      case 'manual':
        return Icons.admin_panel_settings;
      default:
        return Icons.card_giftcard_outlined;
    }
  }
}
