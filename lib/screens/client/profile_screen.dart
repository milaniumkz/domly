import 'dart:async';

import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/address_search_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../admin_web/widgets/osm_point_picker.dart';
import '../common/legal_document_screen.dart';
import '../../localization/translation_controller.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _background = Color(0xFFF2FAF7);
  static const _foreground = Color(0xFF2B4338);
  static const _muted = Color(0xFF658170);
  static const _border = Color(0xFFDEECE3);
  static const _orange = Color(0xFFCF7548);
  static const _soft = Color(0xFFF0F7F2);

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: data.customerProfileStream(),
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyClientBottomNav(currentIndex: 2),
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

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: data.customerSubscriptionsStream(),
          builder: (context, subscriptionsSnap) {
            if (subscriptionsSnap.hasError && !subscriptionsSnap.hasData) {
              return const DomlyShell(
                bottomNavigationBar: DomlyClientBottomNav(currentIndex: 2),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: DomlyEmptyStateCard(
                        title: 'Не удалось загрузить подписку',
                        subtitle: 'Обновите экран и попробуйте снова.',
                        icon: Icons.error_outline,
                      ),
                    ),
                  ),
                ),
              );
            }
            final loading =
                profileSnap.connectionState == ConnectionState.waiting &&
                !profileSnap.hasData &&
                subscriptionsSnap.connectionState == ConnectionState.waiting &&
                !subscriptionsSnap.hasData;
            if (loading) {
              return const DomlyShell(
                bottomNavigationBar: DomlyClientBottomNav(currentIndex: 2),
                child: SafeArea(
                  child: Center(
                    child: CircularProgressIndicator(color: _orange),
                  ),
                ),
              );
            }

            final profile = profileSnap.data ?? <String, dynamic>{};
            final subscriptions =
                subscriptionsSnap.data ?? <Map<String, dynamic>>[];
            final activeSubscription = subscriptions
                .cast<Map<String, dynamic>?>()
                .firstWhere(
                  (item) =>
                      (item?['status'] ?? '').toString().toLowerCase() ==
                      'active',
                  orElse: () => null,
                );
            final monthlySpent =
                (profile['monthly_spent'] as num?)?.toDouble() ?? 0;
            final nextTierThreshold =
                (profile['next_tier_threshold'] as num?)?.toDouble() ?? 0;
            final tierProgress =
                ((profile['tier_progress'] as num?)?.toDouble() ?? 0).clamp(
                  0.0,
                  1.0,
                );
            final tierDiscountPercent =
                (profile['tier_discount_percent'] as num?)?.toInt() ?? 0;
            final addressMissing = !_hasAddress(profile);

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
                        padding: const EdgeInsets.fromLTRB(15, 16, 15, 110),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Профиль'.tr(),
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
                                'Ваши данные и подписка'.tr(),
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 16 / 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (addressMissing) ...[
                              _AddressRequiredBanner(
                                onTap: () =>
                                    openProfileEditor(context, data, profile),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: _ProfileMetricCard(
                                    label: 'Заказов',
                                    value: '${profile['ordersCount'] ?? 0}',
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      '/client/orders',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 30),
                                Expanded(
                                  child: _ProfileMetricCard(
                                    label: 'Рейтинг',
                                    value: '${profile['rating'] ?? 5.0}',
                                    onTap: () => _showInfo(
                                      context,
                                      'Рейтинг',
                                      'Средняя оценка по завершенным уборкам.',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 30),
                                Expanded(
                                  child: _ProfileMetricCard(
                                    label: 'Бонусов',
                                    value: '${profile['bonusPoints'] ?? 0} ₸',
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      '/client/bonus',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 19),
                            _ProfileActionBanner(
                              icon: Icons.payments_outlined,
                              title: 'История оплат',
                              subtitle: 'Счета, оплаты и статусы платежей',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/client/payment-history',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ProfileActionBanner(
                              icon: Icons.description_outlined,
                              title: 'Оферта',
                              subtitle: 'Условия оказания услуг DOMLY',
                              onTap: () => Navigator.pushNamed(
                                context,
                                LegalDocumentScreen.offerRoute,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ProfileActionBanner(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Политика конфиденциальности',
                              subtitle: 'Как DOMLY обрабатывает ваши данные',
                              onTap: () => Navigator.pushNamed(
                                context,
                                LegalDocumentScreen.privacyRoute,
                              ),
                            ),
                            const SizedBox(height: 19),
                            _ProfileCard(
                              height: 120,
                              padding: const EdgeInsets.fromLTRB(
                                27,
                                15,
                                27,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Текущая подписка'.tr(),
                                    style: TextStyle(
                                      color: _foreground,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      height: 24 / 18,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _subscriptionPriceText(
                                      activeSubscription,
                                      profile,
                                    ),
                                    style: const TextStyle(
                                      color: _foreground,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      height: 32 / 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Следующий платеж: ${_nextPaymentText(activeSubscription, profile)}'
                                        .tr(),
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 18 / 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _ProfileCard(
                                    height: 180,
                                    padding: const EdgeInsets.fromLTRB(
                                      27,
                                      14,
                                      27,
                                      17,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ваш прогресс'.tr(),
                                          style: TextStyle(
                                            color: _foreground,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            height: 24 / 18,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _tierLabel(
                                            (profile['tier'] ?? 'NEWBIE')
                                                .toString(),
                                          ),
                                          style: const TextStyle(
                                            color: _foreground,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            height: 27 / 20,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          tierDiscountPercent > 0
                                              ? 'Ваша скидка: $tierDiscountPercent%'
                                              : 'Скидка пока не активирована',
                                          style: const TextStyle(
                                            color: _orange,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            height: 19 / 14,
                                          ),
                                        ),
                                        const SizedBox(height: 19),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Stack(
                                            children: [
                                              Container(
                                                height: 10,
                                                width: double.infinity,
                                                color: _soft,
                                              ),
                                              FractionallySizedBox(
                                                widthFactor: tierProgress <= 0
                                                    ? 0.34
                                                    : tierProgress,
                                                child: Container(
                                                  height: 10,
                                                  color: _orange,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 19),
                                        Text(
                                          nextTierThreshold > 0
                                              ? 'Потрачено в этом месяце: ${monthlySpent.toInt()} / ${nextTierThreshold.toInt()} ₸'
                                              : 'Потрачено в этом месяце: ${monthlySpent.toInt()} ₸',
                                          style: const TextStyle(
                                            color: _muted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            height: 18 / 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Material(
                                    color: const Color(0xFFCF7548),
                                    shape: const CircleBorder(),
                                    elevation: 10,
                                    shadowColor: const Color(
                                      0xFFCF7548,
                                    ).withValues(alpha: 0.75),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _showInfo(
                                        context,
                                        'Ваш прогресс',
                                        'Прогресс зависит от ваших оплат и активности в сервисе. Здесь отображается текущий уровень, доступная скидка и сумма трат за месяц.',
                                      ),
                                      child: const SizedBox(
                                        width: 23,
                                        height: 23,
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
                            const SizedBox(height: 20),
                            _ProfileCard(
                              height: 260,
                              padding: const EdgeInsets.fromLTRB(3, 11, 3, 17),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(left: 25),
                                    child: Text(
                                      'Обязательные поля'.tr(),
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 19 / 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _RequiredProfileTile(
                                    title: 'Мой адрес *',
                                    subtitle: _addressSummary(profile),
                                    onTap: () => openProfileEditor(
                                      context,
                                      data,
                                      profile,
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  _RequiredProfileTile(
                                    title: 'Площадь квартиры *',
                                    subtitle:
                                        '${profile['area'] ?? 0} м² · ${_areaStatusText(profile)}',
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      '/client/area-confirmation',
                                      arguments: {
                                        'area':
                                            profile['area'] ??
                                            profile['apartmentArea'] ??
                                            profile['actualArea'] ??
                                            profile['initialArea'],
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  _RequiredProfileTile(
                                    title: 'Телефон *',
                                    subtitle:
                                        (profile['phone'] ?? '')
                                            .toString()
                                            .trim()
                                            .isEmpty
                                        ? 'Не заполнен'
                                        : (profile['phone'] ?? '').toString(),
                                    onTap: () =>
                                        _showPhoneInfo(context, profile),
                                  ),
                                  const SizedBox(height: 11),
                                  _RequiredProfileTile(
                                    title: 'Кто вас пригласил',
                                    subtitle:
                                        (profile['referredByCode'] ?? '')
                                            .toString()
                                            .trim()
                                            .isEmpty
                                        ? 'Код не указан'
                                        : (profile['referredByCode'] ?? '')
                                              .toString(),
                                    onTap: () => _openReferrerCodeEditor(
                                      context,
                                      data,
                                      profile,
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _subscriptionPriceText(
    Map<String, dynamic>? subscription,
    Map<String, dynamic> profile,
  ) {
    final amount = (subscription?['price'] ?? profile['planPrice'] ?? 0);
    final packageId = (subscription?['packageId'] ?? subscription?['id'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final packageName =
        (subscription?['package'] ?? subscription?['frequencyLabel'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    if (packageId == 'quarter' || packageName.contains('кварт')) {
      return '$amount ₸ / квартал';
    }
    if (packageId == 'general_cleaning' ||
        packageId == 'post_renovation' ||
        packageId == 'single' ||
        packageId == 'one_time' ||
        packageName.contains('ген') ||
        packageName.contains('ремонт') ||
        packageName.contains('разов')) {
      return '$amount ₸ / заказ';
    }
    return '$amount ₸ / месяц';
  }

  static String _editableName(Object? value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty ||
        text == 'null' ||
        text.toLowerCase() == 'пользователь') {
      return '';
    }
    return text;
  }

  static String _nextPaymentText(
    Map<String, dynamic>? subscription,
    Map<String, dynamic> profile,
  ) {
    final renewal = subscription?['renewalAt'];
    if (renewal is Timestamp) {
      return domlyDateText(
        _normalizeNextPaymentDate(renewal.toDate(), subscription),
      );
    }
    final fallback = (profile['nextPaymentDate'] ?? '').toString().trim();
    final parsedFallback = _parseProfilePaymentDate(fallback);
    if (parsedFallback != null) {
      return domlyDateText(
        _normalizeNextPaymentDate(parsedFallback, subscription),
      );
    }
    return fallback.isEmpty ? '—' : fallback;
  }

  static DateTime _normalizeNextPaymentDate(
    DateTime date,
    Map<String, dynamic>? subscription,
  ) {
    final today = DateTime.now();
    var candidate = DateTime(date.year, date.month, date.day);
    final floorToday = DateTime(today.year, today.month, today.day);
    final packageId = (subscription?['packageId'] ?? subscription?['id'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final packageName =
        (subscription?['package'] ?? subscription?['frequencyLabel'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final isQuarterly = packageId == 'quarter' || packageName.contains('кварт');
    final isOneTime =
        packageId == 'general_cleaning' ||
        packageId == 'post_renovation' ||
        packageId == 'single' ||
        packageId == 'one_time' ||
        packageName.contains('ген') ||
        packageName.contains('ремонт') ||
        packageName.contains('разов');
    if (isOneTime) {
      return candidate;
    }
    final monthsStep = isQuarterly ? 3 : 1;
    while (candidate.isBefore(floorToday)) {
      candidate = DateTime(
        candidate.year,
        candidate.month + monthsStep,
        candidate.day,
      );
    }
    return candidate;
  }

  static DateTime? _parseProfilePaymentDate(String value) {
    if (value.isEmpty || value == '—') {
      return null;
    }
    final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final day = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final year = int.tryParse(match.group(3) ?? '');
    if (day == null || month == null || year == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static String _addressSummary(Map<String, dynamic> profile) {
    final addresses = (profile['addresses'] as List?)?.whereType<Map>();
    final extraCount = (addresses?.length ?? 0) > 1
        ? ' + ещё ${(addresses?.length ?? 1) - 1}'
        : '';
    final parts = [
      profile['residentialComplex'],
      profile['entrance'] != null && '${profile['entrance']}'.isNotEmpty
          ? 'подъезд ${profile['entrance']}'
          : null,
      profile['apartment'] != null && '${profile['apartment']}'.isNotEmpty
          ? 'кв. ${profile['apartment']}'
          : null,
      profile['area'] != null && '${profile['area']}' != '0'
          ? '${profile['area']} м²'
          : null,
    ].where((value) => value != null && '$value'.isNotEmpty).join(', ');
    return parts.isEmpty
        ? 'Адрес и параметры квартиры не заполнены'
        : '$parts$extraCount';
  }

  static bool _hasAddress(Map<String, dynamic> profile) {
    final addresses = profile['addresses'];
    if (addresses is List && addresses.isNotEmpty) {
      return true;
    }
    for (final key in const [
      'houseId',
      'residentialComplex',
      'address',
      'homeAddress',
    ]) {
      if ((profile[key] ?? '').toString().trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static String _areaStatusText(Map<String, dynamic> profile) {
    final status = (profile['areaStatus'] ?? '').toString().toUpperCase();
    if (status == 'VERIFIED') {
      return 'проверено';
    }
    if (status == 'MISMATCH') {
      return 'есть расхождение';
    }
    return 'не проверено';
  }

  static String _tierLabel(String tier) {
    switch (tier) {
      case 'CLEANSTER':
        return 'Наш любимый чистюля';
      case 'GURU':
        return 'Гуру чистоты';
      case 'GOD':
        return 'Бог чистоты';
      default:
        return 'Наш любимый Новичок';
    }
  }

  static void _showInfo(BuildContext context, String title, String subtitle) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DomlyColors.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: DomlyColors.muted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _showPhoneInfo(
    BuildContext context,
    Map<String, dynamic> profile,
  ) {
    final phone = (profile['phone'] ?? '').toString().trim();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Телефон'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
        content: Text(
          phone.isEmpty
              ? 'Телефон пока не добавлен. Обновить его можно через повторный вход по номеру.'
              : 'Номер подтверждён: $phone',
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: DomlyColors.foreground,
          ),
        ),
        actions: [
          SizedBox(
            width: 132,
            child: DomlyPrimaryButton(
              label: 'Понятно',
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  static void _openReferrerCodeEditor(
    BuildContext context,
    FirestoreDataService data,
    Map<String, dynamic> profile,
  ) {
    final codeController = TextEditingController(
      text: (profile['referredByCode'] ?? '').toString(),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Кто вас пригласил'.tr(),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Введите реферальный код знакомого, чтобы активировать бонусы.'
                        .tr(),
                    style: TextStyle(fontSize: 13, color: DomlyColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Реферальный код',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DomlyPrimaryButton(
                    label: 'Применить код',
                    onPressed: () async {
                      try {
                        await data.applyReferralCodeIfMissing(
                          codeController.text.trim().toUpperCase(),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.pop(context);
                        showDomlySnackBar(
                          context,
                          title: 'Код сохранён',
                          subtitle: 'Реферальный код применён к аккаунту.',
                          type: DomlySnackBarType.success,
                        );
                      } catch (error) {
                        if (!context.mounted) {
                          return;
                        }
                        showDomlySnackBar(
                          context,
                          title: 'Ошибка сохранения',
                          subtitle: '$error',
                          type: DomlySnackBarType.error,
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(codeController.dispose);
  }

  static Future<bool> openProfileEditor(
    BuildContext context,
    FirestoreDataService data,
    Map<String, dynamic> profile, {
    bool requireCompletion = false,
    bool stayInCurrentFlow = false,
  }) async {
    final nameController = TextEditingController(
      text: _editableName(profile['name'] ?? profile['fullName']),
    );
    final residentialController = TextEditingController(
      text: (profile['residentialComplex'] ?? profile['address'] ?? '')
          .toString(),
    );
    final initialResidentialText = residentialController.text.trim();
    final entranceController = TextEditingController(
      text: (profile['entrance'] ?? '').toString(),
    );
    final apartmentController = TextEditingController(
      text: (profile['apartment'] ?? '').toString(),
    );
    final areaController = TextEditingController(
      text: (profile['area'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (profile['phone'] ?? '').toString(),
    );
    var detectedCity = (profile['city'] ?? '').toString().trim();
    AddressSuggestion? selectedAddress;
    List<AddressSuggestion> addressOptions = const <AddressSuggestion>[];
    try {
      final houses = await data.getAvailableHouses();
      addressOptions = houses.map((house) {
        final residential =
            (house['residentialComplex'] ??
                    house['title'] ??
                    house['address'] ??
                    '')
                .toString()
                .trim();
        final address = (house['address'] ?? residential).toString().trim();
        return AddressSuggestion(
          title: residential.isEmpty ? address : residential,
          subtitle: address == residential ? '' : address,
          placeId: (house['id'] ?? '').toString(),
          residentialComplex: residential,
          addressLine: address,
          isResidentialComplex: residential.isNotEmpty,
          lat: _readDouble(house['lat']),
          lng: _readDouble(house['lng']),
          city: (house['city'] ?? '').toString(),
        );
      }).toList();
    } catch (_) {
      addressOptions = const <AddressSuggestion>[];
    }
    if (!context.mounted) {
      return false;
    }

    List<AddressSuggestion> filterAddressOptions(String value) {
      final normalized = _normalizeAddressQuery(value);
      final looseNormalized = _normalizeAddressLooseQuery(value);
      final normalizedCity = _normalizeAddressQuery(detectedCity);
      if (normalized.isEmpty) {
        return const <AddressSuggestion>[];
      }
      final queryTokens = normalized
          .split(' ')
          .where((token) => token.length > 1)
          .toList();
      final items = addressOptions.where((item) {
        final itemCity = _normalizeAddressQuery(item.city);
        if (normalizedCity.isNotEmpty &&
            itemCity.isNotEmpty &&
            itemCity != normalizedCity) {
          return false;
        }
        final complexText = _normalizeAddressQuery(
          '${item.residentialComplex} ${item.title}',
        );
        final looseComplexText = _normalizeAddressLooseQuery(complexText);
        final haystack = _normalizeAddressQuery(
          '${item.title} ${item.subtitle} ${item.residentialComplex} ${item.addressLine}',
        );
        final tokens = normalized
            .split(' ')
            .where((token) => token.length > 1)
            .toList();
        final complexMatched =
            complexText.contains(normalized) ||
            looseComplexText.contains(looseNormalized) ||
            queryTokens.every((token) => complexText.contains(token));
        return complexMatched ||
            haystack.contains(normalized) ||
            tokens.every((token) => haystack.contains(token)) ||
            _addressLooksSimilar(value, haystack);
      }).toList();
      items.sort((a, b) {
        final aComplex = _normalizeAddressQuery(
          '${a.residentialComplex} ${a.title}',
        );
        final bComplex = _normalizeAddressQuery(
          '${b.residentialComplex} ${b.title}',
        );
        final aComplexMatch =
            normalized.isNotEmpty && aComplex.contains(normalized);
        final bComplexMatch =
            normalized.isNotEmpty && bComplex.contains(normalized);
        if (aComplexMatch != bComplexMatch) {
          return aComplexMatch ? -1 : 1;
        }
        return a.fullText.compareTo(b.fullText);
      });
      return items.take(10).toList();
    }

    AddressSuggestion? resolveTypedAddress(String value) {
      final normalized = _normalizeAddressQuery(value);
      if (normalized.isEmpty) {
        return null;
      }
      final options = filterAddressOptions(value);
      if (options.isEmpty) {
        return null;
      }
      for (final item in options) {
        final itemText = _normalizeAddressQuery(item.fullText);
        if (itemText == normalized) {
          return item;
        }
      }
      for (final item in options) {
        final itemText = _normalizeAddressQuery(
          '${item.title} ${item.subtitle} ${item.residentialComplex} ${item.addressLine}',
        );
        if (itemText.contains(normalized) ||
            normalized.contains(itemText) ||
            _addressLooksSimilar(value, itemText)) {
          return item;
        }
      }
      return options.length == 1 ? options.first : null;
    }

    var filteredAddressOptions = filterAddressOptions(
      residentialController.text.trim(),
    );
    var addressLookupRequestId = 0;
    var addressLookupLoading = false;
    var detectingCity = false;
    var cityDetectionAttempted = false;

    Future<void> detectCityFromLocation(
      void Function(void Function()) setModalState,
    ) async {
      if (detectedCity.isNotEmpty) {
        return;
      }
      if (detectingCity || cityDetectionAttempted) {
        return;
      }
      detectingCity = true;
      cityDetectionAttempted = true;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) {
          return;
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 5));
        final suggestion = await AddressSearchService.instance.reverse(
          position.latitude,
          position.longitude,
        );
        final city = suggestion?.city.trim() ?? '';
        if (city.isNotEmpty && context.mounted) {
          setModalState(() => detectedCity = city);
        }
      } catch (_) {
        // Геолокация необязательна: если нет доступа, поиск останется по городу профиля.
      } finally {
        detectingCity = false;
      }
    }

    List<AddressSuggestion> mergeAddressSuggestions(
      List<AddressSuggestion> localItems,
      List<AddressSuggestion> remoteItems,
    ) {
      final seen = <String>{};
      final items = <AddressSuggestion>[];
      for (final item in [...localItems, ...remoteItems]) {
        final key = _normalizeAddressQuery(item.fullText);
        if (key.isEmpty || seen.contains(key)) {
          continue;
        }
        seen.add(key);
        items.add(item);
      }
      return items.take(10).toList();
    }

    final saved =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: !requireCompletion,
          enableDrag: !requireCompletion,
          showDragHandle: true,
          builder: (context) {
            return PopScope(
              canPop: !requireCompletion,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  unawaited(detectCityFromLocation(setModalState));
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 12,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Данные аккаунта'.tr(),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Поля с * обязательны для работы аккаунта.'.tr(),
                            style: TextStyle(
                              fontSize: 13,
                              color: DomlyColors.muted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'ФИО',
                              hintText: 'Введите ФИО',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: residentialController,
                            onChanged: (value) {
                              final requestId = ++addressLookupRequestId;
                              final localItems = filterAddressOptions(value);
                              setModalState(() {
                                selectedAddress = null;
                                filteredAddressOptions = localItems;
                                addressLookupLoading = value.trim().length >= 3;
                              });
                              if (value.trim().length < 3) {
                                setModalState(
                                  () => addressLookupLoading = false,
                                );
                                return;
                              }
                              AddressSearchService.instance
                                  .search(value, city: detectedCity)
                                  .then((remoteItems) {
                                    if (!context.mounted ||
                                        requestId != addressLookupRequestId) {
                                      return;
                                    }
                                    setModalState(() {
                                      filteredAddressOptions =
                                          mergeAddressSuggestions(
                                            localItems,
                                            remoteItems,
                                          );
                                      if (remoteItems.isNotEmpty &&
                                          remoteItems.first.city
                                              .trim()
                                              .isNotEmpty) {
                                        detectedCity = remoteItems.first.city
                                            .trim();
                                      }
                                      addressLookupLoading = false;
                                    });
                                  })
                                  .catchError((_) {
                                    if (!context.mounted ||
                                        requestId != addressLookupRequestId) {
                                      return;
                                    }
                                    setModalState(
                                      () => addressLookupLoading = false,
                                    );
                                  });
                            },
                            decoration: InputDecoration(
                              labelText: 'Мой адрес *',
                              hintText:
                                  'Начните вводить ЖК, улицу или номер дома',
                              suffixIcon: addressLookupLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.search),
                            ),
                          ),
                          if (filteredAddressOptions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: DomlyColors.border),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredAddressOptions.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: DomlyColors.border,
                                ),
                                itemBuilder: (context, index) {
                                  final item = filteredAddressOptions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: DomlyColors.buttonPrimary,
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: item.subtitle.isEmpty
                                        ? null
                                        : Text(
                                            item.subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () {
                                      setModalState(() {
                                        selectedAddress = item;
                                        residentialController.text =
                                            item.fullText;
                                        filteredAddressOptions =
                                            const <AddressSuggestion>[];
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ] else if (residentialController.text.trim().length >=
                                  2 &&
                              selectedAddress == null) ...[
                            const SizedBox(height: 8),
                            DomlyCard(
                              color: DomlyColors.backgroundSoft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Адрес не найден среди подключенных домов'
                                        .tr(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Запросите подключение: отметьте дом на карте, и адрес попадет в лист ожидания.'
                                        .tr(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: DomlyColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DomlySecondaryButton(
                                    label: 'Запросить подключение',
                                    onPressed: () async {
                                      final requested =
                                          await _openAddressConnectionRequest(
                                            context,
                                            data,
                                            initialAddress:
                                                residentialController.text
                                                    .trim(),
                                            initialCity: detectedCity,
                                            entrance: entranceController.text
                                                .trim(),
                                            apartment: apartmentController.text
                                                .trim(),
                                            area:
                                                (_parseArea(
                                                          areaController.text,
                                                        ) ??
                                                        0)
                                                    .ceil(),
                                          );
                                      if (requested == null ||
                                          !context.mounted) {
                                        return;
                                      }
                                      final houseId =
                                          (requested['houseId'] ?? '')
                                              .toString();
                                      final addressText =
                                          (requested['address'] ?? '')
                                              .toString();
                                      final residentialText =
                                          (requested['residentialComplex'] ??
                                                  addressText)
                                              .toString();
                                      final nextAddress = AddressSuggestion(
                                        title: residentialText,
                                        subtitle: addressText == residentialText
                                            ? ''
                                            : addressText,
                                        placeId: houseId,
                                        residentialComplex: residentialText,
                                        addressLine: addressText,
                                        isResidentialComplex: true,
                                        lat: _readDouble(requested['lat']),
                                        lng: _readDouble(requested['lng']),
                                        city: (requested['city'] ?? '')
                                            .toString(),
                                      );
                                      setModalState(() {
                                        selectedAddress = nextAddress;
                                        residentialController.text =
                                            nextAddress.fullText;
                                        filteredAddressOptions =
                                            const <AddressSuggestion>[];
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: entranceController,
                                  decoration: const InputDecoration(
                                    labelText: 'Подъезд',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: apartmentController,
                                  decoration: const InputDecoration(
                                    labelText: 'Квартира',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: areaController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Площадь квартиры *',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Телефон *',
                              hintText: '+7 777 000 00 00',
                            ),
                          ),
                          const SizedBox(height: 16),
                          DomlyPrimaryButton(
                            label: 'Сохранить',
                            onPressed: () async {
                              final residential = residentialController.text
                                  .trim();
                              final phone = phoneController.text.trim();
                              final area = _parseArea(areaController.text) ?? 0;
                              final previousArea =
                                  (_readDouble(profile['apartmentArea']) ??
                                  _readDouble(profile['area']) ??
                                  0);
                              final shouldConfirmAreaDocuments =
                                  area > 0 &&
                                  (previousArea != area ||
                                      profile['areaVerified'] != true);
                              if (residential.isEmpty ||
                                  area <= 0 ||
                                  phone.isEmpty) {
                                showDomlySnackBar(
                                  context,
                                  title: 'Заполните обязательные поля',
                                  subtitle: 'Нужны адрес, площадь и телефон.',
                                  type: DomlySnackBarType.error,
                                );
                                return;
                              }
                              try {
                                var address = selectedAddress;
                                final existingHouseId =
                                    (profile['houseId'] ?? '')
                                        .toString()
                                        .trim();
                                final addressUnchanged =
                                    residential == initialResidentialText;
                                if (address == null &&
                                    existingHouseId.isNotEmpty &&
                                    addressUnchanged) {
                                  address = AddressSuggestion(
                                    title:
                                        (profile['residentialComplex'] ??
                                                profile['address'] ??
                                                residential)
                                            .toString(),
                                    subtitle: (profile['address'] ?? '')
                                        .toString(),
                                    placeId: existingHouseId,
                                    residentialComplex:
                                        (profile['residentialComplex'] ??
                                                residential)
                                            .toString(),
                                    addressLine:
                                        (profile['address'] ?? residential)
                                            .toString(),
                                    isResidentialComplex: true,
                                    lat: _readDouble(profile['addressLat']),
                                    lng: _readDouble(profile['addressLng']),
                                  );
                                }
                                address ??= resolveTypedAddress(residential);
                                if (address == null) {
                                  showDomlySnackBar(
                                    context,
                                    title: 'Выберите адрес из списка',
                                    subtitle:
                                        'Доступны только дома и районы, добавленные в админке.',
                                    type: DomlySnackBarType.error,
                                  );
                                  return;
                                }
                                final addressText =
                                    address.addressText.trim().isNotEmpty ==
                                        true
                                    ? address.addressText
                                    : residential;
                                final residentialText =
                                    address.selectionText.trim().isNotEmpty ==
                                        true
                                    ? address.selectionText
                                    : residential;
                                final cityText = address.city.trim().isNotEmpty
                                    ? address.city.trim()
                                    : detectedCity;
                                final house = await data.resolveHouseForAddress(
                                  residentialComplex: residentialText,
                                  addressLine: addressText,
                                  placeId: address.placeId.isNotEmpty
                                      ? address.placeId
                                      : (profile['addressPlaceId'] ?? '')
                                            .toString(),
                                  lat:
                                      address.lat ??
                                      _readDouble(profile['addressLat']),
                                  lng:
                                      address.lng ??
                                      _readDouble(profile['addressLng']),
                                );
                                var houseId = (house?['id'] ?? '').toString();
                                var houseStatus = (house?['status'] ?? '')
                                    .toString();
                                if (houseId.isEmpty) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  showDomlySnackBar(
                                    context,
                                    title: 'Адрес недоступен',
                                    subtitle:
                                        'Выберите дом из списка, который добавлен в админке.',
                                    type: DomlySnackBarType.error,
                                  );
                                  return;
                                }
                                await data.updateCustomerProfile({
                                  'name': nameController.text.trim(),
                                  'initialArea': area,
                                  'actualArea': area,
                                  'residentialComplex': residentialText,
                                  'address': addressText,
                                  'addressPlaceId': address.placeId.isNotEmpty
                                      ? address.placeId
                                      : (profile['addressPlaceId'] ?? '')
                                            .toString(),
                                  'addressLat':
                                      address.lat ??
                                      _readDouble(profile['addressLat']),
                                  'addressLng':
                                      address.lng ??
                                      _readDouble(profile['addressLng']),
                                  if (houseId.isNotEmpty) 'houseId': houseId,
                                  if (houseStatus.isNotEmpty)
                                    'houseStatus': houseStatus,
                                  if (cityText.isNotEmpty) 'city': cityText,
                                  'entrance': entranceController.text.trim(),
                                  'apartment': apartmentController.text.trim(),
                                  'area': area,
                                  'phone': phone,
                                  'addresses': [
                                    {
                                      'address': addressText,
                                      'residentialComplex': residentialText,
                                      'addressPlaceId':
                                          address.placeId.isNotEmpty
                                          ? address.placeId
                                          : (profile['addressPlaceId'] ?? '')
                                                .toString(),
                                      'addressLat':
                                          address.lat ??
                                          _readDouble(profile['addressLat']),
                                      'addressLng':
                                          address.lng ??
                                          _readDouble(profile['addressLng']),
                                      'houseId': houseId,
                                      'houseStatus': houseStatus,
                                      if (cityText.isNotEmpty) 'city': cityText,
                                      'entrance': entranceController.text
                                          .trim(),
                                      'apartment': apartmentController.text
                                          .trim(),
                                      'area': area,
                                      'phone': phone,
                                      'isPrimary': true,
                                    },
                                  ],
                                });
                                if (!context.mounted) {
                                  return;
                                }
                                Navigator.pop(context, true);
                                if (stayInCurrentFlow) {
                                  return;
                                }
                                final normalizedHouseStatus = houseStatus
                                    .trim()
                                    .toUpperCase();
                                showDomlySnackBar(
                                  context,
                                  title: 'Профиль сохранён',
                                  subtitle: shouldConfirmAreaDocuments
                                      ? 'Подтвердите площадь документом.'
                                      : normalizedHouseStatus == 'ACTIVE'
                                      ? 'Дом подключен. Можно выбрать пакет.'
                                      : 'Адрес сохранён. Откроем экран подключения дома.',
                                  type: DomlySnackBarType.success,
                                );
                                if (shouldConfirmAreaDocuments) {
                                  Navigator.pushNamed(
                                    context,
                                    '/client/area-confirmation',
                                    arguments: {
                                      'initialArea': area,
                                      'actualArea': area,
                                      'forceTechPlanPrompt': true,
                                    },
                                  );
                                  return;
                                }
                                if (normalizedHouseStatus == 'ACTIVE') {
                                  Navigator.pushNamed(
                                    context,
                                    '/client/packages',
                                  );
                                } else {
                                  Navigator.pushNamed(
                                    context,
                                    '/client/house-waitlist',
                                    arguments: {'houseId': houseId},
                                  );
                                }
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                showDomlySnackBar(
                                  context,
                                  title: 'Ошибка сохранения',
                                  subtitle: '$error',
                                  type: DomlySnackBarType.error,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ).whenComplete(() {
          nameController.dispose();
          residentialController.dispose();
          entranceController.dispose();
          apartmentController.dispose();
          areaController.dispose();
          phoneController.dispose();
        });
    return saved == true;
  }

  static Future<Map<String, dynamic>?> _openAddressConnectionRequest(
    BuildContext context,
    FirestoreDataService data, {
    required String initialAddress,
    String initialCity = '',
    required String entrance,
    required String apartment,
    required int area,
  }) {
    final addressController = TextEditingController(text: initialAddress);
    final cityController = TextEditingController(text: initialCity);
    Map<String, double>? point;
    List<AddressSuggestion> suggestions = const <AddressSuggestion>[];
    List<String> citySuggestions = const <String>[];
    var searching = false;
    var saving = false;
    var reverseGeneration = 0;
    var detectingCity = false;
    var cityDetectionAttempted = false;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> detectCityFromLocation() async {
              if (cityController.text.trim().isNotEmpty ||
                  detectingCity ||
                  cityDetectionAttempted) {
                return;
              }
              detectingCity = true;
              cityDetectionAttempted = true;
              try {
                if (!await Geolocator.isLocationServiceEnabled()) {
                  return;
                }
                var permission = await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) {
                  permission = await Geolocator.requestPermission();
                }
                if (permission == LocationPermission.denied ||
                    permission == LocationPermission.deniedForever) {
                  return;
                }
                final position = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.low,
                ).timeout(const Duration(seconds: 5));
                final item = await AddressSearchService.instance.reverse(
                  position.latitude,
                  position.longitude,
                );
                if (!context.mounted) {
                  return;
                }
                setModalState(() {
                  point = {'lat': position.latitude, 'lng': position.longitude};
                  if ((item?.city ?? '').trim().isNotEmpty) {
                    cityController.text = item!.city.trim();
                  }
                });
              } catch (_) {
                // Геолокация необязательна.
              } finally {
                detectingCity = false;
              }
            }

            unawaited(detectCityFromLocation());

            Future<void> searchAddress() async {
              final query = addressController.text.trim();
              if (query.length < 2 || searching) {
                return;
              }
              setModalState(() => searching = true);
              try {
                final selectedPoint = point;
                final items = await AddressSearchService.instance.search(
                  query,
                  city: cityController.text.trim(),
                  bias: selectedPoint == null
                      ? null
                      : AddressSearchBias(
                          lat: selectedPoint['lat']!,
                          lng: selectedPoint['lng']!,
                          radiusKm: 18,
                        ),
                );
                if (!context.mounted) {
                  return;
                }
                setModalState(() {
                  suggestions = items;
                  if (items.isNotEmpty &&
                      items.first.lat != null &&
                      items.first.lng != null) {
                    if (items.first.city.trim().isNotEmpty) {
                      cityController.text = items.first.city.trim();
                    }
                    point = {'lat': items.first.lat!, 'lng': items.first.lng!};
                  }
                });
              } finally {
                if (context.mounted) {
                  setModalState(() => searching = false);
                }
              }
            }

            Future<void> reversePoint(Map<String, double> value) async {
              final generation = ++reverseGeneration;
              final lat = value['lat'];
              final lng = value['lng'];
              if (lat == null || lng == null) {
                return;
              }
              final item = await AddressSearchService.instance.reverse(
                lat,
                lng,
              );
              if (!context.mounted ||
                  generation != reverseGeneration ||
                  item == null) {
                return;
              }
              setModalState(() {
                if (item.city.trim().isNotEmpty) {
                  cityController.text = item.city.trim();
                }
                final text = item.fullText.trim();
                if (text.isNotEmpty) {
                  addressController.text = text;
                }
                suggestions = const <AddressSuggestion>[];
              });
            }

            Future<void> submit() async {
              if (saving) {
                return;
              }
              final address = addressController.text.trim();
              final selectedPoint = point;
              if (address.isEmpty ||
                  selectedPoint == null ||
                  selectedPoint['lat'] == null ||
                  selectedPoint['lng'] == null) {
                showDomlySnackBar(
                  context,
                  title: 'Укажите адрес и точку дома',
                  subtitle: 'Найдите адрес или поставьте точку дома на карте.',
                  type: DomlySnackBarType.error,
                );
                return;
              }
              setModalState(() => saving = true);
              try {
                final result = await data.requestServiceAddress(
                  residentialComplex: address,
                  address: address,
                  city: cityController.text.trim(),
                  lat: selectedPoint['lat'],
                  lng: selectedPoint['lng'],
                  entrance: entrance,
                  apartment: apartment,
                  area: area <= 0 ? 1 : area,
                );
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(context, {
                  ...result,
                  'address': address,
                  'residentialComplex': address,
                  'city': cityController.text.trim(),
                  'lat': selectedPoint['lat'],
                  'lng': selectedPoint['lng'],
                });
              } catch (error) {
                if (!context.mounted) {
                  return;
                }
                showDomlySnackBar(
                  context,
                  title: 'Не удалось отправить запрос',
                  subtitle: '$error',
                  type: DomlySnackBarType.error,
                );
              } finally {
                if (context.mounted) {
                  setModalState(() => saving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Запросить подключение'.tr(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Найдите дом по адресу или поставьте точку на карте.'
                          .tr(),
                      style: TextStyle(fontSize: 13, color: DomlyColors.muted),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: cityController,
                      onChanged: (value) {
                        setModalState(() {
                          citySuggestions = AddressSearchService.instance
                              .searchCities(value);
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Город',
                        hintText: 'Начните вводить город',
                      ),
                    ),
                    if (citySuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 88,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: citySuggestions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final city = citySuggestions[index];
                            return ActionChip(
                              label: Text(city),
                              onPressed: () {
                                setModalState(() {
                                  cityController.text = city;
                                  citySuggestions = const <String>[];
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: addressController,
                      onSubmitted: (_) => searchAddress(),
                      decoration: InputDecoration(
                        labelText: 'Адрес дома',
                        suffixIcon: IconButton(
                          onPressed: searching ? null : searchAddress,
                          icon: searching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search),
                        ),
                      ),
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 240,
                        child: ListView.separated(
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = suggestions[index];
                            return ListTile(
                              dense: true,
                              tileColor: DomlyColors.backgroundSoft,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: Text(
                                item.fullText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                setModalState(() {
                                  addressController.text = item.fullText;
                                  if (item.city.trim().isNotEmpty) {
                                    cityController.text = item.city.trim();
                                  }
                                  if (item.lat != null && item.lng != null) {
                                    point = {
                                      'lat': item.lat!,
                                      'lng': item.lng!,
                                    };
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Expanded(
                      child: OsmPointPicker(
                        point: point == null || point!.isEmpty ? null : point,
                        centerLat: point?['lat'] ?? 43.2389,
                        centerLng: point?['lng'] ?? 76.8897,
                        onChanged: (value) {
                          setModalState(() => point = value);
                          reversePoint(value);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    DomlyPrimaryButton(
                      label: 'Отправить запрос подключения',
                      isLoading: saving,
                      onPressed: saving ? null : submit,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      addressController.dispose();
      cityController.dispose();
    });
  }

  static double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value');
  }

  static double? _parseArea(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  static String _normalizeAddressQuery(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('ә', 'а')
        .replaceAll('ғ', 'г')
        .replaceAll('қ', 'к')
        .replaceAll('ң', 'н')
        .replaceAll('ө', 'о')
        .replaceAll('ұ', 'у')
        .replaceAll('ү', 'у')
        .replaceAll('һ', 'х')
        .replaceAll('і', 'и')
        .replaceAll('жилой комплекс', 'жк')
        .replaceAll(RegExp(r'\b(улица|ул|проспект|пр|переулок|пер)\b'), ' ')
        .replaceAll(
          RegExp(r'\b(кошеси|көшесі|коше|көше|дангылы|даңғылы)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normalizeAddressLooseQuery(String value) =>
      _normalizeAddressQuery(value).replaceAll('ы', 'и');

  static bool _isAddressNumberToken(String token) =>
      RegExp(r'^\d+[a-zа-я]?$').hasMatch(token);

  static const Set<String> _addressNoiseTokens = {
    'улица',
    'ул',
    'проспект',
    'пр',
    'переулок',
    'пер',
    'коше',
    'кошеси',
    'көшесі',
    'дангылы',
    'даңғылы',
    'батыр',
    'батыра',
    'батыров',
    'жк',
  };

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((left, right) => left < right ? left : right);
      }
      previous = current;
    }
    return previous.last;
  }

  static bool _tokenLooksLikePart(
    String query,
    String target,
    int maxDistance,
  ) {
    if ((query.length - target.length).abs() <= maxDistance &&
        _editDistance(query, target) <= maxDistance) {
      return true;
    }
    if (query.length < 3 || target.length <= query.length) {
      return false;
    }
    for (var index = 0; index <= target.length - query.length; index += 1) {
      final part = target.substring(index, index + query.length);
      if (_editDistance(query, part) <= maxDistance) {
        return true;
      }
    }
    return false;
  }

  static bool _addressLooksSimilar(String query, String haystack) {
    final queryTokens = _normalizeAddressLooseQuery(
      query,
    ).split(' ').where((token) => token.length > 1).toSet();
    final haystackTokens = _normalizeAddressLooseQuery(
      haystack,
    ).split(' ').where((token) => token.length > 1).toSet();
    final numberMatched = queryTokens
        .where(_isAddressNumberToken)
        .any(haystackTokens.where(_isAddressNumberToken).contains);
    if (!numberMatched) {
      return false;
    }
    final significantQueryTokens = queryTokens
        .where(
          (token) =>
              !_isAddressNumberToken(token) &&
              !_addressNoiseTokens.contains(token),
        )
        .toList();
    if (significantQueryTokens.isEmpty) {
      return false;
    }
    return significantQueryTokens.every((queryToken) {
      for (final houseToken in haystackTokens.where(
        (token) =>
            !_isAddressNumberToken(token) &&
            !_addressNoiseTokens.contains(token),
      )) {
        final maxDistance = queryToken.length <= 4 || houseToken.length <= 4
            ? 1
            : 2;
        if (_tokenLooksLikePart(queryToken, houseToken, maxDistance)) {
          return true;
        }
      }
      return false;
    });
  }
}

class _ProfileMetricCard extends StatelessWidget {
  const _ProfileMetricCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ProfileScreen._orange),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: ProfileScreen._muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 18 / 13,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProfileScreen._foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 22 / 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
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
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ProfileScreen._border),
      ),
      child: child,
    );
  }
}

class _AddressRequiredBanner extends StatelessWidget {
  const _AddressRequiredBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF5C6A6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined, color: ProfileScreen._orange),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Заполните адрес'.tr(),
                      style: TextStyle(
                        color: ProfileScreen._foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'После входа нужно выбрать подключенный дом и параметры квартиры, чтобы заказать уборку.'
                          .tr(),
                      style: TextStyle(
                        color: ProfileScreen._muted,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.chevron_right, color: ProfileScreen._orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileActionBanner extends StatelessWidget {
  const _ProfileActionBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ProfileScreen._border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEFE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: ProfileScreen._orange, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfileScreen._foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 20 / 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfileScreen._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: ProfileScreen._orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequiredProfileTile extends StatelessWidget {
  const _RequiredProfileTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ProfileScreen._soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfileScreen._foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 19 / 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfileScreen._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                '›',
                style: TextStyle(
                  color: ProfileScreen._muted,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
