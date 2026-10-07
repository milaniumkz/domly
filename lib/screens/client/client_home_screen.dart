import 'dart:async';
import 'dart:math' as math;

import '../../utils/backend_compat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/auth_gate.dart';
import '../../app/debug_session.dart';
import '../../app/launch_config.dart';
import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/info_dialog.dart';
import '../../services/payment_link_service.dart';
import '../../ui/domly_ui.dart';
import '../../ui/tutorial_targets.dart';
import '../../utils/app_logger.dart';
import '../../utils/bonus_policy_utils.dart';
import '../../utils/order_display.dart';
import '../../utils/package_catalog_utils.dart';
import '../../utils/user_error_message.dart';
import '../common/kaspi_invoice_request_dialog.dart';
import '../../localization/translation_controller.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _data = FirestoreDataService.instance;
  static const List<Map<String, dynamic>> _fallbackHomePackages = [
    {
      'id': 'single',
      'name': 'Разовый пакет',
      'frequency': 'Разовая уборка',
      'sortOrder': 1,
      'isActive': true,
    },
    {
      'id': 'basic',
      'name': '2 раза в месяц',
      'frequency': '2 раза в месяц',
      'sortOrder': 2,
      'isActive': true,
    },
    {
      'id': 'standard',
      'name': '4 раза в месяц',
      'frequency': '4 раза в месяц',
      'sortOrder': 3,
      'isActive': true,
    },
    {
      'id': 'premium',
      'name': '8 раз в месяц',
      'frequency': '8 раз в месяц',
      'sortOrder': 4,
      'isActive': true,
    },
    {
      'id': 'quarter',
      'name': 'Квартальный пакет',
      'frequency': '3 месяца',
      'sortOrder': 5,
      'isActive': true,
    },
    {
      'id': 'general_cleaning',
      'name': 'Генеральная уборка',
      'frequency': 'Разовая',
      'sortOrder': 6,
      'isActive': true,
    },
    {
      'id': 'post_renovation',
      'name': 'Уборка после ремонта',
      'frequency': 'Разовая',
      'sortOrder': 7,
      'isActive': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    AppLogger.d('HOME', 'ClientHomeScreen initState');
  }

  List<Map<String, dynamic>> _mergeHomePackages(
    List<Map<String, dynamic>> remote,
  ) {
    final merged = remote.isNotEmpty
        ? remote.map((item) => Map<String, dynamic>.from(item)).toList()
        : _fallbackHomePackages
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    merged.sort((a, b) {
      final aOrder =
          PackageCatalogUtils.numValue(a['sortOrder'])?.toInt() ?? 999;
      final bOrder =
          PackageCatalogUtils.numValue(b['sortOrder'])?.toInt() ?? 999;
      if (aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }
      return (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          );
    });
    return merged.where((item) => item['isActive'] != false).toList();
  }

  Future<void> _openPackageCheckout(String packageId) async {
    if (!mounted || packageId.trim().isEmpty) {
      return;
    }
    await _runProtectedAction(
      () => Navigator.pushNamed(
        context,
        '/client/packages',
        arguments: {'preselectedPackageId': packageId},
      ),
    );
  }

  Future<void> _showHomePackagePicker({
    String title = 'Выберите пакет',
    String subtitle = 'Сразу откроем оформление заказа по выбранному пакету.',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 28,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.customerPackagesStream(),
                builder: (context, snapshot) {
                  final packages = _mergeHomePackages(
                    snapshot.data ?? const [],
                  );
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: DomlyColors.foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
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
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (packages.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: DomlyEmptyStateCard(
                                title: 'Пакеты пока не загружены',
                                subtitle:
                                    'Попробуйте открыть экран чуть позже.',
                                icon: Icons.inventory_2_outlined,
                              ),
                            )
                          else
                            Flexible(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: packages.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final package = packages[index];
                                  final packageName =
                                      PackageCatalogUtils.displayName(package);
                                  final frequency =
                                      PackageCatalogUtils.isQuarterlyPackage(
                                    package,
                                  )
                                          ? '3 месяца'
                                          : PackageCatalogUtils.frequencyLabel(
                                              package,
                                            );
                                  return Material(
                                    color: const Color(0xFFF7FBF8),
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        Navigator.pop(sheetContext);
                                        _openPackageCheckout(
                                          package['id']?.toString() ?? '',
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          14,
                                          16,
                                          14,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    packageName,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: DomlyColors
                                                          .foreground,
                                                    ),
                                                  ),
                                                  if (frequency.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      frequency,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            DomlyColors.muted,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 16,
                                              color: DomlyColors.buttonPrimary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openHomeCleaningOrder({
    required Map<String, dynamic>? activeSubscription,
    String? subscriptionId,
    required bool canSelectDates,
  }) {
    final targetSubscriptionId =
        (subscriptionId ?? activeSubscription?['id'] ?? '').toString().trim();
    if (canSelectDates && targetSubscriptionId.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/client/package-calendar',
        arguments: {'subscriptionId': targetSubscriptionId},
      );
      return;
    }
    _showHomePackagePicker(
      title: 'Уборки закончились',
      subtitle:
          'В этом пакете больше нет доступных уборок. Выберите новый пакет, чтобы продолжить.',
    );
  }

  List<Map<String, dynamic>> _profileAddresses(Map<String, dynamic> profile) {
    final items =
        (profile['addresses'] as List?)?.whereType<Map>().toList() ?? const [];
    final normalized =
        items.map((item) => Map<String, dynamic>.from(item)).where((item) {
      final address = (item['address'] ?? '').toString().trim();
      final houseId = (item['houseId'] ?? '').toString().trim();
      return address.isNotEmpty || houseId.isNotEmpty;
    }).toList();
    if (normalized.isEmpty) {
      final fallbackAddress = (profile['address'] ?? '').toString().trim();
      final fallbackHouseId = (profile['houseId'] ?? '').toString().trim();
      if (fallbackAddress.isNotEmpty || fallbackHouseId.isNotEmpty) {
        normalized.add({
          'address': fallbackAddress,
          'residentialComplex':
              (profile['residentialComplex'] ?? '').toString().trim(),
          'addressPlaceId': (profile['addressPlaceId'] ?? '').toString().trim(),
          'addressLat': profile['addressLat'],
          'addressLng': profile['addressLng'],
          'houseId': fallbackHouseId,
          'houseStatus': (profile['houseStatus'] ?? '').toString().trim(),
          'entrance': (profile['entrance'] ?? '').toString().trim(),
          'apartment': (profile['apartment'] ?? '').toString().trim(),
          'area': profile['area'],
          'isPrimary': true,
        });
      }
    }
    return normalized;
  }

  Map<String, dynamic>? _selectedAddressFromProfile(
    Map<String, dynamic> profile,
  ) {
    final addresses = _profileAddresses(profile);
    if (addresses.isEmpty) {
      return null;
    }
    final selectedHouseId = (profile['houseId'] ?? '').toString().trim();
    final selectedAddress = (profile['address'] ?? '').toString().trim();
    for (final item in addresses) {
      final itemHouseId = (item['houseId'] ?? '').toString().trim();
      final itemAddress = (item['address'] ?? '').toString().trim();
      if (selectedHouseId.isNotEmpty && itemHouseId == selectedHouseId) {
        return item;
      }
      if (selectedHouseId.isEmpty &&
          selectedAddress.isNotEmpty &&
          itemAddress == selectedAddress) {
        return item;
      }
    }
    return addresses.first;
  }

  List<Map<String, dynamic>> _pendingConnectionAddresses(
    Map<String, dynamic> profile,
  ) {
    return _profileAddresses(
      profile,
    ).where((address) => !_isAddressConnected(address)).toList();
  }

  Map<String, dynamic>? _selectedPendingConnectionAddress(
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> addresses,
  ) {
    if (addresses.isEmpty) {
      return null;
    }
    final selected = _selectedAddressFromProfile(profile);
    if (selected == null) {
      return addresses.first;
    }
    final selectedHouseId = (selected['houseId'] ?? '').toString().trim();
    final selectedAddress = (selected['address'] ?? '').toString().trim();
    for (final item in addresses) {
      final itemHouseId = (item['houseId'] ?? '').toString().trim();
      final itemAddress = (item['address'] ?? '').toString().trim();
      if (selectedHouseId.isNotEmpty && itemHouseId == selectedHouseId) {
        return item;
      }
      if (selectedHouseId.isEmpty &&
          selectedAddress.isNotEmpty &&
          itemAddress == selectedAddress) {
        return item;
      }
    }
    return addresses.first;
  }

  bool _isAddressConnected(Map<String, dynamic> address) {
    if (address['canOrder'] == true || address['isConnected'] == true) {
      return true;
    }
    final status = ((address['houseStatus'] ??
                address['status'] ??
                address['connectionStatus'] ??
                '')
            .toString()
            .trim()
            .toUpperCase())
        .replaceAll('-', '_');
    if (status == 'ACTIVE' ||
        status == 'CONNECTED' ||
        status == 'APPROVED' ||
        status == 'AVAILABLE') {
      return true;
    }
    if (status == 'INACTIVE' ||
        status == 'IN_PROGRESS' ||
        status == 'PENDING' ||
        status == 'WAITING' ||
        status == 'WAITLIST' ||
        status == 'NOT_CONNECTED' ||
        status == 'REQUESTED') {
      return false;
    }
    final threshold = _addressInt(address, const [
      'threshold',
      'requiredUsers',
      'activationThreshold',
      'targetUsers',
    ]);
    final current = _addressInt(address, const [
      'currentUsers',
      'current_users',
      'waitlistCount',
      'requestsCount',
      'usersCount',
      'total_users',
    ]);
    if (threshold <= 0) {
      return true;
    }
    return current >= threshold;
  }

  int _addressInt(Map<String, dynamic> address, List<String> keys) {
    for (final key in keys) {
      final value = address[key];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return 0;
  }

  String _addressConnectionProgressText(Map<String, dynamic> address) {
    final threshold = _addressInt(address, const [
      'threshold',
      'requiredUsers',
      'activationThreshold',
      'targetUsers',
    ]);
    final current = _addressInt(address, const [
      'currentUsers',
      'current_users',
      'waitlistCount',
      'requestsCount',
      'usersCount',
      'total_users',
    ]);
    if (threshold <= 0) {
      return 'Собираем заявки от соседей';
    }
    final remaining = math.max(threshold - current, 0);
    return 'До подключения осталось: $remaining · Сейчас $current из $threshold';
  }

  String _addressStatusLabel(String rawStatus) {
    switch (rawStatus.trim().toUpperCase()) {
      case 'ACTIVE':
        return 'Дом подключен';
      case 'IN_PROGRESS':
        return 'Дом подключается';
      case 'INACTIVE':
      default:
        return 'Ожидает подключения';
    }
  }

  Color _addressStatusColor(String rawStatus) {
    switch (rawStatus.trim().toUpperCase()) {
      case 'ACTIVE':
        return DomlyColors.primary;
      case 'IN_PROGRESS':
        return const Color(0xFFFF9800);
      case 'INACTIVE':
      default:
        return const Color(0xFFC96A4A);
    }
  }

  String _addressTitle(Map<String, dynamic> address) {
    final complex = (address['residentialComplex'] ?? '').toString().trim();
    final line = (address['address'] ?? '').toString().trim();
    if (complex.isNotEmpty && line.isNotEmpty && complex != line) {
      return '$complex, $line';
    }
    return complex.isNotEmpty ? complex : line;
  }

  Future<void> _switchCustomerAddress(
    Map<String, dynamic> profile,
    Map<String, dynamic> address,
  ) async {
    final addresses = _profileAddresses(profile);
    final selectedHouseId = (address['houseId'] ?? '').toString().trim();
    final selectedAddress = (address['address'] ?? '').toString().trim();
    final updatedAddresses = addresses.map((item) {
      final next = Map<String, dynamic>.from(item);
      final itemHouseId = (item['houseId'] ?? '').toString().trim();
      final itemAddress = (item['address'] ?? '').toString().trim();
      final isSelected = selectedHouseId.isNotEmpty
          ? itemHouseId == selectedHouseId
          : itemAddress == selectedAddress;
      next['isPrimary'] = isSelected;
      return next;
    }).toList();
    await _data.updateCustomerProfile({
      'address': selectedAddress,
      'residentialComplex':
          (address['residentialComplex'] ?? '').toString().trim(),
      'addressPlaceId': (address['addressPlaceId'] ?? '').toString().trim(),
      'addressLat': address['addressLat'],
      'addressLng': address['addressLng'],
      'houseId': selectedHouseId,
      'houseStatus': (address['houseStatus'] ?? '').toString().trim(),
      'entrance': (address['entrance'] ?? '').toString().trim(),
      'apartment': (address['apartment'] ?? '').toString().trim(),
      'area': address['area'] ?? profile['area'],
      'addresses': updatedAddresses,
    });
  }

  Widget _addressSwitcherCard(Map<String, dynamic> profile) {
    final addresses = _pendingConnectionAddresses(profile);
    final selected = _selectedPendingConnectionAddress(profile, addresses);
    if (selected == null || addresses.isEmpty) {
      return const SizedBox.shrink();
    }
    final status = (selected['houseStatus'] ?? '').toString();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: addresses.length < 2
              ? null
              : () => _showAddressPicker(profile, addresses, selected),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2FAF7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: _addressStatusColor(status),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Дом ожидает подключения'.tr(),
                        style: TextStyle(
                          fontSize: 11,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _addressTitle(selected),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _addressConnectionProgressText(selected),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DomlyStatusChip(
                            label: _addressStatusLabel(status),
                            color: _addressStatusColor(status),
                          ),
                          if (addresses.length > 1) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${addresses.length} адреса'.tr(),
                              style: const TextStyle(
                                fontSize: 11,
                                color: DomlyColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (addresses.length > 1)
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: DomlyColors.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddressPicker(
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> addresses,
    Map<String, dynamic> selected,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 28,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Выберите адрес'.tr(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: DomlyColors.foreground,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Для каждого адреса будет свой сценарий: ожидание подключения или оформление уборки.'
                                    .tr(),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: DomlyColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: addresses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = addresses[index];
                          final isSelected =
                              _addressTitle(item) == _addressTitle(selected) &&
                                  (item['houseId'] ?? '').toString() ==
                                      (selected['houseId'] ?? '').toString();
                          final status = (item['houseStatus'] ?? '').toString();
                          return Material(
                            color: isSelected
                                ? const Color(0xFFF2FAF7)
                                : const Color(0xFFF7FBF8),
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () async {
                                Navigator.pop(sheetContext);
                                if (isSelected) {
                                  return;
                                }
                                await _switchCustomerAddress(profile, item);
                                if (!mounted) {
                                  return;
                                }
                                showDomlySnackBar(
                                  this.context,
                                  title: 'Адрес переключен',
                                  subtitle: _addressStatusLabel(status),
                                  type: DomlySnackBarType.success,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _addressTitle(item),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: DomlyColors.foreground,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          DomlyStatusChip(
                                            label: _addressStatusLabel(status),
                                            color: _addressStatusColor(status),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.arrow_forward_ios_rounded,
                                      size: isSelected ? 22 : 16,
                                      color: isSelected
                                          ? DomlyColors.buttonPrimary
                                          : DomlyColors.buttonPrimary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = AppScope.of(context).authController.isAuthenticated;
    AppLogger.d('HOME', 'Building client home. authenticated=$isAuthenticated');

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.customerProfileStream(),
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyClientBottomNav(currentIndex: 0),
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
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.customerSubscriptionsStream(),
          builder: (context, subscriptionsSnap) {
            if (subscriptionsSnap.hasError) {
              return const DomlyShell(
                bottomNavigationBar: DomlyClientBottomNav(currentIndex: 0),
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
            final subscriptions =
                subscriptionsSnap.data ?? <Map<String, dynamic>>[];

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _data.customerScheduleSlotsStream(),
              builder: (context, slotsSnap) {
                try {
                  if (slotsSnap.hasError) {
                    return const DomlyShell(
                      bottomNavigationBar: DomlyClientBottomNav(
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
                  if (profileSnap.connectionState == ConnectionState.waiting &&
                      !profileSnap.hasData &&
                      subscriptionsSnap.connectionState ==
                          ConnectionState.waiting &&
                      !subscriptionsSnap.hasData &&
                      slotsSnap.connectionState == ConnectionState.waiting &&
                      !slotsSnap.hasData) {
                    return const DomlyShell(
                      bottomNavigationBar: DomlyClientBottomNav(
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
                  final slots = List<Map<String, dynamic>>.from(
                    slotsSnap.data ?? [],
                  );
                  slots.sort(
                    (a, b) => _slotMoment(a).compareTo(_slotMoment(b)),
                  );
                  final activeSubscription = _selectActiveSubscription(
                    subscriptions,
                    slots,
                  );
                  final schedulingSubscription = _selectSchedulingSubscription(
                    subscriptions,
                    slots,
                  );
                  final upcoming = _homeVisibleSlots(slots);

                  final recentHistory = slots
                      .where((slot) => !_isCanceledSlot(slot))
                      .toList()
                      .reversed
                      .take(2)
                      .toList();
                  final houseId = (profile['houseId'] ?? '').toString().trim();
                  final houseStatus = (profile['houseStatus'] ?? '')
                      .toString()
                      .trim()
                      .toUpperCase();
                  final showHouseWaitlistHome = isAuthenticated &&
                      houseId.isNotEmpty &&
                      houseStatus.isNotEmpty &&
                      houseStatus != 'ACTIVE';
                  final userName =
                      isAuthenticated ? _profileDisplayName(profile) : 'Гость';
                  final planName = isAuthenticated
                      ? (activeSubscription?['package'] ??
                              activeSubscription?['frequencyLabel'] ??
                              profile['planName'] ??
                              'Нет подписки')
                          .toString()
                      : 'Войдите в аккаунт';
                  final upcomingSlot = _homePrimarySlot(upcoming);

                  if (_useFigmaHomeDesign()) {
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _data.customerOrdersStream(),
                      builder: (context, ordersSnap) {
                        final orders = List<Map<String, dynamic>>.from(
                          ordersSnap.data ?? const [],
                        );
                        final orderIdsWithSelectedSlots = slots
                            .map(
                              (slot) => (slot['sourceOrderId'] ??
                                      slot['customerOrderId'] ??
                                      '')
                                  .toString()
                                  .trim(),
                            )
                            .where((id) => id.isNotEmpty)
                            .toSet();
                        final pendingHomeOrder = _selectPendingHomeOrder(
                          orders,
                          hiddenOrderIds: orderIdsWithSelectedSlots,
                        );
                        final effectivePlanName = isAuthenticated
                            ? (activeSubscription?['package'] ??
                                    activeSubscription?['frequencyLabel'] ??
                                    pendingHomeOrder?['package'] ??
                                    pendingHomeOrder?['frequencyLabel'] ??
                                    profile['planName'] ??
                                    'Нет подписки')
                                .toString()
                            : 'Войдите в аккаунт';
                        final hasPendingDateSelection =
                            _aggregateAvailableSelections(
                                  subscriptions,
                                  slots,
                                ) >
                                0;
                        if (upcomingSlot != null) {
                          return _buildFigmaHomeShell(
                            context: context,
                            profile: profile,
                            activeSubscription: activeSubscription,
                            schedulingSubscription: schedulingSubscription,
                            allSubscriptions: subscriptions,
                            slots: slots,
                            upcomingSlot: upcomingSlot,
                            userName: userName,
                            planName: effectivePlanName,
                          );
                        }
                        if (hasPendingDateSelection &&
                            activeSubscription != null) {
                          return _buildFigmaPendingOrderShell(
                            context: context,
                            profile: profile,
                            activeSubscription: activeSubscription,
                            schedulingSubscription: schedulingSubscription,
                            allSubscriptions: subscriptions,
                            slots: slots,
                            order: {
                              'id': activeSubscription['sourceOrderId'] ??
                                  activeSubscription['id'],
                              'paymentStatus': 'paid',
                              'orderStatus': 'pending_assignment',
                              'area': activeSubscription['area'],
                              'package': activeSubscription['package'],
                              'frequencyLabel':
                                  activeSubscription['frequencyLabel'],
                              'address': activeSubscription['address'],
                            },
                            userName: userName,
                            planName: effectivePlanName,
                          );
                        }
                        if (pendingHomeOrder != null) {
                          return _buildFigmaPendingOrderShell(
                            context: context,
                            profile: profile,
                            activeSubscription: activeSubscription,
                            schedulingSubscription: schedulingSubscription,
                            allSubscriptions: subscriptions,
                            slots: slots,
                            order: pendingHomeOrder,
                            userName: userName,
                            planName: effectivePlanName,
                          );
                        }
                        return _buildFigmaHomeEmptyShell(
                          context: context,
                          userName: userName,
                          profile: profile,
                        );
                      },
                    );
                  }

                  return DomlyShell(
                    bottomNavigationBar: const DomlyClientBottomNav(
                      currentIndex: 0,
                    ),
                    child: SafeArea(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: DomlyHeader(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                20,
                                64,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                    userName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _videoActionButton(),
                                      const SizedBox(width: 8),
                                      _notificationsActionButton(),
                                      const SizedBox(width: 8),
                                      domlyTopIconButton(
                                        icon: Icons.person_outline,
                                        onPressed: () => _runProtectedAction(
                                          () => Navigator.pushNamed(
                                            context,
                                            '/client/profile',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isAuthenticated) ...[
                                    const SizedBox(height: 18),
                                    Transform.translate(
                                      offset: const Offset(0, 40),
                                      child: showHouseWaitlistHome
                                          ? _houseStatusSection(
                                              context,
                                              houseId,
                                            )
                                          : DomlyCard(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'Следующая уборка'
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
                                                              upcomingSlot !=
                                                                      null
                                                                  ? domlyDateText(
                                                                      _slotDate(
                                                                        upcomingSlot,
                                                                      ),
                                                                    )
                                                                  : 'Не запланировано',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: DomlyColors
                                                                    .foreground,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      DomlyStatusChip(
                                                        color: DomlyColors
                                                            .buttonPrimary,
                                                        label: upcomingSlot ==
                                                                null
                                                            ? 'Ожидание'
                                                            : _slotStatusText(
                                                                upcomingSlot[
                                                                        'status']
                                                                    .toString(),
                                                              ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: _metaBlock(
                                                          icon:
                                                              Icons.access_time,
                                                          title: 'Время',
                                                          value: (upcomingSlot?[
                                                                      'time'] ??
                                                                  '10:00 - 13:00')
                                                              .toString(),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: _metaBlock(
                                                          icon:
                                                              Icons.straighten,
                                                          title: 'Площадь',
                                                          value:
                                                              '${profile['area'] ?? upcomingSlot?['area'] ?? '—'} м²',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Container(
                                                    height: 1,
                                                    color: DomlyColors.border,
                                                  ),
                                                  const SizedBox(height: 14),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Container(
                                                        width: 42,
                                                        height: 42,
                                                        decoration:
                                                            const BoxDecoration(
                                                          gradient:
                                                              LinearGradient(
                                                            colors: [
                                                              DomlyColors
                                                                  .buttonPrimary,
                                                              DomlyColors
                                                                  .buttonAccent,
                                                            ],
                                                          ),
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                          _cleanerInitials(
                                                            upcomingSlot?[
                                                                        'cleanerName']
                                                                    ?.toString() ??
                                                                'DP',
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w700,
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
                                                              (upcomingSlot?[
                                                                          'cleanerName'] ??
                                                                      'Исполнитель будет назначен')
                                                                  .toString(),
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: DomlyColors
                                                                    .foreground,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              planName,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    DomlyColors
                                                                        .muted,
                                                              ),
                                                            ),
                                                            if (activeSubscription !=
                                                                null)
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  top: 2,
                                                                ),
                                                                child: Text(
                                                                  _subscriptionUsageSummary(
                                                                    activeSubscription,
                                                                    slots:
                                                                        slots,
                                                                  ),
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: DomlyColors
                                                                        .muted,
                                                                  ),
                                                                ),
                                                              ),
                                                            if (activeSubscription !=
                                                                    null &&
                                                                _canSelectMoreDates(
                                                                  activeSubscription,
                                                                  slots,
                                                                )) ...[
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              InkWell(
                                                                onTap: () =>
                                                                    _runProtectedAction(
                                                                  () => Navigator
                                                                      .pushNamed(
                                                                    context,
                                                                    '/client/package-calendar',
                                                                    arguments: {
                                                                      'subscriptionId':
                                                                          activeSubscription[
                                                                              'id'],
                                                                    },
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  'Выбрать даты'
                                                                      .tr(),
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        15,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: DomlyColors
                                                                        .primary,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          14,
                                                        ),
                                                        onTap: () =>
                                                            _runProtectedAction(
                                                          () => Navigator
                                                              .pushNamed(
                                                            context,
                                                            '/client/orders',
                                                          ),
                                                        ),
                                                        child: Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                            horizontal: 10,
                                                            vertical: 8,
                                                          ),
                                                          child: Text(
                                                            'Детали'.tr(),
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: DomlyColors
                                                                  .buttonPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (activeSubscription !=
                                                          null &&
                                                      _canSelectMoreDates(
                                                        activeSubscription,
                                                        slots,
                                                      )) ...[
                                                    const SizedBox(height: 16),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: DomlyPrimaryButton(
                                                        label:
                                                            'Заказать уборку',
                                                        icon: Icons
                                                            .cleaning_services,
                                                        onPressed: () =>
                                                            _runProtectedAction(
                                                          () =>
                                                              _showBookingSheet(
                                                            activeSubscription,
                                                            profile,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(height: isAuthenticated ? 44 : 8),
                          ),
                          if (isAuthenticated)
                            const SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              sliver: SliverToBoxAdapter(
                                child: _PromoBannersSection(),
                              ),
                            ),
                          if (isAuthenticated)
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 16),
                            ),
                          if (isAuthenticated &&
                              _pendingConnectionAddresses(profile).isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: _addressSwitcherCard(profile),
                              ),
                            ),
                          if (isAuthenticated &&
                              _pendingConnectionAddresses(profile).isNotEmpty)
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 18),
                            ),
                          if (isAuthenticated &&
                              (profile['houseId'] ?? '')
                                  .toString()
                                  .isNotEmpty &&
                              !showHouseWaitlistHome)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: _houseStatusSection(
                                  context,
                                  profile['houseId'].toString(),
                                ),
                              ),
                            ),
                          if (isAuthenticated &&
                              (profile['houseId'] ?? '')
                                  .toString()
                                  .isNotEmpty &&
                              !showHouseWaitlistHome)
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 18),
                            ),
                          if (isAuthenticated)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _quickActionCard(
                                        title: 'Выбрать пакет',
                                        subtitle: 'Подобрать подписку',
                                        icon: Icons.inventory_2_outlined,
                                        reverse: false,
                                        onTap: _showHomePackagePicker,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _quickActionCard(
                                        title: 'Калькулятор',
                                        subtitle: 'Рассчитать стоимость',
                                        icon: Icons.calculate_outlined,
                                        reverse: true,
                                        onTap: () => Navigator.pushNamed(
                                          context,
                                          '/client/calculator',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: DomlyPrimaryButton(
                                        label: 'Подобрать подписку',
                                        onPressed: () => _runProtectedAction(
                                          _showHomePackagePicker,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'У Вас нет активной подписки'.tr(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: DomlyColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Оформите ее, чтобы начать пользоваться сервисом'
                                          .tr(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: DomlyColors.muted,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (isAuthenticated)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      '/client/bonus',
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 20,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFFD700),
                                            Color(0xFFFFA500),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x33FFA500),
                                            blurRadius: 12,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.card_giftcard,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                          SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Получи бонусы'.tr(),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Приглашай друзей — получай 2000₸ за каждого'
                                                      .tr(),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xCCFFFFFF),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (isAuthenticated)
                            const SliverPadding(
                              padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                              sliver: SliverToBoxAdapter(
                                child: _CompanyPromotionsSection(),
                              ),
                            ),
                          if (isAuthenticated) ...[
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 28),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: DomlySectionTitle(
                                  title: 'Последние заказы',
                                  actionLabel: 'Все',
                                  onAction: () => _runProtectedAction(
                                    () => Navigator.pushNamed(
                                      context,
                                      '/client/orders',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 12),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: recentHistory.isEmpty
                                  ? const SliverToBoxAdapter(
                                      child: DomlyEmptyStateCard(
                                        title: 'История пока пуста',
                                        subtitle:
                                            'После первой завершенной уборки здесь появятся последние заказы.',
                                        icon: Icons.receipt_long_outlined,
                                      ),
                                    )
                                  : SliverList(
                                      delegate: SliverChildBuilderDelegate((
                                        context,
                                        index,
                                      ) {
                                        final order = recentHistory[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
                                          child: _recentOrderCard(
                                            order,
                                            onTap: () => _runProtectedAction(
                                              () => Navigator.pushNamed(
                                                context,
                                                '/client/orders',
                                              ),
                                            ),
                                          ),
                                        );
                                      }, childCount: recentHistory.length),
                                    ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 96)),
                        ],
                      ),
                    ),
                  );
                } catch (error, stackTrace) {
                  AppLogger.e(
                    'HOME',
                    'Client home build failed',
                    error,
                    stackTrace,
                  );
                  return DomlyShell(
                    bottomNavigationBar: const DomlyClientBottomNav(
                      currentIndex: 0,
                    ),
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const DomlyEmptyStateCard(
                                title: 'Не удалось открыть главный экран',
                                subtitle: 'Обновите экран и попробуйте снова.',
                                icon: Icons.error_outline,
                              ),
                              if (kDebugMode || DebugSession.enabled)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: SelectableText(
                                    error.toString(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: DomlyColors.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  bool _useFigmaHomeDesign() => true;

  void _openFocusedClientOrder(Map<String, dynamic> item) {
    final focusOrderId = _homeFocusOrderId(item);
    Navigator.pushNamed(
      context,
      '/client/orders',
      arguments: {
        'initialTab': 'active',
        if (focusOrderId.isNotEmpty) 'focusOrderId': focusOrderId,
      },
    );
  }

  String _homeFocusOrderId(Map<String, dynamic> item) {
    for (final key in const [
      'scheduleSlotId',
      'slotId',
      'id',
      'chatId',
      'sourceOrderId',
      'customerOrderId',
      'orderId',
      'paymentId',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  Widget _buildFigmaHomeShell({
    required BuildContext context,
    required Map<String, dynamic> profile,
    required Map<String, dynamic>? activeSubscription,
    required Map<String, dynamic>? schedulingSubscription,
    required List<Map<String, dynamic>> allSubscriptions,
    required List<Map<String, dynamic>> slots,
    required Map<String, dynamic>? upcomingSlot,
    required String userName,
    required String planName,
  }) {
    if (upcomingSlot == null) {
      return _buildFigmaHomeEmptyShell(
        context: context,
        userName: userName,
        profile: profile,
      );
    }

    final dateText = domlyDateText(_slotDate(upcomingSlot));
    final statusText = _slotStatusText(
      (upcomingSlot['status'] ?? '').toString(),
    );
    final timeText = (upcomingSlot['time'] ?? '09:00 - 12:27').toString();
    final area = profile['area'] ?? upcomingSlot['area'] ?? 100;
    final cleanerName = _slotCleanerDisplayName(upcomingSlot);
    final totalVisits = _aggregateIncludedVisits(allSubscriptions);
    final availableSelections = _aggregateAvailableSelections(
      allSubscriptions,
      slots,
    );
    final used = _aggregateUsedVisits(allSubscriptions, slots);
    final canSelectDates = availableSelections > 0;
    final primaryActionLabel =
        canSelectDates ? 'Заказать уборку' : 'Выбрать пакет';
    void primaryAction() {
      _runProtectedAction(() {
        if (canSelectDates) {
          _openHomeCleaningOrder(
            activeSubscription: activeSubscription,
            subscriptionId: schedulingSubscription?['id']?.toString() ??
                activeSubscription?['id']?.toString(),
            canSelectDates: canSelectDates,
          );
          return;
        }
        _showHomePackagePicker();
      });
    }

    final isCurrentCleaning = _isInProgressSlot(upcomingSlot);
    final canCancelCleaning = !isCurrentCleaning &&
        _canCustomerCancelSlot((upcomingSlot['status'] ?? '').toString());

    return DomlyShell(
      bottomNavigationBar: const _FigmaClientBottomNav(currentIndex: 0),
      child: Container(
        color: const Color(0xFFFBFDF9),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FigmaHomeHero(
                  key: DomlyTutorialTargets.clientHomeTop,
                  userName: userName,
                ),
                if (_pendingConnectionAddresses(profile).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _addressSwitcherCard(profile),
                  ),
                ],
                const SizedBox(height: 12),
                const _PromoBannersSection(),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCurrentCleaning
                            ? 'Текущая уборка'
                            : 'Следующая уборка',
                        style: const TextStyle(
                          color: Color(0xFF658170),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 19 / 14,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dateText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF2B4338),
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                                height: 38 / 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _FigmaStatusPill(label: statusText),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 19),
                _FigmaNextCleaningCard(
                  onTap: () => _runProtectedAction(
                    () => _openFocusedClientOrder(upcomingSlot),
                  ),
                  timeText: timeText,
                  areaText: '$area м²',
                  cleanerName: cleanerName,
                  planName: planName,
                  totalVisits: totalVisits,
                  availableSelections: availableSelections,
                  used: used,
                  showUsageStats: true,
                  onSelectDates: isCurrentCleaning || !canSelectDates
                      ? null
                      : () => _runProtectedAction(
                            () => Navigator.pushNamed(
                              context,
                              '/client/package-calendar',
                              arguments: {
                                'subscriptionId':
                                    schedulingSubscription?['id'] ??
                                        activeSubscription!['id'],
                              },
                            ),
                          ),
                  onDetails: () => _runProtectedAction(
                    () => _openFocusedClientOrder(upcomingSlot),
                  ),
                  onCancel: canCancelCleaning
                      ? () => _runProtectedAction(
                            () => _cancelScheduledCleaning(upcomingSlot),
                          )
                      : null,
                ),
                const SizedBox(height: 12),
                _FigmaPrimaryHomeButton(
                  key: DomlyTutorialTargets.clientOrderButton,
                  label: primaryActionLabel,
                  onPressed: primaryAction,
                ),
                const SizedBox(height: 10),
                _prelaunchBookingButton(),
                const SizedBox(height: 14),
                const _CompanyPromotionsSection(),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: DomlyTutorialTargets.clientPackageActions,
                  child: Row(
                    children: [
                      Expanded(
                        child: _FigmaHomeAction(
                          caption: 'Готовые решения\nна любой случай',
                          label: 'Выбрать пакет',
                          icon: Icons.shopping_bag_outlined,
                          onTap: () =>
                              _runProtectedAction(_showHomePackagePicker),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FigmaHomeAction(
                          caption: 'Рассчитай стоимость\nза пару шагов',
                          label: 'Калькулятор',
                          icon: Icons.calculate_outlined,
                          onTap: () => _runProtectedAction(
                            () => Navigator.pushNamed(
                              context,
                              '/client/calculator',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _figmaBonusBanner(context),
                const SizedBox(height: 88),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFigmaHomeEmptyShell({
    required BuildContext context,
    required String userName,
    required Map<String, dynamic> profile,
  }) {
    final houseId = (profile['houseId'] ?? '').toString().trim();
    final houseStatus =
        (profile['houseStatus'] ?? '').toString().trim().toUpperCase();
    final showHouseWaitlistHome =
        houseId.isNotEmpty && houseStatus.isNotEmpty && houseStatus != 'ACTIVE';
    return DomlyShell(
      bottomNavigationBar: const _FigmaClientBottomNav(currentIndex: 0),
      child: Container(
        color: const Color(0xFFFBFDF9),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FigmaHomeHero(
                  key: DomlyTutorialTargets.clientHomeTop,
                  userName: userName,
                ),
                if (_pendingConnectionAddresses(profile).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _addressSwitcherCard(profile),
                  ),
                ],
                const SizedBox(height: 12),
                const _PromoBannersSection(),
                const SizedBox(height: 24),
                if (showHouseWaitlistHome) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _houseStatusSection(context, houseId),
                  ),
                ] else ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 34),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Следующая уборка'.tr(),
                          style: TextStyle(
                            color: Color(0xFF658170),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 19 / 14,
                          ),
                        ),
                        SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Не запланировано'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFF2B4338),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 38 / 16,
                                ),
                              ),
                            ),
                            SizedBox(width: 14),
                            _FigmaStatusPill(label: 'Ожидание', muted: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 19),
                  _FigmaEmptyCleaningCard(
                    onTap: () => _runProtectedAction(_showHomePackagePicker),
                  ),
                  const SizedBox(height: 14),
                  _FigmaPrimaryHomeButton(
                    key: DomlyTutorialTargets.clientOrderButton,
                    label: 'Подобрать подписку',
                    onPressed: () =>
                        _runProtectedAction(_showHomePackagePicker),
                  ),
                  const SizedBox(height: 10),
                  _prelaunchBookingButton(),
                  const SizedBox(height: 14),
                  const _CompanyPromotionsSection(),
                  const SizedBox(height: 14),
                  KeyedSubtree(
                    key: DomlyTutorialTargets.clientPackageActions,
                    child: Row(
                      children: [
                        Expanded(
                          child: _FigmaHomeAction(
                            caption: 'Готовые решения\nна любой случай',
                            label: 'Выбрать пакет',
                            icon: Icons.shopping_bag_outlined,
                            onTap: () =>
                                _runProtectedAction(_showHomePackagePicker),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FigmaHomeAction(
                            caption: 'Рассчитай стоимость\nза пару шагов',
                            label: 'Калькулятор',
                            icon: Icons.calculate_outlined,
                            onTap: () => _runProtectedAction(
                              () => Navigator.pushNamed(
                                context,
                                '/client/calculator',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  Padding(
                    padding: const EdgeInsets.only(left: 33, right: 33),
                    child: Text(
                      'У Вас нет активной подписки\n'
                              'Оформите ее, чтобы начать пользоваться сервисом'
                          .tr(),
                      style: const TextStyle(
                        color: Color(0xFF658170),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 18 / 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 20),
                _figmaBonusBanner(context),
                const SizedBox(height: 88),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFigmaPendingOrderShell({
    required BuildContext context,
    required Map<String, dynamic> profile,
    required Map<String, dynamic>? activeSubscription,
    required Map<String, dynamic>? schedulingSubscription,
    required List<Map<String, dynamic>> allSubscriptions,
    required List<Map<String, dynamic>> slots,
    required Map<String, dynamic> order,
    required String userName,
    required String planName,
  }) {
    final area = profile['area'] ?? order['area'] ?? 100;
    final statusText = _homeOrderStatusText(order);
    final subtitle = _homeOrderSubtitle(order);
    final orderId = (order['id'] ?? order['orderId'] ?? '').toString().trim();
    final orderSubscriptionId =
        (order['subscriptionId'] ?? '').toString().trim();
    final calendarSubscriptionId = schedulingSubscription?['id']?.toString() ??
        activeSubscription?['id']?.toString() ??
        (orderSubscriptionId.isNotEmpty ? orderSubscriptionId : orderId);
    final pendingSelections = _aggregateAvailableSelections(
      allSubscriptions,
      slots,
    );
    final canSelectDates =
        calendarSubscriptionId.isNotEmpty && pendingSelections > 0;
    void scheduleAction() {
      _runProtectedAction(
        () => _openHomeCleaningOrder(
          activeSubscription: activeSubscription,
          subscriptionId: calendarSubscriptionId,
          canSelectDates: canSelectDates,
        ),
      );
    }

    void primaryAction() {
      if (canSelectDates) {
        scheduleAction();
        return;
      }
      _runProtectedAction(_showHomePackagePicker);
    }

    final actionLabel = canSelectDates ? 'Заказать уборку' : 'Выбрать пакет';
    final timeText = canSelectDates ? 'Выберите дату и время' : subtitle;
    final cleanerText = canSelectDates
        ? 'Исполнитель после выбора даты'
        : 'Исполнитель будет назначен';
    final totalVisits = _aggregateIncludedVisits(allSubscriptions);
    final usedSelections = _aggregateUsedVisits(allSubscriptions, slots);

    return DomlyShell(
      bottomNavigationBar: const _FigmaClientBottomNav(currentIndex: 0),
      child: Container(
        color: const Color(0xFFFBFDF9),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FigmaHomeHero(
                  key: DomlyTutorialTargets.clientHomeTop,
                  userName: userName,
                ),
                if (_pendingConnectionAddresses(profile).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _addressSwitcherCard(profile),
                  ),
                ],
                const SizedBox(height: 12),
                const _PromoBannersSection(),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Следующая уборка'.tr(),
                        style: TextStyle(
                          color: Color(0xFF658170),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 19 / 14,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              canSelectDates
                                  ? 'Выберите\nвремя'
                                  : 'Ожидает назначения',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF2B4338),
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 28 / 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _FigmaStatusPill(label: statusText),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 19),
                _FigmaNextCleaningCard(
                  onTap: canSelectDates
                      ? scheduleAction
                      : () => _runProtectedAction(
                            () => _openFocusedClientOrder(order),
                          ),
                  timeText: timeText,
                  areaText: '$area м²',
                  cleanerName: cleanerText,
                  planName: planName,
                  totalVisits: totalVisits,
                  availableSelections: pendingSelections,
                  used: usedSelections,
                  showUsageStats: true,
                  onSelectDates: canSelectDates ? scheduleAction : null,
                  onDetails: () =>
                      _runProtectedAction(() => _openFocusedClientOrder(order)),
                  onCancel: null,
                ),
                const SizedBox(height: 12),
                _FigmaPrimaryHomeButton(
                  key: DomlyTutorialTargets.clientOrderButton,
                  label: actionLabel,
                  onPressed: primaryAction,
                ),
                const SizedBox(height: 10),
                _prelaunchBookingButton(),
                const SizedBox(height: 14),
                const _CompanyPromotionsSection(),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: DomlyTutorialTargets.clientPackageActions,
                  child: Row(
                    children: [
                      Expanded(
                        child: _FigmaHomeAction(
                          caption: 'Готовые решения\nна любой случай',
                          label: 'Выбрать пакет',
                          icon: Icons.shopping_bag_outlined,
                          onTap: () =>
                              _runProtectedAction(_showHomePackagePicker),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FigmaHomeAction(
                          caption: 'Рассчитай стоимость\nза пару шагов',
                          label: 'Калькулятор',
                          icon: Icons.calculate_outlined,
                          onTap: () => _runProtectedAction(
                            () => Navigator.pushNamed(
                              context,
                              '/client/calculator',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _figmaBonusBanner(context),
                const SizedBox(height: 88),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _figmaBonusBanner(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _runProtectedAction(
          () => Navigator.pushNamed(context, '/client/bonus'),
        ),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFE3F1DF), Color(0xFFF8F0CC)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Получи бонусы'.tr(),
                      style: TextStyle(
                        color: Color(0xFF143E21),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 28 / 22,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Приглашай друзей — получай 2000₸\nза каждого'.tr(),
                      style: TextStyle(
                        color: Color(0xFF143E21),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 18 / 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 14,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_forward,
                  color: Color(0xFF143E21),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _houseStatusSection(BuildContext context, String houseId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _data.getHouseStats(houseId: houseId),
      builder: (context, statsSnap) {
        if (statsSnap.connectionState == ConnectionState.waiting &&
            !statsSnap.hasData) {
          return const DomlyCard(
            child: SizedBox(
              height: 168,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      DomlyColors.buttonPrimary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        final stats = statsSnap.data;
        if (stats == null) {
          return DomlyCard(
            child: Text(
              'Не удалось загрузить информацию по дому.'.tr(),
              style: TextStyle(color: DomlyColors.muted),
            ),
          );
        }
        final house = Map<String, dynamic>.from(stats['house'] as Map? ?? {});
        final status = (house['status'] ?? 'INACTIVE').toString().toUpperCase();
        final threshold = (house['threshold'] as num?)?.toInt() ?? 20;
        final current = (house['current_users'] as num?)?.toInt() ?? 0;
        final progress = (stats['progress'] as num?)?.toDouble() ?? 0;
        final remaining = (stats['remaining'] as num?)?.toInt() ?? 0;
        final packageBreakdown = Map<String, dynamic>.from(
          stats['packageBreakdown'] as Map? ?? {},
        );

        return StreamBuilder<Map<String, dynamic>?>(
          stream: _data.referralStatsStream(),
          builder: (context, referralSnap) {
            final referralStats =
                referralSnap.data ?? const <String, dynamic>{};
            final invited = (referralStats['invited'] as num?)?.toInt() ?? 0;
            final paid = (referralStats['paid'] as num?)?.toInt() ?? 0;
            return DomlyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status == 'ACTIVE'
                            ? 'Дом подключен'
                            : status == 'IN_PROGRESS'
                                ? 'Дом почти подключен'
                                : 'Мы скоро стартуем в вашем доме',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DomlyStatusChip(
                        label: status == 'ACTIVE'
                            ? 'Активен'
                            : status == 'IN_PROGRESS'
                                ? 'Подключается'
                                : 'Ожидание',
                        color: status == 'ACTIVE'
                            ? DomlyColors.primary
                            : const Color(0xFFFF9800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text((house['address'] ?? houseId).toString()),
                  const SizedBox(height: 10),
                  Text(
                    (stats['activationText'] ?? '').toString(),
                    style: const TextStyle(color: DomlyColors.muted),
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: DomlyColors.backgroundSoft,
                    color: DomlyColors.buttonPrimary,
                  ),
                  const SizedBox(height: 10),
                  Text('Заявок: $current из $threshold'.tr()),
                  Text('До запуска осталось: $remaining'.tr()),
                  if (status == 'ACTIVE')
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Пользователей: ${house['total_users'] ?? 0}'),
                          Text(
                            'Популярный пакет: ${stats['popularPackage'] ?? '—'}',
                          ),
                          if (packageBreakdown.isNotEmpty)
                            Text(
                              'Пакеты: ${packageBreakdown.entries.map((e) => '.tr()${e.key}: ${e.value}').join(' · ')}',
                              style: const TextStyle(color: DomlyColors.muted),
                            ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _statLine('Приглашено вами', '$invited'),
                          const SizedBox(height: 6),
                          _statLine('Оплатили пакет', '$paid'),
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: DomlyPrimaryButton(
                                  label: 'Оставить заявку',
                                  onPressed: () => Navigator.pushNamed(
                                    context,
                                    '/client/house-waitlist',
                                    arguments: {'houseId': houseId},
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: DomlySecondaryButton(
                                  label: 'Пригласить соседей',
                                  onPressed: () =>
                                      _shareNeighborInvite(houseId),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DomlySecondaryButton(
                            label: 'Карта покрытия',
                            onPressed: () =>
                                Navigator.pushNamed(context, '/map/clusters'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statLine(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
      ],
    );
  }

  Future<void> _shareNeighborInvite(String houseId) async {
    await _runProtectedAction(() async {
      final invite = await _data.ensureReferralLink();
      final referralCode = (invite['referralCode'] ?? '').toString().trim();
      final referralLink = (invite['referralLink'] ?? '').toString().trim();
      final shareText = StringBuffer('Подключай DOMLY в наш дом. ')
        ..write('Открой веб-версию приложения: $referralLink');
      if (referralCode.isNotEmpty) {
        shareText.write(' Используй мой код: $referralCode');
      }
      await Share.share(shareText.toString(), subject: 'Приглашение в DOMLY');
    });
  }

  Widget _metaBlock({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: DomlyColors.buttonPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: DomlyColors.buttonPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: DomlyColors.muted),
              ),
              Text(
                value,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DomlyColors.foreground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required bool reverse,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: DomlyCard(
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              Positioned(
                top: -16,
                right: -10,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: (reverse ? DomlyColors.accent : DomlyColors.primary)
                        .withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DomlyIconBadge(
                    size: 44,
                    icon: icon,
                    colors: reverse
                        ? const [
                            DomlyColors.buttonAccent,
                            DomlyColors.buttonPrimary,
                          ]
                        : const [
                            DomlyColors.buttonPrimary,
                            DomlyColors.buttonAccent,
                          ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DomlyColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentOrderCard(Map<String, dynamic> order, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: DomlyColors.buttonPrimary.withValues(alpha: 0.10),
        highlightColor: DomlyColors.buttonPrimary.withValues(alpha: 0.05),
        child: DomlyCard(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          domlyDateText(_slotDate(order)),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (order['time'] ?? '10:00').toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: DomlyColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  DomlyStatusChip(
                    label: _slotStatusText((order['status'] ?? '').toString()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          DomlyColors.buttonPrimary,
                          DomlyColors.buttonAccent,
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _cleanerInitials(
                        (order['cleanerName'] ?? order['cleaner'] ?? 'DP')
                            .toString(),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (order['cleanerName'] ??
                                  order['cleaner'] ??
                                  'Исполнитель будет назначен')
                              .toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (order['residentialComplex'] ??
                                  order['address'] ??
                                  'Адрес будет уточнен')
                              .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DomlyColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (((order['price'] as num?)?.toInt() ?? 0) > 0)
                        Text(
                          '${order['price']} ₸',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                      if (onTap != null)
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: DomlyColors.buttonPrimary,
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runProtectedAction(VoidCallback action) async {
    final authorized = await AuthGate.ensureAuthorized(context);
    if (!mounted || !authorized) {
      return;
    }
    action();
  }

  Widget _prelaunchBookingButton() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.customerPrelaunchBookingsStream(),
      builder: (context, prelaunchSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.customerSubscriptionsStream(),
          builder: (context, subscriptionsSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _data.customerOrdersStream(),
              builder: (context, ordersSnapshot) {
                final hasPrelaunch = _hasActivePrelaunchBooking(
                  prelaunchSnapshot.data,
                );
                final hasPackage = _hasAnyPackagePurchase(
                  subscriptionsSnapshot.data,
                  ordersSnapshot.data,
                );
                if (hasPrelaunch || hasPackage) {
                  return const SizedBox.shrink();
                }
                return _FigmaSecondaryHomeButton(
                  key: DomlyTutorialTargets.clientPrelaunchButton,
                  label: 'Предварительная запись',
                  icon: Icons.event_available_outlined,
                  onPressed: () => _runProtectedAction(() {
                    unawaited(_showPrelaunchBookingDialog());
                  }),
                );
              },
            );
          },
        );
      },
    );
  }

  bool _hasActivePrelaunchBooking(List<Map<String, dynamic>>? rows) {
    return (rows ?? const <Map<String, dynamic>>[]).any((item) {
      final status = (item['status'] ?? item['orderStatus'] ?? '')
          .toString()
          .toLowerCase();
      return !{'canceled', 'cancelled', 'rejected', 'deleted'}.contains(status);
    });
  }

  bool _hasAnyPackagePurchase(
    List<Map<String, dynamic>>? subscriptions,
    List<Map<String, dynamic>>? orders,
  ) {
    if ((subscriptions ?? const <Map<String, dynamic>>[]).any((item) {
      final status = (item['status'] ?? item['subscriptionStatus'] ?? '')
          .toString()
          .toLowerCase();
      final paymentStatus =
          (item['paymentStatus'] ?? '').toString().toLowerCase();
      return !{
            'canceled',
            'cancelled',
            'deleted',
            'expired',
          }.contains(status) ||
          paymentStatus == 'paid';
    })) {
      return true;
    }
    return (orders ?? const <Map<String, dynamic>>[]).any((item) {
      final packageId = (item['packageId'] ?? '').toString().trim();
      final packageName = (item['package'] ?? '').toString().trim();
      final type = (item['type'] ?? '').toString().toLowerCase();
      final status = (item['status'] ?? item['orderStatus'] ?? '')
          .toString()
          .toLowerCase();
      final isPackage = packageId.isNotEmpty ||
          type.contains('package') ||
          (packageName.isNotEmpty &&
              !packageName.toLowerCase().contains('доп. услуг'));
      return isPackage &&
          !{'canceled', 'cancelled', 'rejected', 'deleted'}.contains(status);
    });
  }

  Future<void> _showPrelaunchBookingDialog() async {
    final profile = await _data.customerProfileStream().first;
    if (!mounted) {
      return;
    }
    final nameController = TextEditingController(
      text: _firstNonEmpty([profile?['name'], profile?['fullName']]),
    );
    final phoneController = TextEditingController(
      text: _firstNonEmpty([profile?['phone'], profile?['phoneNumber']]),
    );
    final areaController = TextEditingController(
      text: _firstNonEmpty([profile?['area'], profile?['apartmentArea']]),
    );
    final formKey = GlobalKey<FormState>();
    const timeOptions = [
      '09:00 - 12:00',
      '12:00 - 15:00',
      '15:00 - 18:00',
      '18:00 - 21:00',
    ];
    final today = DateTime.now();
    final prelaunchStartDate = LaunchConfig.bookingStartDate;
    var selectedDate = LaunchConfig.nextBookingDate(today);
    var selectedTime = timeOptions.first;
    var saving = false;

    String dateText(DateTime date) {
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(date.day)}.${two(date.month)}.${date.year}';
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (saving || !(formKey.currentState?.validate() ?? false)) {
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              setDialogState(() => saving = true);
              try {
                final area = _parseAreaForRequest(areaController.text);
                if (area == null) {
                  throw 'Введите площадь';
                }
                await _data.createPrelaunchBookingRequest(
                  name: nameController.text,
                  phone: phoneController.text,
                  area: area,
                  desiredDate: selectedDate,
                  preferredTime: selectedTime,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  final selectedDateText = dateText(selectedDate);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Предварительная запись сохранена на $selectedDateText. Мы напишем для подтверждения информации и оплаты.'
                            .tr(),
                      ),
                    ),
                  );
                }
              } catch (error) {
                if (!context.mounted) {
                  return;
                }
                setDialogState(() => saving = false);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Не удалось сохранить запись: $error'.tr()),
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text('Предварительная запись'.tr()),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'До запуска оплата не требуется. Оставьте данные, выберите дату, и мы напишем для подтверждения информации.'
                            .tr(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Имя'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Введите имя'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Телефон',
                          hintText: '+7 777 000 00 00',
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 6
                                ? 'Введите телефон'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: areaController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Площадь, м²',
                        ),
                        validator: (value) {
                          final parsed = _parseAreaForRequest(value ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Введите площадь';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: DomlyColors.buttonPrimary.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: DomlyColors.buttonPrimary.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Желаемая дата'.tr(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: DomlyColors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateText(selectedDate),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: DomlyColors.foreground,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: selectedDate,
                                        firstDate: prelaunchStartDate,
                                        lastDate: prelaunchStartDate.add(
                                          const Duration(days: 120),
                                        ),
                                      );
                                      if (picked != null) {
                                        setDialogState(
                                          () => selectedDate = picked,
                                        );
                                      }
                                    },
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                              ),
                              label: Text('Выбрать дату'.tr()),
                            ),
                          ],
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: selectedTime,
                        decoration: const InputDecoration(
                          labelText: 'Удобное время',
                        ),
                        items: [
                          for (final option in timeOptions)
                            DropdownMenuItem(
                              value: option,
                              child: Text(option),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => selectedTime = value);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text('Отмена'.tr()),
                ),
                ElevatedButton(
                  onPressed: saving ? null : submit,
                  child: Text(saving ? 'Сохраняем...' : 'Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    areaController.dispose();
  }

  String _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty &&
          text != 'null' &&
          text.toLowerCase() != 'пользователь') {
        return text;
      }
    }
    return '';
  }

  int? _parseAreaForRequest(String value) {
    final area = double.tryParse(value.trim().replaceAll(',', '.'));
    if (area == null || area <= 0) {
      return null;
    }
    return area.ceil();
  }

  String _slotStatusText(String status) {
    switch (status) {
      case 'assigned':
      case 'confirmed':
      case 'accepted':
      case 'scheduled_confirmed':
        return 'Подтверждено';
      case 'in_progress':
        return 'В процессе';
      case 'completed':
        return 'Выполнено';
      case 'pending':
      case 'pending_assignment':
        return 'Ожидание';
      case 'canceled':
      case 'cancelled':
        return 'Отменено';
      default:
        return orderStatusLabel(status);
    }
  }

  List<Map<String, dynamic>> _homeVisibleSlots(
    List<Map<String, dynamic>> slots,
  ) {
    final visible = slots.where((slot) {
      final date = _slotMoment(slot);
      return date.isAfter(DateTime.now().subtract(const Duration(days: 1))) &&
          !_isCanceledSlot(slot) &&
          (slot['status'] ?? '').toString().toLowerCase() != 'completed';
    }).toList();
    visible.sort((a, b) {
      final priority = _homeSlotPriority(a).compareTo(_homeSlotPriority(b));
      if (priority != 0) {
        return priority;
      }
      return _slotMoment(a).compareTo(_slotMoment(b));
    });
    return visible;
  }

  Map<String, dynamic>? _homePrimarySlot(List<Map<String, dynamic>> slots) {
    if (slots.isEmpty) {
      return null;
    }
    return slots.first;
  }

  int _homeSlotPriority(Map<String, dynamic> slot) {
    if (_isInProgressSlot(slot)) {
      return 0;
    }
    return 1;
  }

  bool _isInProgressSlot(Map<String, dynamic> slot) {
    const activeStatuses = {'in_progress', 'started', 'cleaning'};
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final orderStatus =
        (slot['orderStatus'] ?? '').toString().trim().toLowerCase();
    return activeStatuses.contains(status) ||
        activeStatuses.contains(orderStatus);
  }

  String _slotCleanerDisplayName(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final cleanerName = (slot['cleanerName'] ?? '').toString().trim();
    final assignmentStatus =
        (slot['assignmentStatus'] ?? '').toString().trim().toLowerCase();
    final isConfirmed = status == 'assigned' ||
        status == 'confirmed' ||
        status == 'in_progress' ||
        status == 'completed' ||
        assignmentStatus == 'accepted' ||
        assignmentStatus == 'scheduled_confirmed' ||
        assignmentStatus == 'assigned';
    if (isConfirmed && cleanerName.isNotEmpty) {
      return cleanerName;
    }
    final hasActiveOffer =
        (slot['currentOfferId'] ?? '').toString().trim().isNotEmpty ||
            assignmentStatus == 'offer_pending' ||
            assignmentStatus == 'scheduled_pending_confirmation';
    return hasActiveOffer ? 'Ждем ответ уборщицы' : 'Ищем уборщицу';
  }

  bool _isCanceledSlot(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().toLowerCase();
    final orderStatus = (slot['orderStatus'] ?? '').toString().toLowerCase();
    return status == 'canceled' ||
        status == 'cancelled' ||
        orderStatus == 'canceled' ||
        orderStatus == 'cancelled';
  }

  bool _canCustomerCancelSlot(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending_assignment' ||
        normalized == 'assigned' ||
        normalized == 'confirmed';
  }

  Future<void> _cancelScheduledCleaning(Map<String, dynamic> slot) async {
    final slotId = (slot['id'] ?? slot['slotId'] ?? '').toString().trim();
    if (slotId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не удалось отменить уборку',
        subtitle: 'Не найден номер уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Отменить уборку?'.tr()),
        content: Text(
          'После отмены уборка вернется в доступные, и вы сможете выбрать другую дату и время.'
              .tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Нет'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Да, отменить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final result = await _data.cancelScheduleSlot(slotId: slotId);
      if (!mounted) {
        return;
      }
      final penaltyApplied = result['penaltyApplied'] == true;
      showDomlySnackBar(
        context,
        title: 'Уборка отменена',
        subtitle: penaltyApplied
            ? 'Уборка списана по правилам отмены.'
            : 'Уборка вернулась в доступные.',
        type:
            penaltyApplied ? DomlySnackBarType.info : DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отменить уборку',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  Map<String, dynamic>? _selectPendingHomeOrder(
    List<Map<String, dynamic>> orders, {
    Set<String>? hiddenOrderIds,
  }) {
    final hiddenIds = hiddenOrderIds ?? const <String>{};
    final relevant = orders.where((order) {
      final orderId = (order['id'] ?? order['orderId'] ?? '').toString();
      if (hiddenIds.contains(orderId)) {
        return false;
      }
      final orderStatus = (order['orderStatus'] ?? '').toString().toLowerCase();
      final paymentStatus =
          (order['paymentStatus'] ?? '').toString().toLowerCase();
      final packageId = (order['packageId'] ?? '').toString().toLowerCase();
      final hasSubscription = (order['subscriptionId'] ?? '')
              .toString()
              .trim()
              .isNotEmpty ||
          (order['subscriptionStatus'] ?? '').toString().trim().toLowerCase() ==
              'active';
      if (paymentStatus == 'paid' &&
          orderStatus == 'pending_assignment' &&
          hasSubscription &&
          packageId != 'addons_only') {
        return false;
      }
      return orderStatus == 'pending_assignment' ||
          orderStatus == 'assigned' ||
          paymentStatus == 'paid' ||
          paymentStatus == 'invoice_requested';
    }).toList();
    if (relevant.isEmpty) {
      return null;
    }
    relevant.sort((a, b) => _orderTimestamp(b).compareTo(_orderTimestamp(a)));
    return relevant.first;
  }

  DateTime _orderTimestamp(Map<String, dynamic> order) {
    final value = order['paidAt'] ??
        order['updatedAt'] ??
        order['createdAt'] ??
        order['date'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
  }

  String _homeOrderStatusText(Map<String, dynamic> order) {
    final paymentStatus =
        (order['paymentStatus'] ?? '').toString().toLowerCase();
    final orderStatus = (order['orderStatus'] ?? '').toString().toLowerCase();
    if (paymentStatus == 'paid' && orderStatus == 'pending_assignment') {
      return 'Подтверждено';
    }
    if (paymentStatus == 'invoice_requested') {
      return 'Проверка';
    }
    return _slotStatusText(orderStatus);
  }

  String _homeOrderSubtitle(Map<String, dynamic> order) {
    final paymentStatus =
        (order['paymentStatus'] ?? '').toString().toLowerCase();
    final orderStatus = (order['orderStatus'] ?? '').toString().toLowerCase();
    if (paymentStatus == 'paid' && orderStatus == 'pending_assignment') {
      return 'Оплата подтверждена, выберите дату и время';
    }
    if (paymentStatus == 'invoice_requested') {
      return 'Ожидаем проверку оплаты менеджером';
    }
    return 'Заказ создан и обрабатывается';
  }

  String _cleanerInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'DP';
    }
    return parts.take(2).map((e) => e.characters.first.toUpperCase()).join();
  }

  String _profileDisplayName(Map<String, dynamic> profile) {
    final candidates = [
      profile['firstName'],
      profile['displayName'],
      profile['name'],
      profile['fullName'],
      profile['phone'],
    ];
    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return 'Пользователь';
  }

  DateTime _slotDate(Map<String, dynamic> slot) {
    final value =
        slot['scheduledFor'] ?? slot['date'] ?? slot['scheduledDateKey'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime(2100);
    }
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
      }
    }
    return DateTime(2100);
  }

  DateTime _slotMoment(Map<String, dynamic> slot) {
    final base = _slotDate(slot);
    if (base.year == 2100) {
      return base;
    }
    if (base.hour != 0 || base.minute != 0) {
      return base;
    }
    final time = (slot['time'] ?? '').toString();
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(time);
    if (match == null) {
      return base;
    }
    final hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match.group(2) ?? '') ?? 0;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  String _subscriptionUsageSummary(
    Map<String, dynamic> subscription, {
    List<Map<String, dynamic>> slots = const [],
  }) {
    final relevantSlots = _subscriptionRelatedSlots(subscription, slots);
    final subscriptionId = (subscription['id'] ?? '').toString();
    final hasLiveSlotsForSubscription =
        subscriptionId.isNotEmpty && relevantSlots.isNotEmpty;
    final completedCount = relevantSlots
        .where((slot) => (slot['status'] ?? '').toString() == 'completed')
        .length;
    final forfeitedCount = relevantSlots
        .where(
          (slot) =>
              (((slot['status'] ?? '').toString() == 'canceled') ||
                  ((slot['status'] ?? '').toString() == 'cancelled')) &&
              (slot['cancellationPenaltyApplied'] ?? false) == true,
        )
        .length;
    final completedValue = hasLiveSlotsForSubscription
        ? completedCount
        : ((subscription['completedVisits'] ?? subscription['usedVisits'] ?? 0)
                as num)
            .toInt();
    final completed = completedValue.toString();
    final forfeited = hasLiveSlotsForSubscription
        ? forfeitedCount
        : (subscription['forfeitedVisits'] as num?)?.toInt() ?? 0;
    final scheduled = _scheduledVisits(subscription, slots);
    final included = _includedVisits(subscription);
    final remaining = math.max(
      included - completedValue - forfeited - scheduled,
      0,
    );
    if (forfeited > 0) {
      return 'Осталось: $remaining · Использовано: $completed · Списано: $forfeited';
    }
    return 'Осталось: $remaining · Использовано: $completed';
  }

  bool _canSelectMoreDates(
    Map<String, dynamic>? subscription,
    List<Map<String, dynamic>> slots,
  ) {
    if (subscription == null) {
      return false;
    }
    return _availableSelections(subscription, slots) > 0;
  }

  Map<String, dynamic>? _selectActiveSubscription(
    List<Map<String, dynamic>> subscriptions,
    List<Map<String, dynamic>> slots,
  ) {
    final active = _activePaidPackageSubscriptions(subscriptions);
    if (active.isEmpty) {
      return null;
    }

    active.sort((a, b) {
      final aAddon = _isAddonOnlySubscription(a) ? 1 : 0;
      final bAddon = _isAddonOnlySubscription(b) ? 1 : 0;
      if (aAddon != bAddon) {
        return aAddon.compareTo(bAddon);
      }

      final aAvailable = _availableSelections(a, slots);
      final bAvailable = _availableSelections(b, slots);
      if (aAvailable != bAvailable) {
        return bAvailable.compareTo(aAvailable);
      }

      return _subscriptionCreatedMillis(
        b,
      ).compareTo(_subscriptionCreatedMillis(a));
    });

    return active.first;
  }

  Map<String, dynamic>? _selectSchedulingSubscription(
    List<Map<String, dynamic>> subscriptions,
    List<Map<String, dynamic>> slots,
  ) {
    final active = _activePaidPackageSubscriptions(
      subscriptions,
    ).where((item) => _availableSelections(item, slots) > 0).toList();
    if (active.isEmpty) {
      return _selectActiveSubscription(subscriptions, slots);
    }
    active.sort((a, b) {
      final aAvailable = _availableSelections(a, slots);
      final bAvailable = _availableSelections(b, slots);
      if (aAvailable != bAvailable) {
        return bAvailable.compareTo(aAvailable);
      }
      return _subscriptionCreatedMillis(
        a,
      ).compareTo(_subscriptionCreatedMillis(b));
    });
    return active.first;
  }

  List<Map<String, dynamic>> _activePaidPackageSubscriptions(
    List<Map<String, dynamic>> subscriptions,
  ) {
    return subscriptions
        .where(
          (item) =>
              (item['status'] ?? '').toString().trim().toLowerCase() ==
                  'active' &&
              _isPaidSubscription(item) &&
              !_isAddonOnlySubscription(item) &&
              _includedVisits(item) > 0,
        )
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int _aggregateIncludedVisits(List<Map<String, dynamic>> subscriptions) {
    return _activePaidPackageSubscriptions(subscriptions).fold<int>(
      0,
      (total, subscription) => total + _includedVisits(subscription),
    );
  }

  int _aggregateUsedVisits(
    List<Map<String, dynamic>> subscriptions,
    List<Map<String, dynamic>> slots,
  ) {
    return _activePaidPackageSubscriptions(subscriptions).fold<int>(
      0,
      (total, subscription) => total + _usedVisits(subscription, slots),
    );
  }

  int _aggregateScheduledVisits(
    List<Map<String, dynamic>> subscriptions,
    List<Map<String, dynamic>> slots,
  ) {
    return _activePaidPackageSubscriptions(subscriptions).fold<int>(
      0,
      (total, subscription) => total + _scheduledVisits(subscription, slots),
    );
  }

  int _aggregateAvailableSelections(
    List<Map<String, dynamic>> subscriptions,
    List<Map<String, dynamic>> slots,
  ) {
    final active = _activePaidPackageSubscriptions(subscriptions);
    final included = active.fold<int>(
      0,
      (total, subscription) => total + _includedVisits(subscription),
    );
    final used = _aggregateUsedVisits(active, slots);
    final scheduled = _aggregateScheduledVisits(active, slots);
    return math.max(included - used - scheduled, 0);
  }

  bool _isAddonOnlySubscription(Map<String, dynamic> subscription) {
    final type = (subscription['type'] ??
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

  bool _isPaidSubscription(Map<String, dynamic>? subscription) {
    if (subscription == null) {
      return false;
    }
    final paymentStatus = (subscription['paymentStatus'] ??
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

  int _subscriptionCreatedMillis(Map<String, dynamic> subscription) {
    final value = subscription['createdAt'] ?? subscription['updatedAt'];
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    try {
      final converted = (value as dynamic).toDate();
      if (converted is DateTime) {
        return converted.millisecondsSinceEpoch;
      }
    } catch (_) {}
    return 0;
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
    final catalogVisits = PackageCatalogUtils.cleaningsPerMonth(subscription);
    final stored = ((subscription['includedVisits'] ??
            subscription['cleaningsPerMonth'] ??
            0) as num)
        .toInt();
    final billingMonths =
        (subscription['billingPeriodMonths'] as num?)?.toInt() ?? 1;
    final source =
        '${subscription['frequencyLabel'] ?? ''} ${subscription['package'] ?? ''}'
            .toLowerCase();
    var parsed = 0;
    if (source.contains('8 раз') || source.contains('8/')) {
      parsed = 8;
    } else if (source.contains('4 раза') || source.contains('4/')) {
      parsed = 4;
    } else if (source.contains('2 раза') ||
        source.contains('два раза') ||
        source.contains('2/')) {
      parsed = 2;
    }
    final monthlyFromStored =
        billingMonths > 1 ? (stored / billingMonths).ceil() : stored;
    return math.max(math.max(monthlyFromStored, catalogVisits), parsed);
  }

  DateTime? _dateValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
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

  ({DateTime start, DateTime end}) _currentSubscriptionPeriod(
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

  bool _slotInCurrentSubscriptionPeriod(
    Map<String, dynamic> slot,
    Map<String, dynamic> subscription,
  ) {
    final date = DateUtils.dateOnly(_slotDate(slot));
    final period = _currentSubscriptionPeriod(subscription);
    return !date.isBefore(period.start) && date.isBefore(period.end);
  }

  int _usedVisits(
    Map<String, dynamic>? subscription,
    List<Map<String, dynamic>> slots,
  ) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final matched = _subscriptionRelatedSlots(subscription, slots);
    final stored = ((subscription['currentPeriodUsedVisits'] ??
            subscription['usedVisits'] ??
            subscription['completedVisits'] ??
            0) as num)
        .toInt();
    if (matched.isNotEmpty) {
      final liveUsed = matched
          .where(
            (slot) =>
                _slotInCurrentSubscriptionPeriod(slot, subscription) &&
                    _isCompletedSlotStatus(slot) ||
                (_slotInCurrentSubscriptionPeriod(slot, subscription) &&
                    _isCanceledSlotStatus(slot) &&
                    (slot['cancellationPenaltyApplied'] ?? false) == true),
          )
          .length;
      return math.max(liveUsed, stored);
    }
    return stored;
  }

  int _scheduledVisits(
    Map<String, dynamic>? subscription,
    List<Map<String, dynamic>> slots,
  ) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final matched = _subscriptionRelatedSlots(subscription, slots);
    final stored = ((subscription['currentPeriodScheduledVisits'] ??
            subscription['scheduledVisits'] ??
            subscription['selectedVisitsCount'] ??
            0) as num)
        .toInt();
    if (matched.isNotEmpty) {
      final liveScheduled = matched
          .where(
            (slot) =>
                _slotInCurrentSubscriptionPeriod(slot, subscription) &&
                    _isActiveScheduledStatus(
                      (slot['status'] ?? '').toString(),
                    ) ||
                (_slotInCurrentSubscriptionPeriod(slot, subscription) &&
                    _isActiveScheduledStatus(
                      (slot['orderStatus'] ?? '').toString(),
                    )),
          )
          .length;
      return math.max(liveScheduled, stored);
    }
    return stored;
  }

  List<Map<String, dynamic>> _subscriptionRelatedSlots(
    Map<String, dynamic>? subscription,
    List<Map<String, dynamic>> slots,
  ) {
    if (subscription == null || slots.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final ids = <String>{
      _compactId(subscription['id']),
      _compactId(subscription['sourceOrderId']),
      _compactId(subscription['customerOrderId']),
      _compactId(subscription['orderId']),
    }..remove('');
    if (ids.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return slots.where((slot) {
      final slotIds = <String>{
        _compactId(slot['subscriptionId']),
        _compactId(slot['sourceOrderId']),
        _compactId(slot['customerOrderId']),
        _compactId(slot['orderId']),
      }..remove('');
      return slotIds.any(ids.contains);
    }).toList(growable: false);
  }

  String _compactId(Object? value) => (value ?? '').toString().trim();

  bool _isCompletedSlotStatus(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final orderStatus =
        (slot['orderStatus'] ?? '').toString().trim().toLowerCase();
    return status == 'completed' || orderStatus == 'completed';
  }

  bool _isCanceledSlotStatus(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().trim().toLowerCase();
    final orderStatus =
        (slot['orderStatus'] ?? '').toString().trim().toLowerCase();
    return status == 'canceled' ||
        status == 'cancelled' ||
        orderStatus == 'canceled' ||
        orderStatus == 'cancelled';
  }

  bool _isActiveScheduledStatus(String rawStatus) {
    final status = rawStatus.toLowerCase().trim();
    return status == 'pending_assignment' ||
        status == 'pending_payment' ||
        status == 'offered' ||
        status == 'assigned' ||
        status == 'confirmed' ||
        status == 'rescheduled' ||
        status == 'in_progress';
  }

  int _availableSelections(
    Map<String, dynamic>? subscription,
    List<Map<String, dynamic>> slots,
  ) {
    if (subscription == null || !_isPaidSubscription(subscription)) {
      return 0;
    }
    final calculated = _includedVisits(subscription) -
        _usedVisits(subscription, slots) -
        _scheduledVisits(subscription, slots);
    return math.max(calculated, 0);
  }

  Widget _videoActionButton() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.clientVideosStream(),
      builder: (context, videosSnap) {
        final videos = videosSnap.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.userVideoViewsStream(),
          builder: (context, viewsSnap) {
            final viewedIds = (viewsSnap.data ?? const <Map<String, dynamic>>[])
                .where((view) => (view['completed'] ?? false) == true)
                .map((view) => (view['videoId'] ?? '').toString())
                .toSet();
            final unseenCount = videos
                .where((video) => !viewedIds.contains(video['id']))
                .length;
            return domlyTopBadgeIconButton(
              icon: Icons.lightbulb_outline,
              badgeCount: unseenCount,
              onPressed: () => _runProtectedAction(
                () => Navigator.pushNamed(context, '/client/videos'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _notificationsActionButton() {
    return StreamBuilder<int>(
      stream: _data.userUnreadActivityCountStream(),
      initialData: 0,
      builder: (context, notificationsSnap) {
        final unreadCount = notificationsSnap.data ?? 0;
        return domlyTopBadgeIconButton(
          icon: Icons.notifications_none,
          badgeCount: unreadCount,
          onPressed: () => _runProtectedAction(
            () => Navigator.pushNamed(context, '/notifications'),
          ),
        );
      },
    );
  }

  Future<void> _showBookingSheet(
    Map<String, dynamic> subscription,
    Map<String, dynamic> profile,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingSheet(
        subscription: subscription,
        profile: profile,
        data: _data,
      ),
    );
  }
}

class _FigmaHomeHero extends StatelessWidget {
  const _FigmaHomeHero({super.key, required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF439F73), Color(0xFF80D4B0)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 279,
            top: -49,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 22,
            top: 9,
            right: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добро пожаловать'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 18 / 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  userName.trim().isEmpty ? 'Пользователь' : userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 29 / 23,
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

class _FigmaStatusPill extends StatelessWidget {
  const _FigmaStatusPill({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final isLong = label.length > 12;
    return Container(
      constraints: BoxConstraints(
        minWidth: muted ? 112 : 118,
        maxWidth: isLong ? 168 : 150,
        minHeight: 34,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isLong ? 10 : 14,
        vertical: isLong ? 6 : 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF1F1F1) : const Color(0xFFF8E7DD),
        borderRadius: BorderRadius.circular(18),
        border: muted ? Border.all(color: const Color(0x12000000)) : null,
        boxShadow: muted
            ? null
            : const [
                BoxShadow(
                  color: Color(0x18CF7548),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!muted) ...[
            Icon(
              Icons.check_circle,
              color: const Color(0xFFCF7548),
              size: isLong ? 16 : 18,
            ),
            SizedBox(width: isLong ? 5 : 7),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.visible,
              softWrap: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    muted ? const Color(0xFF8A8A8A) : const Color(0xFFCF7548),
                fontSize: isLong ? 11.5 : 13,
                fontWeight: FontWeight.w600,
                height: isLong ? 1.12 : 17 / 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaEmptyCleaningCard extends StatelessWidget {
  const _FigmaEmptyCleaningCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalMargin = screenWidth < 380 ? 4.0 : 10.0;
    final tileGap = screenWidth < 380 ? 10.0 : 14.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          constraints: const BoxConstraints(minHeight: 199),
          margin: EdgeInsets.only(left: horizontalMargin, right: 5),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F3),
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: _FigmaEmptyMetricTile(
                      icon: Icons.schedule_outlined,
                      label: 'Время',
                      value: '-',
                    ),
                  ),
                  SizedBox(width: tileGap),
                  const Expanded(
                    child: _FigmaEmptyMetricTile(
                      icon: Icons.straighten_outlined,
                      label: 'Площадь',
                      value: '- м²',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FigmaEmptyAvatar(),
                  SizedBox(width: 12),
                  Expanded(child: _FigmaEmptyCleanerText()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FigmaEmptyMetricTile extends StatelessWidget {
  const _FigmaEmptyMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFCF7548)),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFF658170),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 16 / 12,
              ),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFF22352D),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 22 / 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoBannersSection extends StatefulWidget {
  const _PromoBannersSection();

  @override
  State<_PromoBannersSection> createState() => _PromoBannersSectionState();
}

class _PromoBannersSectionState extends State<_PromoBannersSection> {
  static const List<Map<String, dynamic>> _fallbackBanners = [
    {
      'id': 'promo_packages',
      'title': 'Подписка на уборку',
      'subtitle': 'Выберите пакет и закрепите удобные даты на месяц вперед.',
      'ctaLabel': 'Открыть пакеты',
      'route': '/client/packages',
      'imageUrl':
          'https://placehold.co/1200x420/7DC9A5/FFFFFF.png?text=Domly+Packages',
      'sortOrder': 1,
      'isActive': true,
    },
    {
      'id': 'promo_bonus',
      'title': 'Приглашайте соседей',
      'subtitle': 'Получайте бонусы за подключения и ускоряйте активацию дома.',
      'ctaLabel': 'Смотреть бонусы',
      'route': '/client/bonus',
      'imageUrl':
          'https://placehold.co/1200x420/CF7548/FFFFFF.png?text=Invite+Neighbors',
      'sortOrder': 2,
      'isActive': true,
    },
    {
      'id': 'promo_videos',
      'title': 'Советы и видео',
      'subtitle': 'Посмотрите короткие ролики о подготовке квартиры к уборке.',
      'ctaLabel': 'Открыть видео',
      'route': '/client/videos',
      'imageUrl':
          'https://placehold.co/1200x420/5C8DFF/FFFFFF.png?text=Domly+Tips',
      'sortOrder': 3,
      'isActive': true,
    },
  ];

  final PageController _pageController = PageController(viewportFraction: 1);
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  int _bannerCount = 0;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _syncAutoScroll(int count) {
    if (_bannerCount != count) {
      _bannerCount = count;
      if (_currentPage >= count && count > 0) {
        _currentPage = 0;
      }
    }
    _autoScrollTimer?.cancel();
    if (count <= 1) {
      return;
    }
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients || _bannerCount <= 1) {
        return;
      }
      final nextPage = (_currentPage + 1) % _bannerCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: AppConfigService.instance.promoBannersStream(),
      builder: (context, snapshot) {
        final remoteBanners = snapshot.data ?? const <Map<String, dynamic>>[];
        final banners = (remoteBanners.isNotEmpty
                ? remoteBanners
                : _fallbackBanners
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList())
            .where((item) => item['isActive'] != false)
            .toList();
        if (banners.isEmpty) {
          return const SizedBox.shrink();
        }

        _syncAutoScroll(banners.length);

        return Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final height = (constraints.maxWidth * 0.34).clamp(
                  124.0,
                  148.0,
                );
                return SizedBox(
                  key: DomlyTutorialTargets.clientInfoBanner,
                  height: height,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: banners.length,
                    onPageChanged: (index) {
                      if (!mounted) {
                        return;
                      }
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PromoBannerCard(banner: banners[index]),
                      );
                    },
                  ),
                );
              },
            ),
            if (banners.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  banners.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _currentPage ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == _currentPage
                          ? const Color(0xFFCF7548)
                          : const Color(0xFFD7E5DC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PromoBannerCard extends StatelessWidget {
  const _PromoBannerCard({required this.banner});

  final Map<String, dynamic> banner;

  static String _stringValue(Object? value) => (value ?? '').toString().trim();

  static String _imageUrlFrom(Map<String, dynamic> source) {
    for (final key in const [
      'imageUrl',
      'imageURL',
      'photoUrl',
      'photoURL',
      'bannerImageUrl',
      'bannerImageURL',
      'coverUrl',
      'coverImageUrl',
      'mediaUrl',
      'downloadUrl',
      'url',
    ]) {
      final value = _stringValue(source[key]);
      if (_isNetworkImageUrl(value)) {
        return value;
      }
    }

    for (final key in const ['image', 'photo', 'media', 'file']) {
      final nested = source[key];
      if (nested is Map) {
        final value = _imageUrlFrom(Map<String, dynamic>.from(nested));
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  static bool _isNetworkImageUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  Future<void> _open(BuildContext context) async {
    final title = (banner['title'] ?? 'Информация').toString().trim();
    final subtitle = (banner['subtitle'] ?? '').toString().trim();
    final description = (banner['description'] ??
            banner['fullInfo'] ??
            banner['longDescription'] ??
            '')
        .toString()
        .trim();
    final imageUrl = _imageUrlFrom(banner);
    if (title.isNotEmpty ||
        subtitle.isNotEmpty ||
        description.isNotEmpty ||
        imageUrl.isNotEmpty) {
      await InfoDialog.showFromConfig(
        context,
        config: {
          'title': title.isEmpty ? 'Информация' : title,
          'shortInfo': subtitle,
          'fullInfo': description,
          'imageUrl': imageUrl,
        },
      );
      return;
    }

    final externalUrl = (banner['externalUrl'] ?? '').toString().trim();
    final route = externalUrl.isNotEmpty
        ? externalUrl
        : (banner['route'] ?? '').toString().trim();
    if (route.isEmpty) {
      return;
    }
    if (route.startsWith('http://') || route.startsWith('https://')) {
      final uri = Uri.tryParse(route);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    Navigator.pushNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _imageUrlFrom(banner);
    final title = (banner['title'] ?? '').toString().trim();
    final subtitle = (banner['subtitle'] ?? '').toString().trim();
    final description = (banner['description'] ??
            banner['fullInfo'] ??
            banner['longDescription'] ??
            '')
        .toString()
        .trim();
    final ctaLabel = (banner['ctaLabel'] ?? '').toString().trim();
    final clickable = ((banner['route'] ?? '').toString().trim().isNotEmpty) ||
        ((banner['externalUrl'] ?? '').toString().trim().isNotEmpty) ||
        ctaLabel.isNotEmpty ||
        title.isNotEmpty ||
        subtitle.isNotEmpty ||
        description.isNotEmpty ||
        imageUrl.isNotEmpty;

    final background = imageUrl.isEmpty
        ? const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(24)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF70B68C), Color(0xFFCF7548)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white,
            image: DecorationImage(
              image: NetworkImage(imageUrl),
              fit: BoxFit.contain,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: !clickable ? null : () => _open(context),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: double.infinity,
          decoration: background,
          child: imageUrl.isNotEmpty
              ? const SizedBox.expand()
              : Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (ctaLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ctaLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _CompanyPromotionsSection extends StatefulWidget {
  const _CompanyPromotionsSection();

  @override
  State<_CompanyPromotionsSection> createState() =>
      _CompanyPromotionsSectionState();
}

class _CompanyPromotionsSectionState extends State<_CompanyPromotionsSection> {
  final PageController _controller = PageController();
  Timer? _autoScrollTimer;
  int _page = 0;
  int _promotionCount = 0;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _syncAutoScroll(int count) {
    if (_promotionCount != count) {
      _promotionCount = count;
      if (_page >= count && count > 0) {
        _page = 0;
      }
    }
    _autoScrollTimer?.cancel();
    if (count <= 1) {
      return;
    }
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients || _promotionCount <= 1) {
        return;
      }
      final nextPage = (_page + 1) % _promotionCount;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: AppConfigService.instance.promotionsStream(),
      builder: (context, snapshot) {
        final promotions = (snapshot.data ?? const <Map<String, dynamic>>[])
            .where((item) => item['isActive'] != false)
            .toList();
        if (promotions.isEmpty) {
          _autoScrollTimer?.cancel();
          return const SizedBox.shrink();
        }
        _syncAutoScroll(promotions.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 132,
              child: PageView.builder(
                controller: _controller,
                itemCount: promotions.length,
                onPageChanged: (value) {
                  if (mounted) {
                    setState(() => _page = value);
                  }
                },
                itemBuilder: (context, index) {
                  return _CompanyPromotionBanner(promotion: promotions[index]);
                },
              ),
            ),
            if (promotions.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  promotions.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _page ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == _page
                          ? const Color(0xFFCF7548)
                          : const Color(0xFFD7E5DC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CompanyPromotionBanner extends StatelessWidget {
  const _CompanyPromotionBanner({required this.promotion});

  final Map<String, dynamic> promotion;

  @override
  Widget build(BuildContext context) {
    final title = (promotion['title'] ?? 'Важная информация').toString();
    final shortInfo = (promotion['shortInfo'] ??
            promotion['description'] ??
            promotion['packageName'] ??
            '')
        .toString();
    final rewardMode = (promotion['rewardMode'] ?? 'fixed').toString();
    final rewardAmount = (promotion['rewardAmount'] as num?)?.toInt() ?? 0;
    final rewardPercent = (promotion['rewardPercent'] as num?)?.toDouble() ?? 0;
    final rewardLabel = rewardMode == 'percent'
        ? '${rewardPercent.toStringAsFixed(rewardPercent % 1 == 0 ? 0 : 1)}%'
        : '$rewardAmount ₸';
    final showTitle = promotion['showBannerTitle'] != false;
    final showShortInfo = promotion['showBannerShortInfo'] != false;
    final showReward = promotion['showBannerReward'] != false;
    final showInfoIcon = promotion['showBannerInfoIcon'] != false;
    final showAnyText =
        showTitle || (showShortInfo && shortInfo.isNotEmpty) || showReward;
    final imageUrl = (promotion['homeBannerImageUrl'] ??
            promotion['bannerImageUrl'] ??
            promotion['imageUrl'] ??
            '')
        .toString()
        .trim();
    final infoConfig = {
      'title': title,
      'shortInfo':
          shortInfo.isEmpty ? 'Бонус по акции: $rewardLabel' : shortInfo,
      'fullInfo': promotion['fullInfo'] ?? promotion['longDescription'] ?? '',
      'features':
          promotion['features'] is List ? promotion['features'] : const [],
      'exclusions':
          promotion['exclusions'] is List ? promotion['exclusions'] : const [],
      'price': rewardMode == 'fixed' ? rewardAmount : null,
      'imageUrl': imageUrl,
    };

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => InfoDialog.showFromConfig(context, config: infoConfig),
          child: Ink(
            decoration: BoxDecoration(
              gradient: imageUrl.isEmpty
                  ? const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFFEAF7EE), Color(0xFFFFF2DA)],
                    )
                  : null,
              image: imageUrl.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.contain,
                      colorFilter: showAnyText
                          ? ColorFilter.mode(
                              Colors.white.withValues(alpha: 0.18),
                              BlendMode.lighten,
                            )
                          : null,
                    ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2EDE6)),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: imageUrl.isEmpty || !showAnyText
                    ? null
                    : const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xEFFFFFFF), Color(0xB3FFFFFF)],
                      ),
              ),
              child: Row(
                children: [
                  if (showAnyText)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showTitle)
                            Text(
                              title.isEmpty ? 'Важная информация' : title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF143E21),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                          if (showTitle &&
                              ((showShortInfo && shortInfo.isNotEmpty) ||
                                  showReward))
                            const SizedBox(height: 6),
                          if (showShortInfo && shortInfo.isNotEmpty)
                            Text(
                              shortInfo,
                              maxLines: showReward ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF456557),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                              ),
                            ),
                          if (showShortInfo &&
                              shortInfo.isNotEmpty &&
                              showReward)
                            const SizedBox(height: 3),
                          if (showReward)
                            Text(
                              'Бонус: $rewardLabel'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFCF7548),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  if (showInfoIcon) ...[
                    const SizedBox(width: 12),
                    const Material(
                      color: Colors.white,
                      shape: CircleBorder(),
                      elevation: 4,
                      shadowColor: Color(0x1A000000),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(
                          Icons.info_outline,
                          color: Color(0xFF143E21),
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FigmaEmptyAvatar extends StatelessWidget {
  const _FigmaEmptyAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFCF7548), Color(0xFFEEB09B)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
    );
  }
}

class _FigmaEmptyCleanerText extends StatelessWidget {
  const _FigmaEmptyCleanerText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Исполнитель будет назначен'.tr(),
          maxLines: 2,
          softWrap: true,
          style: TextStyle(
            color: Color(0xFF2B4338),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'После оформления подписки'.tr(),
          maxLines: 2,
          softWrap: true,
          style: TextStyle(
            color: Color(0xFF658170),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _FigmaNextCleaningCard extends StatelessWidget {
  const _FigmaNextCleaningCard({
    required this.onTap,
    required this.timeText,
    required this.areaText,
    required this.cleanerName,
    required this.planName,
    required this.totalVisits,
    required this.availableSelections,
    required this.used,
    required this.showUsageStats,
    required this.onSelectDates,
    required this.onDetails,
    required this.onCancel,
  });

  final VoidCallback onTap;
  final String timeText;
  final String areaText;
  final String cleanerName;
  final String planName;
  final int totalVisits;
  final int availableSelections;
  final int used;
  final bool showUsageStats;
  final VoidCallback? onSelectDates;
  final VoidCallback onDetails;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 304),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FigmaInfoTile(
                        icon: Icons.schedule_outlined,
                        title: 'Время',
                        value: timeText,
                        iconSize: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FigmaInfoTile(
                        icon: Icons.straighten_outlined,
                        title: 'Площадь',
                        value: areaText,
                        iconSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFCF7548), Color(0xFFEEB09B)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        cleanerName.characters.isEmpty
                            ? 'A'
                            : cleanerName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 28 / 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanerName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2B4338),
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 24 / 19,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            planName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF658170),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 18 / 13,
                            ),
                          ),
                          if (showUsageStats) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _FigmaUsagePill(
                                    text: 'Осталось: $availableSelections',
                                    compactText: 'Ост.: $availableSelections',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _FigmaUsagePill(
                                    text: 'Использовано: $used',
                                    compactText: 'Исп.: $used',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFDEECE3)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (onSelectDates != null)
                      TextButton(
                        onPressed: onSelectDates,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(126, 18),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: const Color(0xFFCF7548),
                        ),
                        child: Text(
                          'Выбрать даты'.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 18 / 13,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 18),
                    const Spacer(),
                    if (onCancel != null) ...[
                      TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(70, 18),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: DomlyColors.danger,
                        ),
                        child: Text(
                          'Отменить'.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 19 / 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Container(
                        width: 1,
                        height: 24,
                        color: const Color(0xFFE4DDD8),
                      ),
                      const SizedBox(width: 18),
                    ],
                    TextButton(
                      onPressed: onDetails,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 18),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFFCF7548),
                      ),
                      child: Text(
                        'Детали'.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 19 / 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FigmaPrimaryHomeButton extends StatelessWidget {
  const _FigmaPrimaryHomeButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC96A4A),
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: const Color(0x55C96A4A),
          padding: EdgeInsets.zero,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 20 / 16,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FigmaInfoTile extends StatelessWidget {
  const _FigmaInfoTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.iconSize,
  });

  final IconData icon;
  final String title;
  final String value;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDEECE3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 12,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: iconSize, color: const Color(0xFFCF7548)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF658170),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 16 / 12,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 21 / 17,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FigmaSecondaryHomeButton extends StatelessWidget {
  const _FigmaSecondaryHomeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFC96A4A),
          side: const BorderSide(color: Color(0x80C96A4A)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 20 / 15,
          ),
        ),
      ),
    );
  }
}

class _FigmaUsagePill extends StatelessWidget {
  const _FigmaUsagePill({required this.text, this.compactText});

  final String text;
  final String? compactText;

  @override
  Widget build(BuildContext context) {
    final icon = text.toLowerCase().contains('использ')
        ? Icons.check_circle_outline
        : Icons.schedule_outlined;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 150;
        return Container(
          height: 40,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8E7DD),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x80CF7548)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: isCompact ? 15 : 18,
                color: const Color(0xFF4AAA62),
              ),
              SizedBox(width: isCompact ? 4 : 7),
              Flexible(
                child: Text(
                  isCompact ? (compactText ?? text) : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF4AAA62),
                    fontSize: isCompact ? 11 : 13,
                    fontWeight: FontWeight.w600,
                    height: isCompact ? 14 / 11 : 16 / 13,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FigmaHomeAction extends StatelessWidget {
  const _FigmaHomeAction({
    required this.caption,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String caption;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 170;
              final iconBox = isCompact ? 38.0 : 44.0;
              return Container(
                height: 86,
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 10 : 13,
                  13,
                  isCompact ? 9 : 10,
                  13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFCFB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDEECE3)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF54B85F),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: isCompact ? 24 : 27,
                      ),
                    ),
                    SizedBox(width: isCompact ? 8 : 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: isCompact ? 32 : 20,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                label,
                                softWrap: false,
                                maxLines: 1,
                                style: TextStyle(
                                  color: const Color(0xFF143E21),
                                  fontSize: isCompact ? 13 : 15,
                                  fontWeight: FontWeight.w700,
                                  height: isCompact ? 16 / 13 : 19 / 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF658170),
                              fontSize: isCompact ? 10 : 11,
                              fontWeight: FontWeight.w500,
                              height: isCompact ? 12 / 10 : 14 / 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isCompact)
                      const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF658170),
                        size: 23,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FigmaClientBottomNav extends StatelessWidget {
  const _FigmaClientBottomNav({required this.currentIndex});

  final int currentIndex;

  static const _routes = [
    '/client/home',
    '/client/orders',
    '/client/profile',
    '/notifications',
    '/client/settings',
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreDataService.instance.userUnreadActivityCountStream(),
      initialData: 0,
      builder: (context, snapshot) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final sideInset = screenWidth <= 380 ? 10.0 : 16.0;
        return SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(sideInset, 0, sideInset, 10),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(430, screenWidth - sideInset * 2),
              ),
              child: Container(
                width: double.infinity,
                height: 66,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDEECE3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FigmaNavItem(
                      key: DomlyTutorialTargets.clientBottomNav[0],
                      label: 'Главная',
                      icon: Icons.home_outlined,
                      selected: currentIndex == 0,
                      onTap: () => _go(context, 0),
                    ),
                    _FigmaNavItem(
                      key: DomlyTutorialTargets.clientBottomNav[1],
                      label: 'Заказы',
                      icon: Icons.receipt_long_outlined,
                      selected: currentIndex == 1,
                      onTap: () => _go(context, 1),
                    ),
                    _FigmaNavItem(
                      key: DomlyTutorialTargets.clientBottomNav[2],
                      label: 'Профиль',
                      icon: Icons.person_outline,
                      selected: currentIndex == 2,
                      onTap: () => _go(context, 2),
                    ),
                    _FigmaNavItem(
                      key: DomlyTutorialTargets.clientBottomNav[3],
                      label: 'Уведомления',
                      icon: Icons.notifications_none,
                      selected: currentIndex == 3,
                      badgeCount: snapshot.data ?? 0,
                      onTap: () => _go(context, 3),
                    ),
                    _FigmaNavItem(
                      key: DomlyTutorialTargets.clientBottomNav[4],
                      label: 'Настройки',
                      icon: Icons.settings_outlined,
                      selected: currentIndex == 4,
                      onTap: () => _go(context, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _go(BuildContext context, int index) {
    if (index == currentIndex) {
      return;
    }
    Navigator.pushReplacementNamed(context, _routes[index]);
  }
}

class _FigmaNavItem extends StatelessWidget {
  const _FigmaNavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? const Color(0x61EEB09A) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: const Color(0xFFCF7548)),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF2B4338)
                              : const Color(0xFF658170),
                          fontSize: 9,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          height: 14 / 9,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: 3,
                    right: 6,
                    child: _FigmaNavBadge(count: badgeCount),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FigmaNavBadge extends StatelessWidget {
  const _FigmaNavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _BookingSheet extends StatefulWidget {
  final Map<String, dynamic> subscription;
  final Map<String, dynamic> profile;
  final FirestoreDataService data;

  const _BookingSheet({
    required this.subscription,
    required this.profile,
    required this.data,
  });

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
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

  static const _fallbackAddonGroups = <_BookingAddonGroupDef>[
    _BookingAddonGroupDef(
      key: 'windows',
      label: 'Окна и стекла',
      items: [
        _BookingAddonItemDef(
          key: 'window_standard',
          label: 'Мытье окон стандарт',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'window_panorama',
          label: 'Панорама',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'window_mosquito',
          label: 'Мытье москитных сеток',
          supportsQuantity: true,
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'balcony',
      label: 'Балкон',
      items: [
        _BookingAddonItemDef(
          key: 'balcony_window_standard',
          label: 'Мытье окон стандарт',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'balcony_panorama',
          label: 'Панорама',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'balcony_balcony',
          label: 'Балкон',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'balcony_loggia',
          label: 'Лоджия',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'balcony_terrace',
          label: 'Терасса',
          supportsQuantity: true,
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'kitchen',
      label: 'Кухня',
      items: [
        _BookingAddonItemDef(
          key: 'kitchen_oven',
          label: 'Чистка духовки внутри',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_hood',
          label: 'Чистка вытяжки и фильтров',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_fridge',
          label: 'Мытье холодильника внутри',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_facades',
          label: 'Мытье фасадов кухонного гарнитура',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_full_set',
          label: 'Полное мытье кухонного гарнитура',
          note: 'Внутри и снаружи',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_stove',
          label: 'Чистка плит и варочных панелей',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_microwave',
          label: 'Чистка микроволновки',
        ),
        _BookingAddonItemDef(key: 'kitchen_apron', label: 'Мытье фартука'),
        _BookingAddonItemDef(
          key: 'kitchen_dishes_hand',
          label: 'Мытье посуды вручную',
        ),
        _BookingAddonItemDef(
          key: 'kitchen_dishwasher_loading',
          label: 'Загрузка посуды в посудомойку',
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'bathroom',
      label: 'Санузлы',
      items: [
        _BookingAddonItemDef(key: 'bath_tile_walls', label: 'Стены кафель'),
        _BookingAddonItemDef(
          key: 'bath_glass_walls',
          label: 'Стеклянные стены душа и ванны',
        ),
        _BookingAddonItemDef(
          key: 'bath_washer_wipe',
          label: 'Протирка стиральной машины',
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'textile',
      label: 'Комфорт и текстиль',
      items: [
        _BookingAddonItemDef(
          key: 'textile_bed_linen_ironing',
          label: 'Глажка постельного белья',
        ),
        _BookingAddonItemDef(
          key: 'textile_clothes_ironing',
          label: 'Глажка одежды',
        ),
        _BookingAddonItemDef(
          key: 'textile_curtains_ironing',
          label: 'Глажка штор',
        ),
        _BookingAddonItemDef(
          key: 'textile_bed_change',
          label: 'Замена постельного белья и заправка кроватей',
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'hard',
      label: 'Труднодоступные зоны',
      items: [
        _BookingAddonItemDef(
          key: 'hard_chandelier_standard',
          label: 'Чистка люстр стандартная',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'hard_chandelier_complex',
          label: 'Чистка люстр сложная',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'hard_chandelier_super',
          label: 'Чистка люстр супер сложная',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'hard_lamps',
          label: 'Светильники и плафоны',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'hard_upper_shelves',
          label: 'Чистка верхних полок, антресолей и шкафов',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(key: 'hard_baseboards', label: 'Чистка плинтусов'),
        _BookingAddonItemDef(
          key: 'hard_doors',
          label: 'Мытье дверей',
          supportsQuantity: true,
        ),
        _BookingAddonItemDef(
          key: 'hard_cobweb',
          label: 'Удаление паутины и пыли в труднодоступных местах',
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'furniture',
      label: 'Мебель и поверхности',
      note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
      items: [
        _BookingAddonItemDef(
          key: 'furniture_sofa',
          label: 'Химчистка диванов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
        _BookingAddonItemDef(
          key: 'furniture_mattress',
          label: 'Химчистка матрасов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
      ],
    ),
    _BookingAddonGroupDef(
      key: 'carpet',
      label: 'Химчистка ковров и паласов',
      note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
      items: [
        _BookingAddonItemDef(
          key: 'carpet_cleaning',
          label: 'Химчистка ковров и паласов',
          supportsQuantity: true,
          separatePayment: true,
          note: 'Данная услуга оплачивается отдельно при оценке специалиста.',
        ),
      ],
    ),
  ];

  DateTime? _selectedDate;
  String? _selectedTime;
  String _accessMethod = 'Я дома';
  final _config = AppConfigService.instance;
  final Map<String, int> _addonUnitPrices = Map<String, int>.from(
    _fallbackAddonUnitPrices,
  );
  List<_BookingAddonGroupDef> _addonGroups = List<_BookingAddonGroupDef>.from(
    _fallbackAddonGroups,
  );
  StreamSubscription<List<Map<String, dynamic>>>? _addonCatalogSubscription;
  final Set<String> _expandedAddonGroups = <String>{};
  final Map<String, int> _addonQuantities = <String, int>{};
  List<String> _availableTimeSlots = const [];
  bool _loadingTimeSlots = false;
  bool _submitting = false;

  static const _accessMethods = [
    'Я дома',
    'Ключи у консьержа',
    'Код замка',
    'Сейф-бокс',
  ];

  int _pendingScheduleSelections(Map<String, dynamic> subscription) {
    final included = (subscription['includedVisits'] as num?)?.toInt() ?? 0;
    final used = (subscription['usedVisits'] as num?)?.toInt() ?? 0;
    final scheduled = (subscription['scheduledVisits'] as num?)?.toInt() ?? 0;
    final pending = included - used - scheduled;
    return pending > 0 ? pending : 0;
  }

  Future<void> _showAddonInfo(
    String addonKey, {
    String? title,
    String? shortInfo,
    String? fullInfo,
    List<String>? features,
  }) async {
    Map<String, dynamic>? infoConfig;
    for (final infoKey in _addonInfoKeys(addonKey)) {
      infoConfig = await _config.getInfoContent(infoKey);
      if (infoConfig != null && infoConfig.isNotEmpty) {
        break;
      }
    }
    if (!mounted) {
      return;
    }
    if (infoConfig != null && infoConfig.isNotEmpty) {
      await InfoDialog.showFromConfig(
        context,
        config: {
          'title': title ?? addonKey.replaceAll('_', ' '),
          'shortInfo': shortInfo ?? 'Информация по услуге пока не заполнена.',
          'description': shortInfo ?? 'Информация по услуге пока не заполнена.',
          'fullInfo': fullInfo ?? '',
          'longDescription': fullInfo ?? '',
          'features': features ?? const <String>[],
          'price': _unitPriceFor(addonKey),
          ...infoConfig,
        },
      );
      return;
    }
    final unitPrice = _unitPriceFor(addonKey);
    await InfoDialog.showFromConfig(
      context,
      config: {
        'title': title ?? addonKey.replaceAll('_', ' '),
        'shortInfo': shortInfo ?? 'Информация по услуге пока не заполнена.',
        'description': shortInfo ?? 'Информация по услуге пока не заполнена.',
        'fullInfo': fullInfo ?? '',
        'longDescription': fullInfo ?? '',
        'features': features ?? const <String>[],
        'price': unitPrice,
      },
    );
  }

  List<String> _addonInfoKeys(String key) {
    final keys = <String>[key];
    if (key.contains('window') ||
        key.contains('panorama') ||
        key.contains('mosquito')) {
      keys.add('addon_windows');
    } else if (key.startsWith('kitchen_')) {
      keys.add('addon_kitchen');
    } else if (key.startsWith('bath_')) {
      keys.add('addon_bathroom');
    } else if (key.startsWith('balcony_')) {
      keys.add('addon_balcony');
    } else if (key.startsWith('textile_')) {
      keys.add('addon_textile');
    } else if (key.startsWith('hard_')) {
      keys.add('addon_hard');
    } else if (key.startsWith('furniture_')) {
      keys.add('addon_furniture');
    } else if (key.startsWith('carpet_')) {
      keys.add('addon_carpet');
    }
    return keys.toSet().toList();
  }

  @override
  void initState() {
    super.initState();
    _addonCatalogSubscription = _config.addonGroupConfigsStream().listen((
      groups,
    ) {
      if (!mounted) return;
      setState(() {
        _addonGroups = _mapAddonGroupConfigs(groups);
      });
    });
  }

  @override
  void dispose() {
    _addonCatalogSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: DomlyColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Выбор даты и времени'.tr(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Выберите день и доступное окно для уборки.'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Доступно'.tr(),
                            style: TextStyle(
                              fontSize: 13,
                              color: DomlyColors.buttonPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_pendingScheduleSelections(widget.subscription)} уборок'
                                .tr(),
                            style: const TextStyle(
                              fontSize: 16,
                              color: DomlyColors.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Date
                      Text(
                        'День'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DomlySecondaryButton(
                        label: _selectedDate != null
                            ? '${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}'
                            : 'Выберите дату',
                        icon: Icons.calendar_today,
                        onPressed: _submitting ? null : _pickBookingDate,
                      ),
                      const SizedBox(height: 16),

                      // Time
                      Text(
                        'Время'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedDate == null)
                        Text(
                          'Сначала выберите дату, затем загрузятся доступные окна.'
                              .tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: DomlyColors.muted,
                          ),
                        )
                      else if (_loadingTimeSlots)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_availableTimeSlots.isEmpty)
                        Text(
                          'На выбранную дату нет доступных окон. Выберите другую дату.'
                              .tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: DomlyColors.muted,
                          ),
                        )
                      else
                        AbsorbPointer(
                          absorbing: _submitting,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableTimeSlots.map((time) {
                              final selected = _selectedTime == time;
                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () =>
                                    setState(() => _selectedTime = time),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? DomlyColors.primary.withValues(
                                            alpha: 0.10,
                                          )
                                        : DomlyColors.backgroundSoft,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? DomlyColors.primary
                                          : DomlyColors.border,
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? DomlyColors.primary
                                          : DomlyColors.foreground,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Access
                      Text(
                        'Доступ к квартире'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: DomlyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _accessMethod,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: DomlyColors.backgroundSoft,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: DomlyColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: DomlyColors.border,
                            ),
                          ),
                        ),
                        items: _accessMethods
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _accessMethod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Add-ons
                      Text(
                        'Дополнительные\nуслуги'.tr(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ..._addonGroups.map(_buildAddonGroup),
                      if (_selectedAddonsDetailed().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: DomlyColors.backgroundSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: DomlyColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Итого по допуслугам'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: DomlyColors.foreground,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatMoney(_billableAddonTotal()),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: DomlyColors.foreground,
                                ),
                              ),
                              if (_hasSeparatePaymentAddons()) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Услуги с пометкой "Оплачивается отдельно при оценке специалиста" менеджер рассчитает отдельно.'
                                      .tr(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DomlyColors.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      DomlyPrimaryButton(
                        label: _billableAddonTotal() > 0
                            ? 'Заказать и оплатить допы'
                            : 'Заказать',
                        icon: Icons.check,
                        isLoading: _submitting,
                        onPressed: _selectedDate == null ||
                                _selectedTime == null ||
                                _submitting
                            ? null
                            : () => _submitBooking(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitBooking() async {
    if (_submitting) return;
    final detailedAddons = _selectedAddonsDetailed();
    final billableTotal = _billableAddonTotal();
    final bookingDate = _selectedDate!;
    final bookingTime = _selectedTime!;
    DomlyPaymentMethod? paymentMethod;
    String? kaspiPhone;
    var bonusToSpend = 0;
    final sheetNavigator = Navigator.of(context);

    setState(() => _submitting = true);
    try {
      if (billableTotal > 0) {
        if (!mounted) return;
        final profile = await widget.data.customerProfileStream().first;
        if (!mounted) return;
        final bonusBalance = (profile?['bonusPoints'] as num?)?.toInt() ?? 0;
        final bonusLimit = addonBonusSpendLimit(
          billableTotal,
          await AppConfigService.instance.promotionsStream().first,
        );
        if (!mounted) return;
        final paymentSelection = await showPaymentMethodOptionsDialog(
          context,
          bonusBalance: bonusBalance,
          maxBonusToSpend: bonusLimit,
          paymentAmount: billableTotal,
        );
        if (!mounted) return;
        if (paymentSelection == null) {
          showDomlySnackBar(
            context,
            title: 'Оплата допуслуг не отправлена',
            subtitle: 'Выберите способ оплаты для допуслуг.',
            type: DomlySnackBarType.info,
          );
          return;
        }
        paymentMethod = paymentSelection.method;
        bonusToSpend = paymentSelection.useBonus
            ? bonusBalance.clamp(0, bonusLimit).clamp(0, billableTotal).toInt()
            : 0;
        if (paymentMethod == DomlyPaymentMethod.bonus) {
          bonusToSpend = billableTotal;
        }
        if (bonusToSpend >= billableTotal) {
          paymentMethod = DomlyPaymentMethod.bonus;
          kaspiPhone = null;
        }
        if (paymentMethod == DomlyPaymentMethod.kaspi &&
            bonusToSpend < billableTotal) {
          final paymentRequest = await showKaspiInvoiceRequestOptionsDialog(
            context,
            bonusBalance: bonusBalance,
            maxBonusToSpend: bonusLimit,
            paymentAmount: billableTotal,
            initialUseBonus: bonusToSpend > 0,
          );
          if (!mounted) return;
          if (paymentRequest == null) {
            showDomlySnackBar(
              context,
              title: 'Оплата допуслуг не отправлена',
              subtitle: 'Для допуслуг нужен номер KASPI.KZ.',
              type: DomlySnackBarType.info,
            );
            return;
          }
          kaspiPhone = paymentRequest.phone;
          bonusToSpend = paymentRequest.useBonus
              ? bonusBalance
                  .clamp(0, bonusLimit)
                  .clamp(0, billableTotal)
                  .toInt()
              : 0;
        }
      }

      final result = await PaymentLinkService.runBlocking(
        context,
        task: () => widget.data.bookSchedule(
          subscriptionId: widget.subscription['id'].toString(),
          selections: [
            {
              'date':
                  '${bookingDate.year.toString().padLeft(4, '0')}-${bookingDate.month.toString().padLeft(2, '0')}-${bookingDate.day.toString().padLeft(2, '0')}',
              'time': bookingTime,
              if (billableTotal > 0) 'newAddonsDetailed': detailedAddons,
              if (billableTotal > 0) 'kaspiPhone': kaspiPhone,
              if (billableTotal > 0) 'bonusToSpend': bonusToSpend,
            },
          ],
        ),
        message: 'Подтверждаем расписание...',
      );
      final addonPaymentIds = (result['addonPaymentIds'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
      if (!mounted) return;
      if (paymentMethod == DomlyPaymentMethod.online &&
          addonPaymentIds.isNotEmpty) {
        final paymentSession = await PaymentLinkService.runBlocking(
          context,
          task: () => widget.data.createBccPaymentSession(
            orderId: addonPaymentIds.first,
          ),
          message: 'Открываем онлайн-оплату...',
        );
        if (!mounted) return;
        if (sheetNavigator.canPop()) {
          sheetNavigator.pop();
        }
        Navigator.pushNamed(
          context,
          '/client/online-payment',
          arguments: paymentSession,
        );
        return;
      }

      if (!mounted) return;
      if (sheetNavigator.canPop()) {
        sheetNavigator.pop();
      }
      showDomlySnackBar(
        context,
        title: 'Уборка запланирована',
        subtitle: billableTotal > 0
            ? paymentMethod == DomlyPaymentMethod.bonus
                ? 'Доп. услуги оплачены бонусами и добавлены к уборке.'
                : 'Менеджер выставит счёт за допуслуги в ближайшее время.'
            : _hasSeparatePaymentAddons()
                ? 'По услугам с отдельной оплатой менеджер свяжется отдельно.'
                : 'Расписание сохранено.',
        type: DomlySnackBarType.success,
      );
    } catch (error) {
      if (!mounted) return;
      final message = UserErrorMessage.message(error);
      showDomlySnackBar(
        context,
        title: 'Не удалось оформить уборку',
        subtitle: message,
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _pickBookingDate() async {
    final now = DateTime.now();
    final initialDate = LaunchConfig.nextBookingDate(now);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDate = date;
      _selectedTime = null;
      _availableTimeSlots = const [];
      _loadingTimeSlots = true;
    });
    await _loadAvailableSlots(date);
  }

  Future<void> _loadAvailableSlots(DateTime date) async {
    try {
      final response = await widget.data.getAvailableSlots(
        subscriptionId: widget.subscription['id'].toString(),
        date: date,
      );
      if (!mounted) {
        return;
      }
      final slots = (response['slots'] as List? ?? const [])
          .whereType<Map>()
          .map((slot) => slot['time']?.toString() ?? '')
          .where((time) => time.isNotEmpty)
          .toList();
      setState(() {
        _availableTimeSlots = slots;
      });
      if (slots.isEmpty) {
        showDomlySnackBar(
          context,
          title: 'Нет доступных окон',
          subtitle: 'Выберите другую дату.',
          type: DomlySnackBarType.info,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedDate = null;
        _availableTimeSlots = const [];
      });
      showDomlySnackBar(
        context,
        title: 'Не удалось загрузить окна',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loadingTimeSlots = false);
      }
    }
  }

  Widget _buildAddonGroup(_BookingAddonGroupDef group) {
    final expanded = _expandedAddonGroups.contains(group.key);
    final selectedCount = _selectedCountForGroup(group);
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
              height: group.note == null ? 44 : 82,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  group.note == null ? 0 : 11,
                  12,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: group.note == null
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: group.note == null
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.label,
                            maxLines: group.note == null ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: DomlyColors.foreground,
                            ),
                          ),
                          if (group.note != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              group.note!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
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
                          color: DomlyColors.buttonPrimary.withValues(
                            alpha: 0.10,
                          ),
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

  Widget _buildAddonItem(_BookingAddonItemDef item) {
    final quantity = _addonQuantities[item.key] ?? 0;
    final unitPrice = _unitPriceFor(item.key);
    final isSeparate = item.separatePayment || item.key == 'carpet_cleaning';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DomlyColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
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
              width: 112,
              child: DomlySecondaryButton(
                onPressed: _submitting
                    ? null
                    : () =>
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
    required VoidCallback? onPlus,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DomlyColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _submitting ? null : onMinus,
            icon: const Icon(Icons.remove, size: 18),
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          IconButton(
            onPressed: _submitting ? null : onPlus,
            icon: const Icon(Icons.add, size: 18),
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
        .map(
          (entry) => <String, dynamic>{
            'key': entry.key,
            'label': labels[entry.key] ?? entry.key,
            'quantity': entry.value,
            'separate': separateKeys.contains(entry.key),
            'durationMinutes': (durations[entry.key] ?? 15) * entry.value,
          },
        )
        .toList();
  }

  int _selectedCountForGroup(_BookingAddonGroupDef group) {
    var total = 0;
    for (final item in group.items) {
      total += _addonQuantities[item.key] ?? 0;
    }
    return total;
  }

  int _billableAddonTotal() {
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

  List<_BookingAddonGroupDef> _mapAddonGroupConfigs(
    List<Map<String, dynamic>> groups,
  ) {
    if (groups.isEmpty) {
      return List<_BookingAddonGroupDef>.from(_fallbackAddonGroups);
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
                return _BookingAddonItemDef(
                  key: key,
                  label: (item['label'] ?? key).toString(),
                  supportsQuantity: item['supportsQuantity'] == true,
                  note: (item['note'] ?? '').toString().trim().isEmpty
                      ? null
                      : (item['note'] ?? '').toString(),
                  shortInfo: (item['shortInfo'] ??
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
          return _BookingAddonGroupDef(
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
        ? List<_BookingAddonGroupDef>.from(_fallbackAddonGroups)
        : mapped;
  }

  bool _hasSeparatePaymentAddons() {
    return _selectedAddonsDetailed().any((item) => item['separate'] == true);
  }

  void _changeAddonQuantity(String key, int nextQuantity) {
    setState(() {
      if (nextQuantity <= 0) {
        _addonQuantities.remove(key);
      } else {
        _addonQuantities[key] = nextQuantity;
      }
    });
  }

  String _formatMoney(int value) => '$value ₸';
}

class _BookingAddonItemDef {
  const _BookingAddonItemDef({
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

class _BookingAddonGroupDef {
  const _BookingAddonGroupDef({
    required this.key,
    required this.label,
    required this.items,
    this.note,
  });

  final String key;
  final String label;
  final List<_BookingAddonItemDef> items;
  final String? note;
}
