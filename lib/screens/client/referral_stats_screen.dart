import 'package:flutter/material.dart';

import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class ReferralStatsScreen extends StatefulWidget {
  const ReferralStatsScreen({super.key});

  @override
  State<ReferralStatsScreen> createState() => _ReferralStatsScreenState();
}

class _ReferralStatsScreenState extends State<ReferralStatsScreen> {
  static const _background = Color(0xFFF2FAF7);
  static const _foreground = Color(0xFF2B4338);
  static const _muted = Color(0xFF658170);
  static const _border = Color(0xFFDEECE3);
  static const _green = Color(0xFF439F73);
  static const _orange = Color(0xFFCF7548);
  static const _greenSoft = Color(0xFFF0F7F2);
  static const _orangeSoft = Color(0xFFF8E7DD);

  final _data = FirestoreDataService.instance;
  final _config = AppConfigService.instance;

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 2),
      child: ColoredBox(
        color: _background,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: _config.referralConfigStream(),
                builder: (context, configSnap) {
                  if (configSnap.hasError) {
                    return const _ReferralStatsError();
                  }
                  final referralConfig = configSnap.data ?? {};
                  final bonusPerReferral =
                      (referralConfig['bonusPerReferral'] as num?)?.toInt() ??
                          2000;
                  return StreamBuilder<Map<String, dynamic>?>(
                    stream: _data.customerProfileStream(),
                    builder: (context, profileSnap) {
                      if (profileSnap.hasError) {
                        return const _ReferralStatsError();
                      }
                      return StreamBuilder<Map<String, dynamic>?>(
                        stream: _data.referralStatsStream(),
                        builder: (context, statsSnap) {
                          final loading = (configSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  profileSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  statsSnap.connectionState ==
                                      ConnectionState.waiting) &&
                              !configSnap.hasData &&
                              !profileSnap.hasData &&
                              !statsSnap.hasData;
                          if (loading) {
                            return const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: _green,
                                ),
                              ),
                            );
                          }
                          if (statsSnap.hasError) {
                            return const _ReferralStatsError();
                          }

                          final profile =
                              profileSnap.data ?? const <String, dynamic>{};
                          final stats =
                              statsSnap.data ?? const <String, dynamic>{};
                          final invited =
                              (stats['invited'] as num?)?.toInt() ?? 0;
                          final registered =
                              (stats['registered'] as num?)?.toInt() ?? 0;
                          final paid = (stats['paid'] as num?)?.toInt() ?? 0;
                          final monthlyActivated =
                              (stats['monthlyActivated'] as num?)?.toInt() ?? 0;
                          final bonus = (stats['bonus'] as num?)?.toInt() ?? 0;
                          final referralDiscountPercent =
                              (stats['referralDiscountPercent'] as num?)
                                      ?.toInt() ??
                                  (profile['referralDiscountPercent'] as num?)
                                      ?.toInt() ??
                                  0;
                          final nextDiscountPercent =
                              (stats['nextReferralDiscountPercent'] as num?)
                                      ?.toInt() ??
                                  _nextDiscountPercent(referralDiscountPercent);
                          final remainingForNextDiscount =
                              (stats['remainingForNextDiscount'] as num?)
                                      ?.toInt() ??
                                  _remainingForNextDiscount(monthlyActivated);
                          final nextDiscountThreshold =
                              (stats['nextReferralDiscountThreshold'] as num?)
                                      ?.toInt() ??
                                  _nextDiscountThreshold(monthlyActivated);

                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(15, 0, 15, 120),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _ReferralStatsHeader(),
                                const SizedBox(height: 20),
                                _ReferralFunnelCard(
                                  bonus: bonus,
                                  invited: invited,
                                  registered: registered,
                                  paid: paid,
                                  monthlyActivated: monthlyActivated,
                                ),
                                const SizedBox(height: 20),
                                _ReferralProgressCard(
                                  monthlyActivated: monthlyActivated,
                                  currentDiscountPercent:
                                      referralDiscountPercent,
                                  nextDiscountPercent: nextDiscountPercent,
                                  remainingForNextDiscount:
                                      remainingForNextDiscount,
                                  nextDiscountThreshold: nextDiscountThreshold,
                                ),
                                const SizedBox(height: 28),
                                _ReferralPotentialCard(
                                  paid: paid,
                                  bonus: bonus,
                                  bonusPerReferral: bonusPerReferral,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static int _nextDiscountPercent(int current) {
    if (current < 3) {
      return 3;
    }
    if (current < 7) {
      return 7;
    }
    if (current < 10) {
      return 10;
    }
    return 10;
  }

  static int _remainingForNextDiscount(int monthlyActivated) {
    final target = _nextDiscountThreshold(monthlyActivated);
    return (target - monthlyActivated).clamp(0, target);
  }

  static int _nextDiscountThreshold(int monthlyActivated) {
    if (monthlyActivated < 5) {
      return 5;
    }
    if (monthlyActivated < 10) {
      return 10;
    }
    if (monthlyActivated < 20) {
      return 20;
    }
    return monthlyActivated == 0 ? 5 : monthlyActivated;
  }
}

class _ReferralStatsHeader extends StatelessWidget {
  const _ReferralStatsHeader();

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
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Реферальная статистика'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Переходы, регистрации, покупки, бонусы'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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

class _ReferralFunnelCard extends StatelessWidget {
  const _ReferralFunnelCard({
    required this.bonus,
    required this.invited,
    required this.registered,
    required this.paid,
    required this.monthlyActivated,
  });

  final int bonus;
  final int invited;
  final int registered;
  final int paid;
  final int monthlyActivated;

  @override
  Widget build(BuildContext context) {
    return _ReferralCard(
      height: 297,
      padding: const EdgeInsets.fromLTRB(20, 17, 35, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Воронка рефералов'.tr(),
            style: TextStyle(
              color: _ReferralStatsScreenState._foreground,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 23 / 18,
            ),
          ),
          const SizedBox(height: 24),
          _ReferralMetricRow(
            label: 'Бонусов получено',
            value: '${_formatMoney(bonus)} ₸',
            background: _ReferralStatsScreenState._orangeSoft,
            valueColor: _ReferralStatsScreenState._orange,
          ),
          const SizedBox(height: 10),
          _ReferralMetricRow(label: 'Приглашено', value: '$invited'),
          const SizedBox(height: 10),
          _ReferralMetricRow(
            label: 'Зарегистрировалось',
            value: '$registered',
          ),
          const SizedBox(height: 10),
          _ReferralMetricRow(label: 'Оплатили', value: '$paid'),
          const SizedBox(height: 10),
          _ReferralMetricRow(
            label: 'Активировали месячный пакет',
            value: '$monthlyActivated',
          ),
        ],
      ),
    );
  }
}

class _ReferralProgressCard extends StatelessWidget {
  const _ReferralProgressCard({
    required this.monthlyActivated,
    required this.currentDiscountPercent,
    required this.nextDiscountPercent,
    required this.remainingForNextDiscount,
    required this.nextDiscountThreshold,
  });

  final int monthlyActivated;
  final int currentDiscountPercent;
  final int nextDiscountPercent;
  final int remainingForNextDiscount;
  final int nextDiscountThreshold;

  @override
  Widget build(BuildContext context) {
    final progress = nextDiscountThreshold > 0
        ? (monthlyActivated / nextDiscountThreshold).clamp(0.0, 1.0)
        : 1.0;
    final subtitle = remainingForNextDiscount > 0
        ? 'До следующей скидки осталось $remainingForNextDiscount\nподключение'
        : 'Максимальная скидка уже активна';

    return _ReferralCard(
      height: 180,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прогресс скидки'.tr(),
            style: TextStyle(
              color: _ReferralStatsScreenState._foreground,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 23 / 18,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: const TextStyle(
              color: _ReferralStatsScreenState._muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 17 / 13,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  color: _ReferralStatsScreenState._greenSoft,
                ),
                FractionallySizedBox(
                  widthFactor: progress <= 0 ? 0.68 : progress,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: _ReferralStatsScreenState._orange,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _ReferralDiscountPill(
                label: 'Текущая скидка $currentDiscountPercent%',
                background: _ReferralStatsScreenState._orangeSoft,
                foreground: _ReferralStatsScreenState._orange,
              ),
              const Spacer(),
              _ReferralDiscountPill(
                label: 'Следующая $nextDiscountPercent%',
                background: _ReferralStatsScreenState._greenSoft,
                foreground: _ReferralStatsScreenState._green,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferralPotentialCard extends StatelessWidget {
  const _ReferralPotentialCard({
    required this.paid,
    required this.bonus,
    required this.bonusPerReferral,
  });

  final int paid;
  final int bonus;
  final int bonusPerReferral;

  @override
  Widget build(BuildContext context) {
    final potential = paid * bonusPerReferral;
    return _ReferralCard(
      height: 120,
      padding: const EdgeInsets.fromLTRB(31, 14, 31, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Потенциал бонусов'.tr(),
            style: TextStyle(
              color: _ReferralStatsScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 21 / 16,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '$paid оплат × $bonusPerReferral ₸ = ${_formatMoney(potential)} ₸\n'
                    'Уже начислено: ${_formatMoney(bonus)} ₸'
                .tr(),
            style: const TextStyle(
              color: _ReferralStatsScreenState._muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 17 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  const _ReferralCard({
    required this.height,
    required this.padding,
    required this.child,
  });

  final double height;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ReferralStatsScreenState._border),
      ),
      child: child,
    );
  }
}

class _ReferralMetricRow extends StatelessWidget {
  const _ReferralMetricRow({
    required this.label,
    required this.value,
    this.background = _ReferralStatsScreenState._greenSoft,
    this.valueColor = _ReferralStatsScreenState._green,
  });

  final String label;
  final String value;
  final Color background;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 12, right: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ReferralStatsScreenState._foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 17 / 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 17 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralDiscountPill extends StatelessWidget {
  const _ReferralDiscountPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 16 / 12,
        ),
      ),
    );
  }
}

class _ReferralStatsError extends StatelessWidget {
  const _ReferralStatsError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: DomlyEmptyStateCard(
          icon: Icons.group_outlined,
          title: 'Не удалось загрузить реферальные данные',
          subtitle: 'Обновите экран и попробуйте снова.',
        ),
      ),
    );
  }
}

String _formatMoney(int value) {
  final raw = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i += 1) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(' ');
    }
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}
