import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_env.dart';
import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../ui/info_dialog.dart';
import '../../utils/app_logger.dart';
import 'referral_stats_screen.dart';
import '../../localization/translation_controller.dart';

class BonusScreen extends StatefulWidget {
  const BonusScreen({super.key});

  @override
  State<BonusScreen> createState() => _BonusScreenState();
}

class _BonusScreenState extends State<BonusScreen> {
  static const _background = Color(0xFFF2FAF7);
  static const _foreground = Color(0xFF20382F);
  static const _muted = Color(0xFF6C8A7B);
  static const _border = Color(0xFFDDEAE3);
  static const _button = Color(0xFFCC7750);
  static const _green = Color(0xFF4EA16C);

  final _data = FirestoreDataService.instance;
  final _config = AppConfigService.instance;
  bool _isGeneratingLink = false;

  @override
  void initState() {
    super.initState();
    _ensureReferralLink();
  }

  Future<void> _ensureReferralLink() async {
    if (_isGeneratingLink) {
      return;
    }
    setState(() => _isGeneratingLink = true);
    try {
      await _data.ensureReferralLink();
    } catch (error) {
      AppLogger.w('BONUS', 'Failed to ensure referral link', error);
    } finally {
      if (mounted) {
        setState(() => _isGeneratingLink = false);
      }
    }
  }

  Future<void> _copyReferralCode(String referralCode) async {
    if (referralCode.trim().isEmpty) {
      await _ensureReferralLink();
      return;
    }
    await Clipboard.setData(ClipboardData(text: referralCode.toUpperCase()));
    if (!mounted) {
      return;
    }
    showDomlySnackBar(
      context,
      title: 'Код скопирован',
      subtitle: 'Реферальный код добавлен в буфер обмена.',
      type: DomlySnackBarType.info,
    );
  }

  Future<void> _shareReferralLink(String referralCode) async {
    if (referralCode.trim().isEmpty) {
      await _ensureReferralLink();
      return;
    }
    final link = _referralLinkFromCode(referralCode);
    await Share.share(
      'Присоединяйся к DOMLY. Используй мой код: $referralCode. $link',
      subject: 'Приглашение в DOMLY',
    );
  }

  Future<void> _enterReferralCode(String existingCode) async {
    final controller = TextEditingController(text: existingCode);
    final code = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            'Код пригласившего'.tr(),
            style: TextStyle(
              color: _foreground,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'DOMLY-XXXX',
              filled: true,
              fillColor: _background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _green, width: 1.4),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          actions: [
            Row(
              children: [
                Expanded(
                  child: DomlySecondaryButton(
                    label: 'Отмена',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DomlyPrimaryButton(
                    label: 'Сохранить',
                    onPressed: () => Navigator.pop(
                      context,
                      controller.text.trim().toUpperCase(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (code == null || code.isEmpty) {
      return;
    }
    try {
      await _data.applyReferralCodeIfMissing(code);
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Код сохранен',
        subtitle: 'Код пригласившего указан в профиле.',
        type: DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось сохранить код',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  String _referralLinkFromCode(String referralCode) {
    final normalized = referralCode.trim().toUpperCase();
    if (normalized.isEmpty) {
      return '';
    }
    return 'https://${AppEnv.firebaseProjectId}.web.app/?ref=$normalized';
  }

  Future<void> _showBonusInfo(
    String key, {
    required String title,
    required String shortInfo,
    String? fullInfo,
    int? bonusAmount,
  }) async {
    final infoConfig = await _config.getInfoContent(key);
    if (!mounted) {
      return;
    }
    if (infoConfig != null && infoConfig.isNotEmpty) {
      await InfoDialog.showFromConfig(context, config: infoConfig);
      return;
    }
    await InfoDialog.showFromConfig(
      context,
      config: {
        'title': title,
        'shortInfo': shortInfo,
        'fullInfo': fullInfo ?? '',
        if (bonusAmount != null) 'bonusAmount': bonusAmount,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.customerProfileStream(),
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyClientBottomNav(currentIndex: 2),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _BonusMessageCard(
                    title: 'Не удалось загрузить бонусы',
                    subtitle: 'Обновите экран и попробуйте снова.',
                  ),
                ),
              ),
            ),
          );
        }
        if (profileSnap.connectionState == ConnectionState.waiting &&
            !profileSnap.hasData) {
          return const DomlyShell(
            bottomNavigationBar: DomlyClientBottomNav(currentIndex: 2),
            child: SafeArea(
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: _green,
                  ),
                ),
              ),
            ),
          );
        }

        final profile = profileSnap.data ?? const <String, dynamic>{};
        final bonusBalance = (profile['bonusPoints'] as num?)?.toInt() ?? 0;
        final referralCode = (profile['referralCode'] ?? '').toString();
        final referredByCode = (profile['referredByCode'] ?? '').toString();
        final referralQualifiedCount =
            (profile['referralQualifiedCount'] as num?)?.toInt() ?? 0;
        final progress = (referralQualifiedCount / 8).clamp(0.0, 1.0);

        return DomlyShell(
          bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 2),
          child: ColoredBox(
            color: _background,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(15, 16, 15, 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.maybePop(context),
                                child: const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Icon(
                                    Icons.arrow_back,
                                    color: _button,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Бонусы'.tr(),
                              style: TextStyle(
                                color: _foreground,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 27 / 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            'Реферальная программа и ваши скидки'.tr(),
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 16 / 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _BonusBalanceCard(
                          balance: bonusBalance,
                          onTap: null,
                          onInfo: () => _showBonusInfo(
                            'bonus_balance',
                            title: 'Ваш бонусный баланс',
                            shortInfo:
                                'Баланс бонусов, доступных для следующих заказов.',
                            fullInfo:
                                'Здесь отображаются накопленные бонусы. История начислений и оплат открывается по нажатию на карточку.',
                            bonusAmount: bonusBalance,
                          ),
                        ),
                        const SizedBox(height: 10),
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _data.customerBonusTransactionsStream(),
                          builder: (context, bonusSnap) {
                            final items = bonusSnap.data ?? const [];
                            return _BonusTransactionsCard(items: items);
                          },
                        ),
                        const SizedBox(height: 8),
                        _ReferralCodeCard(
                          referralCode: referralCode,
                          isGenerating: _isGeneratingLink,
                          onCopy: () => _copyReferralCode(referralCode),
                          onShare: () => _shareReferralLink(referralCode),
                        ),
                        const SizedBox(height: 10),
                        _TierDiscountCard(
                          progress: progress,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ReferralStatsScreen(),
                              ),
                            );
                          },
                          onInfo: () => _showBonusInfo(
                            'bonus_tiers',
                            title: 'Скидка по уровням',
                            shortInfo: 'Как работает прогресс и уровни скидок.',
                            fullInfo:
                                'Уровень скидки растет по мере оплаченных приглашений. Подробную статистику можно открыть на этом экране.',
                          ),
                        ),
                        const SizedBox(height: 22),
                        _InvitedByCard(
                          referredByCode: referredByCode,
                          onEnterCode: () => _enterReferralCode(referredByCode),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BonusCard extends StatelessWidget {
  const _BonusCard({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(27, 10, 27, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _BonusScreenState._border),
      ),
      child: child,
    );
  }
}

class _BonusBalanceCard extends StatelessWidget {
  const _BonusBalanceCard({
    required this.balance,
    required this.onTap,
    required this.onInfo,
  });

  final int balance;
  final VoidCallback? onTap;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return _BonusCardWithInfo(
      height: 100,
      onTap: onTap,
      onInfo: onInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Ваш бонусный баланс'.tr(),
            style: TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$balance ₸',
            style: const TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Реферальная программа активна'.tr(),
            style: TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralCodeCard extends StatelessWidget {
  const _ReferralCodeCard({
    required this.referralCode,
    required this.isGenerating,
    required this.onCopy,
    required this.onShare,
  });

  final String referralCode;
  final bool isGenerating;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final code = referralCode.trim().isEmpty
        ? (isGenerating ? 'Создание кода...' : 'Код создается')
        : referralCode.toUpperCase();
    return _BonusCard(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Реферальный код'.tr(),
            style: TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Пригласите соседей'.tr(),
            style: TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _BonusSmallButton(
                label: 'Скопировать',
                background: const Color(0xFFC86A4A),
                foreground: Colors.white,
                onTap: onCopy,
              ),
              const Spacer(),
              _BonusSmallButton(
                label: 'Поделиться',
                background: const Color(0xFFF8FBF9),
                foreground: _BonusScreenState._button,
                borderColor: const Color(0xFFF3D6CC),
                onTap: onShare,
              ),
            ],
          ),
          const SizedBox(height: 7),
        ],
      ),
    );
  }
}

class _TierDiscountCard extends StatelessWidget {
  const _TierDiscountCard({
    required this.progress,
    required this.onTap,
    required this.onInfo,
  });

  final double progress;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return _BonusCardWithInfo(
      onTap: onTap,
      onInfo: onInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            'Скидка по уровням'.tr(),
            style: TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'До следующего уровня 1 оплата'.tr(),
            style: TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
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
                  color: const Color(0xFFE5EFE8),
                ),
                FractionallySizedBox(
                  widthFactor: progress <= 0 ? 0.56 : progress,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: _BonusScreenState._green,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            '3% / 7% / 10%',
            style: TextStyle(
              color: _BonusScreenState._green,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitedByCard extends StatelessWidget {
  const _InvitedByCard({
    required this.referredByCode,
    required this.onEnterCode,
  });

  final String referredByCode;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    final hasCode = referredByCode.trim().isNotEmpty;
    return _BonusCard(
      height: 164,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 5),
          Text(
            'Кто вас пригласил'.tr(),
            style: TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            hasCode ? 'Код указан' : 'Код не указан',
            style: const TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasCode ? referredByCode.toUpperCase() : 'Код не указан',
            style: const TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Можно указать только один раз'.tr(),
            style: TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: _BonusSmallButton(
              label: 'Ввести код',
              background: _BonusScreenState._button,
              foreground: Colors.white,
              onTap: hasCode ? null : onEnterCode,
            ),
          ),
        ],
      ),
    );
  }
}

class _BonusTransactionsCard extends StatelessWidget {
  const _BonusTransactionsCard({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(5).toList();
    return _BonusCard(
      height: visible.isEmpty ? 118 : (92 + visible.length * 54).toDouble(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'История бонусов'.tr(),
            style: TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (visible.isEmpty)
            Text(
              'Пока нет начислений и списаний.'.tr(),
              style: TextStyle(
                color: _BonusScreenState._muted,
                fontSize: 12,
                height: 1.35,
              ),
            )
          else
            ...visible.map((item) => _BonusTransactionRow(item: item)),
        ],
      ),
    );
  }
}

class _BonusTransactionRow extends StatelessWidget {
  const _BonusTransactionRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final amount = (item['amount'] as num?)?.toInt() ?? 0;
    final positive = amount >= 0;
    final title = (item['title'] ?? (positive ? 'Начисление' : 'Списание'))
        .toString()
        .trim();
    final reason = (item['reason'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  (positive
                          ? _BonusScreenState._green
                          : _BonusScreenState._button)
                      .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              positive ? Icons.add : Icons.remove,
              size: 18,
              color: positive
                  ? _BonusScreenState._green
                  : _BonusScreenState._button,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty
                      ? (positive ? 'Начисление' : 'Списание')
                      : title,
                  softWrap: true,
                  style: const TextStyle(
                    color: _BonusScreenState._foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason.isEmpty ? _dateText(item['createdAt']) : reason,
                  softWrap: true,
                  style: const TextStyle(
                    color: _BonusScreenState._muted,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${positive ? '+' : ''}$amount ₸',
            style: TextStyle(
              color: positive
                  ? _BonusScreenState._green
                  : _BonusScreenState._button,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static String _dateText(Object? value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }
    if (date == null) {
      return 'Дата появится после синхронизации';
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

class _BonusSmallButton extends StatelessWidget {
  const _BonusSmallButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? background.withValues(alpha: 0.55) : background,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 130,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? foreground.withValues(alpha: 0.65)
                  : foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _BonusCardWithInfo extends StatelessWidget {
  const _BonusCardWithInfo({
    required this.child,
    required this.onInfo,
    this.onTap,
    this.height = 167,
  });

  final Widget child;
  final VoidCallback onInfo;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: _BonusCard(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.only(right: 34),
                  child: child,
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: const Color(0xFFCF7548),
              shape: const CircleBorder(),
              elevation: 8,
              shadowColor: const Color(0xFFCF7548).withValues(alpha: 0.42),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onInfo,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: Text(
                      'i',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BonusMessageCard extends StatelessWidget {
  const _BonusMessageCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _BonusScreenState._border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _BonusScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _BonusScreenState._muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
