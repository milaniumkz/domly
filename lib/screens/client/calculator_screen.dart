import 'dart:async';

// ignore_for_file: unused_element

import 'package:flutter/material.dart';

import '../../app/auth_gate.dart';
import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/payment_link_service.dart';
import '../../ui/domly_ui.dart';
import '../../ui/info_dialog.dart';
import '../../utils/package_catalog_utils.dart';
import '../common/kaspi_invoice_request_dialog.dart';
import 'payment_history_screen.dart';
import '../../localization/translation_controller.dart';

class _AddonItemDef {
  const _AddonItemDef({
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

class _AddonGroupDef {
  const _AddonGroupDef({
    required this.key,
    required this.label,
    required this.items,
    this.note,
  });

  final String key;
  final String label;
  final List<_AddonItemDef> items;
  final String? note;
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _data = FirestoreDataService.instance;
  final _configService = AppConfigService.instance;
  static const double _addonControlWidth = 124;

  Future<void> _showSubmissionDialog({
    required String title,
    required String message,
    bool openPaymentHistoryAction = false,
    bool openOrdersOnClose = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: DomlyColors.foreground,
                height: 1.4,
              ),
            ),
            if (openOrdersOnClose) ...[
              const SizedBox(height: 20),
              DomlyPrimaryButton(
                label: 'Открыть заказ',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/client/orders',
                    (_) => false,
                    arguments: {'initialTab': 'active'},
                  );
                },
              ),
            ],
            if (openPaymentHistoryAction) ...[
              const SizedBox(height: 12),
              DomlySecondaryButton(
                label: 'Открыть историю оплат',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PaymentHistoryScreen(),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            DomlySecondaryButton(
              label: openPaymentHistoryAction ? 'Понятно' : 'Ок',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
        actionsPadding: EdgeInsets.zero,
        actions: const [
          SizedBox.shrink(),
        ],
      ),
    );
  }

  static const _fallbackAddonUnitPrices = <String, int>{
    'window_standard': 3000,
    'window_panorama': 5500,
    'window_mosquito': 1200,
    'balcony_window_standard': 3000,
    'balcony_panorama': 5500,
    'balcony_balcony': 2500,
    'balcony_loggia': 2500,
    'balcony_terrace': 5000,
    'kitchen_oven': 2500,
    'kitchen_hood': 2200,
    'kitchen_fridge': 2500,
    'kitchen_facades': 3000,
    'kitchen_full_set': 6500,
    'kitchen_stove': 1800,
    'kitchen_microwave': 1200,
    'kitchen_apron': 1500,
    'kitchen_dishes_hand': 2500,
    'kitchen_dishwasher_loading': 800,
    'bath_tile_walls': 3000,
    'bath_glass_walls': 2800,
    'bath_washer_wipe': 900,
    'textile_bed_linen_ironing': 1800,
    'textile_clothes_ironing': 1800,
    'textile_curtains_ironing': 3500,
    'textile_bed_change': 1500,
    'hard_chandelier_standard': 2500,
    'hard_chandelier_complex': 4500,
    'hard_chandelier_super': 7000,
    'hard_lamps': 1200,
    'hard_upper_shelves': 1800,
    'hard_baseboards': 1400,
    'hard_doors': 900,
    'hard_cobweb': 1600,
    'furniture_sofa': 9000,
    'furniture_mattress': 7000,
    'carpet_cleaning': 0,
  };
  static const _fallbackAddonGroups = <_AddonGroupDef>[
    _AddonGroupDef(
      key: 'windows',
      label: 'Окна и стекла',
      items: [
        _AddonItemDef(
            key: 'window_standard',
            label: 'Мытье окон стандарт',
            supportsQuantity: true),
        _AddonItemDef(
            key: 'window_panorama', label: 'Панорама', supportsQuantity: true),
        _AddonItemDef(
            key: 'window_mosquito',
            label: 'Мытье москитных сеток',
            supportsQuantity: true),
      ],
    ),
    _AddonGroupDef(
      key: 'balcony',
      label: 'Балкон',
      items: [
        _AddonItemDef(
            key: 'balcony_window_standard',
            label: 'Мытье окон стандарт',
            supportsQuantity: true),
        _AddonItemDef(
            key: 'balcony_panorama', label: 'Панорама', supportsQuantity: true),
        _AddonItemDef(
            key: 'balcony_balcony', label: 'Балкон', supportsQuantity: true),
        _AddonItemDef(
            key: 'balcony_loggia', label: 'Лоджия', supportsQuantity: true),
        _AddonItemDef(
            key: 'balcony_terrace', label: 'Терасса', supportsQuantity: true),
      ],
    ),
    _AddonGroupDef(
      key: 'kitchen',
      label: 'Кухня',
      items: [
        _AddonItemDef(key: 'kitchen_oven', label: 'Чистка духовки внутри'),
        _AddonItemDef(key: 'kitchen_hood', label: 'Чистка вытяжки и фильтров'),
        _AddonItemDef(
            key: 'kitchen_fridge', label: 'Мытье холодильника внутри'),
        _AddonItemDef(
            key: 'kitchen_facades', label: 'Мытье фасадов кухонного гарнитура'),
        _AddonItemDef(
            key: 'kitchen_full_set',
            label: 'Полное мытье кухонного гарнитура',
            note: 'Внутри и снаружи'),
        _AddonItemDef(
            key: 'kitchen_stove', label: 'Чистка плит и варочных панелей'),
        _AddonItemDef(key: 'kitchen_microwave', label: 'Чистка микроволновки'),
        _AddonItemDef(key: 'kitchen_apron', label: 'Мытье фартука'),
        _AddonItemDef(
            key: 'kitchen_dishes_hand', label: 'Мытье посуды вручную'),
        _AddonItemDef(
            key: 'kitchen_dishwasher_loading',
            label: 'Загрузка посуды в посудомойку'),
      ],
    ),
    _AddonGroupDef(
      key: 'bathroom',
      label: 'Санузлы',
      items: [
        _AddonItemDef(key: 'bath_tile_walls', label: 'Стены кафель'),
        _AddonItemDef(
            key: 'bath_glass_walls', label: 'Стеклянные стены душа и ванны'),
        _AddonItemDef(
            key: 'bath_washer_wipe', label: 'Протирка стиральной машины'),
      ],
    ),
    _AddonGroupDef(
      key: 'textile',
      label: 'Комфорт и текстиль',
      items: [
        _AddonItemDef(
            key: 'textile_bed_linen_ironing',
            label: 'Глажка постельного белья'),
        _AddonItemDef(key: 'textile_clothes_ironing', label: 'Глажка одежды'),
        _AddonItemDef(key: 'textile_curtains_ironing', label: 'Глажка штор'),
        _AddonItemDef(
            key: 'textile_bed_change',
            label: 'Замена постельного белья и заправка кроватей'),
      ],
    ),
    _AddonGroupDef(
      key: 'hard',
      label: 'Труднодоступные зоны',
      items: [
        _AddonItemDef(
            key: 'hard_chandelier_standard',
            label: 'Чистка люстр стандартная',
            supportsQuantity: true),
        _AddonItemDef(
            key: 'hard_chandelier_complex',
            label: 'Чистка люстр сложная',
            supportsQuantity: true),
        _AddonItemDef(
            key: 'hard_chandelier_super',
            label: 'Чистка люстр супер сложная',
            supportsQuantity: true),
        _AddonItemDef(
            key: 'hard_lamps',
            label: 'Светильники и плафоны',
            supportsQuantity: true),
        _AddonItemDef(
            key: 'hard_upper_shelves',
            label: 'Чистка верхних полок, антресолей и шкафов',
            supportsQuantity: true),
        _AddonItemDef(key: 'hard_baseboards', label: 'Чистка плинтусов'),
        _AddonItemDef(
            key: 'hard_doors', label: 'Мытье дверей', supportsQuantity: true),
        _AddonItemDef(
            key: 'hard_cobweb',
            label: 'Удаление паутины и пыли в труднодоступных местах'),
      ],
    ),
    _AddonGroupDef(
      key: 'furniture',
      label: 'Мебель и поверхности',
      items: [
        _AddonItemDef(
          key: 'furniture_sofa',
          label: 'Химчистка диванов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
        _AddonItemDef(
          key: 'furniture_mattress',
          label: 'Химчистка матрасов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
      ],
    ),
    _AddonGroupDef(
      key: 'carpet',
      label: 'Химчистка ковров и паласов',
      note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
      items: [
        _AddonItemDef(
          key: 'carpet_cleaning',
          label: 'Химчистка ковров и паласов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
      ],
    ),
  ];

  static const _defaultPackages = <Map<String, dynamic>>[
    {
      'id': 'single',
      'name': 'Разовый пакет',
      'frequency': 1,
      'label': 'Разовый пакет',
      'discount': 0.0
    },
    {
      'id': 'twice',
      'name': 'Два раза в месяц',
      'frequency': 2,
      'label': '2 раза в месяц',
      'discount': 0.0
    },
    {
      'id': 'four',
      'name': '4 раза в месяц',
      'frequency': 4,
      'label': '4 раза в месяц',
      'discount': 0.0
    },
    {
      'id': 'eight',
      'name': '8 раз в месяц',
      'frequency': 8,
      'label': '8 раз в месяц',
      'discount': 0.0
    },
    {
      'id': 'quarterly',
      'name': 'Квартальный пакет',
      'frequency': 0,
      'label': 'Квартальный пакет',
      'discount': 0.10,
      'isQuarterly': true
    },
    {
      'id': 'general',
      'name': 'Генеральная уборка',
      'frequency': 1,
      'label': 'Генеральная',
      'discount': 0.0,
      'isSpecial': true
    },
    {
      'id': 'renovation',
      'name': 'Уборка после ремонта',
      'frequency': 1,
      'label': 'Уборка после ремонта',
      'discount': 0.0,
      'isSpecial': true
    },
  ];

  StreamSubscription<List<Map<String, dynamic>>>? _packagesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _addonCatalogSubscription;

  double _area = 0;
  String? _selectedPackageId;
  int _quarterlyVisitsPerMonth = 2;
  List<Map<String, dynamic>> _remotePackages = const [];
  final Map<String, int> _addonUnitPrices = Map<String, int>.from(
    _fallbackAddonUnitPrices,
  );
  List<_AddonGroupDef> _addonGroups = List<_AddonGroupDef>.from(
    _fallbackAddonGroups,
  );
  final Set<String> _expandedAddonGroups = <String>{};
  final Map<String, int> _addonQuantities = <String, int>{};
  bool _loadingQuote = false;
  bool _submittingOrder = false;
  int _quoteRequestId = 0;
  Map<String, dynamic> _quote = const {
    'perCleaningPrice': 0,
    'monthlyPrice': 0,
    'subtotal': 0,
    'discountRate': 0.0,
    'discountAmount': 0,
    'cleaningCount': 1,
  };

  List<Map<String, dynamic>> get _packages {
    final merged = _remotePackages.isNotEmpty
        ? _remotePackages.map(_normalizeRemotePackage).toList()
        : _defaultPackages
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    merged.sort((a, b) {
      final aOrder =
          PackageCatalogUtils.numValue(a['sortOrder'])?.toInt() ?? 999;
      final bOrder =
          PackageCatalogUtils.numValue(b['sortOrder'])?.toInt() ?? 999;
      return aOrder.compareTo(bOrder);
    });
    return merged;
  }

  Map<String, dynamic> _normalizeRemotePackage(Map<String, dynamic> remote) {
    final remoteId = (remote['id'] ?? '').toString();
    final mappedId = switch (remoteId) {
      'basic' => 'twice',
      'standard' => 'four',
      'premium' => 'eight',
      'quarter' => 'quarterly',
      'general_cleaning' => 'general',
      'post_renovation' => 'renovation',
      _ => remoteId,
    };
    return {
      ...remote,
      'id': mappedId,
      'label': remote['label'] ?? remote['name'] ?? remote['frequency'],
      'sortOrder': remote['sortOrder'] ?? 999,
      'isSpecial':
          remoteId == 'general_cleaning' || remoteId == 'post_renovation',
    };
  }

  Map<String, dynamic>? get _selectedPackage {
    if (_selectedPackageId == null) return null;
    return _packages.firstWhere(
      (p) => p['id'] == _selectedPackageId,
      orElse: () =>
          _packages.isNotEmpty ? _packages.first : _defaultPackages.first,
    );
  }

  int get _displayQuoteTotal => (_quote['monthlyPrice'] as num?)?.toInt() ?? 0;

  String get _displayQuoteCaption {
    final pkg = _selectedPackage;
    if (PackageCatalogUtils.isQuarterlyPackage(pkg)) {
      return 'Итого за $_billingPeriodMonths месяца';
    }
    if (PackageCatalogUtils.isSpecialPackage(pkg)) {
      return 'Итого к оплате';
    }
    if (_selectedFrequency <= 1) {
      return 'Итого за уборку';
    }
    return 'Итого за месяц';
  }

  String? get _displayQuoteDetails {
    final pkg = _selectedPackage;
    if (pkg == null) {
      return null;
    }
    final perCleaningPrice = (_quote['perCleaningPrice'] as num?)?.toInt() ?? 0;
    final cleaningCount = (_quote['cleaningCount'] as num?)?.toInt() ?? 0;
    final discountAmount = (_quote['discountAmount'] as num?)?.toInt() ?? 0;
    final addonTotal = (_quote['addonTotalPrice'] as num?)?.toInt() ?? 0;
    if (PackageCatalogUtils.isSpecialPackage(pkg)) {
      return addonTotal > 0
          ? '${_formatMoney(perCleaningPrice - addonTotal)} + доп. услуги ${_formatMoney(addonTotal)}'
          : 'Стоимость по выбранному пакету';
    }
    final parts = <String>[
      '${_formatMoney(perCleaningPrice)} за 1 уборку',
      '$cleaningCount ${_cleaningsWord(cleaningCount)}',
    ];
    if (addonTotal > 0) {
      parts.add('доп. услуги ${_formatMoney(addonTotal)}');
    }
    if (discountAmount > 0) {
      parts.add('скидка ${_formatMoney(discountAmount)}');
    }
    return parts.join(' • ');
  }

  String _cleaningsWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) {
      return 'уборка';
    }
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'уборки';
    }
    return 'уборок';
  }

  Future<void> _selectQuarterlyVisits() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          'Квартальный пакет'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Выберите количество уборок в месяц:'.tr(),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: DomlyColors.foreground,
              ),
            ),
            const SizedBox(height: 12),
            ...[2, 4, 8].map(
              (value) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '$value уборки в месяц'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DomlyColors.foreground,
                  ),
                ),
                trailing: value == _quarterlyVisitsPerMonth
                    ? const Icon(Icons.check, color: DomlyColors.buttonPrimary)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _quarterlyVisitsPerMonth = selected);
      _refreshQuote();
    }
  }

  int get _selectedFrequency {
    final pkg = _selectedPackage;
    return PackageCatalogUtils.cleaningsPerMonth(
      pkg,
      quarterlyVisitsPerMonth: _quarterlyVisitsPerMonth,
    );
  }

  int get _billingPeriodMonths {
    final pkg = _selectedPackage;
    return PackageCatalogUtils.billingPeriodMonths(pkg);
  }

  @override
  void initState() {
    super.initState();
    _selectedPackageId = 'single';
    _packagesSubscription = _data.customerPackagesStream().listen((items) {
      if (!mounted) return;
      setState(() {
        _remotePackages = items;
        final availableIds = _packages
            .map((package) => (package['id'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        if (!availableIds.contains(_selectedPackageId) &&
            availableIds.isNotEmpty) {
          _selectedPackageId = availableIds.first;
        }
      });
      _refreshQuote();
    });
    _addonCatalogSubscription =
        _configService.addonGroupConfigsStream().listen((groups) {
      if (!mounted) return;
      setState(() {
        _addonGroups = _mapAddonGroupConfigs(groups);
      });
      _refreshQuote();
    });
    _refreshQuote();
  }

  Future<void> _showAddonInfo(
    String addonKey, {
    String? title,
    String? shortInfo,
    String? fullInfo,
    List<String>? features,
  }) async {
    final infoConfig = await _configService.getInfoContent(addonKey);
    if (!mounted) {
      return;
    }
    if (infoConfig != null && infoConfig.isNotEmpty) {
      await InfoDialog.showFromConfig(context, config: infoConfig);
    } else {
      // Fallback
      final unitPrice = _unitPriceFor(addonKey);
      await InfoDialog.showFromConfig(context, config: {
        'title': title ?? addonKey.replaceAll('_', ' '),
        'shortInfo': shortInfo ?? 'Дополнительная услуга',
        'description': shortInfo ?? 'Дополнительная услуга',
        'fullInfo': fullInfo ?? '',
        'longDescription': fullInfo ?? '',
        'features': features ?? const <String>[],
        'price': unitPrice,
      });
    }
  }

  @override
  void dispose() {
    _packagesSubscription?.cancel();
    _addonCatalogSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.customerProfileStream(),
      builder: (context, profileSnap) {
        final profile = profileSnap.data ?? const <String, dynamic>{};
        _syncAreaFromProfile(profile);
        final hasProfileArea = _area > 0;
        final addonTotalPrice =
            (_quote['addonTotalPrice'] as num?)?.toInt() ?? 0;
        final quoteTotal = _displayQuoteTotal;

        return DomlyShell(
          bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 0),
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FigmaCalculatorHeader(),
                  const SizedBox(height: 16),
                  _FigmaAreaCard(
                    area: hasProfileArea ? _area : null,
                    onFillProfile: () =>
                        Navigator.pushNamed(context, '/client/profile'),
                  ),
                  const SizedBox(height: 13),
                  _FigmaPackageCard(
                    packages: _packages,
                    buildPackage: (package) => Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _packageButton(
                        pkgId: (package['id'] ?? '').toString(),
                        label: (package['label'] ?? package['name'] ?? '')
                            .toString(),
                        name: (package['name'] ?? package['label'] ?? 'Пакет')
                            .toString(),
                        selected: (package['id'] ?? '').toString() ==
                            _selectedPackageId,
                        discount: PackageCatalogUtils.discountRate(package),
                        isQuarterly:
                            PackageCatalogUtils.isQuarterlyPackage(package),
                        isSpecial:
                            PackageCatalogUtils.isSpecialPackage(package),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  _FigmaAddonCard(
                    groups: _addonGroups,
                    total: quoteTotal > 0 ? quoteTotal : addonTotalPrice,
                    caption: _displayQuoteCaption,
                    details: _displayQuoteDetails,
                    loading: _loadingQuote,
                    buildGroup: _buildFigmaAddonGroup,
                  ),
                  const SizedBox(height: 29),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _loadingQuote ||
                                _submittingOrder ||
                                !hasProfileArea ||
                                quoteTotal <= 0 ||
                                _selectedPackage == null
                            ? null
                            : () => _handleBuy(
                                  quoteTotal,
                                  bonusToSpend: 0,
                                  profile: profile,
                                ),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFFC96A4A),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.25),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 18 / 14,
                          ),
                        ),
                        child: Text(
                          _submittingOrder
                              ? 'Оформляем...'
                              : 'Заказать и оплатить',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 25),
                    child: Text(
                      hasProfileArea
                          ? '${_area.ceil()} м²'
                          : 'Заполните площадь в профиле',
                      style: const TextStyle(
                        color: Color(0xFF658170),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 16 / 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _syncAreaFromProfile(Map<String, dynamic> profile) {
    final parsed = _profileArea(profile);
    if (parsed == null || parsed <= 0 || (_area - parsed).abs() < 0.01) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (_area - parsed).abs() < 0.01) {
        return;
      }
      setState(() => _area = parsed);
      _refreshQuote();
    });
  }

  double? _profileArea(Map<String, dynamic> profile) {
    for (final key in const ['confirmedArea', 'apartmentArea', 'area']) {
      final value = profile[key];
      if (value is num && value > 0) {
        return value.toDouble();
      }
      final parsed = double.tryParse(
        (value ?? '').toString().trim().replaceAll(',', '.'),
      );
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  Widget _buildFigmaAddonGroup(_AddonGroupDef group) {
    final expanded = _expandedAddonGroups.contains(group.key);
    final selectedCount = _selectedCountForGroup(group);
    final hasNote = (group.note ?? '').trim().isNotEmpty;
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
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedAddonGroups.remove(group.key);
                } else {
                  _expandedAddonGroups.add(group.key);
                }
              });
            },
            child: SizedBox(
              height: hasNote ? 82 : 44,
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, hasNote ? 11 : 0, 12, 0),
                child: Row(
                  crossAxisAlignment: hasNote
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: hasNote
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.label,
                            maxLines: hasNote ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2B4338),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 20 / 15,
                            ),
                          ),
                          if (hasNote) ...[
                            const SizedBox(height: 7),
                            Text(
                              group.note!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF658170),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 17 / 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selectedCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        height: 22,
                        constraints: const BoxConstraints(minWidth: 22),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFEEB09B).withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$selectedCount',
                          style: const TextStyle(
                            color: Color(0xFF2B4338),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: const Color(0xFF658170),
                      size: 24,
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
                      (item) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _buildFigmaAddonItem(item),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFigmaAddonItem(_AddonItemDef item) {
    final quantity = _addonQuantities[item.key] ?? 0;
    final unitPrice = _unitPriceFor(item.key);
    final isSeparate = item.separatePayment || item.key == 'carpet_cleaning';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Material(
              color: const Color(0xFFF0F7F2),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _showAddonInfo(
                  item.key,
                  title: item.label,
                  shortInfo: item.infoText,
                  fullInfo: item.fullInfo,
                  features: item.features,
                ),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Color(0xFFCF7548),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 18 / 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isSeparate
                      ? 'Оплачивается отдельно при оценке специалиста'
                      : item.supportsQuantity
                          ? '${_formatMoney(unitPrice)} за 1 шт.'
                          : _formatMoney(unitPrice),
                  style: TextStyle(
                    color: isSeparate
                        ? const Color(0xFFC96A4A)
                        : const Color(0xFF658170),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 14 / 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.supportsQuantity)
            _FigmaQuantityStepper(
              quantity: quantity,
              onMinus: quantity <= 0
                  ? null
                  : () => _changeAddonQuantity(item.key, quantity - 1),
              onPlus: () => _changeAddonQuantity(item.key, quantity + 1),
            )
          else
            GestureDetector(
              onTap: () => _changeAddonQuantity(item.key, quantity > 0 ? 0 : 1),
              child: Container(
                width: 86,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: quantity > 0
                      ? const Color(0xFFC96A4A)
                      : const Color(0xFFF0F7F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  quantity > 0 ? 'Убрать' : 'Добавить',
                  style: TextStyle(
                    color:
                        quantity > 0 ? Colors.white : const Color(0xFF2B4338),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _packageButton({
    required String pkgId,
    required String label,
    required String name,
    required bool selected,
    required double discount,
    bool isQuarterly = false,
    bool isSpecial = false,
  }) {
    return GestureDetector(
      onTap: () async {
        setState(() {
          _selectedPackageId = pkgId;
        });
        if (isQuarterly) {
          await _selectQuarterlyVisits();
          if (!mounted) {
            return;
          }
        }
        _refreshQuote();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? DomlyColors.primary.withValues(alpha: 0.08)
              : DomlyColors.backgroundSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? DomlyColors.primary : DomlyColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? DomlyColors.primary
                                : DomlyColors.foreground,
                          ),
                        ),
                      ),
                      if (isSpecial) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: DomlyColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Спец.'.tr(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: DomlyColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    isQuarterly
                        ? 'Скидка 10% от суммы за 3 месяца'
                        : isSpecial
                            ? 'Стоимость рассчитывается после площади'
                            : 'Стоимость = цена за уборку × количество уборок',
                    style: const TextStyle(
                        fontSize: 11, color: DomlyColors.foreground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? DomlyColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? DomlyColors.primary : DomlyColors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddonGroup(_AddonGroupDef group) {
    final expanded = _expandedAddonGroups.contains(group.key);
    final selectedCount = _selectedCountForGroup(group);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedAddonGroups.remove(group.key);
                } else {
                  _expandedAddonGroups.add(group.key);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        if (group.note != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            group.note!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DomlyColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selectedCount > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            DomlyColors.buttonPrimary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DomlyColors.foreground,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: DomlyColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: group.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildAddonItem(item),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddonItem(_AddonItemDef item) {
    final quantity = _addonQuantities[item.key] ?? 0;
    final unitPrice = _unitPriceFor(item.key);
    final isSeparate = item.separatePayment || item.key == 'carpet_cleaning';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DomlyColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            child: Material(
              color: DomlyColors.backgroundSoft,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _showAddonInfo(
                  item.key,
                  title: item.label,
                  shortInfo: item.infoText,
                  fullInfo: item.fullInfo,
                  features: item.features,
                ),
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
                    fontWeight: FontWeight.w600,
                    color: DomlyColors.foreground,
                  ),
                ),
                if (item.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.note!,
                    style:
                        const TextStyle(fontSize: 12, color: DomlyColors.muted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  isSeparate
                      ? 'Оплачивается отдельно при оценке специалиста'
                      : item.supportsQuantity
                          ? '${_formatMoney(unitPrice)} за 1 шт.'
                          : _formatMoney(unitPrice),
                  style: TextStyle(
                    fontSize: 12,
                    color: isSeparate ? DomlyColors.primary : DomlyColors.muted,
                    fontWeight: isSeparate ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (item.supportsQuantity)
            _quantityStepper(
              quantity: quantity,
              onMinus: quantity <= 0
                  ? null
                  : () => _changeAddonQuantity(item.key, quantity - 1),
              onPlus: () => _changeAddonQuantity(item.key, quantity + 1),
            )
          else
            SizedBox(
              width: _addonControlWidth,
              child: DomlySecondaryButton(
                onPressed: () =>
                    _changeAddonQuantity(item.key, quantity > 0 ? 0 : 1),
                foregroundColor:
                    quantity > 0 ? DomlyColors.primary : DomlyColors.foreground,
                label: quantity > 0 ? 'Убрать' : 'Добавить',
              ),
            ),
        ],
      ),
    );
  }

  Widget _quantityStepper({
    required int quantity,
    required VoidCallback? onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      width: _addonControlWidth,
      height: 42,
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedAddonsBlock({
    required List<Map<String, dynamic>> included,
    required List<Map<String, dynamic>> separate,
    Map<String, dynamic>? selectedPackage,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Вы выбрали'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          // Show selected package
          if (selectedPackage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DomlyColors.buttonPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: DomlyColors.buttonPrimary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedPackage['name']?.toString() ?? 'Пакет',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        if ((_quote['monthlyPrice'] as num?)?.toInt() != null &&
                            ((_quote['monthlyPrice'] as num?)?.toInt() ?? 0) >
                                0)
                          Text(
                            '${(_quote['monthlyPrice'] as num?)?.toInt() ?? 0} ₸',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DomlyColors.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (included.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Доп. услуги (входят в заказ):'.tr(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DomlyColors.foreground,
              ),
            ),
            const SizedBox(height: 6),
            ...included.map((item) {
              final label = item['label']?.toString() ?? '';
              final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
              final key = item['key']?.toString() ?? '';
              final unitPrice = _unitPriceFor(key);
              final total = unitPrice * quantity;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  quantity > 1
                      ? '• $label × $quantity — $total ₸'
                      : '• $label — $total ₸',
                  style: const TextStyle(
                      fontSize: 13, color: DomlyColors.foreground),
                ),
              );
            }).toList(),
          ],
          if (separate.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Оплачивается отдельно:'.tr(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DomlyColors.danger,
              ),
            ),
            const SizedBox(height: 6),
            ...separate.map((item) {
              final label = item['label']?.toString() ?? '';
              final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  quantity > 1 ? '• $label × $quantity' : '• $label',
                  style: const TextStyle(
                    fontSize: 13,
                    color: DomlyColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ],
          if (selectedPackage == null && included.isEmpty && separate.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Выберите пакет или дополнительные услуги'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  color: DomlyColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _selectedAddonsDetailed() {
    final labels = <String, String>{};
    final separateKeys = <String>{};
    final durations = <String, int>{};
    for (final group in _addonGroups) {
      for (final item in group.items) {
        labels[item.key] = item.label;
        durations[item.key] = item.durationMinutes;
        if (item.separatePayment || item.key == 'carpet_cleaning') {
          separateKeys.add(item.key);
        }
      }
    }
    return _addonQuantities.entries
        .where((entry) => entry.value > 0)
        .map((entry) => <String, dynamic>{
              'key': entry.key,
              'label': labels[entry.key] ?? entry.key,
              'quantity': entry.value,
              'separate': separateKeys.contains(entry.key),
              'durationMinutes': (durations[entry.key] ?? 15) * entry.value,
            })
        .toList();
  }

  int _selectedCountForGroup(_AddonGroupDef group) {
    var total = 0;
    for (final item in group.items) {
      total += _addonQuantities[item.key] ?? 0;
    }
    return total;
  }

  int _localBillableAddonTotal() {
    var total = 0;
    for (final item in _selectedAddonsDetailed()) {
      if (item['separate'] == true) {
        continue;
      }
      final key = item['key']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      total += _unitPriceFor(key) * quantity;
    }
    return total;
  }

  int _unitPriceFor(String addonKey) => _addonUnitPrices[addonKey] ?? 0;

  List<_AddonGroupDef> _mapAddonGroupConfigs(
      List<Map<String, dynamic>> groups) {
    if (groups.isEmpty) {
      return List<_AddonGroupDef>.from(_fallbackAddonGroups);
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
                }
                return _AddonItemDef(
                  key: key,
                  label: (item['label'] ?? key).toString(),
                  supportsQuantity: item['supportsQuantity'] == true,
                  note: (item['note'] ?? '').toString().trim().isEmpty
                      ? null
                      : (item['note'] ?? '').toString(),
                  shortInfo: (item['shortInfo'] ?? item['description'] ?? '')
                          .toString()
                          .trim()
                          .isEmpty
                      ? null
                      : (item['shortInfo'] ?? item['description']).toString(),
                  fullInfo: (item['fullInfo'] ?? item['longDescription'] ?? '')
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
                  separatePayment: item['separatePayment'] == true,
                  durationMinutes:
                      (item['durationMinutes'] as num?)?.toInt() ?? 15,
                );
              })
              .where((item) => item.key.isNotEmpty)
              .toList();

          return _AddonGroupDef(
            key: (group['key'] ?? group['id'] ?? '').toString(),
            label: (group['label'] ?? group['key'] ?? 'Группа').toString(),
            note: (group['note'] ?? '').toString().trim().isEmpty
                ? null
                : (group['note'] ?? '').toString(),
            items: items,
          );
        })
        .where((group) => group.key.isNotEmpty && group.items.isNotEmpty)
        .toList();

    return mapped.isEmpty
        ? List<_AddonGroupDef>.from(_fallbackAddonGroups)
        : mapped;
  }

  Map<String, dynamic> _buildLocalRegularQuote({
    required int cleaningCount,
    required int addonTotal,
    required double discountRate,
  }) {
    final packageAreaRate =
        PackageCatalogUtils.numValue(_selectedPackage?['price'])?.toInt() ?? 0;
    final basePerCleaning = packageAreaRate > 0
        ? (packageAreaRate * _area.ceil()).round()
        : (_area.ceil() * 120).round();
    final packageSubtotal = basePerCleaning * cleaningCount;
    final discountAmount = (packageSubtotal * discountRate).round();
    final subtotal = packageSubtotal + addonTotal;
    return <String, dynamic>{
      'perCleaningPrice': basePerCleaning,
      'monthlyPrice': subtotal - discountAmount,
      'subtotal': subtotal,
      'discountRate': discountRate,
      'discountAmount': discountAmount,
      'cleaningCount': cleaningCount,
      'billingPeriodMonths': _billingPeriodMonths,
      'addonTotalPrice': addonTotal,
      'addonsBillableTotal': addonTotal,
      'addonsSeparatePaymentTotal': 0,
      'separatePaymentAddons': const <Map<String, dynamic>>[],
    };
  }

  void _changeAddonQuantity(String key, int nextQuantity) {
    setState(() {
      if (nextQuantity <= 0) {
        _addonQuantities.remove(key);
      } else {
        _addonQuantities[key] = nextQuantity;
      }
    });
    _refreshQuote();
  }

  Future<void> _refreshQuote() async {
    final requestId = ++_quoteRequestId;
    final pkg = _selectedPackage;
    if (_area <= 0) {
      if (!mounted) return;
      setState(() {
        _quote = const {
          'perCleaningPrice': 0,
          'monthlyPrice': 0,
          'subtotal': 0,
          'discountRate': 0.0,
          'discountAmount': 0,
          'cleaningCount': 1,
        };
        _loadingQuote = false;
      });
      return;
    }
    final frequency = _selectedFrequency;
    final freq = frequency > 0 ? frequency : 2;
    final cleaningCount = _billingPeriodMonths == 3 ? freq * 3 : freq;
    final discountRate = PackageCatalogUtils.discountRate(pkg);
    final localAddonTotal = _localBillableAddonTotal();
    try {
      final isSpecial = PackageCatalogUtils.isSpecialPackage(pkg);

      if (isSpecial) {
        final pkgId = (pkg?['id'] ?? '').toString();
        final basePrice =
            PackageCatalogUtils.numValue(pkg?['price'])?.toInt() ??
                (pkgId == 'renovation' ? 60000 : 45000);
        final addonTotal = _localBillableAddonTotal();
        final specialQuote = <String, dynamic>{
          'perCleaningPrice': basePrice + addonTotal,
          'monthlyPrice': basePrice + addonTotal,
          'subtotal': basePrice + addonTotal,
          'discountRate': 0.0,
          'discountAmount': 0,
          'cleaningCount': 1,
          'billingPeriodMonths': 1,
          'addonTotalPrice': addonTotal,
          'addonsBillableTotal': addonTotal,
          'addonsSeparatePaymentTotal': 0,
          'separatePaymentAddons': const <Map<String, dynamic>>[],
        };
        setState(() {
          _quote = specialQuote;
          _loadingQuote = false;
        });
        return;
      }

      if (mounted) {
        setState(() {
          _quote = _buildLocalRegularQuote(
            cleaningCount: cleaningCount,
            addonTotal: localAddonTotal,
            discountRate: discountRate,
          );
          _loadingQuote = false;
        });
      }

      final quote = _buildLocalRegularQuote(
        cleaningCount: cleaningCount,
        addonTotal: localAddonTotal,
        discountRate: discountRate,
      );
      if (!mounted || requestId != _quoteRequestId) return;
      setState(() => _quote = quote);
    } catch (_) {
      if (!mounted || requestId != _quoteRequestId) return;
      setState(() {
        _quote = _buildLocalRegularQuote(
          cleaningCount: cleaningCount,
          addonTotal: localAddonTotal,
          discountRate: discountRate,
        );
        _loadingQuote = false;
      });
    }
  }

  String _formatMoney(int value) => '$value ₸';

  Future<void> _handleBuy(
    int total, {
    required int bonusToSpend,
    required Map<String, dynamic> profile,
  }) async {
    if (_submittingOrder) return;
    final authorized = await AuthGate.ensureAuthorized(context);
    if (!mounted || !authorized) return;

    final pkg = _selectedPackage;
    final packageName = pkg?['name'] ?? 'Индивидуальный';
    if (!mounted) return;

    setState(() => _submittingOrder = true);
    try {
      final paymentSelection = await showPaymentMethodOptionsDialog(
        context,
        bonusBalance: 0,
        maxBonusToSpend: 0,
      );
      if (!mounted || paymentSelection == null) return;
      final paymentMethod = paymentSelection.method;
      const selectedBonusToSpend = 0;
      String? kaspiPhone;
      if (paymentMethod == DomlyPaymentMethod.kaspi) {
        kaspiPhone = await showKaspiInvoiceRequestDialog(context);
      }
      if (!mounted ||
          (paymentMethod == DomlyPaymentMethod.kaspi && kaspiPhone == null)) {
        return;
      }

      final created = await PaymentLinkService.runBlocking(
        context,
        task: () => _data.createOrderAndInvoice(
          amount: total,
          customerId: _data.currentUserId,
          packageName: packageName,
          packageId: pkg?['id']?.toString(),
          pricingMode: 'custom_quote',
          cleaningsPerMonth: _selectedFrequency,
          accessMethod: 'Я дома',
          addons: _selectedAddonLabels(),
          addonsDetailed: _selectedAddonsDetailed(),
          frequencyLabel: PackageCatalogUtils.frequencyLabel(
            pkg,
            quarterlyVisitsPerMonth: _quarterlyVisitsPerMonth,
          ),
          rooms: 0,
          bathrooms: 0,
          area: _area.ceil(),
          address: (profile['address'] ?? '').toString(),
          residentialComplex: (profile['residentialComplex'] ?? '').toString(),
          entrance: (profile['entrance'] ?? '').toString(),
          apartment: (profile['apartment'] ?? '').toString(),
          houseId: (profile['houseId'] ?? '').toString(),
          billingPeriodMonths: _billingPeriodMonths,
          bonusToSpend: selectedBonusToSpend,
        ),
        message: 'Создаем заявку на оплату...',
      );
      final createdLocally = created['localFallback'] == true;

      final orderId = created['orderId']?.toString();

      if (orderId != null && orderId.isNotEmpty) {
        if (createdLocally) {
          if (!mounted) return;
          await _showSubmissionDialog(
            title: 'Оформление временно недоступно',
            message:
                'Сервер не принял заявку. Счёт менеджеру не отправлен. Повторите попытку позже.',
          );
          return;
        }
        if (!mounted) return;

        if (paymentMethod == DomlyPaymentMethod.online) {
          final paymentSession = await PaymentLinkService.runBlocking(
            context,
            task: () => _data.createBccPaymentSession(orderId: orderId),
            message: 'Открываем онлайн-оплату...',
          );
          if (!mounted) return;
          Navigator.of(context).pushNamed(
            '/client/online-payment',
            arguments: paymentSession,
          );
          return;
        }

        final invoiceResult = await PaymentLinkService.runBlocking(
          context,
          task: () => _data.submitKaspiInvoiceRequest(
            orderId: orderId,
            kaspiPhone: kaspiPhone!,
          ),
          message: 'Отправляем заявку на счёт...',
        );
        final invoiceSentLocally = invoiceResult['localFallback'] == true;

        if (!mounted) return;
        if (invoiceSentLocally) {
          await _showSubmissionDialog(
            title: 'Оформление временно недоступно',
            message:
                'Сервер не принял заявку на счёт. Оформление не завершено. Повторите попытку позже.',
          );
          return;
        }
        await _showSubmissionDialog(
          title: 'Заявка отправлена',
          message:
              'Менеджер выставит счёт в ближайшее время. После оплаты менеджер подтвердит заказ.',
          openPaymentHistoryAction: true,
          openOrdersOnClose: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось оформить заказ',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _submittingOrder = false);
      }
    }
  }

  List<String> _selectedAddonLabels() {
    return _selectedAddonsDetailed().map((item) {
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final label = item['label']?.toString() ?? '';
      return quantity > 1 ? '$label × $quantity' : label;
    }).toList();
  }
}

class _FigmaCalculatorHeader extends StatelessWidget {
  const _FigmaCalculatorHeader();

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
            top: 23,
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
            top: 21,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Калькулятор'.tr(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Выберите параметры'.tr(),
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

class _FigmaAreaCard extends StatelessWidget {
  const _FigmaAreaCard({
    required this.area,
    required this.onFillProfile,
  });

  final double? area;
  final VoidCallback onFillProfile;

  @override
  Widget build(BuildContext context) {
    final hasArea = area != null && area! > 0;
    return Container(
      height: 144,
      padding: const EdgeInsets.fromLTRB(25, 25, 28, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Площадь квартиры'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 21 / 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Берется из профиля'.tr(),
            style: TextStyle(
              color: Color(0xFF658170),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 16 / 12,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: hasArea ? null : onFillProfile,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasArea ? '${area!.ceil()} м²' : 'Заполните в профиле',
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(
                        color: Color(0xFF2B4338),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 21 / 16,
                      ),
                    ),
                  ),
                  if (!hasArea) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFC96A4A),
                      size: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaPackageCard extends StatelessWidget {
  const _FigmaPackageCard({
    required this.packages,
    required this.buildPackage,
  });

  final List<Map<String, dynamic>> packages;
  final Widget Function(Map<String, dynamic> package) buildPackage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выберите пакет'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 22 / 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Подписка или разовая уборка'.tr(),
            style: TextStyle(
              color: Color(0xFF658170),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 16 / 12,
            ),
          ),
          const SizedBox(height: 10),
          ...packages.map(buildPackage),
        ],
      ),
    );
  }
}

class _FigmaAddonCard extends StatelessWidget {
  const _FigmaAddonCard({
    required this.groups,
    required this.total,
    required this.caption,
    required this.details,
    required this.loading,
    required this.buildGroup,
  });

  final List<_AddonGroupDef> groups;
  final int total;
  final String caption;
  final String? details;
  final bool loading;
  final Widget Function(_AddonGroupDef group) buildGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Дополнительные\nуслуги'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 22 / 20,
            ),
          ),
          const SizedBox(height: 24),
          ...groups.map(buildGroup),
          const SizedBox(height: 4),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: loading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFC96A4A),
                      ),
                    )
                  : Text(
                      '$total ₸',
                      key: ValueKey(total),
                      style: const TextStyle(
                        color: Color(0xFF2B4338),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 26 / 20,
                      ),
                    ),
            ),
          ),
          const Center(
            child: SizedBox.shrink(),
          ),
          Center(
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF658170),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 16 / 12,
              ),
            ),
          ),
          if ((details ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF94AA9D),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 15 / 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FigmaQuantityStepper extends StatelessWidget {
  const _FigmaQuantityStepper({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FigmaStepperButton(
            icon: Icons.remove,
            onTap: onMinus,
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          _FigmaStepperButton(
            icon: Icons.add,
            onTap: onPlus,
          ),
        ],
      ),
    );
  }
}

class _FigmaStepperButton extends StatelessWidget {
  const _FigmaStepperButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 26,
        height: 30,
        child: Icon(
          icon,
          size: 16,
          color:
              onTap == null ? const Color(0x668A8A8A) : const Color(0xFF2B4338),
        ),
      ),
    );
  }
}
