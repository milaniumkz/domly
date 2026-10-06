import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/debug_session.dart';
import '../../app/auth_gate.dart';
import '../../services/app_config_service.dart';
import '../../ui/info_dialog.dart';
import '../common/kaspi_invoice_request_dialog.dart';
import '../../services/firestore_data_service.dart';
import '../../services/payment_link_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/app_logger.dart';
import '../../utils/package_catalog_utils.dart';
import '../../utils/user_error_message.dart';
import 'payment_history_screen.dart';
import 'profile_screen.dart';
import '../../localization/translation_controller.dart';

class PackageSelectionScreen extends StatefulWidget {
  const PackageSelectionScreen({super.key});

  @override
  State<PackageSelectionScreen> createState() => _PackageSelectionScreenState();
}

class _PackageSelectionScreenState extends State<PackageSelectionScreen> {
  final _data = FirestoreDataService.instance;
  final _configService = AppConfigService.instance;
  late final Stream<Map<String, dynamic>?> _profileStream;
  late final Stream<List<Map<String, dynamic>>> _packagesStream;
  static const List<Map<String, dynamic>> _fallbackPackages = [
    {
      'id': 'single',
      'name': 'Разовый пакет',
      'price': 0,
      'frequency': 'Разовая уборка',
      'sortOrder': 1,
      'isActive': true,
      'cleaningsPerMonth': 1,
      'billingPeriodMonths': 1,
      'discountPercent': 0,
    },
    {
      'id': 'basic',
      'name': 'Два раза в месяц',
      'price': 0,
      'frequency': '2 раза в месяц',
      'sortOrder': 2,
      'isActive': true,
      'cleaningsPerMonth': 2,
      'billingPeriodMonths': 1,
      'discountPercent': 0,
    },
    {
      'id': 'standard',
      'name': '4 раза в месяц',
      'price': 0,
      'frequency': '4 раза в месяц',
      'sortOrder': 3,
      'isActive': true,
      'cleaningsPerMonth': 4,
      'billingPeriodMonths': 1,
      'discountPercent': 0,
    },
    {
      'id': 'premium',
      'name': '8 раз в месяц',
      'price': 0,
      'frequency': '8 раз в месяц',
      'sortOrder': 4,
      'isActive': true,
      'cleaningsPerMonth': 8,
      'billingPeriodMonths': 1,
      'discountPercent': 0,
    },
    {
      'id': 'quarter',
      'name': 'Квартальный пакет',
      'price': 0,
      'frequency': 'Квартальный пакет',
      'sortOrder': 5,
      'isActive': true,
      'isQuarterly': true,
      'billingPeriodMonths': 3,
      'discountPercent': 10,
    },
    {
      'id': 'general_cleaning',
      'name': 'Генеральная уборка',
      'price': 45000,
      'frequency': 'Разовая',
      'sortOrder': 6,
      'isActive': true,
    },
    {
      'id': 'post_renovation',
      'name': 'Уборка после ремонта',
      'price': 60000,
      'frequency': 'Разовая',
      'sortOrder': 7,
      'isActive': true,
    },
  ];
  static const List<int> _quarterlyOptions = [2, 4, 8];
  String? _selectedPackageId;
  bool _submittingPackage = false;
  double? _area;
  int _baseCleaningPrice = 0;
  int _quarterlyVisitsPerMonth = 2;
  String? _selectedApartmentKey;
  final Map<String, GlobalKey> _packageKeys = <String, GlobalKey>{};
  final Map<String, Map<String, dynamic>> _infoCache = {};
  Map<String, dynamic> _latestProfile = const <String, dynamic>{};
  StreamSubscription<List<Map<String, dynamic>>>? _infoSubscription;
  bool _routeArgsApplied = false;
  bool _debugAutoFlowTriggered = false;

  Future<void> _showSubmissionDialog({
    required String title,
    required String message,
    bool openPaymentHistoryAction = false,
    bool navigateHomeOnClose = false,
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
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (navigateHomeOnClose && mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/client/home',
                    (_) => false,
                  );
                }
              },
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

  @override
  void initState() {
    super.initState();
    _profileStream = _data.customerProfileStream();
    _packagesStream = _data.customerPackagesStream();
    _loadInfoContent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeArgsApplied) {
      return;
    }
    _routeArgsApplied = true;
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final args = routeArgs is Map ? routeArgs : const <String, dynamic>{};
    final preselectedPackageId =
        args['preselectedPackageId']?.toString().trim() ?? '';
    if (preselectedPackageId.isNotEmpty) {
      _selectedPackageId = preselectedPackageId;
      _scrollSelectedPackageToCenter();
    }
  }

  Future<void> _loadInfoContent() async {
    try {
      final infoStream = _configService.infoContentStream();
      _infoSubscription?.cancel();
      _infoSubscription = infoStream.listen((infoList) {
        if (!mounted) return;
        setState(() {
          _infoCache.clear();
          for (final info in infoList) {
            _infoCache[info['key']?.toString() ?? ''] = info;
          }
        });
      });
    } catch (e) {
      AppLogger.w('PACKAGE', 'Error loading info content', e);
    }
  }

  Future<void> _showPackageInfo(Map<String, dynamic> package) async {
    final packageKey = _resolvePackageInfoKey(package);

    // Try to get info from Firestore config
    Map<String, dynamic>? infoConfig;
    if (packageKey.isNotEmpty) {
      infoConfig = await _configService.getInfoContent(packageKey);
    }
    if (!mounted) {
      return;
    }

    final packageInfo = {
      'title': package['name'] ?? package['title'] ?? 'Информация',
      'shortInfo': package['shortInfo'] ?? 'Информация по пакету',
      'fullInfo': package['fullInfo'] ?? '',
      'price': _packageDisplayPrice(package),
      'features': package['features'] is List
          ? List<String>.from(package['features'] as List)
          : null,
    };
    await InfoDialog.showFromConfig(
      context,
      config: _mergePackageInfoConfig(infoConfig, packageInfo),
    );
  }

  Map<String, dynamic> _mergePackageInfoConfig(
    Map<String, dynamic>? infoConfig,
    Map<String, dynamic> packageInfo,
  ) {
    final merged = <String, dynamic>{
      if (infoConfig != null) ...infoConfig,
      ...packageInfo,
    };
    if ((packageInfo['shortInfo'] ?? '').toString().trim().isEmpty &&
        infoConfig != null) {
      merged['shortInfo'] =
          infoConfig['shortInfo'] ?? infoConfig['description'];
    }
    if ((packageInfo['fullInfo'] ?? '').toString().trim().isEmpty &&
        infoConfig != null) {
      merged['fullInfo'] =
          infoConfig['fullInfo'] ?? infoConfig['longDescription'];
    }
    if (packageInfo['features'] == null && infoConfig != null) {
      merged['features'] = infoConfig['features'];
    }
    return merged;
  }

  Future<void> _showInfoCardInfo({
    required String key,
    required String title,
    required String shortInfo,
    String fullInfo = '',
  }) async {
    Map<String, dynamic>? infoConfig;
    if (key.isNotEmpty) {
      infoConfig = await _configService.getInfoContent(key);
    }
    if (!mounted) {
      return;
    }

    if (infoConfig != null && infoConfig.isNotEmpty) {
      await InfoDialog.showFromConfig(context, config: infoConfig);
    } else {
      await InfoDialog.showFromConfig(context, config: {
        'title': title,
        'shortInfo': shortInfo,
        'fullInfo': fullInfo,
      });
    }
  }

  String _resolvePackageInfoKey(Map<String, dynamic> package) {
    final explicitKey = (package['key'] ?? '').toString().trim();
    if (explicitKey.isNotEmpty) {
      return explicitKey;
    }

    final id = (package['id'] ?? '').toString().trim();
    switch (id) {
      case 'single':
        return 'single_package';
      case 'basic':
        return '2x_month';
      case 'standard':
        return '4x_month';
      case 'premium':
        return '8x_month';
      case 'quarter':
      case 'quarterly':
        return 'quarter';
      case 'general_cleaning':
      case 'post_renovation':
        return id;
    }

    final name = (package['name'] ?? package['title'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (name.contains('разов')) return 'single_package';
    if (name.contains('два раза')) return '2x_month';
    if (name.contains('2 раза')) return '2x_month';
    if (name.contains('4 раза')) return '4x_month';
    if (name.contains('8 раз')) return '8x_month';
    if (name.contains('кварт')) return 'quarter';
    if (name.contains('ген')) return 'general_cleaning';
    if (name.contains('ремонт')) return 'post_renovation';

    return id;
  }

  List<Map<String, dynamic>> _profileApartments(Map<String, dynamic> profile) {
    final rawAddresses =
        (profile['addresses'] as List?)?.whereType<Map>() ?? [];
    final mapped = rawAddresses.map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final key = [
        item['addressPlaceId'],
        item['houseId'],
        item['address'],
        item['apartment'],
      ].where((value) => value != null && '$value'.trim().isNotEmpty).join('|');
      return {
        ...item,
        '_key': key.isNotEmpty ? key : 'apt_${raw.hashCode}',
      };
    }).toList();
    if (mapped.isNotEmpty) {
      return mapped;
    }
    final fallbackAddress = (profile['address'] ?? '').toString().trim();
    final fallbackResidential =
        (profile['residentialComplex'] ?? '').toString().trim();
    if (fallbackAddress.isEmpty && fallbackResidential.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return [
      {
        '_key': 'primary_profile_apartment',
        'address': fallbackAddress,
        'residentialComplex': fallbackResidential,
        'addressPlaceId': profile['addressPlaceId'],
        'addressLat': profile['addressLat'],
        'addressLng': profile['addressLng'],
        'houseId': profile['houseId'],
        'houseStatus': profile['houseStatus'],
        'entrance': profile['entrance'],
        'apartment': profile['apartment'],
        'area': profile['area'],
        'isPrimary': true,
      }
    ];
  }

  Map<String, dynamic>? _selectedApartment(Map<String, dynamic> profile) {
    final apartments = _profileApartments(profile);
    if (apartments.isEmpty) {
      return null;
    }
    final explicit = apartments.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['_key']?.toString() == _selectedApartmentKey,
          orElse: () => null,
        );
    if (explicit != null) {
      return explicit;
    }
    return apartments.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['isPrimary'] == true,
          orElse: () => apartments.first,
        );
  }

  void _applyApartmentArea(Map<String, dynamic>? apartment) {
    if (apartment == null) {
      return;
    }
    final profileVerified = _latestProfile['areaVerified'] == true ||
        (_latestProfile['areaStatus'] ?? '').toString().toUpperCase() ==
            'VERIFIED';
    if (profileVerified) {
      final verifiedArea = PackageCatalogUtils.numValue(
        _latestProfile['actualArea'] ??
            _latestProfile['apartmentArea'] ??
            _latestProfile['area'] ??
            _latestProfile['initialArea'],
      )?.toDouble();
      if (verifiedArea != null && verifiedArea > 0) {
        setState(() {
          _area = verifiedArea;
          _baseCleaningPrice = _localBaseCleaningPrice(verifiedArea.ceil());
        });
      }
      return;
    }
    final apartmentArea = (apartment['area'] as num?)?.toDouble();
    if (apartmentArea == null || apartmentArea <= 0) {
      return;
    }
    setState(() {
      _area = apartmentArea;
      _baseCleaningPrice = _localBaseCleaningPrice(apartmentArea.ceil());
    });
    unawaited(_persistAreaBaseline(apartmentArea));
  }

  void _seedAreaFromProfile(Map<String, dynamic> profile) {
    if (_area != null && _area! > 0 && _baseCleaningPrice > 0) {
      return;
    }
    final apartment = _selectedApartment(profile);
    final profileVerified = profile['areaVerified'] == true ||
        (profile['areaStatus'] ?? '').toString().toUpperCase() == 'VERIFIED';
    final apartmentVerified = apartment?['areaVerified'] == true ||
        (apartment?['areaStatus'] ?? '').toString().toUpperCase() == 'VERIFIED';
    final area = profileVerified
        ? PackageCatalogUtils.numValue(
            profile['actualArea'] ??
                profile['apartmentArea'] ??
                profile['area'] ??
                profile['initialArea'],
          )?.toDouble()
        : apartmentVerified
            ? PackageCatalogUtils.numValue(
                apartment?['actualArea'] ?? apartment?['area'],
              )?.toDouble()
            : PackageCatalogUtils.numValue(
                profile['apartmentArea'] ??
                    profile['area'] ??
                    apartment?['area'] ??
                    profile['initialArea'],
              )?.toDouble();
    if (area == null || area <= 0) {
      return;
    }
    _area = area;
    _baseCleaningPrice = _localBaseCleaningPrice(area.ceil());
  }

  int _localBaseCleaningPrice(int area) {
    if (area <= 0) return 0;
    return area * 120;
  }

  bool _needsInitialAreaConfirmation(
    Map<String, dynamic> profile,
    Map<String, dynamic>? apartment,
    double area,
  ) {
    if (area <= 0) {
      return false;
    }
    final status =
        (apartment?['areaStatus'] ?? profile['areaStatus'] ?? '').toString();
    final verified =
        apartment?['areaVerified'] == true || profile['areaVerified'] == true;
    return !verified &&
        status != 'VERIFIED' &&
        status != 'QUALITY_CHECK_SCHEDULED';
  }

  Future<void> _persistAreaBaseline(double area) async {
    final normalizedArea = area.ceil();
    if (normalizedArea <= 0) {
      return;
    }
    final currentProfile = _latestProfile;
    final profileVerified = currentProfile['areaVerified'] == true ||
        (currentProfile['areaStatus'] ?? '').toString().toUpperCase() ==
            'VERIFIED';
    if (profileVerified) {
      return;
    }
    final existingArea = (currentProfile['apartmentArea'] as num?)?.toInt() ??
        (currentProfile['area'] as num?)?.toInt() ??
        0;
    final existingInitialArea =
        (currentProfile['initialArea'] as num?)?.toInt() ?? 0;
    if (existingArea == normalizedArea && existingInitialArea > 0) {
      return;
    }
    final payload = <String, dynamic>{
      'apartmentArea': normalizedArea,
      'area': normalizedArea,
    };
    if (existingInitialArea <= 0) {
      payload['initialArea'] = normalizedArea;
    }
    try {
      await _data.updateCustomerProfile(payload);
      _latestProfile = {
        ..._latestProfile,
        ...payload,
      };
    } catch (_) {
      // Area persistence is best-effort here; checkout flow should continue.
    }
  }

  Future<bool> _requestProfileDataForCheckout() async {
    final saved = await ProfileScreen.openProfileEditor(
      context,
      _data,
      _latestProfile,
      requireCompletion: true,
      stayInCurrentFlow: true,
    );
    if (!mounted || !saved) {
      return false;
    }
    final profile = await _profileStream
        .where((value) => value != null)
        .cast<Map<String, dynamic>>()
        .first
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => _latestProfile,
        );
    _latestProfile = profile;
    final apartment = _selectedApartment(_latestProfile);
    final apartmentArea = (apartment?['area'] as num?)?.toDouble();
    if (apartmentArea != null && apartmentArea > 0) {
      _applyApartmentArea(apartment);
    } else {
      _area = null;
      _baseCleaningPrice = 0;
      _seedAreaFromProfile(_latestProfile);
    }
    return _area != null && _area! > 0 && _baseCleaningPrice > 0;
  }

  String _formatAreaCheckDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<Map<String, String>?> _showAreaQualityCheckDialog() async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    const timeSlots = <String>[
      '09:00',
      '11:00',
      '13:00',
      '15:00',
      '17:00',
      '19:00',
    ];
    var selectedTime = timeSlots.first;
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Проверка квадратуры'.tr(),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: DomlyColors.foreground,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выберите удобную дату и время для проверки вашей квадратуры отделом контроля качества.'
                      .tr(),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: DomlyColors.foreground,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(now.year, now.month, now.day)
                          .add(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 45)),
                      locale: const Locale('ru'),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_formatAreaCheckDate(selectedDate)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedTime,
                  decoration: InputDecoration(
                    labelText: 'Время',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: [
                    for (final slot in timeSlots)
                      DropdownMenuItem(value: slot, child: Text(slot)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedTime = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DomlyPrimaryButton(
                    label: 'Пройти проверку в приложении',
                    onPressed: () => Navigator.of(context).pop({
                      'mode': 'in_app',
                    }),
                  ),
                  const SizedBox(height: 10),
                  DomlySecondaryButton(
                    label: 'Назначить проверку',
                    onPressed: () => Navigator.of(context).pop({
                      'mode': 'visit',
                      'date': _formatAreaCheckDate(selectedDate),
                      'time': selectedTime,
                    }),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openInAppAreaCheck() async {
    await Navigator.pushNamed(
      context,
      '/client/area-confirmation',
      arguments: {
        'actualArea': _area?.round(),
        'area': _area?.round(),
        'forceTechPlanPrompt': true,
      },
    );
  }

  Future<void> _requestAreaQualityCheckIfNeeded({
    required bool needed,
    String? orderId,
  }) async {
    if (!needed || _area == null || _area! <= 0) {
      return;
    }
    if (orderId != null && orderId.trim().isNotEmpty) {
      final deadline = DateTime.now().add(const Duration(hours: 48));
      final deadlineDate = '${deadline.year.toString().padLeft(4, '0')}-'
          '${deadline.month.toString().padLeft(2, '0')}-'
          '${deadline.day.toString().padLeft(2, '0')}';
      await PaymentLinkService.runBlocking(
        context,
        task: () => _data.requestAreaQualityCheck(
          actualArea: _area!.round(),
          preferredDate: deadlineDate,
          preferredTime: 'В течение 48 часов',
          orderId: orderId,
        ),
        message: 'Создаем проверку квадратуры...',
      );
      _latestProfile = {
        ..._latestProfile,
        'areaVerified': false,
        'areaStatus': 'QUALITY_CHECK_SCHEDULED',
        'areaQualityCheckDate': deadlineDate,
        'areaQualityCheckTime': 'В течение 48 часов',
      };
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Проверка площади',
        subtitle:
            'Пакет можно оплатить сейчас. В течение 48 часов отдел контроля качества приедет к вам для проверки площади. Также вы можете пройти проверку в приложении, загрузив план квартиры.',
        type: DomlySnackBarType.info,
      );
      return;
    }
    final selection = await _showAreaQualityCheckDialog();
    if (!mounted || selection == null) {
      return;
    }
    if (selection['mode'] == 'in_app') {
      await _openInAppAreaCheck();
      return;
    }
    await PaymentLinkService.runBlocking(
      context,
      task: () => _data.requestAreaQualityCheck(
        actualArea: _area!.round(),
        preferredDate: selection['date'] ?? '',
        preferredTime: selection['time'] ?? '',
        orderId: orderId,
      ),
      message: 'Назначаем проверку квадратуры...',
    );
    _latestProfile = {
      ..._latestProfile,
      'areaVerified': false,
      'areaStatus': 'QUALITY_CHECK_SCHEDULED',
      'areaQualityCheckDate': selection['date'],
      'areaQualityCheckTime': selection['time'],
    };
    if (!mounted) {
      return;
    }
    showDomlySnackBar(
      context,
      title: 'Проверка назначена',
      subtitle: orderId == null
          ? 'После подтверждения площади можно будет оформить заказ.'
          : 'Контроль качества проверит квадратуру ${selection['date']} в ${selection['time']}.',
    );
  }

  bool _requiresScheduleSelection(Map<String, dynamic> package) {
    if (PackageCatalogUtils.isSpecialPackage(package)) {
      return false;
    }
    final billingMonths = PackageCatalogUtils.billingPeriodMonths(package);
    final visits = PackageCatalogUtils.cleaningsPerMonth(
      package,
      quarterlyVisitsPerMonth: _quarterlyVisitsPerMonth,
    );
    return billingMonths > 1 || visits > 1;
  }

  Future<Map<String, dynamic>?> _ensureOrderApartment(
    Map<String, dynamic>? apartment,
  ) async {
    final base = <String, dynamic>{
      ..._latestProfile,
      if (apartment != null) ...apartment,
    };
    final existingHouseId = (base['houseId'] ?? '').toString().trim();
    if (existingHouseId.isNotEmpty) {
      return base;
    }

    final address = (base['address'] ?? '').toString().trim();
    final residential = (base['residentialComplex'] ?? '').toString().trim();
    if (address.isEmpty && residential.isEmpty) {
      return base;
    }

    final house = await _data.resolveHouseForAddress(
      residentialComplex: residential,
      addressLine: address,
      placeId: (base['addressPlaceId'] ?? '').toString(),
      lat: (base['addressLat'] as num?)?.toDouble(),
      lng: (base['addressLng'] as num?)?.toDouble(),
    );
    final houseId = (house?['id'] ?? '').toString().trim();
    if (houseId.isEmpty) {
      return base;
    }

    final houseStatus = (house?['status'] ?? '').toString().trim();
    final resolved = {
      ...base,
      'houseId': houseId,
      if (houseStatus.isNotEmpty) 'houseStatus': houseStatus,
    };
    final nextAddresses = _profileApartments(_latestProfile).map((item) {
      final currentAddress = (item['address'] ?? '').toString().trim();
      final currentResidential =
          (item['residentialComplex'] ?? '').toString().trim();
      final matches = item['isPrimary'] == true ||
          currentAddress == address ||
          currentResidential == residential;
      return matches
          ? {
              ...item,
              'houseId': houseId,
              if (houseStatus.isNotEmpty) 'houseStatus': houseStatus,
            }
          : item;
    }).toList();
    if (nextAddresses.isEmpty) {
      nextAddresses.add({
        'address': address,
        'residentialComplex': residential,
        'addressPlaceId': base['addressPlaceId'],
        'addressLat': base['addressLat'],
        'addressLng': base['addressLng'],
        'houseId': houseId,
        if (houseStatus.isNotEmpty) 'houseStatus': houseStatus,
        'entrance': base['entrance'],
        'apartment': base['apartment'],
        'area': base['area'],
        'isPrimary': true,
      });
    }

    await _data.updateCustomerProfile({
      'houseId': houseId,
      if (houseStatus.isNotEmpty) 'houseStatus': houseStatus,
      'addresses': nextAddresses,
    });
    _latestProfile = {
      ..._latestProfile,
      'houseId': houseId,
      if (houseStatus.isNotEmpty) 'houseStatus': houseStatus,
      'addresses': nextAddresses,
    };
    return resolved;
  }

  List<Map<String, dynamic>> _mergePackages(List<Map<String, dynamic>> remote) {
    final merged = remote.isNotEmpty
        ? remote.map((item) => Map<String, dynamic>.from(item)).toList()
        : _fallbackPackages
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

    merged.sort((a, b) {
      final aOrder =
          PackageCatalogUtils.numValue(a['sortOrder'])?.toInt() ?? 999;
      final bOrder =
          PackageCatalogUtils.numValue(b['sortOrder'])?.toInt() ?? 999;
      return aOrder.compareTo(bOrder);
    });

    return merged.where((item) => item['isActive'] != false).toList();
  }

  int _packageDisplayVisits(Map<String, dynamic> package) {
    return PackageCatalogUtils.cleaningsPerMonth(
      package,
      quarterlyVisitsPerMonth: _quarterlyVisitsPerMonth,
    );
  }

  String _visitsLabel(int visits) {
    switch (visits) {
      case 1:
        return '1 уборка';
      case 2:
        return '2 уборки';
      case 4:
        return '4 уборки';
      case 8:
        return '8 уборок';
      default:
        return '$visits уборки';
    }
  }

  int _packageUnitAreaPrice(Map<String, dynamic> package) {
    return PackageCatalogUtils.numValue(package['price'])?.toInt() ?? 0;
  }

  int _packageDisplayPrice(Map<String, dynamic> package) {
    final fallbackPrice =
        PackageCatalogUtils.numValue(package['price'])?.toInt() ?? 0;
    final visits = _packageDisplayVisits(package);
    final billingMonths = PackageCatalogUtils.billingPeriodMonths(package);
    final discountRate = PackageCatalogUtils.discountRate(package);

    if (PackageCatalogUtils.isSpecialPackage(package)) {
      final base = fallbackPrice > 0 ? fallbackPrice : _baseCleaningPrice;
      return base;
    }

    final area = _area?.ceil() ?? 0;
    final areaUnitPrice = _packageUnitAreaPrice(package);
    if (area > 0 && areaUnitPrice > 0) {
      final packageSubtotal = areaUnitPrice * area * visits * billingMonths;
      final discounted =
          (packageSubtotal - (packageSubtotal * discountRate).round())
              .clamp(0, packageSubtotal);
      return discounted;
    }

    if (_baseCleaningPrice <= 0) {
      return fallbackPrice;
    }
    final packageSubtotal = _baseCleaningPrice * visits * billingMonths;
    final discounted =
        (packageSubtotal - (packageSubtotal * discountRate).round())
            .clamp(0, packageSubtotal);
    return discounted;
  }

  String _packagePriceCaption(Map<String, dynamic> package) {
    final areaUnitPrice = _packageUnitAreaPrice(package);
    final visits = _packageDisplayVisits(package);
    final billingMonths = PackageCatalogUtils.billingPeriodMonths(package);
    if (PackageCatalogUtils.isQuarterlyPackage(package)) {
      final discount =
          (PackageCatalogUtils.discountRate(package) * 100).round();
      if (areaUnitPrice > 0) {
        return '$areaUnitPrice ₸ за м² · ${_visitsLabel(_quarterlyVisitsPerMonth)}/мес · $billingMonths мес · -$discount%';
      }
      if (_baseCleaningPrice <= 0) {
        return 'Заполните площадь квартиры';
      }
      return '${_visitsLabel(_quarterlyVisitsPerMonth)}/мес · $billingMonths мес · -$discount%';
    }
    if (PackageCatalogUtils.isSpecialPackage(package)) {
      return 'Фиксированная стоимость пакета';
    }
    if (areaUnitPrice > 0) {
      if (visits <= 1 && billingMonths <= 1) {
        return '$areaUnitPrice ₸ за м²';
      }
      final periodPart = billingMonths > 1 ? ' × $billingMonths мес.' : '';
      return '$areaUnitPrice ₸ за м² × ${_visitsLabel(visits)}$periodPart';
    }
    if (_baseCleaningPrice <= 0) {
      return 'Заполните площадь квартиры';
    }
    if (visits <= 1) {
      return '$_baseCleaningPrice ₸ за одну уборку';
    }
    return '$_baseCleaningPrice ₸ за уборку × $visits';
  }

  Future<void> _handlePackageTap(Map<String, dynamic> package) async {
    setState(() => _selectedPackageId = package['id'].toString());
    _scrollSelectedPackageToCenter();
  }

  void _scrollSelectedPackageToCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final packageId = _selectedPackageId;
      if (packageId == null || packageId.isEmpty) {
        return;
      }
      final context = _packageKeys[packageId]?.currentContext;
      if (context == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  @override
  void dispose() {
    _infoSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileStream,
      initialData: const <String, dynamic>{},
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return const DomlyShell(
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
          stream: _packagesStream,
          initialData: _fallbackPackages,
          builder: (context, snap) {
            _latestProfile = profileSnap.data ?? const <String, dynamic>{};
            _seedAreaFromProfile(_latestProfile);
            final packages = _mergePackages(
              snap.hasError
                  ? const <Map<String, dynamic>>[]
                  : (snap.data ?? const <Map<String, dynamic>>[]),
            );
            final selectedPackage =
                _selectedPackageId == null || packages.isEmpty
                    ? null
                    : packages.cast<Map<String, dynamic>?>().firstWhere(
                          (item) => item?['id'] == _selectedPackageId,
                          orElse: () => null,
                        );
            _triggerDebugAutoFlowIfNeeded(packages, selectedPackage);
            return DomlyShell(
              bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 0),
              child: ColoredBox(
                color: const Color(0xFFF2FAF7),
                child: SafeArea(
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: Stack(
                        children: [
                          SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(15, 0, 15, 220),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _PackageSelectionHeader(),
                                const SizedBox(height: 19),
                                if (packages.isEmpty)
                                  DomlyEmptyStateCard(
                                    title: snap.hasError
                                        ? 'Не удалось загрузить каталог'
                                        : 'Пакеты пока не загружены',
                                    subtitle: snap.hasError
                                        ? 'Сейчас показан резервный сценарий. Попробуйте открыть экран позже.'
                                        : 'Попробуйте обновить экран чуть позже.',
                                    icon: snap.hasError
                                        ? Icons.error_outline
                                        : Icons.inventory_2_outlined,
                                  )
                                else
                                  _PackagePickerCard(
                                    packages: packages,
                                    selectedPackageId: _selectedPackageId,
                                    packageKeys: _packageKeys,
                                    priceBuilder: _packageDisplayPrice,
                                    captionBuilder: _packagePriceCaption,
                                    quarterlyVisitsPerMonth:
                                        _quarterlyVisitsPerMonth,
                                    quarterlyOptions: _quarterlyOptions,
                                    onQuarterlyVisitsSelect: (value) =>
                                        setState(() =>
                                            _quarterlyVisitsPerMonth = value),
                                    onSelect: _handlePackageTap,
                                    onInfo: _showPackageInfo,
                                  ),
                                Builder(
                                  builder: (context) {
                                    final apartments =
                                        _profileApartments(_latestProfile);
                                    if (apartments.length <= 1) {
                                      return const SizedBox.shrink();
                                    }
                                    final selectedApartment =
                                        _selectedApartment(_latestProfile);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 18),
                                      child: _ApartmentPickerCard(
                                        apartments: apartments,
                                        selectedKey: selectedApartment?['_key']
                                            ?.toString(),
                                        onSelect: (apartment) {
                                          setState(() {
                                            _selectedApartmentKey =
                                                apartment['_key']?.toString();
                                          });
                                          _applyApartmentArea(apartment);
                                        },
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 34),
                                _CreateCustomPackageButton(
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/client/calculator',
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _PackageInfoCard(
                                  height: 90,
                                  title: 'Чем больше уборок — тем выгоднее',
                                  subtitle:
                                      'Подписки помогают снизить стоимость уборки и закрепить удобные даты.',
                                  titleBold: true,
                                  onInfo: () => _showInfoCardInfo(
                                    key: 'package_frequency_discount',
                                    title: 'Чем больше уборок — тем выгоднее',
                                    shortInfo:
                                        'Подписки помогают снизить стоимость одной уборки и закрепить удобные даты.',
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _PackageInfoCard(
                                  height: 79,
                                  title: 'Скидки по количеству квартир',
                                  subtitle:
                                      '1 квартира — 3%, 10 квартир — 7%, 20 квартир — 10%',
                                  titleBold: false,
                                  onInfo: () => _showInfoCardInfo(
                                    key: 'package_apartment_discount',
                                    title: 'Скидки по количеству квартир',
                                    shortInfo:
                                        'Скидка зависит от количества квартир, подключенных в доме.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selectedPackage != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _SelectedPackageFooter(
                                package: selectedPackage,
                                price: _packageDisplayPrice(selectedPackage),
                                submitting: _submittingPackage,
                                onContinue: () =>
                                    _selectPackage(selectedPackage),
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
  }

  void _triggerDebugAutoFlowIfNeeded(
    List<Map<String, dynamic>> packages,
    Map<String, dynamic>? selectedPackage,
  ) {
    if (_debugAutoFlowTriggered ||
        !DebugSession.enabled ||
        DebugSession.uid != 'customer_demo') {
      return;
    }
    final debugPackageId = DebugSession.value('debug_package_id')?.trim();
    final autoSubmit = DebugSession.value('debug_autosubmit') == 'package';
    final areaText = DebugSession.value('debug_area')?.trim();
    if ((debugPackageId == null || debugPackageId.isEmpty) && !autoSubmit) {
      return;
    }

    final package = selectedPackage ??
        (debugPackageId == null || debugPackageId.isEmpty
            ? null
            : packages.cast<Map<String, dynamic>?>().firstWhere(
                  (item) => item?['id']?.toString() == debugPackageId,
                  orElse: () => null,
                ));
    if (package == null) {
      return;
    }

    _debugAutoFlowTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final parsedArea = double.tryParse(
        (areaText ?? '60').replaceAll(',', '.'),
      );
      if (parsedArea != null && parsedArea > 0) {
        final quote = await _data.getCustomPackageQuote(
          rooms: 0,
          bathrooms: 0,
          area: parsedArea.toInt(),
          frequency: 1,
          billingPeriodMonths: 1,
          windows: false,
          ironing: false,
          balcony: false,
          addonsDetailed: const [],
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedPackageId = package['id']?.toString();
          _area = parsedArea;
          _baseCleaningPrice =
              (quote['perCleaningPrice'] as num?)?.toInt() ?? 0;
        });
      } else {
        setState(() {
          _selectedPackageId = package['id']?.toString();
        });
      }

      if (autoSubmit) {
        await _selectPackage(package);
      }
    });
  }

  Future<void> _selectPackage(Map<String, dynamic> package) async {
    if (_submittingPackage) {
      return;
    }
    final authorized = await AuthGate.ensureAuthorized(context);
    if (!mounted || !authorized) {
      return;
    }

    var apartment = _selectedApartment(_latestProfile);
    final apartmentArea = (apartment?['area'] as num?)?.toDouble();
    if ((_area == null || _area! <= 0) &&
        apartmentArea != null &&
        apartmentArea > 0) {
      _applyApartmentArea(apartment);
    }

    if (_area == null || _area! <= 0 || _baseCleaningPrice <= 0) {
      final ready = await _requestProfileDataForCheckout();
      if (!mounted || !ready) {
        return;
      }
      setState(() {
        _selectedPackageId = package['id']?.toString();
      });
      return;
    }

    final needsAreaQualityCheck =
        _needsInitialAreaConfirmation(_latestProfile, apartment, _area!);

    final isDebugAutoSubmit = DebugSession.enabled &&
        DebugSession.uid == 'customer_demo' &&
        DebugSession.value('debug_autosubmit') == 'package';
    if (!mounted) {
      return;
    }

    final price = _packageDisplayPrice(package);
    final frequencyLabel = PackageCatalogUtils.frequencyLabel(
      package,
      quarterlyVisitsPerMonth: _quarterlyVisitsPerMonth,
    );
    final billingPeriodMonths =
        PackageCatalogUtils.billingPeriodMonths(package);

    setState(() => _submittingPackage = true);
    try {
      apartment = await _ensureOrderApartment(apartment);
      if (!mounted) {
        return;
      }
      final houseId = (apartment?['houseId'] ?? _latestProfile['houseId'] ?? '')
          .toString()
          .trim();
      final houseStatus =
          (apartment?['houseStatus'] ?? _latestProfile['houseStatus'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
      if (houseId.isEmpty) {
        throw 'Выберите адрес из списка подключенных домов.';
      }
      if (houseStatus.isNotEmpty && houseStatus != 'ACTIVE') {
        throw 'Этот дом еще не активирован для заказов. Выберите активный адрес.';
      }
      final paymentSelection = isDebugAutoSubmit
          ? const DomlyPaymentSelection(
              method: DomlyPaymentMethod.kaspi,
              useBonus: false,
            )
          : await showPaymentMethodOptionsDialog(
              context,
              bonusBalance: 0,
              maxBonusToSpend: 0,
              paymentAmount: price,
            );
      if (!mounted || paymentSelection == null) {
        return;
      }
      final paymentMethod = paymentSelection.method;
      const bonusToSpend = 0;
      String? kaspiPhone;
      if (paymentMethod == DomlyPaymentMethod.kaspi) {
        kaspiPhone = isDebugAutoSubmit
            ? (DebugSession.value('debug_kaspi_phone')?.trim().isNotEmpty ==
                    true
                ? DebugSession.value('debug_kaspi_phone')!.trim()
                : '+77086362153')
            : await showKaspiInvoiceRequestDialog(context);
      }
      if (!mounted ||
          (paymentMethod == DomlyPaymentMethod.kaspi && kaspiPhone == null)) {
        return;
      }

      final result = await PaymentLinkService.runBlocking(
        context,
        task: () => _data.createOrderAndInvoice(
          amount: price,
          customerId: _data.currentUserId,
          packageName: (package['name'] ?? 'Пакет').toString(),
          packageId: package['id']?.toString(),
          pricingMode: 'package_catalog',
          cleaningsPerMonth: PackageCatalogUtils.cleaningsPerMonth(
            package,
            quarterlyVisitsPerMonth: _quarterlyVisitsPerMonth,
          ),
          accessMethod: 'Я дома',
          addons: const <String>[],
          addonsDetailed: const <Map<String, dynamic>>[],
          frequencyLabel: frequencyLabel,
          rooms: 0,
          bathrooms: 0,
          area: _area?.ceil() ?? 0,
          address:
              (apartment?['address'] ?? _latestProfile['address'])?.toString(),
          residentialComplex: (apartment?['residentialComplex'] ??
                  _latestProfile['residentialComplex'])
              ?.toString(),
          entrance: (apartment?['entrance'] ?? _latestProfile['entrance'])
              ?.toString(),
          apartment: (apartment?['apartment'] ?? _latestProfile['apartment'])
              ?.toString(),
          houseId: houseId,
          billingPeriodMonths: billingPeriodMonths,
          bonusToSpend: bonusToSpend,
        ),
        message: 'Создаем заявку на оплату...',
      );
      final createdLocally = result['localFallback'] == true;

      final orderId = result['orderId']?.toString();

      if (orderId != null && orderId.isNotEmpty) {
        if (!mounted) return;
        await _requestAreaQualityCheckIfNeeded(
          needed: needsAreaQualityCheck,
          orderId: orderId,
        );
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
            title: 'Заявка сохранена',
            message:
                'Мы сохранили вашу заявку. Менеджер свяжется с вами для выставления счёта, когда сервис оплаты будет доступен.',
            navigateHomeOnClose: true,
          );
          return;
        }
        if (isDebugAutoSubmit) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/client/orders',
            (_) => false,
          );
          return;
        }
        await _showSubmissionDialog(
          title: createdLocally ? 'Заявка сохранена' : 'Заявка отправлена',
          message: createdLocally
              ? 'Мы сохранили вашу заявку. Менеджер свяжется с вами для выставления счёта.'
              : 'Менеджер выставит счёт в ближайшее время. После оплаты вы сможете продолжить оформление.',
          navigateHomeOnClose: true,
        );
        return;
      }

      if (!mounted) {
        return;
      }
      final packageLabel = (package['name'] ?? '').toString();
      final successText = _requiresScheduleSelection(package)
          ? 'Пакет $packageLabel оформлен. После оплаты выберите даты в подписке.'
          : 'Заявка на $packageLabel оформлена. После оплаты менеджер подтвердит заказ.';
      await _showSubmissionDialog(
        title: 'Оформление завершено',
        message: successText,
      );
    } catch (error) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось оформить пакет',
        subtitle: _checkoutErrorText(error),
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _submittingPackage = false);
      }
    }
  }

  String _checkoutErrorText(Object error) {
    if (UserErrorMessage.isAuthError(error)) {
      return UserErrorMessage.message(error);
    }
    final raw = error.toString();
    final text = raw.replaceFirst(RegExp(r'^FlutterError\s*'), '').trim();
    if (text.contains('Сумма платежа не совпадает')) {
      return 'Сумма изменилась. Обновите экран и попробуйте оформить пакет ещё раз.';
    }
    if (text.contains('customerId required') ||
        text.contains('Не удалось связать заявку')) {
      return 'Сессия устарела. Выйдите и войдите снова.';
    }
    if (text.contains('permission-denied') || text.contains('Not your order')) {
      return 'Нет доступа к этой заявке. Обновите экран и попробуйте снова.';
    }
    if (text.contains('unavailable') ||
        text.contains('internal') ||
        text.contains('Сервис оформления временно недоступен')) {
      return 'Сервис оформления временно недоступен. Попробуйте позже.';
    }
    final firstLine = text.split('\n').first.trim();
    if (firstLine.isEmpty) {
      return 'Попробуйте обновить экран и повторить оформление.';
    }
    return UserErrorMessage.message(
      error,
      fallback: 'Попробуйте обновить экран и повторить оформление.',
    );
  }
}

class _PackageSelectionHeader extends StatelessWidget {
  const _PackageSelectionHeader();

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
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Пакеты'.tr(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Подберите формат подписки'.tr(),
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

class _PackagePickerCard extends StatelessWidget {
  const _PackagePickerCard({
    required this.packages,
    required this.selectedPackageId,
    required this.packageKeys,
    required this.priceBuilder,
    required this.captionBuilder,
    required this.quarterlyVisitsPerMonth,
    required this.quarterlyOptions,
    required this.onQuarterlyVisitsSelect,
    required this.onSelect,
    required this.onInfo,
  });

  final List<Map<String, dynamic>> packages;
  final String? selectedPackageId;
  final Map<String, GlobalKey> packageKeys;
  final int Function(Map<String, dynamic>) priceBuilder;
  final String Function(Map<String, dynamic>) captionBuilder;
  final int quarterlyVisitsPerMonth;
  final List<int> quarterlyOptions;
  final ValueChanged<int> onQuarterlyVisitsSelect;
  final Future<void> Function(Map<String, dynamic>) onSelect;
  final Future<void> Function(Map<String, dynamic>) onInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(19, 25, 19, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 9),
            child: Text(
              'Выберите пакет'.tr(),
              style: TextStyle(
                color: Color(0xFF2B4338),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 23 / 18,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...packages.map(
            (package) {
              final packageId = package['id']?.toString() ?? '';
              return Padding(
                key: packageId.isEmpty
                    ? null
                    : packageKeys.putIfAbsent(packageId, GlobalKey.new),
                padding: const EdgeInsets.only(bottom: 10),
                child: _PackageOptionRow(
                  package: package,
                  selected: packageId == selectedPackageId,
                  showQuarterlyOptions: packageId == selectedPackageId &&
                      PackageCatalogUtils.isQuarterlyPackage(package),
                  quarterlyVisitsPerMonth: quarterlyVisitsPerMonth,
                  quarterlyOptions: quarterlyOptions,
                  price: priceBuilder(package),
                  caption: captionBuilder(package),
                  onQuarterlyVisitsSelect: onQuarterlyVisitsSelect,
                  onSelect: () => onSelect(package),
                  onInfo: () => onInfo(package),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PackageOptionRow extends StatelessWidget {
  const _PackageOptionRow({
    required this.package,
    required this.selected,
    required this.showQuarterlyOptions,
    required this.quarterlyVisitsPerMonth,
    required this.quarterlyOptions,
    required this.price,
    required this.caption,
    required this.onQuarterlyVisitsSelect,
    required this.onSelect,
    required this.onInfo,
  });

  final Map<String, dynamic> package;
  final bool selected;
  final bool showQuarterlyOptions;
  final int quarterlyVisitsPerMonth;
  final List<int> quarterlyOptions;
  final int price;
  final String caption;
  final ValueChanged<int> onQuarterlyVisitsSelect;
  final VoidCallback onSelect;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Material(
                color: selected ? const Color(0xFFF0F7F2) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onSelect,
                  child: Container(
                    height: 84,
                    padding: const EdgeInsets.fromLTRB(14, 7, 13, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF439F73)
                            : const Color(0xFFDEECE3),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (package['name'] ??
                                              package['title'] ??
                                              'Пакет')
                                          .toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF2B4338),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        height: 21 / 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                price > 0
                                    ? '$price ₸'
                                    : 'Стоимость после выбора площади',
                                style: const TextStyle(
                                  color: Color(0xFF2B4338),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 18 / 14,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF658170),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 14 / 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF439F73)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF439F73)
                                  : const Color(0xFFDEECE3),
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: const Color(0xFFCF7548),
              shape: const CircleBorder(),
              elevation: 10,
              shadowColor: const Color(0xFFCF7548).withValues(alpha: 0.75),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onInfo,
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
          ],
        ),
        if (showQuarterlyOptions) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 33),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quarterlyOptions.map((value) {
                final selectedVisits = value == quarterlyVisitsPerMonth;
                return ChoiceChip(
                  label: Text('$value уборки/мес'.tr()),
                  selected: selectedVisits,
                  onSelected: (_) => onQuarterlyVisitsSelect(value),
                  selectedColor: const Color(0xFFF0F7F2),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selectedVisits
                        ? const Color(0xFF439F73)
                        : const Color(0xFFDEECE3),
                    width: selectedVisits ? 2 : 1,
                  ),
                  labelStyle: TextStyle(
                    color: selectedVisits
                        ? const Color(0xFF2B4338)
                        : const Color(0xFF658170),
                    fontSize: 12,
                    fontWeight:
                        selectedVisits ? FontWeight.w700 : FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _CreateCustomPackageButton extends StatelessWidget {
  const _CreateCustomPackageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Material(
        color: const Color(0xFFC96A4A),
        borderRadius: BorderRadius.circular(18),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                'Создать свой пакет'.tr(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 18 / 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageInfoCard extends StatelessWidget {
  const _PackageInfoCard({
    required this.height,
    required this.title,
    required this.subtitle,
    required this.titleBold,
    required this.onInfo,
  });

  final double height;
  final String title;
  final String subtitle;
  final bool titleBold;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            height: height,
            padding: const EdgeInsets.fromLTRB(26, 11, 26, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDEECE3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: titleBold ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF2B4338),
                    fontSize: titleBold ? 18 : 16,
                    fontWeight: titleBold ? FontWeight.w700 : FontWeight.w600,
                    height: titleBold ? 23 / 18 : 21 / 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
            shadowColor: const Color(0xFFCF7548).withValues(alpha: 0.75),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onInfo,
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
    );
  }
}

class _ApartmentPickerCard extends StatelessWidget {
  const _ApartmentPickerCard({
    required this.apartments,
    required this.selectedKey,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> apartments;
  final String? selectedKey;
  final void Function(Map<String, dynamic> apartment) onSelect;

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
            'Квартира для заказа'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...apartments.map((apartment) {
            final key = apartment['_key']?.toString();
            final selected = key == selectedKey;
            final residential =
                (apartment['residentialComplex'] ?? '').toString().trim();
            final address = (apartment['address'] ?? '').toString().trim();
            final entrance = (apartment['entrance'] ?? '').toString().trim();
            final apt = (apartment['apartment'] ?? '').toString().trim();
            final area = (apartment['area'] as num?)?.toInt() ?? 0;
            final summary = [
              if (residential.isNotEmpty) residential,
              if (entrance.isNotEmpty) 'подъезд $entrance',
              if (apt.isNotEmpty) 'кв. $apt',
              if (area > 0) '$area м²',
            ].join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: selected ? const Color(0xFFF0F7F2) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSelect(apartment),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF439F73)
                            : const Color(0xFFDEECE3),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                summary.isNotEmpty ? summary : 'Квартира',
                                style: const TextStyle(
                                  color: Color(0xFF2B4338),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (address.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  address,
                                  style: const TextStyle(
                                    color: Color(0xFF658170),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF439F73)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF439F73)
                                  : const Color(0xFFDEECE3),
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SelectedPackageFooter extends StatelessWidget {
  const _SelectedPackageFooter({
    required this.package,
    required this.price,
    required this.submitting,
    required this.onContinue,
  });

  final Map<String, dynamic> package;
  final int price;
  final bool submitting;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final name = (package['name'] ?? 'Пакет').toString();
    return Container(
      height: 107,
      padding: const EdgeInsets.fromLTRB(31, 6, 31, 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F7F9),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выбран пакет'.tr(),
            style: TextStyle(
              color: Color(0xFF658170),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 16 / 12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 23 / 18,
                  ),
                ),
              ),
              Text(
                price > 0 ? '$price ₸' : '—',
                style: const TextStyle(
                  color: Color(0xFF2B4338),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 23 / 18,
                ),
              ),
            ],
          ),
          const Spacer(),
          Material(
            color: const Color(0xFFC96A4A),
            borderRadius: BorderRadius.circular(16),
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: submitting ? null : onContinue,
              child: SizedBox(
                height: 34,
                child: Center(
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Продолжить'.tr(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 17 / 14,
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
