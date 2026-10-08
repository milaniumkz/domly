import 'dart:math' as math;

import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/debug_session.dart';
import '../../app/app_scope.dart';
import '../../localization/default_translation_sources.dart';
import '../../localization/translation_controller.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/photo_upload_service.dart';
import '../common/legal_document_screen.dart';
import 'widgets/verification_document_preview.dart';
import '../../ui/domly_ui.dart';
import '../../utils/order_display.dart';
import '../../utils/user_error_message.dart';
import 'widgets/osm_point_picker.dart';
import 'widgets/osm_polygon_picker.dart';

class AdminWebDashboardScreen extends StatefulWidget {
  const AdminWebDashboardScreen({super.key});

  @override
  State<AdminWebDashboardScreen> createState() =>
      _AdminWebDashboardScreenState();
}

class _AdminWebDashboardScreenState extends State<AdminWebDashboardScreen> {
  final _data = FirestoreDataService.instance;
  final _photoUploadService = PhotoUploadService();
  static final List<Map<String, dynamic>> _legalInfoContentDefaults = [
    {
      'id': LegalDocumentFallback.offerKey,
      'key': LegalDocumentFallback.offerKey,
      'title': LegalDocumentFallback.offer.title,
      'shortInfo': LegalDocumentFallback.offer.shortInfo,
      'fullInfo': LegalDocumentFallback.offer.fullInfo,
      'type': 'legal',
      'sortOrder': 1,
      'isActive': true,
    },
    {
      'id': LegalDocumentFallback.privacyKey,
      'key': LegalDocumentFallback.privacyKey,
      'title': LegalDocumentFallback.privacy.title,
      'shortInfo': LegalDocumentFallback.privacy.shortInfo,
      'fullInfo': LegalDocumentFallback.privacy.fullInfo,
      'type': 'legal',
      'sortOrder': 2,
      'isActive': true,
    },
  ];
  static const List<Map<String, String>> _promoBannerTargets = [
    {'label': 'Без перехода', 'route': ''},
    {'label': 'Главная', 'route': '/client/home'},
    {'label': 'Выбрать пакет', 'route': '/client/packages'},
    {'label': 'Калькулятор', 'route': '/client/calculator'},
    {'label': 'Бонусы', 'route': '/client/bonus'},
    {'label': 'Заказы', 'route': '/client/orders'},
    {'label': 'История оплат', 'route': '/client/payment-history'},
    {'label': 'Профиль', 'route': '/client/profile'},
    {'label': 'Настройки', 'route': '/client/settings'},
    {'label': 'Подтверждение площади', 'route': '/client/area-confirmation'},
    {'label': 'Выбор даты подписки', 'route': '/client/package-calendar'},
    {'label': 'Лист ожидания дома', 'route': '/client/house-waitlist'},
    {'label': 'Полезные видео', 'route': '/client/videos'},
    {'label': 'Уведомления', 'route': '/notifications'},
    {'label': 'Чат', 'route': '/chat'},
    {'label': 'Жалоба', 'route': '/complaint'},
    {'label': 'Оценка уборки', 'route': '/review'},
  ];
  bool _debugActionApplied = false;
  int _selectedIndex = 0;
  String _searchQuery = '';
  String _statusFilter = 'Все';
  String _clusterFilter = 'Все';
  String _cleanerFilter = 'Все';
  String _serviceAreaFilter = 'Все';
  String _assignmentStatusFilter = 'Все';
  String _ordersTabFilter = 'Все заказы';
  String _customerStatusFilter = 'Все';
  String _customerHouseFilter = 'Все';
  String _dictionaryLocale = 'ru';
  bool _dictionaryOnlyMissing = false;
  String _dateSortOrder = 'Сначала новые';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  final Set<String> _selectedOrderIds = <String>{};
  final Set<String> _selectedVerificationIds = <String>{};
  final Set<String> _selectedAreaReportIds = <String>{};
  String _adminRoleLabel = 'Администратор';
  bool _canManagePolicies = true;
  bool _canPublishVideos = true;
  bool _canRunPayouts = true;
  bool _canEditCleaners = true;
  bool _canEditClusters = true;
  bool _canEditCatalog = true;
  bool _canActivateHouses = true;

  List<Map<String, dynamic>> _debugSeedOrders() {
    final now = DateTime.now();
    return <Map<String, dynamic>>[
      {
        'id': 'cust_order_active_1',
        'orderStatus': 'confirmed',
        'status': 'confirmed',
        'paymentStatus': 'paid',
        'scheduledFor': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day + 1, 10, 0),
        ),
        'createdAt': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 1),
        ),
        'time': '10:00 - 13:00',
        'package': '4 раза в месяц',
        'price': 25000,
        'address': 'ЖК Триумф, кв. 45',
        'residentialComplex': 'ЖК Триумф',
        'clusterName': 'ЖК Триумф',
        'customerId': 'customer_demo',
        'customerName': 'Асет',
        'customerPhone': '+7 708 636 21 53',
        'cleanerId': 'cleaner_demo',
        'cleanerName': 'Мария',
      },
      {
        'id': 'cust_order_done_1',
        'orderStatus': 'completed',
        'status': 'completed',
        'paymentStatus': 'paid',
        'scheduledFor': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 6),
        ),
        'createdAt': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day - 7),
        ),
        'time': '10:00 - 13:00',
        'package': '4 раза в месяц',
        'price': 25000,
        'address': 'ЖК Триумф, кв. 45',
        'residentialComplex': 'ЖК Триумф',
        'clusterName': 'ЖК Триумф',
        'customerId': 'customer_demo',
        'customerName': 'Асет',
        'customerPhone': '+7 708 636 21 53',
        'cleanerId': 'cleaner_demo',
        'cleanerName': 'Мария',
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _applyUrlSectionSelection();
    _applyDebugSectionSelection();
    _loadAdminCapabilities();
  }

  void _applyUrlSectionSelection() {
    final fragment = Uri.base.fragment.trim();
    final queryIndex = fragment.indexOf('?');
    if (queryIndex < 0) {
      return;
    }
    final fragmentUri = Uri.tryParse(fragment);
    final sectionKey = fragmentUri?.queryParameters['section']?.trim();
    if (sectionKey == null || sectionKey.isEmpty) {
      return;
    }
    final index = _sectionIndexByKey(sectionKey);
    if (index >= 0) {
      _selectedIndex = index;
    }
  }

  void _applyDebugSectionSelection() {
    if (!DebugSession.enabled || DebugSession.uid != 'admin_demo') {
      return;
    }
    final sectionKey = DebugSession.value('debug_section')?.trim();
    if (sectionKey == null || sectionKey.isEmpty) {
      return;
    }
    final index = _sectionIndexByKey(sectionKey);
    if (index >= 0) {
      _selectedIndex = index;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyDebugActionIfNeeded();
  }

  void _applyDebugActionIfNeeded() {
    if (_debugActionApplied ||
        !DebugSession.enabled ||
        DebugSession.uid != 'admin_demo') {
      return;
    }
    final debugAction = DebugSession.value('debug_action')?.trim();
    if (debugAction != 'resolve_complaint') {
      _debugActionApplied = true;
      return;
    }
    final complaintId = DebugSession.value('debug_complaint_id')?.trim();
    if (complaintId == null || complaintId.isEmpty) {
      _debugActionApplied = true;
      return;
    }
    final status =
        DebugSession.value('debug_complaint_status')?.trim().toLowerCase() ??
            'resolved';
    _debugActionApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _data.createAdminAction({
        'type': 'complaint_resolution',
        'complaintId': complaintId,
        'status': status,
        'resolution': status == 'compensated'
            ? 'Компенсация клиенту'
            : status == 'refund'
                ? 'Полный возврат'
                : 'Жалоба закрыта',
        'compensationAmount': status == 'compensated' ? 5000 : 0,
      });
      if (!mounted) {
        return;
      }
      if (_statusFilter != 'Все' && _statusFilter != status) {
        setState(() => _statusFilter = 'Все');
      } else {
        setState(() {});
      }
    });
  }

  List<Map<String, dynamic>> _applyDebugComplaintOverrides(
    List<Map<String, dynamic>> source,
  ) {
    if (!DebugSession.enabled || DebugSession.uid != 'admin_demo') {
      return source;
    }
    final action = DebugSession.value('debug_action')?.trim();
    final complaintId = DebugSession.value('debug_complaint_id')?.trim();
    final status = DebugSession.value(
      'debug_complaint_status',
    )?.trim().toLowerCase();
    if (action != 'resolve_complaint' ||
        complaintId == null ||
        complaintId.isEmpty ||
        status == null ||
        status.isEmpty) {
      return source;
    }
    return source
        .map(
          (item) =>
              item['id'] == complaintId ? {...item, 'status': status} : item,
        )
        .toList();
  }

  String _debugComplaintStatusOverride(String complaintId, String fallback) {
    if (!DebugSession.enabled || DebugSession.uid != 'admin_demo') {
      return fallback;
    }
    final action = DebugSession.value('debug_action')?.trim();
    final status = DebugSession.value(
      'debug_complaint_status',
    )?.trim().toLowerCase();
    if (action == 'resolve_complaint' && status != null && status.isNotEmpty) {
      return status;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final currentSection = sections[_selectedIndex];
    final isWide = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        title: Text(
          'DOMLY Админ-панель'.tr(),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined, size: 16),
                const SizedBox(width: 8),
                Text(
                  _adminRoleLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Веб-интерфейс управления'.tr(),
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: _handleSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isWide ? null : Drawer(child: _buildSidebar(compact: false)),
      body: Row(
        children: [
          if (isWide) _buildSidebar(compact: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const minContentWidth = 980.0;
                final contentWidth = constraints.maxWidth < minContentWidth
                    ? minContentWidth
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(currentSection),
                          const SizedBox(height: 18),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0F111827),
                                    blurRadius: 24,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: currentSection.builder(),
                              ),
                            ),
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
    );
  }

  Future<void> _handleSignOut() async {
    final navigator = Navigator.of(context);
    await AppScope.of(context).authController.signOut();
    if (!mounted) {
      return;
    }
    navigator.pushNamedAndRemoveUntil('/admin/web', (_) => false);
  }

  Widget _buildHeader(_AdminSection currentSection) {
    final isNarrowHeader = MediaQuery.of(context).size.width < 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Операционный центр / ${currentSection.title}'.tr(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 8),
        Flex(
          direction: isNarrowHeader ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isNarrowHeader)
              Expanded(child: _headerTitleBlock(currentSection))
            else
              _headerTitleBlock(currentSection),
            SizedBox(
              width: isNarrowHeader ? 0 : 16,
              height: isNarrowHeader ? 16 : 0,
            ),
            if (!isNarrowHeader)
              _headerActions(currentSection.key)
            else
              SizedBox(
                width: double.infinity,
                child: _headerActions(currentSection.key, fullWidth: true),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _globalFiltersBar(),
        const SizedBox(height: 10),
        _savedViewsBar(currentSection.key),
      ],
    );
  }

  Widget _globalFiltersBar() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dateFilterButton(
          label: _filterStartDate == null
              ? 'Дата от'
              : 'От ${_dateLabel(_filterStartDate!)}',
          onTap: () => _pickFilterDate(isStart: true),
        ),
        _dateFilterButton(
          label: _filterEndDate == null
              ? 'Дата до'
              : 'До ${_dateLabel(_filterEndDate!)}',
          onTap: () => _pickFilterDate(isStart: false),
        ),
        _compactDropdown(
          value: _dateSortOrder,
          label: 'Сортировка',
          items: const ['Сначала новые', 'Сначала старые'],
          onChanged: (value) =>
              setState(() => _dateSortOrder = value ?? 'Сначала новые'),
        ),
        if (_filterStartDate != null || _filterEndDate != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _filterStartDate = null;
              _filterEndDate = null;
            }),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text('Сбросить даты'.tr()),
          ),
      ],
    );
  }

  Widget _headerTitleBlock(_AdminSection currentSection) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentSection.title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          currentSection.subtitle,
          style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  Widget _headerActions(String sectionKey, {bool fullWidth = false}) {
    return Column(
      crossAxisAlignment:
          fullWidth ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
      children: [
        Flex(
          direction: fullWidth ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: fullWidth
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: fullWidth ? double.infinity : 320,
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: _selectedIndex == 0
                      ? 'Поиск по панели управления'
                      : 'Поиск в разделе',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ),
            ),
            SizedBox(width: fullWidth ? 0 : 12, height: fullWidth ? 12 : 0),
            OutlinedButton.icon(
              onPressed: () => _openSaveViewDialog(sectionKey),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text('Сохранить вид'.tr()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _savedViewsBar(String sectionKey) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminSavedViewsStream(),
      builder: (context, snapshot) {
        final views = (snapshot.data ?? const <Map<String, dynamic>>[])
            .where((item) => (item['sectionKey'] ?? '') == sectionKey)
            .toList()
          ..sort(
            (a, b) => ((b['updatedAt'] as num?)?.toInt() ?? 0).compareTo(
              (a['updatedAt'] as num?)?.toInt() ?? 0,
            ),
          );
        if (views.isEmpty) {
          return const SizedBox.shrink();
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: views.map((view) {
            final isActive = (view['searchQuery'] ?? '') == _searchQuery &&
                (view['statusFilter'] ?? 'Все') == _statusFilter;
            return Container(
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF93C5FD)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() {
                      _searchQuery = (view['searchQuery'] ?? '').toString();
                      _statusFilter =
                          (view['statusFilter'] ?? 'Все').toString();
                      _clusterFilter =
                          (view['clusterFilter'] ?? 'Все').toString();
                      _cleanerFilter =
                          (view['cleanerFilter'] ?? 'Все').toString();
                      _serviceAreaFilter =
                          (view['serviceAreaFilter'] ?? 'Все').toString();
                      _assignmentStatusFilter =
                          (view['assignmentStatusFilter'] ?? 'Все').toString();
                      _filterStartDate = _millisToDate(
                        (view['filterStartDate'] as num?)?.toInt(),
                      );
                      _filterEndDate = _millisToDate(
                        (view['filterEndDate'] as num?)?.toInt(),
                      );
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        (view['name'] ?? 'Вид').toString(),
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF374151),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        _deleteSavedView((view['id'] ?? '').toString()),
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSidebar({required bool compact}) {
    final sections = _sections;
    return Container(
      width: compact ? 280 : double.infinity,
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DOMLY',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Управление заказами, персоналом и контентом'.tr(),
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  final selected = index == _selectedIndex;
                  return Material(
                    color:
                        selected ? const Color(0xFF1D4ED8) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                          _searchQuery = '';
                          _statusFilter = 'Все';
                          _clusterFilter = 'Все';
                          _cleanerFilter = 'Все';
                          _serviceAreaFilter = 'Все';
                          _assignmentStatusFilter = 'Все';
                          _dateSortOrder = 'Сначала новые';
                          _filterStartDate = null;
                          _filterEndDate = null;
                          _selectedOrderIds.clear();
                          _selectedVerificationIds.clear();
                          _selectedAreaReportIds.clear();
                        });
                        if (!compact) {
                          Navigator.pop(context);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              section.icon,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFFCBD5E1),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                section.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
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
  }

  List<_AdminSection> get _sections => [
        _AdminSection(
          key: 'dashboard',
          title: 'Дашборд',
          subtitle:
              'Главные показатели, узкие места и ближайшие действия менеджера.',
          icon: Icons.dashboard_customize_outlined,
          builder: _dashboard,
        ),
        _AdminSection(
          key: 'orders',
          title: 'Заказы',
          subtitle:
              'Назначение, контроль статусов и ручные действия по заказам.',
          icon: Icons.receipt_long_outlined,
          builder: _orders,
        ),
        _AdminSection(
          key: 'customers',
          title: 'Пользователи',
          subtitle:
              'Новые регистрации, телефоны, адреса, бонусы и быстрый поиск клиентов.',
          icon: Icons.people_alt_outlined,
          builder: _customers,
        ),
        _AdminSection(
          key: 'complaints',
          title: 'Жалобы',
          subtitle:
              'Работа с обращениями клиентов, компенсациями и возвратами.',
          icon: Icons.report_problem_outlined,
          builder: _complaints,
        ),
        _AdminSection(
          key: 'payments',
          title: 'Платежи',
          subtitle: 'Статусы оплат по заказам и контроль денежных поступлений.',
          icon: Icons.payments_outlined,
          builder: _payments,
        ),
        _AdminSection(
          key: 'special_addons',
          title: 'Спец. допы',
          subtitle:
              'Мебель, поверхности и химчистка ковров для вызова профильных специалистов.',
          icon: Icons.handyman_outlined,
          builder: _specialAddons,
        ),
        _AdminSection(
          key: 'payouts',
          title: 'Выплаты',
          subtitle: 'Начисления уборщицам и запуск weekly payout.',
          icon: Icons.account_balance_wallet_outlined,
          builder: _payouts,
        ),
        _AdminSection(
          key: 'admin_notifications',
          title: 'Уведомления',
          subtitle: 'Все push-события для администраторов.',
          icon: Icons.notifications_active_outlined,
          builder: _adminNotifications,
        ),
        _AdminSection(
          key: 'reviews',
          title: 'Отзывы',
          subtitle: 'Клиентские оценки, тексты отзывов и фотографии.',
          icon: Icons.star_border_outlined,
          builder: _reviews,
        ),
        _AdminSection(
          key: 'checklists',
          title: 'Чек-листы',
          subtitle: 'Проверка выполненных задач и допуслуг по заказам.',
          icon: Icons.checklist_outlined,
          builder: _checklists,
        ),
        _AdminSection(
          key: 'cleaners',
          title: 'Уборщицы',
          subtitle: 'Справочник исполнителей, кластеры и статусы верификации.',
          icon: Icons.cleaning_services_outlined,
          builder: _cleaners,
        ),
        _AdminSection(
          key: 'clusters',
          title: 'Кластеры',
          subtitle:
              'Управление зонами закрепления уборщиц и географией работы.',
          icon: Icons.hub_outlined,
          builder: _clusters,
        ),
        _AdminSection(
          key: 'schedule',
          title: 'Расписание',
          subtitle: 'Календарь слотов по кластерам и текущая нагрузка.',
          icon: Icons.calendar_month_outlined,
          builder: _clusterSchedule,
        ),
        _AdminSection(
          key: 'verifications',
          title: 'Верификация',
          subtitle: 'Проверка документов уборщиц и принятие решения.',
          icon: Icons.verified_user_outlined,
          builder: _verifications,
        ),
        _AdminSection(
          key: 'houses',
          title: 'Дома',
          subtitle: 'Статусы подключения домов и пороги активации.',
          icon: Icons.apartment_outlined,
          builder: _houses,
        ),
        _AdminSection(
          key: 'waitlist',
          title: 'Лист ожидания',
          subtitle: 'Заявки домов, которые еще не активированы.',
          icon: Icons.groups_outlined,
          builder: _waitlist,
        ),
        _AdminSection(
          key: 'prelaunch',
          title: 'Предзапись',
          subtitle: 'Предварительные записи клиентов до запуска оплаты.',
          icon: Icons.event_available_outlined,
          builder: _prelaunchBookings,
        ),
        _AdminSection(
          key: 'quality_control',
          title: 'Отдел контроля качества',
          subtitle:
              'Заявки на проверку квадратуры, звонки клиентам и перерасчет.',
          icon: Icons.support_agent_outlined,
          builder: _qualityControlDepartment,
        ),
        _AdminSection(
          key: 'zones',
          title: 'Зоны покрытия',
          subtitle: 'Сервисные зоны, города и состояние покрытия.',
          icon: Icons.map_outlined,
          builder: _zones,
        ),
        _AdminSection(
          key: 'referrals',
          title: 'Рефералы',
          subtitle:
              'Статистика приглашений, регистраций и оплаченных рекомендаций.',
          icon: Icons.campaign_outlined,
          builder: _referrals,
        ),
        _AdminSection(
          key: 'area',
          title: 'Проверка площади',
          subtitle: 'Расхождения по площади квартиры и ручное закрытие кейсов.',
          icon: Icons.square_foot_outlined,
          builder: _areaMismatchReports,
        ),
        _AdminSection(
          key: 'videos',
          title: 'Видео и обучение',
          subtitle: 'Полезные материалы для клиентов и обучение уборщиц.',
          icon: Icons.ondemand_video_outlined,
          builder: _videos,
        ),
        _AdminSection(
          key: 'promo_banners',
          title: 'Баннеры на главной',
          subtitle: 'Рекламные акции и промо-баннеры, которые видят клиенты.',
          icon: Icons.photo_library_outlined,
          builder: _promoBanners,
        ),
        _AdminSection(
          key: 'promotions',
          title: 'Акции',
          subtitle: 'Автоматические бонусы за покупку пакетов и доп. услуг.',
          icon: Icons.local_offer_outlined,
          builder: _promotions,
        ),
        _AdminSection(
          key: 'info_content',
          title: 'Инфо-контент',
          subtitle:
              'Тексты и информация для пакетов, допуслуг и экранов с кнопками i.',
          icon: Icons.info_outline,
          builder: _infoContent,
        ),
        _AdminSection(
          key: 'addon_catalog',
          title: 'Доп. услуги',
          subtitle:
              'Группы и позиции допуслуг для калькулятора и заказа уборки.',
          icon: Icons.playlist_add_check_circle_outlined,
          builder: _addonCatalog,
        ),
        _AdminSection(
          key: 'checklist_templates',
          title: 'Шаблоны чек-листа',
          subtitle:
              'Базовые задачи и шаблоны допуслуг, которые видит уборщица.',
          icon: Icons.fact_check_outlined,
          builder: _checklistTemplates,
        ),
        _AdminSection(
          key: 'dictionaries',
          title: 'Словари',
          subtitle: 'Редактирование переводов приложения по локалям.',
          icon: Icons.translate_outlined,
          builder: _translationDictionaries,
        ),
        _AdminSection(
          key: 'packages',
          title: 'Пакеты',
          subtitle: 'Названия, частота, скидки и параметры клиентских пакетов.',
          icon: Icons.inventory_2_outlined,
          builder: _packagesConfig,
        ),
        _AdminSection(
          key: 'policies',
          title: 'Настройки',
          subtitle: 'Бонусы, пороги домов, проверка площади и время уборки.',
          icon: Icons.tune_outlined,
          builder: _policies,
        ),
      ];

  Widget _dashboard() {
    final query = _searchQuery.trim().toLowerCase();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _listMetricCard(
                title: 'Активные заказы',
                subtitle: 'Заказы в работе и на подтверждении',
                icon: Icons.receipt_long_outlined,
                stream: _data.adminOrdersStream(),
                countBuilder: (items) => items.where((doc) {
                  final status = (doc['orderStatus'] ?? '').toString();
                  return status == 'confirmed' ||
                      status == 'assigned' ||
                      status == 'in_progress';
                }).length,
              ),
              _listMetricCard(
                title: 'Без назначения',
                subtitle: 'Нужен выбор уборщицы',
                icon: Icons.person_search_outlined,
                stream: _data.adminOrdersStream(),
                countBuilder: (items) => items.where((data) {
                  final status =
                      (data['orderStatus'] ?? '').toString().toLowerCase();
                  final cleanerId = (data['cleanerId'] ?? '').toString();
                  return cleanerId.isEmpty &&
                      status != 'completed' &&
                      status != 'canceled' &&
                      status != 'cancelled';
                }).length,
                accent: const Color(0xFFD97706),
              ),
              _listMetricCard(
                title: 'Верификация',
                subtitle: 'Ожидают решения менеджера',
                icon: Icons.verified_user_outlined,
                stream: _data.allCleanerVerificationsStream(),
                countBuilder: (items) => items.where((doc) {
                  final status =
                      (doc['status'] ?? 'pending').toString().toLowerCase();
                  return status == 'pending';
                }).length,
                accent: const Color(0xFF7C3AED),
              ),
              _listMetricCard(
                title: 'Жалобы в работе',
                subtitle: 'Нужна реакция или закрытие',
                icon: Icons.report_problem_outlined,
                stream: _data.complaintsStream(admin: true),
                countBuilder: (items) => items.where((doc) {
                  final status =
                      (doc['status'] ?? 'open').toString().toLowerCase();
                  return status != 'resolved' && status != 'refund';
                }).length,
                accent: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _dashboardPanel(
                      title: 'Требуют внимания',
                      subtitle:
                          'Зоны, где менеджеру лучше действовать в первую очередь',
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _data.housesStream(admin: true),
                        builder: (context, snapshot) {
                          final items =
                              (snapshot.data ?? const <Map<String, dynamic>>[])
                                  .where((house) {
                            final title =
                                '${house['address'] ?? house['id']} ${house['status'] ?? ''}'
                                    .toLowerCase();
                            if (query.isNotEmpty && !title.contains(query)) {
                              return false;
                            }
                            final status = (house['status'] ?? '')
                                .toString()
                                .toUpperCase();
                            return status != 'ACTIVE';
                          }).toList();
                          items.sort((a, b) {
                            final leftThreshold =
                                (a['threshold'] as num?)?.toInt() ?? 20;
                            final rightThreshold =
                                (b['threshold'] as num?)?.toInt() ?? 20;
                            final leftUsers =
                                (a['current_users'] as num?)?.toInt() ?? 0;
                            final rightUsers =
                                (b['current_users'] as num?)?.toInt() ?? 0;
                            final leftGap = math.max(
                              leftThreshold - leftUsers,
                              0,
                            );
                            final rightGap = math.max(
                              rightThreshold - rightUsers,
                              0,
                            );
                            return leftGap.compareTo(rightGap);
                          });
                          return _simpleAdminList(
                            emptyText:
                                'Нет домов, требующих реакции. Все дома либо активны, либо не попали в фильтр поиска.',
                            items: items.take(6).map((house) {
                              final threshold =
                                  (house['threshold'] as num?)?.toInt() ?? 20;
                              final current =
                                  (house['current_users'] as num?)?.toInt() ??
                                      0;
                              final remaining = math.max(
                                threshold - current,
                                0,
                              );
                              final houseStatus =
                                  (house['status'] ?? 'INACTIVE')
                                      .toString()
                                      .toUpperCase();
                              return _AdminListItem(
                                title: (house['address'] ?? house['id'])
                                    .toString(),
                                subtitle:
                                    'Статус: ${_houseStatusLabel(houseStatus)} · Осталось $remaining квартир',
                                trailing: _statusBadge(
                                  _houseStatusLabel(houseStatus),
                                  color: houseStatus == 'ACTIVE'
                                      ? const Color(0xFF047857)
                                      : const Color(0xFFD97706),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dashboardPanel(
                      title: 'Ближайшие операционные действия',
                      subtitle: 'Текущие очереди по критичным объектам',
                      child: Column(
                        children: [
                          _quickActionTile(
                            title: 'Проверить документы уборщиц',
                            subtitle:
                                'Очередь верификации должна закрываться ежедневно',
                            icon: Icons.verified_user_outlined,
                            onTap: () => setState(
                              () => _selectedIndex = _sectionIndexByKey(
                                'verifications',
                              ),
                            ),
                          ),
                          _quickActionTile(
                            title: 'Разобрать заказы без назначения',
                            subtitle:
                                'Исключить провисание в графике и ручные конфликты',
                            icon: Icons.assignment_ind_outlined,
                            onTap: () => setState(
                              () =>
                                  _selectedIndex = _sectionIndexByKey('orders'),
                            ),
                          ),
                          _quickActionTile(
                            title: 'Проверить новые видео и публикации',
                            subtitle:
                                'Контент должен быть актуален для клиентов и уборщиц',
                            icon: Icons.ondemand_video_outlined,
                            onTap: () => setState(
                              () =>
                                  _selectedIndex = _sectionIndexByKey('videos'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _dashboardPanel(
                      title: 'Проблемные сигналы',
                      subtitle: 'Новые обращения и спорные кейсы',
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _data.areaMismatchReportsStream(),
                        builder: (context, mismatchSnapshot) {
                          final mismatchCount = (mismatchSnapshot.data ??
                                  const <Map<String, dynamic>>[])
                              .where(
                                (doc) =>
                                    (doc['status'] ?? 'open') != 'resolved',
                              )
                              .length;
                          return StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _data.adminReferralStatsStream(),
                            builder: (context, referralSnapshot) {
                              final referralDocs = referralSnapshot.data ??
                                  <Map<String, dynamic>>[];
                              referralDocs.sort((a, b) {
                                final left = (a['paid'] as num?)?.toInt() ?? 0;
                                final right = (b['paid'] as num?)?.toInt() ?? 0;
                                return right.compareTo(left);
                              });
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _signalRow(
                                    'Новые area mismatch',
                                    '$mismatchCount кейсов',
                                    const Color(0xFFD97706),
                                  ),
                                  const SizedBox(height: 12),
                                  _signalRow(
                                    'Сильные рефералы',
                                    referralDocs.isEmpty
                                        ? 'Пока нет активности'
                                        : 'Лидеры: ${referralDocs.take(3).map((doc) => (doc['id'] ?? '—').toString()).join(', ')}',
                                    const Color(0xFF2563EB),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dashboardPanel(
                      title: 'Рост и конверсия',
                      subtitle: 'Понимание, как движется спрос и рекомендации',
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _data.adminReferralStatsStream(),
                        builder: (context, referralSnapshot) {
                          final referralDocs =
                              referralSnapshot.data ?? <Map<String, dynamic>>[];
                          final invited = referralDocs.fold<int>(
                            0,
                            (total, doc) =>
                                total +
                                ((doc['invited'] as num?)?.toInt() ?? 0),
                          );
                          final paid = referralDocs.fold<int>(
                            0,
                            (total, doc) =>
                                total + ((doc['paid'] as num?)?.toInt() ?? 0),
                          );
                          final conversion = invited == 0
                              ? 0
                              : ((paid / invited) * 100).round();
                          return StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _data.adminWaitlistStream(),
                            builder: (context, waitlistSnapshot) {
                              final waitlistCount =
                                  waitlistSnapshot.data?.length ?? 0;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _signalRow(
                                    'Waitlist',
                                    '$waitlistCount заявок в неактивных домах',
                                    const Color(0xFF2563EB),
                                  ),
                                  const SizedBox(height: 12),
                                  _signalRow(
                                    'Referral paid conversion',
                                    '$conversion% от приглашений дошли до оплаты',
                                    const Color(0xFF047857),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dashboardPanel(
                      title: 'Ближайшие выплаты',
                      subtitle: 'Мониторинг регулярных переводов',
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _data.adminPayoutsStream(),
                        builder: (context, snapshot) {
                          final docs = _sortRecordsByDate(
                            (snapshot.data ?? <Map<String, dynamic>>[]).where(
                              _matchesRecordDateRange,
                            ),
                          );
                          return _simpleAdminList(
                            emptyText: 'Выплаты пока не созданы.',
                            items: docs.take(5).map((data) {
                              return _AdminListItem(
                                title: (data['cleanerId'] ?? '—').toString(),
                                subtitle:
                                    'К выплате ${(data['net'] ?? 0)} ₸ · Налог ${(data['tax'] ?? 0)} ₸',
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _customers() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminCustomersStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final allCustomers = snapshot.data ?? const <Map<String, dynamic>>[];
        final houseOptions = allCustomers
            .map(
              (item) => _firstText([
                item['residentialComplex'],
                item['houseTitle'],
                item['houseName'],
                item['houseId'],
              ]),
            )
            .where((value) => value != '—')
            .toSet()
            .toList()
          ..sort();
        final filteredCustomers = allCustomers.where((item) {
          final status = _customerProfileStatus(item);
          final house = _firstText([
            item['residentialComplex'],
            item['houseTitle'],
            item['houseName'],
            item['houseId'],
          ]);
          final matchesDate = _matchesRecordDateRange(item);
          final matchesStatus =
              _customerStatusFilter == 'Все' || status == _customerStatusFilter;
          final matchesHouse =
              _customerHouseFilter == 'Все' || house == _customerHouseFilter;
          final matchesQuery =
              query.isEmpty || _customerSearchText(item).contains(query);
          return matchesDate && matchesStatus && matchesHouse && matchesQuery;
        });
        final customers = _sortCustomersByRegistrationDate(filteredCustomers);

        return _sectionScaffold(
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterChip(
                label: 'Все: ${allCustomers.length}',
                selected: _customerStatusFilter == 'Все',
                onTap: () => setState(() => _customerStatusFilter = 'Все'),
              ),
              for (final status in const ['Заполнен', 'Без адреса', 'Новый'])
                _filterChip(
                  label:
                      '$status: ${allCustomers.where((item) => _customerProfileStatus(item) == status).length}',
                  selected: _customerStatusFilter == status,
                  onTap: () => setState(() => _customerStatusFilter = status),
                ),
              DropdownButton<String>(
                value: _customerHouseFilter,
                items: [
                  DropdownMenuItem(value: 'Все', child: Text('Все дома'.tr())),
                  ...houseOptions.map(
                    (house) =>
                        DropdownMenuItem(value: house, child: Text(house)),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _customerHouseFilter = value ?? 'Все'),
              ),
              OutlinedButton.icon(
                onPressed: customers.isEmpty
                    ? null
                    : () => _copyCustomersCsv(customers),
                icon: const Icon(Icons.download_outlined),
                label: Text('Экспорт CSV'.tr()),
              ),
            ],
          ),
          child: snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : customers.isEmpty
                  ? _emptyState(
                      'Пользователи не найдены',
                      'Измените поиск или фильтр. Новый клиент появится здесь после SMS-входа.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _customerCard(context, customers[index], index + 1),
                    ),
        );
      },
    );
  }

  Widget _customerCard(
    BuildContext context,
    Map<String, dynamic> customer,
    int displayNumber,
  ) {
    final name = _firstText([
      customer['name'],
      customer['fullName'],
      customer['displayName'],
      'Пользователь',
    ]);
    final phone = _firstText([
      customer['phone'],
      customer['phoneNumber'],
      customer['customerPhone'],
    ]);
    final address = _customerPrimaryAddress(customer);
    final house = _firstText([
      customer['residentialComplex'],
      customer['houseTitle'],
      customer['houseName'],
      customer['houseId'],
    ]);
    final status = _customerProfileStatus(customer);
    final bonuses = (customer['bonusPoints'] as num?)?.toInt() ??
        (customer['bonuses'] as num?)?.toInt() ??
        0;
    final area = _firstText([customer['area'], customer['apartmentArea']]);

    return _entityCard(
      title: name,
      subtitle: [
        phone,
        if (address != '—') address,
        if (house != '—') house,
      ].where((item) => item != '—').join(' · '),
      badges: [
        _statusBadge(
          status,
          color: status == 'Заполнен'
              ? const Color(0xFF047857)
              : status == 'Без адреса'
                  ? const Color(0xFFD97706)
                  : const Color(0xFF64748B),
        ),
      ],
      body: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _miniInfo('Телефон', phone),
          _miniInfo('№', displayNumber.toString()),
          _miniInfo('Регистрация', _customerDate(customer)),
          _miniInfo('Дом', house),
          _miniInfo('Площадь', area == '—' ? '—' : '$area м²'),
          _miniInfo('Бонусы', '$bonuses ₸'),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: phone == '—'
              ? null
              : () => Clipboard.setData(ClipboardData(text: phone)),
          icon: const Icon(Icons.copy_outlined),
          label: Text('Скопировать телефон'.tr()),
        ),
        TextButton(
          onPressed: () =>
              _openCustomerDetails(context, customer, displayNumber),
          child: Text('Все данные'.tr()),
        ),
      ],
    );
  }

  String _customerSearchText(Map<String, dynamic> customer) {
    final addresses = customer['addresses'];
    final addressText = addresses is List
        ? addresses.map((item) => item.toString()).join(' ')
        : '';
    return [
      customer['id'],
      customer['name'],
      customer['fullName'],
      customer['displayName'],
      customer['phone'],
      customer['phoneNumber'],
      customer['customerPhone'],
      customer['city'],
      customer['address'],
      customer['homeAddress'],
      customer['residentialComplex'],
      customer['houseId'],
      customer['entrance'],
      customer['apartment'],
      customer['referralCode'],
      addressText,
    ].join(' ').toLowerCase();
  }

  String _customerProfileStatus(Map<String, dynamic> customer) {
    final hasAddress = _customerPrimaryAddress(customer) != '—' ||
        _firstText([customer['houseId'], customer['residentialComplex']]) !=
            '—';
    if (hasAddress) {
      return 'Заполнен';
    }
    final createdAt = customer['createdAt'] ?? customer['registeredAt'];
    if (createdAt is Timestamp &&
        DateTime.now().difference(createdAt.toDate()).inHours < 24) {
      return 'Новый';
    }
    return 'Без адреса';
  }

  String _customerPrimaryAddress(Map<String, dynamic> customer) {
    final addresses = customer['addresses'];
    if (addresses is List && addresses.isNotEmpty) {
      final first = addresses.first;
      if (first is Map) {
        return _firstText([
          first['address'],
          first['fullAddress'],
          first['residentialComplex'],
          first['title'],
        ]);
      }
      return first.toString();
    }
    return _firstText([
      customer['address'],
      customer['homeAddress'],
      customer['fullAddress'],
    ]);
  }

  String _personName(
    Map<String, dynamic> profile,
    Map<String, dynamic> fallback, {
    required String prefix,
  }) {
    final fullName = _firstText([
      profile['fullName'],
      [
        profile['lastName'] ?? profile['surname'],
        profile['firstName'] ?? profile['name'],
        profile['middleName'] ?? profile['patronymic'],
      ].where((value) => (value ?? '').toString().trim().isNotEmpty).join(' '),
      profile['displayName'],
      profile['name'],
      fallback['${prefix}Name'],
      fallback[prefix == 'customer' ? 'clientName' : 'executorName'],
    ]);
    return fullName == '—' ? 'Данные не найдены' : fullName;
  }

  String _personPhone(
    Map<String, dynamic> profile,
    Map<String, dynamic> fallback, {
    required String prefix,
  }) {
    return _firstText([
      profile['phone'],
      profile['phoneNumber'],
      fallback['${prefix}Phone'],
      fallback[prefix == 'customer' ? 'clientPhone' : 'executorPhone'],
    ]);
  }

  String _listText(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is Iterable) {
      final text = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
      return text;
    }
    return _firstText([value]);
  }

  String _cleanerAreasText(Map<String, dynamic> cleaner) {
    return _firstText([
      _listText(cleaner['serviceAreas']),
      _listText(cleaner['serviceAreaIds']),
      cleaner['serviceArea'],
      cleaner['district'],
      cleaner['clusterName'],
    ]);
  }

  List<_DetailSection> _cleanerDetailSections(
    Map<String, dynamic> cleaner, {
    Map<String, dynamic>? dailySchedule,
    String? scheduleDate,
    List<Map<String, dynamic>> orders = const [],
  }) {
    final verification =
        (cleaner['verificationStatus'] ?? cleaner['status'] ?? 'draft')
            .toString()
            .toLowerCase();
    final earnings = (cleaner['monthlyEarnings'] as num?)?.toInt() ?? 0;
    final schedule = dailySchedule ?? const <String, dynamic>{};
    final totalSqm = (schedule['totalSqm'] as num?)?.toDouble() ?? 0;
    final totalMinutes = (schedule['totalMinutes'] as num?)?.toInt() ?? 0;
    final totalTravelMinutes =
        (schedule['totalTravelMinutes'] as num?)?.toInt() ?? 0;
    final assignedOrders = ((schedule['orders'] as List?) ?? const []).length;
    final sections = <_DetailSection>[
      _detailSection('Профиль', {
        'ID': _firstText([cleaner['id'], cleaner['cleanerId']]),
        'ФИО': _personName(cleaner, const {}, prefix: 'cleaner'),
        'Телефон': _personPhone(cleaner, const {}, prefix: 'cleaner'),
        'Email': _firstText([cleaner['email']]),
        'Город': _firstText([cleaner['city']]),
        'Районы работы': _cleanerAreasText(cleaner),
        'Кластер': _firstText([cleaner['clusterName']]),
        'Статус верификации': _cleanerVerificationLabel(verification),
      }),
      _detailSection('Метрики', {
        'Рейтинг': _firstText([cleaner['rating']]),
        'Заказы': _firstText([cleaner['jobsCount'], cleaner['ordersCount']]),
        'Доход за месяц': '$earnings ₸',
        'Баланс': '${cleaner['currentBalance'] ?? cleaner['balance'] ?? 0} ₸',
      }),
    ];
    if (dailySchedule != null) {
      sections.add(
        _detailSection('Нагрузка на день', {
          'Дата': scheduleDate ?? _firstText([schedule['dateKey']]),
          'Заказов': '$assignedOrders',
          'м²/день': '${totalSqm.toStringAsFixed(0)} / 220',
          'Часы/день': '${(totalMinutes / 60).toStringAsFixed(1)} ч',
          'Дорога': '$totalTravelMinutes мин',
          'Осталось м²': '${math.max(0, 220 - totalSqm.round())}',
        }),
      );
    }
    if (orders.isNotEmpty) {
      sections.add(
        _detailSection('История заказов', {
          'Всего найдено': '${orders.length}',
          'Последние заказы': _cleanerOrdersText(orders),
        }),
      );
    }
    return sections;
  }

  String _cleanerOrdersText(List<Map<String, dynamic>> orders) {
    final sorted = [...orders]..sort((a, b) {
        final aMs = _timestampValue(a['scheduledFor'] ?? a['createdAt']);
        final bMs = _timestampValue(b['scheduledFor'] ?? b['createdAt']);
        return bMs.compareTo(aMs);
      });
    final lines = sorted.take(12).map((order) {
      final displayId = orderDisplayId(
        Map<String, dynamic>.from(order),
        fallback: (order['id'] ?? order['orderId'] ?? '—').toString(),
      );
      final date = _formatAdminDateTime(
        order['scheduledFor'] ?? order['date'],
      );
      final status = _orderStatusLabel(
        (order['orderStatus'] ?? order['status'] ?? '').toString(),
      );
      final customer = _firstText([
        order['customerName'],
        order['clientName'],
        order['customerPhone'],
      ]);
      final amount = _firstText([order['price'], order['amount']]);
      return '№$displayId · $date · $status · $customer · $amount ₸';
    }).join('\n');
    return lines.isEmpty ? '—' : lines;
  }

  int _timestampValue(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return DateTime.tryParse(
          (value ?? '').toString(),
        )?.millisecondsSinceEpoch ??
        0;
  }

  String _customerDate(Map<String, dynamic> customer) => _formatAdminDateTime(
        customer['createdAt'] ??
            customer['registeredAt'] ??
            customer['lastLoginAt'] ??
            customer['updatedAt'],
      );

  void _openCustomerDetails(
    BuildContext context,
    Map<String, dynamic> customer,
    int displayNumber,
  ) {
    final phone = _firstText([
      customer['phone'],
      customer['phoneNumber'],
      customer['customerPhone'],
    ]);
    final addresses = customer['addresses'];
    final addressesText = addresses is List && addresses.isNotEmpty
        ? addresses
            .map(
              (item) => item is Map
                  ? [
                      item['city'],
                      item['address'],
                      item['residentialComplex'],
                      item['entrance'],
                      item['apartment'],
                    ]
                      .where((v) => (v ?? '').toString().trim().isNotEmpty)
                      .join(', ')
                  : item.toString(),
            )
            .join('\n')
        : _customerPrimaryAddress(customer);
    _openEntityDetails(
      context,
      title: _firstText([customer['name'], customer['fullName'], phone]),
      sections: [
        _detailSection('Основное', {
          '№': displayNumber.toString(),
          'Имя': _firstText([
            customer['name'],
            customer['fullName'],
            customer['displayName'],
          ]),
          'Телефон': phone,
          'Статус профиля': _customerProfileStatus(customer),
          'Дата регистрации': _customerDate(customer),
          'Последний вход': _formatAdminDateTime(customer['lastLoginAt']),
          'Обновлен': _formatAdminDateTime(customer['updatedAt']),
        }),
        _detailSection('Адрес', {
          'Город': _firstText([customer['city']]),
          'Дом / ЖК': _firstText([
            customer['residentialComplex'],
            customer['houseTitle'],
            customer['houseName'],
            customer['houseId'],
          ]),
          'Адрес': _customerPrimaryAddress(customer),
          'Подъезд': _firstText([customer['entrance']]),
          'Квартира': _firstText([customer['apartment']]),
          'Площадь': _firstText([customer['area'], customer['apartmentArea']]),
          'Все адреса': addressesText,
        }),
        _detailSection('Бонусы и рефералы', {
          'Бонусы': _firstText([customer['bonusPoints'], customer['bonuses']]),
          'Реферальный код': _firstText([customer['referralCode']]),
          'Пригласил': _firstText([
            customer['referredBy'],
            customer['referrerId'],
          ]),
          'Уровень': _firstText([customer['tier'], customer['tierName']]),
        }),
      ],
    );
  }

  Future<void> _copyCustomersCsv(List<Map<String, dynamic>> customers) {
    return _copyCsv(
      headers: const [
        '№',
        'Имя',
        'Телефон',
        'Статус',
        'Адрес',
        'Дом',
        'Площадь',
        'Бонусы',
        'Регистрация',
      ],
      rows: customers.indexed
          .map(
            (entry) => [
              (entry.$1 + 1).toString(),
              _firstText([
                entry.$2['name'],
                entry.$2['fullName'],
                entry.$2['displayName'],
              ]),
              _firstText([
                entry.$2['phone'],
                entry.$2['phoneNumber'],
                entry.$2['customerPhone'],
              ]),
              _customerProfileStatus(entry.$2),
              _customerPrimaryAddress(entry.$2),
              _firstText([
                entry.$2['residentialComplex'],
                entry.$2['houseTitle'],
                entry.$2['houseName'],
                entry.$2['houseId'],
              ]),
              _firstText([entry.$2['area'], entry.$2['apartmentArea']]),
              _firstText([entry.$2['bonusPoints'], entry.$2['bonuses']]),
              _customerDate(entry.$2),
            ],
          )
          .toList(),
      successMessage: 'Пользователи скопированы в CSV',
    );
  }

  Widget _orders() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminAssignmentItemsStream(),
      builder: (context, snapshot) {
        final streamOrders = snapshot.data ?? const <Map<String, dynamic>>[];
        final debugSeedOrders = _debugSeedOrders();
        final orders = DebugSession.enabled &&
                DebugSession.uid == 'admin_demo' &&
                streamOrders.isEmpty
            ? debugSeedOrders
            : streamOrders;
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.cleanersDirectoryStream(),
          builder: (context, cleanersSnapshot) {
            final cleaners = cleanersSnapshot.data ?? [];
            final availableClusters = orders
                .map((item) => (item['clusterName'] ?? '—').toString())
                .where((value) => value.isNotEmpty && value != '—')
                .toSet()
                .toList()
              ..sort();
            final availableCleaners = cleaners
                .map((item) => (item['name'] ?? item['id']).toString())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            final availableServiceAreas = orders
                .map(
                  (item) => (item['serviceArea'] ?? item['district'] ?? '—')
                      .toString(),
                )
                .where((value) => value.isNotEmpty && value != '—')
                .toSet()
                .toList()
              ..sort();
            final availableAssignmentStatuses = orders
                .map((item) => (item['assignmentStatus'] ?? '—').toString())
                .where((value) => value.isNotEmpty && value != '—')
                .toSet()
                .toList()
              ..sort();
            final query = _searchQuery.trim().toLowerCase();
            final tabOrders = orders.where(_matchesOrdersTabFilter).toList();
            final packagePurchases =
                orders.where(_isAdminPackagePurchaseOrder).length;
            final cleaningOrders =
                orders.where(_isAdminCleaningVisitOrder).length;
            final filteredOrders = tabOrders.where((data) {
              var status =
                  (data['orderStatus'] ?? '—').toString().toLowerCase();
              var filterStatus = _statusFilter.toLowerCase();
              if (status == 'cancelled') {
                status = 'canceled';
              }
              if (filterStatus == 'cancelled') {
                filterStatus = 'canceled';
              }
              if (_statusFilter != 'Все' && status != filterStatus) {
                return false;
              }
              if (_clusterFilter != 'Все' &&
                  (data['clusterName'] ?? '—').toString() != _clusterFilter) {
                return false;
              }
              final cleanerName =
                  (data['cleanerName'] ?? data['cleanerId'] ?? '—').toString();
              if (_cleanerFilter != 'Все' && cleanerName != _cleanerFilter) {
                return false;
              }
              final serviceArea =
                  (data['serviceArea'] ?? data['district'] ?? '—').toString();
              if (_serviceAreaFilter != 'Все' &&
                  serviceArea != _serviceAreaFilter) {
                return false;
              }
              final assignmentStatus =
                  (data['assignmentStatus'] ?? '—').toString();
              if (_assignmentStatusFilter != 'Все' &&
                  assignmentStatus != _assignmentStatusFilter) {
                return false;
              }
              if (!_matchesRecordDateRange(data)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              final haystack = [
                data['id'],
                data['customerName'],
                data['customerId'],
                data['cleanerId'],
                data['address'],
                data['clusterName'],
                data['serviceArea'],
                data['assignmentStatus'],
                status,
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            });
            final filtered = _sortRecordsByDate(filteredOrders);
            final selectedVisibleOrderIds = filtered
                .map((item) => (item['id'] ?? '').toString())
                .where(_selectedOrderIds.contains)
                .toSet();
            return _sectionScaffold(
              toolbar: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _filterChip(
                        label: 'Все заказы: ${orders.length}',
                        selected: _ordersTabFilter == 'Все заказы',
                        onTap: () =>
                            setState(() => _ordersTabFilter = 'Все заказы'),
                      ),
                      _filterChip(
                        label: 'Покупки пакетов: $packagePurchases',
                        selected: _ordersTabFilter == 'Покупки пакетов',
                        onTap: () => setState(
                          () => _ordersTabFilter = 'Покупки пакетов',
                        ),
                      ),
                      _filterChip(
                        label: 'Заказанные уборки: $cleaningOrders',
                        selected: _ordersTabFilter == 'Заказанные уборки',
                        onTap: () => setState(
                          () => _ordersTabFilter = 'Заказанные уборки',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedVisibleOrderIds.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Выбрано заказов: ${selectedVisibleOrderIds.length}'
                                  .tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              _bulkActionButton(
                                'Назначен',
                                () => _handleSelectedOrdersStatusAction(
                                  selectedVisibleOrderIds,
                                  'assigned',
                                  filtered,
                                  cleaners,
                                  orders,
                                ),
                              ),
                              _bulkActionButton(
                                'В работе',
                                () => _handleSelectedOrdersStatusAction(
                                  selectedVisibleOrderIds,
                                  'in_progress',
                                  filtered,
                                  cleaners,
                                  orders,
                                ),
                              ),
                              _bulkActionButton(
                                'Завершен',
                                () => _handleSelectedOrdersStatusAction(
                                  selectedVisibleOrderIds,
                                  'completed',
                                  filtered,
                                  cleaners,
                                  orders,
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _selectedOrderIds.removeAll(
                                    selectedVisibleOrderIds,
                                  );
                                }),
                                child: Text('Снять выбор'.tr()),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: filtered.isEmpty
                            ? null
                            : () => _copyOrdersCsv(filtered),
                        icon: const Icon(Icons.table_view_outlined),
                        label: Text('Копировать CSV'.tr()),
                      ),
                      _compactDropdown(
                        value: _clusterFilter,
                        label: 'Кластер',
                        items: ['Все', ...availableClusters],
                        onChanged: (value) =>
                            setState(() => _clusterFilter = value ?? 'Все'),
                      ),
                      _compactDropdown(
                        value: _cleanerFilter,
                        label: 'Уборщица',
                        items: ['Все', ...availableCleaners],
                        onChanged: (value) =>
                            setState(() => _cleanerFilter = value ?? 'Все'),
                      ),
                      _compactDropdown(
                        value: _serviceAreaFilter,
                        label: 'Район',
                        items: ['Все', ...availableServiceAreas],
                        onChanged: (value) =>
                            setState(() => _serviceAreaFilter = value ?? 'Все'),
                      ),
                      _compactDropdown(
                        value: _assignmentStatusFilter,
                        label: 'Назначение',
                        items: ['Все', ...availableAssignmentStatuses],
                        onChanged: (value) => setState(
                          () => _assignmentStatusFilter = value ?? 'Все',
                        ),
                      ),
                      _dateFilterButton(
                        label: _filterStartDate == null
                            ? 'Дата от'
                            : 'От ${_dateLabel(_filterStartDate!)}',
                        onTap: () => _pickFilterDate(isStart: true),
                      ),
                      _dateFilterButton(
                        label: _filterEndDate == null
                            ? 'Дата до'
                            : 'До ${_dateLabel(_filterEndDate!)}',
                        onTap: () => _pickFilterDate(isStart: false),
                      ),
                      if (_filterStartDate != null || _filterEndDate != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _filterStartDate = null;
                            _filterEndDate = null;
                          }),
                          child: Text('Сбросить даты'.tr()),
                        ),
                      _filterChip(
                        label: 'Все',
                        selected: _statusFilter == 'Все',
                        onTap: () => setState(() => _statusFilter = 'Все'),
                      ),
                      for (final status in [
                        'pending_payment',
                        'assigned',
                        'confirmed',
                        'in_progress',
                        'completed',
                        'canceled',
                      ])
                        _filterChip(
                          label: _orderStatusLabel(status),
                          selected: _statusFilter == status,
                          onTap: () => setState(() => _statusFilter = status),
                        ),
                    ],
                  ),
                ],
              ),
              child: filtered.isEmpty
                  ? _emptyState(
                      'Заказы не найдены',
                      'Измените фильтры или строку поиска.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _adminOrderCard(
                        context: context,
                        data: filtered[index],
                        cleaners: cleaners,
                        orders: orders,
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _adminOrderCard({
    required BuildContext context,
    required Map<String, dynamic> data,
    required List<Map<String, dynamic>> cleaners,
    required List<Map<String, dynamic>> orders,
  }) {
    final customerId =
        (data['customerId'] ?? data['userId'] ?? '').toString().trim();
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: customerId.isEmpty
          ? Future.value(const <String, Map<String, dynamic>>{})
          : _data.adminCustomersByIds([customerId]),
      builder: (context, snapshot) {
        final customer =
            snapshot.data?[customerId] ?? const <String, dynamic>{};
        return _adminOrderCardContent(
          context: context,
          data: data,
          customer: customer,
          cleaners: cleaners,
          orders: orders,
        );
      },
    );
  }

  Widget _adminOrderCardContent({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> cleaners,
    required List<Map<String, dynamic>> orders,
  }) {
    final orderId = (data['id'] ?? '').toString();
    final displayId = orderDisplayId(data, fallback: orderId);
    final addonLabels = _formatAddonLabels(data);
    final status = _adminOrderDisplayStatus(data);
    final paymentStatus = (data['paymentStatus'] ?? '—').toString();
    final packageName = (data['package'] ??
            data['packageName'] ??
            data['frequencyLabel'] ??
            '—')
        .toString();
    final customerName = _personName(customer, data, prefix: 'customer');
    final customerPhone = _personPhone(customer, data, prefix: 'customer');
    final cleanerId =
        (data['cleanerId'] ?? data['assignedCleanerId'] ?? '').toString();
    final cleaner = cleaners.firstWhere(
      (item) => (item['id'] ?? item['cleanerId'] ?? '').toString() == cleanerId,
      orElse: () => <String, dynamic>{},
    );
    final cleanerName = cleanerId.trim().isEmpty
        ? 'не назначена'
        : _personName(cleaner, data, prefix: 'cleaner');
    final cleanerPhone = cleanerId.trim().isEmpty
        ? '—'
        : _personPhone(cleaner, data, prefix: 'cleaner');
    final address = (data['address'] ?? '—').toString();

    return _entityCard(
      title: 'Заказ $displayId',
      subtitle: '$customerName · $packageName',
      badges: [
        _statusBadge(
          _orderStatusLabel(status),
          color: _orderStatusColor(status),
        ),
        _statusBadge(
          paymentStatusLabel(paymentStatus),
          color: _paymentStatusColor(paymentStatus),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 42,
                child: Checkbox(
                  value: _selectedOrderIds.contains(orderId),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedOrderIds.add(orderId);
                      } else {
                        _selectedOrderIds.remove(orderId);
                      }
                    });
                  },
                ),
              ),
              _miniInfo('Клиент', customerName),
              _miniInfo('Телефон', customerPhone),
              _miniInfo('Адрес', address),
              _miniInfo('Сумма', '${data['price'] ?? 0} ₸'),
              _miniInfo('Дата', _adminOrderDateText(data)),
              _miniInfo('Уборок', _adminOrderCleaningsText(data)),
              _miniInfo('Уборщица', cleanerName),
              if (cleanerId.trim().isNotEmpty)
                _miniInfo('Телефон уборщицы', cleanerPhone),
              _miniInfo('Время', _adminOrderTimeText(data)),
              _miniInfo(
                'Район',
                (data['serviceArea'] ?? data['district'] ?? '—').toString(),
              ),
              _miniInfo('Назначение', _adminOrderAssignmentText(data)),
            ],
          ),
          if (addonLabels.isNotEmpty) ...[
            SizedBox(height: 12),
            _adminOrderLongInfo('Доп. услуги', addonLabels),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _openOrderDetails(context, data, displayId),
          child: Text('Детали'.tr()),
        ),
        TextButton.icon(
          onPressed: () =>
              _openAssignCleaner(context, orderId, data, cleaners, orders),
          icon: Icon(Icons.person_add_alt_1_outlined),
          label: Text('Назначить уборщицу'.tr()),
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            await _handleSelectedOrdersStatusAction(
              {orderId},
              value,
              [data],
              cleaners,
              orders,
            );
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'assigned',
              child: Text('Статус: назначен'.tr()),
            ),
            PopupMenuItem(
              value: 'in_progress',
              child: Text('Статус: в работе'.tr()),
            ),
            PopupMenuItem(
              value: 'completed',
              child: Text('Статус: завершен'.tr()),
            ),
            PopupMenuItem(
              value: 'canceled',
              child: Text('Статус: отменен'.tr()),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openOrderDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String displayId,
  ) async {
    final customerId =
        (data['customerId'] ?? data['userId'] ?? '').toString().trim();
    final customers = customerId.isEmpty
        ? const <String, Map<String, dynamic>>{}
        : await _data.adminCustomersByIds([customerId]);
    final customer = customers[customerId] ?? const <String, dynamic>{};
    final cleanerId =
        (data['cleanerId'] ?? data['assignedCleanerId'] ?? '').toString();
    final cleaners = cleanerId.trim().isEmpty
        ? const <String, Map<String, dynamic>>{}
        : await _data.adminCleanersByIds([cleanerId]);
    final cleaner = cleaners[cleanerId] ?? const <String, dynamic>{};
    final customerName = _personName(customer, data, prefix: 'customer');
    final customerPhone = _personPhone(customer, data, prefix: 'customer');
    final cleanerName = cleanerId.trim().isEmpty
        ? 'не назначена'
        : _personName(cleaner, data, prefix: 'cleaner');
    final cleanerPhone = cleanerId.trim().isEmpty
        ? '—'
        : _personPhone(cleaner, data, prefix: 'cleaner');
    final addonLabels = _formatAddonLabels(data);
    final receiptRows = _adminOrderReceiptRows(data);
    if (!context.mounted) {
      return;
    }
    _openEntityDetails(
      context,
      title: 'Заказ $displayId',
      sections: [
        _detailSection('Основное', {
          'Статус': _orderStatusLabel(_adminOrderDisplayStatus(data)),
          'Пакет': (data['package'] ??
                  data['packageName'] ??
                  data['frequencyLabel'] ??
                  '—')
              .toString(),
          'Дата': _adminOrderDateText(data),
          'Время': _adminOrderTimeText(data),
          'Кластер': (data['clusterName'] ?? '—').toString(),
          'Район': (data['serviceArea'] ?? data['district'] ?? '—').toString(),
          'Площадь': '${_firstText([data['area'], data['apartmentArea']])} м²',
          'Уборок заказано': _adminOrderCleaningsText(data),
        }),
        _detailSection('Участники', {
          'Клиент': customerName,
          'Телефон клиента': customerPhone,
          'Уборщица': cleanerName,
          if (cleanerId.trim().isNotEmpty) 'Телефон уборщицы': cleanerPhone,
        }),
        _detailSection('Финансы', {
          'Сумма': '${data['price'] ?? 0} ₸',
          'Оплата': paymentStatusLabel(
            (data['paymentStatus'] ?? '—').toString(),
          ),
        }),
        _detailSection('Мини-чек', receiptRows),
        _detailSection('Доп. услуги', {
          'Заказанные допы': addonLabels.isEmpty ? 'нет' : addonLabels,
          'Отдельная оплата': '${data['addonsSeparatePaymentTotal'] ?? 0} ₸',
        }),
        _detailSection('Назначение', {
          'Статус назначения': _adminOrderAssignmentText(data),
          'Очередь уборщиц': _candidateQueueDetailsText(
            data['candidateQueueDetails'],
          ),
          'Оффер истекает': (data['offerExpiresAt'] ?? '—').toString(),
        }),
      ],
    );
  }

  Widget _adminOrderLongInfo(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _complaints() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.complaintsStream(admin: true),
      builder: (context, snapshot) {
        final complaints = _applyDebugComplaintOverrides(
          List<Map<String, dynamic>>.from(snapshot.data ?? const []),
        );
        final complaintNumbers = <String, int>{};
        for (var i = 0; i < complaints.length; i += 1) {
          final id = (complaints[i]['id'] ?? '').toString();
          if (id.isNotEmpty) {
            complaintNumbers[id] = complaints.length - i;
          }
        }
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _data.adminCustomersByIds(
            complaints.map((item) => (item['customerId'] ?? '').toString()),
          ),
          builder: (context, customersSnapshot) {
            final customers = customersSnapshot.data ??
                const <String, Map<String, dynamic>>{};
            final query = _searchQuery.trim().toLowerCase();
            final filteredComplaints = complaints.where((item) {
              final itemId = (item['id'] ?? '').toString();
              final customerId = (item['customerId'] ?? '').toString();
              final customer =
                  customers[customerId] ?? const <String, dynamic>{};
              final status = _debugComplaintStatusOverride(
                itemId,
                (item['status'] ?? 'open').toString(),
              ).toLowerCase();
              if (_statusFilter != 'Все' &&
                  status != _statusFilter.toLowerCase()) {
                return false;
              }
              if (!_matchesRecordDateRange(item)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return [
                _complaintDisplayNumber(item, complaintNumbers),
                item['id'],
                item['text'],
                item['customerId'],
                item['orderId'],
                customer['name'],
                customer['fullName'],
                customer['displayName'],
                customer['phone'],
                customer['phoneNumber'],
              ].join(' ').toLowerCase().contains(query);
            });
            final list = _sortRecordsByDate(filteredComplaints);
            return _sectionScaffold(
              toolbar: Wrap(
                spacing: 12,
                children: [
                  _filterChip(
                    label: 'Все',
                    selected: _statusFilter == 'Все',
                    onTap: () => setState(() => _statusFilter = 'Все'),
                  ),
                  for (final status in [
                    'open',
                    'resolved',
                    'compensated',
                    'refund',
                  ])
                    _filterChip(
                      label: _complaintStatusLabel(status),
                      selected: _statusFilter == status,
                      onTap: () => setState(() => _statusFilter = status),
                    ),
                ],
              ),
              child: list.isEmpty
                  ? _emptyState(
                      'Жалобы не найдены',
                      'Измените фильтры или строку поиска.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final c = list[index];
                        final status = _debugComplaintStatusOverride(
                          (c['id'] ?? '').toString(),
                          (c['status'] ?? 'open').toString(),
                        );
                        final customerId = (c['customerId'] ?? '').toString();
                        final customer =
                            customers[customerId] ?? const <String, dynamic>{};
                        return _complaintCard(
                          context: context,
                          complaint: c,
                          status: status,
                          customer: customer,
                          number: _complaintDisplayNumber(c, complaintNumbers),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _complaintCard({
    required BuildContext context,
    required Map<String, dynamic> complaint,
    required String status,
    required Map<String, dynamic> customer,
    required String number,
  }) {
    final customerId = (complaint['customerId'] ?? '').toString();
    final complaintId = (complaint['id'] ?? '').toString();
    final orderId = (complaint['orderId'] ?? '').toString();
    final customerName = _firstText([
      complaint['customerName'],
      customer['name'],
      customer['fullName'],
      customer['displayName'],
      customerId,
    ]);
    final customerPhone = _firstText([
      complaint['customerPhone'],
      customer['phone'],
      customer['phoneNumber'],
    ]);
    final text = (complaint['text'] ?? '').toString();
    final photoUrls = ((complaint['photoUrls'] as List?) ?? const [])
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final legacyPhotoUrl = (complaint['photoUrl'] ?? '').toString();
    if (photoUrls.isEmpty && legacyPhotoUrl.trim().isNotEmpty) {
      photoUrls.add(legacyPhotoUrl);
    }

    return _entityCard(
      title: 'Жалоба №$number',
      subtitle: [
        text.isEmpty ? 'Без текста' : text,
        if (customerName != '—') 'Клиент: $customerName',
        if (customerPhone != '—') customerPhone,
      ].join(' · '),
      badges: [
        _statusBadge(
          _complaintStatusLabel(status),
          color: _complaintStatusColor(status),
        ),
      ],
      body: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _miniInfo('Номер', number),
          _miniInfo('Клиент', customerName),
          _miniInfo('Телефон', customerPhone),
          _miniInfo('Заказ', orderId.isEmpty ? '—' : orderId),
          _miniInfo('Создана', _formatAdminDateTime(complaint['createdAt'])),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _openEntityDetails(
            context,
            title: 'Жалоба №$number',
            sections: [
              _detailSection('Обращение', {
                'Номер жалобы': number,
                'ID жалобы': (complaint['id'] ?? '—').toString(),
                'Заказ': orderId.isEmpty ? '—' : orderId,
                'Статус': _complaintStatusLabel(status),
                'Создана': _formatAdminDateTime(complaint['createdAt']),
                'Текст': text,
              }),
              _detailSection('Клиент', {
                'ID клиента': customerId.isEmpty ? '—' : customerId,
                'Имя': customerName,
                'Телефон': customerPhone,
                'Адрес': _customerPrimaryAddress(customer),
                'Площадь':
                    '${customer['area'] ?? customer['apartmentArea'] ?? '—'} м²',
                'Дом': _firstText([
                  customer['residentialComplex'],
                  customer['houseTitle'],
                  customer['houseName'],
                  customer['houseId'],
                ]),
              }),
            ],
          ),
          child: Text('Открыть'.tr()),
        ),
        TextButton.icon(
          onPressed: customerPhone == '—'
              ? null
              : () => Clipboard.setData(ClipboardData(text: customerPhone)),
          icon: Icon(Icons.copy_outlined),
          label: Text('Телефон'.tr()),
        ),
        TextButton.icon(
          onPressed: customerId.isEmpty || complaintId.isEmpty
              ? null
              : () async {
                  try {
                    final chatId = await _data.createOrOpenComplaintChat(
                      complaintId: complaintId,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.pushNamed(
                      context,
                      '/chat',
                      arguments: {'orderId': chatId},
                    );
                  } catch (error) {
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Не удалось открыть чат: $error'.tr()),
                      ),
                    );
                  }
                },
          icon: Icon(Icons.chat_bubble_outline),
          label: Text('Чат'.tr()),
        ),
        if (photoUrls.isNotEmpty)
          TextButton(
            onPressed: () => _showComplaintPhotos(context, photoUrls),
            child: Text('Фото (${photoUrls.length})'.tr()),
          ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            await _data.createAdminAction({
              'type': 'complaint_resolution',
              'complaintId': complaint['id'],
              'status': value,
              'resolution': value == 'compensated'
                  ? 'Компенсация клиенту'
                  : value == 'refund'
                      ? 'Полный возврат'
                      : 'Жалоба закрыта',
              'compensationAmount': value == 'compensated' ? 5000 : 0,
            });
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'resolved', child: Text('Закрыть'.tr())),
            PopupMenuItem(
              value: 'compensated',
              child: Text('Компенсация'.tr()),
            ),
            PopupMenuItem(value: 'refund', child: Text('Возврат'.tr())),
          ],
        ),
      ],
    );
  }

  String _complaintDisplayNumber(
    Map<String, dynamic> complaint,
    Map<String, int> fallbackNumbers,
  ) {
    final explicit = complaint['number'] ??
        complaint['complaintNumber'] ??
        complaint['sequenceNumber'];
    if (explicit is num && explicit > 0) {
      return explicit.toInt().toString();
    }
    final explicitText = (explicit ?? '').toString().trim();
    final explicitDigits = RegExp(r'\d+').stringMatch(explicitText);
    if (explicitDigits != null && explicitDigits.isNotEmpty) {
      return explicitDigits;
    }
    final id = (complaint['id'] ?? '').toString();
    return (fallbackNumbers[id] ?? 0).toString();
  }

  void _showComplaintPhotos(BuildContext context, List<String> photoUrls) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: photoUrls
                .map(
                  (url) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(url, width: 220, fit: BoxFit.cover),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _payments() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminPaymentsStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final filteredPayments =
            (snapshot.data ?? const <Map<String, dynamic>>[]).where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['id']} ${data['orderId']} ${data['status']} ${data['amount']}'
                  ' ${data['customerName']} ${data['customerPhone']} ${data['packageName']} ${_formatAddonLabels(data)}'
              .toLowerCase()
              .contains(query);
        });
        final docs = _sortRecordsByDate(filteredPayments);
        final invoiceRequests =
            docs.where(_isAdminPaymentActionRequired).toList();
        final otherPayments =
            docs.where((doc) => !_isAdminPaymentActionRequired(doc)).toList();
        return _sectionScaffold(
          child: docs.isEmpty
              ? _emptyState(
                  'Платежи не найдены',
                  'Проверьте строку поиска или период в данных.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _metricTile(
                              'Заявки на оплату',
                              '${invoiceRequests.length}',
                              Icons.payments_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _metricTile(
                              'Всего платежей',
                              '${docs.length}',
                              Icons.receipt_long_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Заявки KASPI.KZ'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (invoiceRequests.isEmpty)
                      _emptyInlineCard(
                        'Сейчас нет заявок на подтверждение оплаты.',
                      )
                    else
                      ...invoiceRequests.map(_paymentRequestCard),
                    const SizedBox(height: 24),
                    Text(
                      'Остальные платежи'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (otherPayments.isEmpty)
                      _emptyInlineCard(
                        'Других платежей по текущему фильтру нет.',
                      )
                    else
                      ...otherPayments.map(_paymentHistoryCard),
                  ],
                ),
        );
      },
    );
  }

  Widget _specialAddons() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminPaymentsStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final filtered = _sortRecordsByDate(
          (snapshot.data ?? const <Map<String, dynamic>>[]).where((data) {
            if (!_matchesRecordDateRange(data)) {
              return false;
            }
            if (_specialAddonCategories(data).isEmpty) {
              return false;
            }
            if (query.isEmpty) {
              return true;
            }
            final haystack = [
              data['id'],
              data['orderId'],
              data['customerName'],
              data['customerPhone'],
              data['address'],
              _formatAddonLabels(data),
              _specialAddonCategories(data).join(' '),
              data['status'],
              data['paymentStatus'],
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          }),
        );
        final furnitureCount = filtered
            .where(
              (item) => _specialAddonCategories(
                item,
              ).contains('Мебель и поверхности'),
            )
            .length;
        final carpetCount = filtered
            .where(
              (item) => _specialAddonCategories(
                item,
              ).contains('Химчистка ковров и паласов'),
            )
            .length;

        return _sectionScaffold(
          child: filtered.isEmpty
              ? _emptyState(
                  'Спец. допы не найдены',
                  'Здесь появятся заказы мебели, поверхностей и химчистки ковров.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _metricTile(
                              'Мебель / поверхности',
                              '$furnitureCount',
                              Icons.chair_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _metricTile(
                              'Химчистка ковров',
                              '$carpetCount',
                              Icons.texture_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...filtered.map(_specialAddonCard),
                  ],
                ),
        );
      },
    );
  }

  Widget _specialAddonCard(Map<String, dynamic> data) {
    final categories = _specialAddonCategories(data);
    final status =
        (data['paymentStatus'] ?? data['status'] ?? '—').toString().trim();
    final orderId = (data['orderId'] ?? data['id'] ?? '—').toString();
    final addonLabels = _formatAddonLabels(data);
    final customerName =
        ((data['customerName'] ?? 'Пользователь').toString()).trim();
    final customerPhone = ((data['customerPhone'] ?? '—').toString()).trim();
    final address = ((data['address'] ?? '—').toString()).trim();
    final amount = data['amount'] ?? data['price'] ?? 0;
    final currency = data['currency'] ?? 'KZT';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  categories.join(' + '),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              _statusBadge(
                paymentStatusLabel(status),
                color: _paymentStatusColor(status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _adminInfoChip('Заказ', orderDisplayId(data, fallback: orderId)),
              _adminInfoChip('Клиент', customerName),
              _adminInfoChip('Телефон', customerPhone),
              _adminInfoChip('Адрес', address.isEmpty ? '—' : address),
              _adminInfoChip('Сумма', '$amount $currency'),
              _adminInfoChip(
                'Дата',
                _formatDateTime(
                  data['invoiceRequestedAt'] ??
                      data['paidAt'] ??
                      data['createdAt'],
                ),
              ),
            ],
          ),
          if (addonLabels.isNotEmpty) ...[
            const SizedBox(height: 12),
            _adminOrderLongInfo('Что заказали', addonLabels),
          ],
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyInlineCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
      ),
    );
  }

  String _formatAddonLabels(Map<String, dynamic> data) {
    final labels = <String>[];
    void addLabel(Object? value) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty && !labels.contains(text)) {
        labels.add(text);
      }
    }

    final detailed = data['addonsDetailed'];
    if (detailed is List) {
      for (final item in detailed) {
        if (item is Map) {
          addLabel(
            item['label'] ??
                item['title'] ??
                item['name'] ??
                item['optionLabel'] ??
                item['key'],
          );
        } else {
          addLabel(item);
        }
      }
    }

    final separate = data['separatePaymentAddons'];
    if (separate is List) {
      for (final item in separate) {
        if (item is Map) {
          addLabel(
            item['label'] ?? item['title'] ?? item['name'] ?? item['key'],
          );
        } else {
          addLabel(item);
        }
      }
    }

    final simple = data['addons'];
    if (simple is List) {
      for (final item in simple) {
        if (item is Map) {
          addLabel(
            item['label'] ?? item['title'] ?? item['name'] ?? item['key'],
          );
        } else {
          addLabel(item);
        }
      }
    }

    return labels.join(', ');
  }

  Map<String, String> _adminOrderReceiptRows(Map<String, dynamic> data) {
    final rows = <String, String>{};
    final packageName = _firstText([
      data['package'],
      data['packageName'],
      data['frequencyLabel'],
    ]);
    final cleaningsText = _adminOrderCleaningsText(data);
    final originalAmount = _moneyValue(data['originalPrice']);
    final payableAmount = _moneyValue(data['amount'] ?? data['price']);
    final addonItems = _adminOrderAddonReceiptItems(data);
    final addonTotal = addonItems.fold<int>(
      0,
      (total, item) => total + (item.price ?? 0),
    );
    final explicitAddonTotal = _moneyValue(
      data['addonsSeparatePaymentTotal'] ?? data['addonAmount'],
    );
    final shownAddonTotal =
        explicitAddonTotal > 0 ? explicitAddonTotal : addonTotal;
    final packageAmount =
        originalAmount > 0 ? math.max(0, originalAmount - shownAddonTotal) : 0;
    final bonus = _moneyValue(
      data['bonusAppliedAmount'] ?? data['bonusToSpend'],
    );

    rows['Пакет'] = [
      packageName,
      if (cleaningsText != '—') cleaningsText,
      if (packageAmount > 0) _moneyText(packageAmount),
    ].join(' · ');
    rows['Площадь'] = '${_firstText([data['area'], data['apartmentArea']])} м²';

    for (var i = 0; i < addonItems.length; i += 1) {
      final item = addonItems[i];
      rows['Доп ${i + 1}'] = [
        item.name,
        if (item.quantity != null && item.quantity! > 1) 'x${item.quantity}',
        item.price == null ? 'цена не указана' : _moneyText(item.price!),
      ].join(' · ');
    }

    rows['Итого допы'] = shownAddonTotal > 0
        ? _moneyText(shownAddonTotal)
        : (addonItems.isEmpty ? 'нет' : 'нет суммы');
    if (originalAmount > 0) {
      rows['Сумма до бонусов'] = _moneyText(originalAmount);
    }
    if (bonus > 0) {
      rows['Списано бонусами'] = '-${_moneyText(bonus)}';
    }
    rows['К оплате / оплачено деньгами'] = _moneyText(payableAmount);
    rows['Статус оплаты'] = paymentStatusLabel(
      (data['paymentStatus'] ?? '—').toString(),
    );
    return rows;
  }

  List<_AdminReceiptAddon> _adminOrderAddonReceiptItems(
    Map<String, dynamic> data,
  ) {
    final items = <_AdminReceiptAddon>[];
    final seen = <String>{};

    void addItem(Object? value) {
      if (value == null) {
        return;
      }
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        final name = _firstText([
          map['label'],
          map['title'],
          map['name'],
          map['optionLabel'],
          map['key'],
        ]);
        if (name == '—') {
          return;
        }
        final price = _nullableMoneyValue(
          map['total'] ??
              map['amount'] ??
              map['price'] ??
              map['cost'] ??
              map['subtotal'],
        );
        final quantity = _nullableMoneyValue(
          map['quantity'] ?? map['count'] ?? map['qty'],
        );
        final key = '$name|${price ?? ''}|${quantity ?? ''}';
        if (seen.add(key)) {
          items.add(_AdminReceiptAddon(name, price: price, quantity: quantity));
        }
        return;
      }
      final name = value.toString().trim();
      if (name.isNotEmpty && seen.add(name)) {
        items.add(_AdminReceiptAddon(name));
      }
    }

    for (final source in [
      data['addonsDetailed'],
      data['separatePaymentAddons'],
      data['addons'],
    ]) {
      if (source is Iterable) {
        for (final item in source) {
          addItem(item);
        }
      }
    }
    return items;
  }

  String _adminOrderCleaningsText(Map<String, dynamic> data) {
    final explicit = _moneyValue(
      data['cleaningsCount'] ??
          data['totalCleanings'] ??
          data['visitsCount'] ??
          data['includedVisits'],
    );
    if (explicit > 0) {
      return '$explicit уборок';
    }
    final perMonth = _moneyValue(data['cleaningsPerMonth']);
    final months = math.max(1, _moneyValue(data['billingPeriodMonths']));
    if (perMonth > 0) {
      final total = perMonth * months;
      return months > 1
          ? '$total уборок ($perMonth в месяц x $months мес.)'
          : '$perMonth уборок';
    }
    return '—';
  }

  bool _matchesOrdersTabFilter(Map<String, dynamic> data) {
    switch (_ordersTabFilter) {
      case 'Покупки пакетов':
        return _isAdminPackagePurchaseOrder(data);
      case 'Заказанные уборки':
        return _isAdminCleaningVisitOrder(data);
      default:
        return true;
    }
  }

  bool _isAdminPackagePurchaseOrder(Map<String, dynamic> data) {
    final pricingMode = (data['pricingMode'] ?? '').toString().toLowerCase();
    final packageId = (data['packageId'] ?? '').toString().toLowerCase();
    if (pricingMode == 'addons_only' || packageId == 'addons_only') {
      return false;
    }
    if (_isAdminCleaningVisitOrder(data)) {
      return false;
    }
    return _firstText([
          data['package'],
          data['packageName'],
          data['frequencyLabel'],
        ]) !=
        '—';
  }

  bool _isAdminCleaningVisitOrder(Map<String, dynamic> data) {
    final pricingMode = (data['pricingMode'] ?? '').toString().toLowerCase();
    final packageId = (data['packageId'] ?? '').toString().toLowerCase();
    final scopeType = (data['scopeType'] ?? '').toString().toLowerCase();
    final hasSlotId =
        _firstText([data['slotId'], data['scheduleSlotId']]) != '—';
    if (scopeType == 'schedule_slot' || hasSlotId) {
      return true;
    }
    if (pricingMode == 'addons_only' || packageId == 'addons_only') {
      return true;
    }
    final status =
        (data['orderStatus'] ?? data['status'] ?? '').toString().toLowerCase();
    final assignmentStatus = (data['assignmentStatus'] ?? '').toString().trim();
    final time = (data['time'] ?? '').toString().trim().toLowerCase();
    final scheduledDate = _firstText([
      data['scheduledFor'],
      data['scheduledDateKey'],
      data['scheduledDate'],
      data['visitDate'],
    ]);
    final explicitType = (data['type'] ?? data['orderType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final hasConcreteTime = time.isNotEmpty &&
        time != '—' &&
        !time.contains('ожидает') &&
        !time.contains('выбор');
    final hasVisitLink = _firstText([
          data['sourceOrderId'],
          data['cleanerId'],
          data['cleanerName'],
        ]) !=
        '—';
    final hasConcreteDate = scheduledDate != '—';
    final isVisitType = explicitType.contains('cleaning') ||
        explicitType.contains('visit') ||
        explicitType.contains('addon');
    if (isVisitType) {
      return true;
    }
    if (hasConcreteTime && hasVisitLink) {
      return true;
    }
    if (hasConcreteDate && hasConcreteTime) {
      return true;
    }
    if (hasConcreteDate &&
        assignmentStatus.isNotEmpty &&
        assignmentStatus != '—') {
      return true;
    }
    return {
          'assigned',
          'confirmed',
          'in_progress',
          'completed',
          'canceled',
          'cancelled',
        }.contains(status) &&
        hasConcreteDate;
  }

  String _areaApprovalStatusLabel(
    Map<String, dynamic> primary,
    Map<String, dynamic> customer,
  ) {
    final verified = primary['areaVerified'] ??
        primary['customerAreaVerified'] ??
        customer['areaVerified'];
    final status = (primary['areaStatus'] ??
            primary['customerAreaStatus'] ??
            customer['areaStatus'] ??
            '')
        .toString()
        .toUpperCase();
    if (verified == true || status == 'VERIFIED' || status == 'APPROVED') {
      return 'Одобрена';
    }
    if (status == 'PENDING_REVIEW' || status == 'QUALITY_CHECK_SCHEDULED') {
      return 'На проверке';
    }
    return 'Не одобрена';
  }

  int _moneyValue(Object? value) => _nullableMoneyValue(value) ?? 0;

  int? _nullableMoneyValue(Object? value) {
    if (value is num) {
      return value.round();
    }
    final text = (value ?? '')
        .toString()
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll(',', '.');
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text)?.round();
  }

  String _moneyText(int value) => '$value ₸';

  List<String> _specialAddonCategories(Map<String, dynamic> data) {
    var hasFurniture = false;
    var hasCarpet = false;

    void scan(Object? value) {
      final text = (value ?? '').toString().trim().toLowerCase();
      if (text.isEmpty) return;
      if (text.contains('furniture') ||
          text.contains('мебел') ||
          text.contains('поверх') ||
          text.contains('диван') ||
          text.contains('матрас')) {
        hasFurniture = true;
      }
      if (text.contains('carpet') ||
          text.contains('ковр') ||
          text.contains('палас')) {
        hasCarpet = true;
      }
    }

    void scanList(Object? value) {
      if (value is! List) return;
      for (final item in value) {
        if (item is Map) {
          scan(item['key']);
          scan(item['label']);
          scan(item['title']);
          scan(item['name']);
          scan(item['groupKey']);
          scan(item['groupLabel']);
        } else {
          scan(item);
        }
      }
    }

    scanList(data['addonsDetailed']);
    scanList(data['separatePaymentAddons']);
    scanList(data['addons']);
    scan(data['package']);
    scan(data['packageName']);
    scan(data['frequencyLabel']);

    return [
      if (hasFurniture) 'Мебель и поверхности',
      if (hasCarpet) 'Химчистка ковров и паласов',
    ];
  }

  Widget _paymentRequestCard(Map<String, dynamic> d) {
    final customerId = (d['customerId'] ?? d['userId'] ?? '').toString().trim();
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _data.adminCustomersByIds([customerId]),
      builder: (context, snapshot) {
        final customer =
            snapshot.data?[customerId] ?? const <String, dynamic>{};
        return _paymentRequestCardContent(d, customer);
      },
    );
  }

  Widget _paymentRequestCardContent(
    Map<String, dynamic> d,
    Map<String, dynamic> customer,
  ) {
    final status = (d['status'] ?? '—').toString();
    final orderId = (d['orderId'] ?? d['id']).toString();
    final customerName = _personName(customer, d, prefix: 'customer');
    final customerPhone = _personPhone(customer, d, prefix: 'customer');
    final packageName =
        ((d['package'] ?? d['packageName'] ?? '—').toString()).trim();
    final frequencyLabel = ((d['frequencyLabel'] ?? '').toString()).trim();
    final paymentTypeLabel = _paymentTypeLabel(d);
    final address = _firstText([
      d['address'],
      d['customerAddress'],
      _customerPrimaryAddress(customer),
    ]);
    final addonLabels = _formatAddonLabels(d);
    final priceLabel =
        '${d['amount'] ?? d['price'] ?? 0} ${(d['currency'] ?? 'KZT')}';
    final areaStatusLabel = _areaApprovalStatusLabel(d, customer);
    final paymentId = (d['id'] ?? '').toString();
    final isAreaRecalculation =
        (d['type'] ?? '').toString().toLowerCase() == 'area_recalculation';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName.isEmpty ? 'Пользователь' : customerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Телефон: $customerPhone'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(status, color: _paymentStatusColor(status)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _adminInfoChip('Заказ', orderDisplayId(d, fallback: orderId)),
              _adminInfoChip('Тип', paymentTypeLabel),
              _adminInfoChip('KASPI.KZ', (d['kaspiPhone'] ?? '—').toString()),
              _adminInfoChip('Сумма', priceLabel),
              _adminInfoChip('Квадратура', areaStatusLabel),
              if (isAreaRecalculation) ...[
                _adminInfoChip(
                  'Было',
                  '${d['previousArea'] ?? '—'} м² · ${d['previousPaidAmount'] ?? 0} KZT',
                ),
                _adminInfoChip(
                  'Стало',
                  '${d['actualArea'] ?? '—'} м² · ${d['recalculatedAmount'] ?? 0} KZT',
                ),
                _adminInfoChip(
                  'Доплата',
                  '${d['areaAdjustmentAmount'] ?? d['amount'] ?? 0} KZT',
                ),
              ],
              _adminInfoChip(
                'Пакет',
                frequencyLabel.isEmpty
                    ? packageName
                    : '$packageName · $frequencyLabel',
              ),
              _adminInfoChip('Адрес', address.isEmpty ? '—' : address),
              if (addonLabels.isNotEmpty)
                _adminInfoChip('Доп. услуги', addonLabels),
              _adminInfoChip(
                'Создано',
                _formatDateTime(d['invoiceRequestedAt'] ?? d['createdAt']),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () async {
                  await _data.reviewManualPayment(
                    orderId: isAreaRecalculation && paymentId.isNotEmpty
                        ? paymentId
                        : orderId,
                    approved: true,
                  );
                },
                child: Text('Одобрить'.tr()),
              ),
              OutlinedButton(
                onPressed: () async {
                  await _data.reviewManualPayment(
                    orderId: isAreaRecalculation && paymentId.isNotEmpty
                        ? paymentId
                        : orderId,
                    approved: false,
                  );
                },
                child: Text('Отклонить'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentHistoryCard(Map<String, dynamic> d) {
    final customerId = (d['customerId'] ?? d['userId'] ?? '').toString().trim();
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _data.adminCustomersByIds([customerId]),
      builder: (context, snapshot) {
        final customer =
            snapshot.data?[customerId] ?? const <String, dynamic>{};
        return _paymentHistoryCardContent(d, customer);
      },
    );
  }

  Widget _paymentHistoryCardContent(
    Map<String, dynamic> d,
    Map<String, dynamic> customer,
  ) {
    final status = (d['status'] ?? '—').toString();
    final orderId = (d['orderId'] ?? d['id'] ?? '—').toString();
    final customerName = _personName(customer, d, prefix: 'customer');
    final customerPhone = _personPhone(customer, d, prefix: 'customer');
    final packageName =
        ((d['package'] ?? d['packageName'] ?? '—').toString()).trim();
    final frequencyLabel = ((d['frequencyLabel'] ?? '').toString()).trim();
    final address = _firstText([
      d['address'],
      d['customerAddress'],
      _customerPrimaryAddress(customer),
    ]);
    final addonLabels = _formatAddonLabels(d);
    final areaStatusLabel = _areaApprovalStatusLabel(d, customer);
    final priceLabel =
        '${d['amount'] ?? d['price'] ?? 0} ${(d['currency'] ?? 'KZT')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customerName.isEmpty ? 'Пользователь' : customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              _statusBadge(
                paymentStatusLabel(status),
                color: _paymentStatusColor(status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _adminInfoChip(
                'Заказ',
                orderDisplayId(Map<String, dynamic>.from(d), fallback: orderId),
              ),
              _adminInfoChip('Тип', _paymentTypeLabel(d)),
              _adminInfoChip('Клиент', customerName),
              _adminInfoChip('Телефон', customerPhone),
              _adminInfoChip('KASPI.KZ', (d['kaspiPhone'] ?? '—').toString()),
              _adminInfoChip('Сумма', priceLabel),
              _adminInfoChip('Квадратура', areaStatusLabel),
              _adminInfoChip(
                'Пакет',
                frequencyLabel.isEmpty
                    ? packageName
                    : '$packageName · $frequencyLabel',
              ),
              _adminInfoChip('Адрес', address.isEmpty ? '—' : address),
              if (addonLabels.isNotEmpty)
                _adminInfoChip('Доп. услуги', addonLabels),
              _adminInfoChip(
                'Создано',
                _formatDateTime(
                  d['invoiceRequestedAt'] ?? d['paidAt'] ?? d['createdAt'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _paymentTypeLabel(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['paymentType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final paymentId = (data['id'] ?? '').toString().toLowerCase();
    final addonLabels = _formatAddonLabels(data);
    if (type == 'area_recalculation' || paymentId.startsWith('area_recalc_')) {
      return 'Перерасчет площади';
    }
    if (type.contains('addon') ||
        paymentId.startsWith('addon_') ||
        addonLabels.isNotEmpty) {
      return 'Доп. услуги';
    }
    if (type.contains('subscription') ||
        type.contains('package') ||
        (data['subscriptionId'] ?? '').toString().trim().isNotEmpty) {
      return 'Покупка пакета';
    }
    if ((data['orderId'] ?? '').toString().trim().isNotEmpty) {
      return 'Заказ уборки';
    }
    return 'Платёж';
  }

  bool _isAdminPaymentActionRequired(Map<String, dynamic> data) {
    final status = (data['status'] ?? data['paymentStatus'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return status == 'invoice_requested' ||
        status == 'pending_invoice' ||
        status == 'initiated';
  }

  Widget _adminInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(dynamic value) {
    if (value is Timestamp) {
      return domlyDateTimeText(value.toDate().toLocal());
    }
    return '—';
  }

  String _formatAdminDateTime(dynamic value) {
    if (value is Timestamp) {
      return domlyDateTimeText(value.toDate().toLocal());
    }
    final parsed = DateTime.tryParse((value ?? '').toString());
    if (parsed != null) {
      return domlyDateTimeText(parsed.toLocal());
    }
    return '—';
  }

  String _firstAdminDateTime(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty || raw == 'Январь 2025') {
        continue;
      }
      final formatted = _formatAdminDateTime(value);
      if (formatted != '—') {
        return formatted;
      }
      return raw;
    }
    return '—';
  }

  String _firstText(List<Object?> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '—';
  }

  String _numText(Object? value) {
    if (value is num) {
      return value.toStringAsFixed(6);
    }
    final parsed = num.tryParse((value ?? '').toString());
    return parsed == null ? '—' : parsed.toStringAsFixed(6);
  }

  Widget _miniInfo(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _waitlistStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'joined':
        return 'В листе ожидания';
      case 'waiting':
        return 'Ожидает';
      case 'approved':
        return 'Одобрено';
      case 'rejected':
        return 'Отклонено';
      default:
        return status.isEmpty ? 'Ожидает' : status;
    }
  }

  String _waitlistSourceLabel(String source) {
    switch (source.trim().toLowerCase()) {
      case 'address_request':
        return 'Запрос адреса';
      case 'app':
        return 'Приложение';
      case 'invite_neighbors':
        return 'Приглашение';
      default:
        return source.isEmpty ? 'Приложение' : source;
    }
  }

  Widget _adminNotifications() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminNotificationsStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final docs = (snapshot.data ?? const <Map<String, dynamic>>[]).where((
          data,
        ) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['title']} ${data['body']} ${data['type']} ${data['sourceId']}'
              .toLowerCase()
              .contains(query);
        }).toList();

        return _sectionScaffold(
          child: docs.isEmpty
              ? _emptyState(
                  'Уведомлений нет',
                  'Новые события приложений появятся здесь.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    final payload =
                        (data['payload'] as Map?)?.cast<String, dynamic>() ??
                            const <String, dynamic>{};
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.notifications_active_outlined,
                                color: Color(0xFFCD704A),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (data['title'] ?? 'Уведомление')
                                          .toString(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      (data['body'] ?? '').toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF475569),
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatAdminDateTime(data['createdAt']),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _miniInfo(
                                'Тип',
                                (data['type'] ?? payload['type'] ?? '—')
                                    .toString(),
                              ),
                              if ((payload['orderId'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _miniInfo(
                                  'Заказ',
                                  payload['orderId'].toString(),
                                ),
                              if ((payload['userId'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _miniInfo(
                                  'Клиент',
                                  payload['userId'].toString(),
                                ),
                              if ((payload['cleanerId'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _miniInfo(
                                  'Уборщица',
                                  payload['cleanerId'].toString(),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _payouts() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminPayoutsStream(),
      builder: (context, snapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.cleanersDirectoryStream(),
          builder: (context, cleanersSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _data.adminOrdersStream(),
              builder: (context, ordersSnapshot) {
                final cleanersById = {
                  for (final cleaner in cleanersSnapshot.data ??
                      const <Map<String, dynamic>>[])
                    (cleaner['id'] ?? '').toString(): cleaner,
                };
                final orders =
                    ordersSnapshot.data ?? const <Map<String, dynamic>>[];
                final query = _searchQuery.trim().toLowerCase();
                final filteredPayouts =
                    (snapshot.data ?? const <Map<String, dynamic>>[]).where((
                  data,
                ) {
                  final cleanerId = (data['cleanerId'] ?? '').toString();
                  final cleaner =
                      cleanersById[cleanerId] ?? const <String, dynamic>{};
                  if (!_matchesRecordDateRange(data)) {
                    return false;
                  }
                  if (query.isEmpty) {
                    return true;
                  }
                  return [
                    data['id'],
                    cleanerId,
                    data['net'],
                    data['amount'],
                    data['weekId'],
                    data['kaspiPhone'],
                    data['status'],
                    cleaner['name'],
                    cleaner['fullName'],
                    cleaner['phone'],
                    cleaner['clusterName'],
                    cleaner['serviceAreas'],
                  ].join(' ').toLowerCase().contains(query);
                });
                final docs = _sortRecordsByDate(filteredPayouts);
                return _sectionScaffold(
                  toolbar: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: !_canRunPayouts
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await _data.requestWeeklyPayout(
                                  cleanerId: 'all',
                                );
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Запрос на еженедельные выплаты отправлен'
                                          .tr(),
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text('Запустить weekly payout'.tr()),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            docs.isEmpty ? null : () => _copyPayoutsCsv(docs),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: Text('Копировать CSV'.tr()),
                      ),
                    ],
                  ),
                  child: docs.isEmpty
                      ? _emptyState(
                          'Выплаты не найдены',
                          'Начисления появятся после расчета payout batch.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final d = docs[index];
                            final cleanerId = (d['cleanerId'] ?? '').toString();
                            final cleaner = cleanersById[cleanerId] ??
                                const <String, dynamic>{};
                            final cleanerOrders = orders.where((order) {
                              return (order['cleanerId'] ?? '').toString() ==
                                  cleanerId;
                            }).toList();
                            final cleanerName = _personName(
                              cleaner,
                              d,
                              prefix: 'cleaner',
                            );
                            final cleanerPhone = _personPhone(
                              cleaner,
                              d,
                              prefix: 'cleaner',
                            );
                            final payoutId = (d['id'] ?? '').toString();
                            final status = (d['status'] ?? 'pending')
                                .toString()
                                .trim()
                                .toLowerCase();
                            final payoutType =
                                (d['payoutType'] ?? 'manual').toString();
                            final net = d['net'] ?? d['amount'] ?? 0;
                            final gross = d['gross'] ?? d['amount'] ?? 0;
                            final tax = d['tax'] ?? 0;
                            final kaspiPhone =
                                (d['kaspiPhone'] ?? '').toString();
                            final canReview = payoutId.isNotEmpty &&
                                (status == 'pending' || status == 'requested');
                            return _entityCard(
                              title: cleanerName,
                              subtitle:
                                  'Телефон: $cleanerPhone · К выплате $net ₸ · Начислено $gross ₸ · Налог $tax ₸',
                              badges: [
                                _statusBadge(
                                  _payoutStatusLabel(status),
                                  color: _payoutStatusColor(status),
                                ),
                                if ((d['weekId'] ?? '').toString().isNotEmpty)
                                  _statusBadge(
                                    'Период ${(d['weekId'] ?? '').toString()}',
                                    color: const Color(0xFF1D4ED8),
                                  ),
                              ],
                              actions: [
                                TextButton(
                                  onPressed: () => _openEntityDetails(
                                    context,
                                    title: cleanerName,
                                    sections: [
                                      _detailSection('Выплата', {
                                        'ID выплаты': payoutId,
                                        'Статус': _payoutStatusLabel(status),
                                        'Тип': payoutType == 'manual'
                                            ? 'Запрос уборщицы'
                                            : payoutType,
                                        'К выплате': '$net ₸',
                                        'Начислено': '$gross ₸',
                                        'Налог': '$tax ₸',
                                        'Kaspi': kaspiPhone.isEmpty
                                            ? '—'
                                            : kaspiPhone,
                                        'Создано': _formatDateTime(
                                          d['createdAt'],
                                        ),
                                      }),
                                      ..._cleanerDetailSections(
                                        cleaner,
                                        orders: cleanerOrders,
                                      ),
                                    ],
                                  ),
                                  child: Text('Подробнее'.tr()),
                                ),
                                if (canReview) ...[
                                  FilledButton(
                                    onPressed: () => _reviewPayout(
                                      payoutId: payoutId,
                                      approved: true,
                                    ),
                                    child: Text('Одобрить'.tr()),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _reviewPayout(
                                      payoutId: payoutId,
                                      approved: false,
                                    ),
                                    child: Text('Отклонить'.tr()),
                                  ),
                                ],
                              ],
                              body: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _adminInfoChip('Телефон', cleanerPhone),
                                  _adminInfoChip(
                                    'Районы',
                                    _cleanerAreasText(cleaner),
                                  ),
                                  _adminInfoChip(
                                    'Тип',
                                    payoutType == 'manual'
                                        ? 'Запрос уборщицы'
                                        : payoutType,
                                  ),
                                  _adminInfoChip(
                                    'Kaspi',
                                    kaspiPhone.isEmpty ? '—' : kaspiPhone,
                                  ),
                                  _adminInfoChip(
                                    'Заказов',
                                    cleanerOrders.length.toString(),
                                  ),
                                  _adminInfoChip(
                                    'Создано',
                                    _formatDateTime(d['createdAt']),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _reviewPayout({
    required String payoutId,
    required bool approved,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await _data.reviewCleanerPayout(payoutId: payoutId, approved: approved);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(approved ? 'Выплата одобрена' : 'Выплата отклонена'),
      ),
    );
  }

  Widget _reviews() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminReviewsStream(),
      builder: (context, snapshot) {
        final baseReviews = snapshot.data ?? const <Map<String, dynamic>>[];
        final customerIds = baseReviews.map(
          (review) => (review['customerId'] ?? '').toString(),
        );
        final cleanerIds = baseReviews.map(
          (review) => (review['cleanerId'] ?? '').toString(),
        );
        return FutureBuilder<List<Map<String, Map<String, dynamic>>>>(
          future: Future.wait([
            _data.adminCustomersByIds(customerIds),
            _data.adminCleanersByIds(cleanerIds),
          ]),
          builder: (context, peopleSnapshot) {
            final customers = peopleSnapshot.data?.first ??
                const <String, Map<String, dynamic>>{};
            final cleaners =
                peopleSnapshot.data != null && peopleSnapshot.data!.length > 1
                    ? peopleSnapshot.data![1]
                    : const <String, Map<String, dynamic>>{};
            final query = _searchQuery.trim().toLowerCase();
            final filteredReviews = baseReviews.where((review) {
              if (!_matchesRecordDateRange(review)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              final customer =
                  customers[(review['customerId'] ?? '').toString()] ??
                      const <String, dynamic>{};
              final cleaner =
                  cleaners[(review['cleanerId'] ?? '').toString()] ??
                      const <String, dynamic>{};
              return [
                review['orderId'],
                review['text'],
                review['rating'],
                review['customerName'],
                review['customerPhone'],
                review['cleanerName'],
                review['cleanerPhone'],
                customer['name'],
                customer['fullName'],
                customer['phone'],
                cleaner['name'],
                cleaner['fullName'],
                cleaner['phone'],
              ].join(' ').toLowerCase().contains(query);
            });
            final reviews = _sortRecordsByDate(filteredReviews);
            return _sectionScaffold(
              toolbar: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        reviews.isEmpty ? null : () => _copyReviewsCsv(reviews),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text('Копировать CSV'.tr()),
                  ),
                ],
              ),
              child: reviews.isEmpty
                  ? _emptyState(
                      'Отзывы не найдены',
                      'Оценки появятся после завершенных заказов.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: reviews.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final review = reviews[index];
                        final customer = customers[
                                (review['customerId'] ?? '').toString()] ??
                            const <String, dynamic>{};
                        final cleaner =
                            cleaners[(review['cleanerId'] ?? '').toString()] ??
                                const <String, dynamic>{};
                        return _reviewCard(
                          context: context,
                          review: review,
                          customer: customer,
                          cleaner: cleaner,
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _reviewCard({
    required BuildContext context,
    required Map<String, dynamic> review,
    required Map<String, dynamic> customer,
    required Map<String, dynamic> cleaner,
  }) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final customerName = _personName(customer, review, prefix: 'customer');
    final customerPhone = _personPhone(customer, review, prefix: 'customer');
    final cleanerName = _personName(cleaner, review, prefix: 'cleaner');
    final cleanerPhone = _personPhone(cleaner, review, prefix: 'cleaner');
    return _entityCard(
      title:
          'Заказ ${orderDisplayId(Map<String, dynamic>.from(review), fallback: (review['orderId'] ?? review['id'] ?? '—').toString())}',
      subtitle: [
        (review['text'] ?? 'Текст отзыва не указан').toString(),
        'Клиент: $customerName',
        'Уборщица: $cleanerName',
      ].where((item) => item.trim().isNotEmpty).join(' · '),
      badges: [
        _statusBadge(
          '$rating / 5',
          color: rating >= 4
              ? const Color(0xFF047857)
              : rating >= 3
                  ? const Color(0xFFD97706)
                  : const Color(0xFFDC2626),
        ),
        ...(((review['positiveTraits'] ?? const []) as List)
            .cast<dynamic>()
            .take(3)
            .map(
              (item) =>
                  _statusBadge(item.toString(), color: const Color(0xFF047857)),
            )),
        ...(((review['negativeTraits'] ?? const []) as List)
            .cast<dynamic>()
            .take(3)
            .map(
              (item) =>
                  _statusBadge(item.toString(), color: const Color(0xFFDC2626)),
            )),
      ],
      actions: [
        TextButton(
          onPressed: () => _openEntityDetails(
            context,
            title: 'Отзыв по заказу ${review['orderId'] ?? '—'}',
            sections: [
              _detailSection('Отзыв', {
                'Автор': review['authorRole'] == 'cleaner'
                    ? 'Уборщица оценила клиента'
                    : 'Клиент оценил уборщицу',
                'Оценка': '$rating / 5',
                'Текст': (review['text'] ?? '—').toString(),
                'Плюсы': ((review['positiveTraits'] ?? const []) as List).join(
                  ', ',
                ),
                'Минусы': ((review['negativeTraits'] ?? const []) as List).join(
                  ', ',
                ),
                'Создан': _formatAdminDateTime(review['createdAt']),
              }),
              _detailSection('Клиент', {
                'ФИО': customerName,
                'Телефон': customerPhone,
                'Email': _firstText([
                  customer['email'],
                  review['customerEmail'],
                ]),
                'Город': _firstText([customer['city'], review['customerCity']]),
                'Адрес': _firstText([
                  customer['address'],
                  customer['houseAddress'],
                  review['address'],
                  review['orderAddress'],
                ]),
                'Дом / ЖК': _firstText([
                  customer['residentialComplex'],
                  customer['houseName'],
                ]),
                'Подъезд': _firstText([customer['entrance']]),
                'Квартира': _firstText([customer['apartment']]),
                'Площадь': _firstText([customer['area'], review['area']]),
                'ID клиента': _firstText([
                  review['customerId'],
                  customer['id'],
                ]),
              }),
              _detailSection('Уборщица', {
                'ФИО': cleanerName,
                'Телефон': cleanerPhone,
                'Email': _firstText([cleaner['email'], review['cleanerEmail']]),
                'Статус': _firstText([
                  cleaner['verificationStatus'],
                  cleaner['status'],
                ]),
                'Рейтинг': _firstText([cleaner['rating']]),
                'ID уборщицы': _firstText([review['cleanerId'], cleaner['id']]),
              }),
              _detailSection('Заказ', {
                'ID заказа': _firstText([review['orderId'], review['id']]),
                'Дата': _formatAdminDateTime(
                  review['orderDate'] ?? review['scheduledDate'],
                ),
                'Время': _firstText([review['orderTime'], review['time']]),
                'Пакет': _firstText([review['package'], review['packageName']]),
                'Сумма': _firstText([review['price'], review['amount']]),
              }),
            ],
          ),
          child: Text('Открыть'.tr()),
        ),
        if ((review['photoUrl'] ?? '').toString().isNotEmpty)
          TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) =>
                    Dialog(child: Image.network(review['photoUrl'].toString())),
              );
            },
            child: Text('Фото'.tr()),
          ),
      ],
    );
  }

  Widget _checklists() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminChecklistsStream(),
      builder: (context, snapshot) {
        final baseDocs = snapshot.data ?? const <Map<String, dynamic>>[];
        final cleanerIds = baseDocs.map(
          (data) => (data['cleanerId'] ?? '').toString(),
        );
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _data.adminCleanersByIds(cleanerIds),
          builder: (context, cleanersSnapshot) {
            final cleaners =
                cleanersSnapshot.data ?? const <String, Map<String, dynamic>>{};
            final query = _searchQuery.trim().toLowerCase();
            final filteredChecklists = baseDocs.where((data) {
              final cleaner = cleaners[(data['cleanerId'] ?? '').toString()] ??
                  const <String, dynamic>{};
              if (!_matchesRecordDateRange(data)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return [
                data['id'],
                data['orderId'],
                data['cleanerId'],
                data['completedTasks'],
                cleaner['name'],
                cleaner['fullName'],
                cleaner['phone'],
                cleaner['clusterName'],
                cleaner['serviceAreas'],
              ].join(' ').toLowerCase().contains(query);
            });
            final docs = _sortRecordsByDate(filteredChecklists);
            return _sectionScaffold(
              toolbar: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        docs.isEmpty ? null : () => _copyChecklistsCsv(docs),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text('Копировать CSV'.tr()),
                  ),
                ],
              ),
              child: docs.isEmpty
                  ? _emptyState(
                      'Чек-листы не найдены',
                      'Заполненные чек-листы появятся после выполнения заказов.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final data = docs[index];
                        final cleanerId = (data['cleanerId'] ?? '').toString();
                        final cleaner =
                            cleaners[cleanerId] ?? const <String, dynamic>{};
                        final cleanerName = _personName(
                          cleaner,
                          data,
                          prefix: 'cleaner',
                        );
                        final cleanerPhone = _personPhone(
                          cleaner,
                          data,
                          prefix: 'cleaner',
                        );
                        final tasks = ((data['completedTasks'] ?? []) as List)
                            .map((e) => '$e')
                            .join(', ');
                        final addons = ((data['addons'] ?? []) as List)
                            .map((e) => '$e')
                            .join(', ');
                        final orderedAddons = ((data['orderedAddons'] ??
                                data['addonsDetailed'] ??
                                []) as List)
                            .map((e) {
                              if (e is Map) {
                                return (e['label'] ??
                                        e['title'] ??
                                        e['name'] ??
                                        e['key'] ??
                                        '')
                                    .toString();
                              }
                              return '$e';
                            })
                            .where((e) => e.trim().isNotEmpty)
                            .join(', ');
                        return _entityCard(
                          title:
                              'Заказ ${orderDisplayId(Map<String, dynamic>.from(data), fallback: (data['orderId'] ?? data['id'] ?? '—').toString())}',
                          subtitle:
                              'Уборщица: $cleanerName · Телефон: $cleanerPhone · Районы: ${_cleanerAreasText(cleaner)} · Чек-лист: ${tasks.isEmpty ? 'нет' : tasks}',
                          badges: [
                            _statusBadge(
                              '${((data['completedTasks'] ?? []) as List).length} задач',
                              color: const Color(0xFF1D4ED8),
                            ),
                          ],
                          actions: [
                            TextButton(
                              onPressed: () => _openEntityDetails(
                                context,
                                title:
                                    'Чек-лист ${data['orderId'] ?? data['id']}',
                                sections: [
                                  _detailSection('Выполнение', {
                                    'Уборщица': cleanerName,
                                    'Телефон уборщицы': cleanerPhone,
                                    'Районы работы': _cleanerAreasText(cleaner),
                                    'Задачи': tasks.isEmpty ? 'нет' : tasks,
                                    'Заказанные доп. услуги':
                                        orderedAddons.isEmpty
                                            ? 'нет'
                                            : orderedAddons,
                                    'Выполненные доп. услуги':
                                        addons.isEmpty ? 'нет' : addons,
                                    'Комментарий':
                                        (data['note'] ?? '—').toString(),
                                  }),
                                  ..._cleanerDetailSections(cleaner),
                                ],
                              ),
                              child: Text('Открыть'.tr()),
                            ),
                            TextButton(
                              onPressed: cleaner.isEmpty
                                  ? null
                                  : () => _openEntityDetails(
                                        context,
                                        title: cleanerName,
                                        sections:
                                            _cleanerDetailSections(cleaner),
                                      ),
                              child: Text('Уборщица'.tr()),
                            ),
                          ],
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _cleaners() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.cleanersDirectoryStream(),
      builder: (context, snapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.adminCleanerDailyScheduleStream(),
          builder: (context, scheduleSnapshot) {
            final selectedDate = _filterStartDate ?? DateTime.now();
            final selectedDateKey =
                '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
            final scheduleByCleaner = <String, Map<String, dynamic>>{
              for (final item
                  in (scheduleSnapshot.data ?? const <Map<String, dynamic>>[]))
                if ((item['dateKey'] ?? '').toString() == selectedDateKey)
                  (item['cleanerId'] ?? '').toString(): item,
            };
            final query = _searchQuery.trim().toLowerCase();
            final filteredCleaners = (snapshot.data ?? []).where((cleaner) {
              if (!_matchesRecordDateRange(cleaner)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              final haystack = [
                cleaner['id'],
                cleaner['name'],
                cleaner['clusterName'],
                cleaner['verificationStatus'],
                cleaner['cleanerStatusLabel'],
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            });
            final cleaners = _sortRecordsByDate(filteredCleaners);
            return _sectionScaffold(
              toolbar: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: !_canEditCleaners
                        ? null
                        : () => _openCleanerEditor(context, null),
                    icon: const Icon(Icons.add),
                    label: Text('Добавить уборщицу'.tr()),
                  ),
                  _statusLegendChip('Approved', const Color(0xFF047857)),
                  _statusLegendChip('Pending', const Color(0xFFD97706)),
                  _statusLegendChip(
                    'Нагрузка на ${_dateLabel(selectedDate)}',
                    const Color(0xFF1D4ED8),
                  ),
                ],
              ),
              child: cleaners.isEmpty
                  ? _emptyState(
                      'Уборщицы не найдены',
                      'Измените поиск или добавьте нового исполнителя.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: cleaners.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final cleaner = cleaners[index];
                        final earnings =
                            (cleaner['monthlyEarnings'] as num?)?.toInt() ?? 0;
                        final verification =
                            (cleaner['verificationStatus'] ?? 'draft')
                                .toString()
                                .toLowerCase();
                        final dailySchedule = scheduleByCleaner[
                                (cleaner['id'] ?? '').toString()] ??
                            const <String, dynamic>{};
                        final totalSqm =
                            (dailySchedule['totalSqm'] as num?)?.toDouble() ??
                                0;
                        final totalMinutes =
                            (dailySchedule['totalMinutes'] as num?)?.toInt() ??
                                0;
                        final assignedOrders =
                            ((dailySchedule['orders'] as List?) ?? const [])
                                .length;
                        final remainingSqm = math.max(
                          0,
                          220 - totalSqm.round(),
                        );
                        final loadHours = (totalMinutes / 60).toStringAsFixed(
                          1,
                        );
                        final cleanerName = _personName(
                          cleaner,
                          const {},
                          prefix: 'cleaner',
                        );
                        return _entityCard(
                          title: cleanerName,
                          subtitle:
                              'Телефон: ${_personPhone(cleaner, const {}, prefix: 'cleaner')} · Районы: ${_cleanerAreasText(cleaner)} · Рейтинг: ${(cleaner['rating'] ?? 0)} · За месяц: $earnings ₸',
                          badges: [
                            _statusBadge(
                              _cleanerVerificationLabel(verification),
                              color: verification == 'approved'
                                  ? const Color(0xFF047857)
                                  : verification == 'rejected'
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFD97706),
                            ),
                            if ((cleaner['cleanerStatusLabel'] ?? '')
                                .toString()
                                .isNotEmpty)
                              _statusBadge(
                                (cleaner['cleanerStatusLabel'] ?? '')
                                    .toString(),
                                color: const Color(0xFF1D4ED8),
                              ),
                            _statusBadge(
                              totalSqm >= 220 ? 'День заполнен' : 'Есть запас',
                              color: totalSqm >= 220
                                  ? const Color(0xFF7C2D12)
                                  : const Color(0xFF0F766E),
                            ),
                          ],
                          actions: [
                            TextButton(
                              onPressed: () => _openCleanerDetails(
                                context,
                                cleaner,
                                initialDate: selectedDate,
                              ),
                              child: Text('Детали'.tr()),
                            ),
                            IconButton(
                              onPressed: !_canEditCleaners
                                  ? null
                                  : () => _openCleanerEditor(context, cleaner),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Удалить уборщицу',
                              onPressed: !_canEditCleaners
                                  ? null
                                  : () => _deleteCleaner(cleaner),
                              color: const Color(0xFFDC2626),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                          body: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _adminInfoChip(
                                'Нагрузка',
                                '${totalSqm.toStringAsFixed(0)} из 220 м²',
                              ),
                              _adminInfoChip('Часы', '$loadHours ч'),
                              _adminInfoChip(
                                'Заказов',
                                assignedOrders.toString(),
                              ),
                              _adminInfoChip('Остаток', '$remainingSqm м²'),
                              _adminInfoChip(
                                'Регистрация',
                                _firstAdminDateTime(cleaner, const [
                                  'registeredAt',
                                  'createdAt',
                                  'joinedAt',
                                  'joinDate',
                                ]),
                              ),
                              _adminInfoChip(
                                'Верификация',
                                _firstAdminDateTime(cleaner, const [
                                  'approvedAt',
                                  'verifiedAt',
                                  'reviewedAt',
                                  'verificationApprovedAt',
                                ]),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _clusters() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.clustersStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final filteredClusters = (snapshot.data ?? []).where((cluster) {
          if (!_matchesRecordDateRange(cluster)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${cluster['id']} ${cluster['name']} ${cluster['residentialComplex'] ?? ''}'
              .toLowerCase()
              .contains(query);
        });
        final clusters = _sortRecordsByDate(filteredClusters);
        return _sectionScaffold(
          toolbar: ElevatedButton.icon(
            onPressed: !_canEditClusters
                ? null
                : () => _openClusterEditor(context, null),
            icon: const Icon(Icons.add),
            label: Text('Добавить кластер'.tr()),
          ),
          child: clusters.isEmpty
              ? _emptyState(
                  'Кластеры не найдены',
                  'Добавьте новый кластер или измените поиск.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: clusters.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final cluster = clusters[index];
                    return _entityCard(
                      title: (cluster['name'] ?? cluster['id']).toString(),
                      subtitle:
                          'ЖК: ${(cluster['residentialComplex'] ?? '—')} · Радиус: ${(cluster['radiusMeters'] ?? 300)} м · Уборщиц: ${(cluster['cleanersCount'] ?? 0)}',
                      actions: [
                        TextButton(
                          onPressed: () => _openEntityDetails(
                            context,
                            title:
                                (cluster['name'] ?? cluster['id']).toString(),
                            sections: [
                              _detailSection('Параметры', {
                                'ID': (cluster['id'] ?? '—').toString(),
                                'ЖК': (cluster['residentialComplex'] ?? '—')
                                    .toString(),
                                'Широта': '${cluster['lat'] ?? 0}',
                                'Долгота': '${cluster['lng'] ?? 0}',
                                'Радиус': '${cluster['radiusMeters'] ?? 300} м',
                              }),
                            ],
                          ),
                          child: Text('Открыть'.tr()),
                        ),
                        IconButton(
                          onPressed: !_canEditClusters
                              ? null
                              : () => _openClusterEditor(context, cluster),
                          icon: const Icon(Icons.edit_location_alt_outlined),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _clusterSchedule() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.clustersStream(),
      builder: (context, snapshot) {
        final clusters = snapshot.data ?? [];
        if (clusters.isEmpty) {
          return _emptyState(
            'Кластеры не настроены',
            'Сначала создайте хотя бы один кластер.',
          );
        }
        return _sectionScaffold(
          child: DefaultTabController(
            length: clusters.length,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  alignment: Alignment.centerLeft,
                  child: TabBar(
                    isScrollable: true,
                    tabs: clusters
                        .map(
                          (cluster) => Tab(
                            text: (cluster['name'] ?? cluster['id']).toString(),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: clusters
                        .map(
                          (cluster) => _clusterScheduleList(
                            (cluster['name'] ?? cluster['id']).toString(),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _clusterScheduleList(String clusterName) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.scheduleSlotsByClusterStream(clusterName),
      builder: (context, snapshot) {
        final slots = snapshot.data ?? [];
        final query = _searchQuery.trim().toLowerCase();
        final filteredSlots = slots.where((slot) {
          if (!_matchesDateRange(slot['scheduledFor'] ?? _slotDate(slot))) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${slot['customerName'] ?? ''} ${slot['customerPhone'] ?? ''} ${slot['cleanerName'] ?? ''} ${slot['package'] ?? ''} ${slot['status'] ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList();
        filteredSlots.sort(
          (a, b) => _dateSortOrder == 'Сначала старые'
              ? _slotDate(a).compareTo(_slotDate(b))
              : _slotDate(b).compareTo(_slotDate(a)),
        );
        final filtered = filteredSlots;
        if (filtered.isEmpty) {
          return _emptyState(
            'Слоты не найдены',
            'Для этого кластера пока нет подходящих записей.',
            compact: true,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final slot = filtered[index];
            return _entityCard(
              title: '${_slotDateText(slot)} · ${_firstText([
                    slot['customerName'],
                    'Клиент'
                  ])}',
              subtitle:
                  'Уборщица: ${(slot['cleanerName'] ?? 'не назначена')} · Статус: ${(slot['status'] ?? '—')} · Пакет: ${(slot['package'] ?? '—')}',
              badges: [
                _statusBadge(
                  (slot['status'] ?? '—').toString(),
                  color: (slot['status'] ?? '') == 'scheduled'
                      ? const Color(0xFF1D4ED8)
                      : const Color(0xFFD97706),
                ),
              ],
              actions: [
                TextButton(
                  onPressed: () => _openEntityDetails(
                    context,
                    title: 'Слот ${(slot['id'] ?? '—')}',
                    sections: [
                      _detailSection('Расписание', {
                        'Дата и время': _slotDateText(slot),
                        'Клиент': _firstText([slot['customerName'], 'Клиент']),
                        'Телефон клиента': _firstText([
                          slot['customerPhone'],
                          slot['phone'],
                        ]),
                        'Уборщица':
                            (slot['cleanerName'] ?? 'не назначена').toString(),
                        'Статус': (slot['status'] ?? '—').toString(),
                        'Пакет': (slot['package'] ?? '—').toString(),
                      }),
                    ],
                  ),
                  child: Text('Открыть'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _adminDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  DateTime _adminOrderDate(Map<String, dynamic> order) {
    final dateKey = (order['scheduledDateKey'] ??
            order['visitDateKey'] ??
            order['dateKey'] ??
            '')
        .toString()
        .trim();
    final parsedDateKey = DateTime.tryParse(dateKey);
    if (parsedDateKey != null) {
      return parsedDateKey;
    }
    return _normalizeToDate(
          order['scheduledFor'] ??
              order['scheduledDate'] ??
              order['visitDate'] ??
              order['date'] ??
              order['createdAt'],
        ) ??
        DateTime.now();
  }

  String _adminOrderDateText(Map<String, dynamic> order) {
    final dateKey = (order['scheduledDateKey'] ??
            order['visitDateKey'] ??
            order['dateKey'] ??
            '')
        .toString()
        .trim();
    final parsedDateKey = DateTime.tryParse(dateKey);
    if (parsedDateKey != null) {
      return _dateLabel(parsedDateKey);
    }
    final date = _normalizeToDate(
      order['scheduledFor'] ??
          order['scheduledDate'] ??
          order['visitDate'] ??
          order['date'] ??
          order['createdAt'],
    );
    return date == null ? '—' : _dateLabel(date);
  }

  String _adminOrderTimeText(Map<String, dynamic> order) {
    final raw = (order['time'] ??
            order['scheduledTime'] ??
            order['orderTime'] ??
            order['timeRange'] ??
            '')
        .toString()
        .trim();
    if (raw.isEmpty || raw == '—') {
      return '—';
    }
    final range = RegExp(
      r'\d{1,2}:\d{2}\s*[-–—]\s*\d{1,2}:\d{2}',
    ).firstMatch(raw);
    if (range != null) {
      return range.group(0)!.replaceAll(RegExp(r'\s*[–—]\s*'), ' - ');
    }
    final times = RegExp(r'\d{1,2}:\d{2}').allMatches(raw).toList();
    if (times.length >= 2) {
      return '${times[0].group(0)} - ${times[1].group(0)}';
    }
    return raw;
  }

  List<int>? _adminTimeRange(String raw) {
    final matches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(raw).toList();
    if (matches.length < 2) {
      return null;
    }
    int minutes(RegExpMatch match) =>
        (int.tryParse(match.group(1) ?? '') ?? 0) * 60 +
        (int.tryParse(match.group(2) ?? '') ?? 0);
    final start = minutes(matches.first);
    final end = minutes(matches[1]);
    if (end <= start) {
      return null;
    }
    return [start, end];
  }

  bool _adminRangesOverlap(List<int> left, List<int> right) =>
      left[0] < right[1] && right[0] < left[1];

  bool _adminActiveAssignedOrder(Map<String, dynamic> order) {
    final status = (order['orderStatus'] ?? order['status'] ?? '')
        .toString()
        .toLowerCase();
    return const {
      'assigned',
      'confirmed',
      'start_pending',
      'in_progress',
    }.contains(status);
  }

  bool _cleanerIsFreeForOrder(
    Map<String, dynamic> cleaner,
    Map<String, dynamic> targetOrder,
    List<Map<String, dynamic>> allOrders,
  ) {
    final cleanerId = (cleaner['id'] ?? cleaner['cleanerId'] ?? '').toString();
    if (cleanerId.isEmpty ||
        (cleaner['verificationStatus'] ?? '').toString() != 'approved') {
      return false;
    }
    final targetDateKey = _adminDateKey(_adminOrderDate(targetOrder));
    final targetRange = _adminTimeRange((targetOrder['time'] ?? '').toString());
    if (targetRange == null) {
      return true;
    }
    final targetId =
        (targetOrder['id'] ?? targetOrder['orderId'] ?? '').toString().trim();
    for (final order in allOrders) {
      final orderId = (order['id'] ?? order['orderId'] ?? '').toString().trim();
      if (orderId == targetId ||
          (order['cleanerId'] ?? '').toString() != cleanerId ||
          !_adminActiveAssignedOrder(order) ||
          _adminDateKey(_adminOrderDate(order)) != targetDateKey) {
        continue;
      }
      final range = _adminTimeRange((order['time'] ?? '').toString());
      if (range != null && _adminRangesOverlap(range, targetRange)) {
        return false;
      }
    }
    return true;
  }

  String _adminOrderScopeType(Map<String, dynamic> order) {
    final raw = _firstText([
      order['scopeType'],
      order['sourceType'],
      order['type'],
    ]).toLowerCase();
    if (raw.contains('schedule') || raw.contains('slot')) {
      return 'schedule_slot';
    }
    final subscriptionId = (order['subscriptionId'] ?? '').toString().trim();
    final scheduledDateKey =
        (order['scheduledDateKey'] ?? '').toString().trim();
    final sourceOrderId =
        (order['sourceOrderId'] ?? order['customerOrderId'] ?? '')
            .toString()
            .trim();
    final bookingMode = (order['bookingMode'] ?? '').toString().toLowerCase();
    if (subscriptionId.isNotEmpty &&
        scheduledDateKey.isNotEmpty &&
        sourceOrderId.isNotEmpty &&
        (bookingMode.contains('date_confirmation') ||
            bookingMode.contains('schedule') ||
            bookingMode.isEmpty)) {
      return 'schedule_slot';
    }
    return 'order';
  }

  Future<void> _openCleanerDetails(
    BuildContext context,
    Map<String, dynamic> cleaner, {
    required DateTime initialDate,
  }) async {
    var selectedDate = initialDate;
    final cleanerId = (cleaner['id'] ?? cleaner['cleanerId'] ?? '').toString();
    final cleanerName = _personName(cleaner, const {}, prefix: 'cleaner');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.86,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.adminAssignmentItemsStream(),
                builder: (context, snapshot) {
                  final dateKey = _adminDateKey(selectedDate);
                  final orders = (snapshot.data ??
                          const <Map<String, dynamic>>[])
                      .where(
                        (order) =>
                            (order['cleanerId'] ?? '').toString() ==
                                cleanerId &&
                            _adminDateKey(_adminOrderDate(order)) == dateKey,
                      )
                      .toList()
                    ..sort(
                      (a, b) => (a['time'] ?? '').toString().compareTo(
                            (b['time'] ?? '').toString(),
                          ),
                    );
                  final minutes = orders.fold<int>(0, (total, order) {
                    final value = order['totalDurationMinutes'] ??
                        order['estimatedDurationMinutes'];
                    return total + ((value as num?)?.toInt() ?? 0);
                  });
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cleanerName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Телефон: ${_personPhone(cleaner, const {}, prefix: '.tr()cleaner')} · Районы: ${_cleanerAreasText(cleaner)}',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _adminInfoChip(
                            'Зарегистрировалась',
                            _firstAdminDateTime(cleaner, const [
                              'registeredAt',
                              'createdAt',
                              'joinedAt',
                              'joinDate',
                            ]),
                          ),
                          _adminInfoChip(
                            'Загрузила документы',
                            _firstAdminDateTime(cleaner, const [
                              'documentsSubmittedAt',
                              'submittedAt',
                              'verificationSubmittedAt',
                              'documentsUploadedAt',
                            ]),
                          ),
                          _adminInfoChip(
                            'Верификацию прошла',
                            _firstAdminDateTime(cleaner, const [
                              'approvedAt',
                              'verifiedAt',
                              'reviewedAt',
                              'verificationApprovedAt',
                            ]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2028),
                              );
                              if (picked != null) {
                                setModalState(() => selectedDate = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_month),
                            label: Text(_dateLabel(selectedDate)),
                          ),
                          _adminInfoChip('Заказов', '${orders.length}'),
                          _adminInfoChip(
                            'Часы',
                            '${(minutes / 60).toStringAsFixed(1)} ч',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (orders.isEmpty)
                        _emptyState(
                          'Уборок на дату нет',
                          'Выберите другую дату в календаре.',
                        )
                      else
                        ...orders.map(
                          (order) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _entityCard(
                              title: '${order['time'] ?? '—'} · ${_firstText([
                                    order['customerName'],
                                    'Клиент'
                                  ])}',
                              subtitle:
                                  '${order['address'] ?? 'Адрес не указан'} · ${order['apartmentArea'] ?? order['area'] ?? '—'} м²',
                              badges: [
                                _statusBadge(
                                  (order['orderStatus'] ??
                                          order['status'] ??
                                          '—')
                                      .toString(),
                                  color: const Color(0xFF0F766E),
                                ),
                              ],
                              actions: [
                                TextButton(
                                  onPressed: () => _openEntityDetails(
                                    context,
                                    title: 'Заказ ${order['id'] ?? ''}',
                                    sections: [
                                      _detailSection('Данные заказа', {
                                        'Клиент': _firstText([
                                          order['customerName'],
                                          'Клиент',
                                        ]),
                                        'Телефон': _firstText([
                                          order['customerPhone'],
                                          order['phone'],
                                        ]),
                                        'Дата': _dateLabel(
                                          _adminOrderDate(order),
                                        ),
                                        'Время':
                                            (order['time'] ?? '—').toString(),
                                        'Адрес': (order['address'] ?? '—')
                                            .toString(),
                                        'Статус': (order['orderStatus'] ??
                                                order['status'] ??
                                                '—')
                                            .toString(),
                                      }),
                                    ],
                                  ),
                                  child: Text('Открыть'.tr()),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _openAssignCleaner(
    BuildContext context,
    String orderId,
    Map<String, dynamic> order,
    List<Map<String, dynamic>> cleaners,
    List<Map<String, dynamic>> allOrders,
  ) async {
    final alreadyAssigned =
        (order['cleanerId'] ?? '').toString().trim().isNotEmpty;
    var scheduleSlots = const <Map<String, dynamic>>[];
    try {
      scheduleSlots = await _data.adminScheduleSlotsStream().first.timeout(
            const Duration(seconds: 4),
          );
    } catch (_) {
      scheduleSlots = const <Map<String, dynamic>>[];
    }
    final busyItems = <Map<String, dynamic>>[
      ...allOrders,
      ...scheduleSlots.map(
        (slot) => {
          ...slot,
          'orderStatus': slot['status'],
          'scopeType': 'schedule_slot',
        },
      ),
    ];
    if (!context.mounted) {
      return false;
    }
    var assigned = false;
    final freeCleaners = cleaners
        .where(
          (cleaner) => _cleanerIsFreeForOrder(cleaner, order, busyItems),
        )
        .toList()
      ..sort(
        (a, b) => _personName(
          a,
          const {},
          prefix: 'cleaner',
        ).compareTo(_personName(b, const {}, prefix: 'cleaner')),
      );
    String? selectedCleanerId;
    String? selectedCleanerName;
    final timeController = TextEditingController(
      text: (order['time'] ?? '10:00 - 13:00').toString(),
    );
    final addressController = TextEditingController(
      text: (order['address'] ?? '').toString(),
    );
    final orderStatus =
        (order['orderStatus'] ?? order['status'] ?? '').toString();
    final scopeType = _adminOrderScopeType(order);
    final statusWarning = scopeType == 'schedule_slot'
        ? ''
        : orderStatus != 'pending_assignment'
            ? 'Заказ сейчас нельзя назначить: статус "$orderStatus". Нужно, чтобы заказ был в ожидании назначения уборщицы.'
            : '';
    final noCleanerWarning = freeCleaners.isEmpty
        ? 'Нет свободных уборщиц. Проверьте: уборщица подтверждена, работает в этом городе и районе, и у нее нет пересечения по времени.'
        : '';
    var assignError = '';
    var assigning = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Назначить уборщицу'.tr(),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Свободны на ${_dateLabel(_adminOrderDate(order))}, ${timeController.text.trim()}: ${freeCleaners.length}'
                        .tr(),
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  if (statusWarning.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _adminWarningBox(statusWarning),
                  ],
                  if (noCleanerWarning.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _adminWarningBox(noCleanerWarning),
                  ],
                  if (assignError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _adminWarningBox(assignError),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCleanerId,
                    items: freeCleaners
                        .map(
                          (cleaner) => DropdownMenuItem<String>(
                            value: cleaner['id'].toString(),
                            child: Text(
                              '${_personName(cleaner, const {}, prefix: 'cleaner')} · ${_personPhone(cleaner, const {}, prefix: 'cleaner')}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      final cleaner = freeCleaners.firstWhere(
                        (item) => item['id'].toString() == value,
                        orElse: () => const {},
                      );
                      setModalState(() {
                        selectedCleanerId = value;
                        selectedCleanerName = _personName(
                          cleaner,
                          const {},
                          prefix: 'cleaner',
                        );
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Уборщица'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: timeController,
                    decoration: const InputDecoration(labelText: 'Время'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Адрес'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedCleanerId == null ||
                              freeCleaners.isEmpty ||
                              assigning
                          ? null
                          : () async {
                              setModalState(() {
                                assigning = true;
                                assignError = '';
                              });
                              try {
                                await _data.assignCleanerFromAdmin(
                                  orderId: orderId,
                                  cleanerId: selectedCleanerId!,
                                  cleanerName: selectedCleanerName ?? '',
                                  scheduledDate: _adminOrderDate(order),
                                  time: timeController.text.trim(),
                                  address: addressController.text.trim(),
                                  scopeType: scopeType,
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                assigned = true;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Уборщица назначена.'.tr()),
                                  ),
                                );
                              } catch (error) {
                                final message = _assignCleanerErrorMessage(
                                  error,
                                );
                                setModalState(() {
                                  assignError = message;
                                  assigning = false;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(message)),
                                  );
                                }
                              }
                            },
                      child: assigning
                          ? Text('Назначаем...'.tr())
                          : Text(
                              alreadyAssigned ? 'Переназначить' : 'Назначить',
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    return assigned;
  }

  Widget _adminWarningBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9A3412),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _assignCleanerErrorMessage(Object error) {
    final raw = error.toString();
    final text = raw.toLowerCase();
    if (text.contains('order must be pending assignment')) {
      return 'Не удалось назначить: заказ не в ожидании назначения. Верните заказ в статус ожидания назначения или создайте новый подбор уборщицы.';
    }
    if (text.contains('cleaner verification must be approved')) {
      return 'Не удалось назначить: уборщица не подтверждена. Откройте карточку уборщицы и подтвердите ее.';
    }
    if (text.contains('cleaner not found')) {
      return 'Не удалось назначить: уборщица не найдена в базе. Обновите список уборщиц.';
    }
    if (text.contains('slot not found')) {
      return 'Не удалось назначить: визит уборки не найден. Обновите страницу заказов, проверьте, что заказ не отменен, и попробуйте снова.';
    }
    if (text.contains('order not found')) {
      return 'Не удалось назначить: заказ не найден. Обновите страницу заказов.';
    }
    if (text.contains('вне рабочих районов')) {
      return 'Не удалось назначить: заказ вне рабочих районов уборщицы. Добавьте ей нужный район или выберите другую уборщицу.';
    }
    if (text.contains('другого города')) {
      return 'Не удалось назначить: уборщица из другого города. Выберите уборщицу из города клиента.';
    }
    if (text.contains('у уборщицы уже есть заказ')) {
      return raw;
    }
    if (text.contains('unauthenticated') || text.contains('unauthorized')) {
      return 'Не удалось назначить: сессия администратора истекла. Войдите в админку заново.';
    }
    if (text.contains('permission-denied')) {
      return 'Не удалось назначить: у аккаунта нет прав администратора.';
    }
    if (text.contains('deadline') || text.contains('unavailable')) {
      return 'Не удалось назначить: функция временно недоступна. Проверьте интернет и попробуйте еще раз.';
    }
    return 'Не удалось назначить уборщицу. Проверьте статус заказа, район, город, занятость уборщицы и попробуйте снова.';
  }

  Future<void> _openCleanerEditor(
    BuildContext context,
    Map<String, dynamic>? cleaner,
  ) async {
    final idController = TextEditingController(
      text: (cleaner?['id'] ?? '').toString(),
    );
    final nameController = TextEditingController(
      text: (cleaner?['name'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (cleaner?['phone'] ?? '').toString(),
    );
    final clusterController = TextEditingController(
      text: (cleaner?['clusterName'] ?? '').toString(),
    );
    final serviceAreasController = TextEditingController(
      text: ((cleaner?['serviceAreas'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .join(', '),
    );
    final addressController = TextEditingController(
      text: (cleaner?['homeAddress'] ?? '').toString(),
    );
    final verificationController = TextEditingController(
      text: (cleaner?['verificationStatus'] ?? 'draft').toString(),
    );
    final areaController = TextEditingController(
      text: '${cleaner?['totalCleanedArea'] ?? 0}',
    );
    final dailyIncomeController = TextEditingController(
      text: '${cleaner?['dailyIncomeOverride'] ?? 0}',
    );
    final manualBonusController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cleaner == null
                      ? 'Новая уборщица'
                      : 'Редактирование уборщицы',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idController,
                  readOnly: cleaner != null,
                  decoration: const InputDecoration(labelText: 'ID'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Имя'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Телефон'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clusterController,
                  decoration: const InputDecoration(labelText: 'Кластер'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: serviceAreasController,
                  decoration: const InputDecoration(
                    labelText: 'Рабочие районы',
                    helperText:
                        'Через запятую, например: ЖК Триумф, Астана центр',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Домашний адрес',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: verificationController,
                  decoration: const InputDecoration(
                    labelText: 'Статус верификации',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: areaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Убрано квадратных метров',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dailyIncomeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ставка за день (override, 0 = по политике)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: manualBonusController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Добавить бонус вручную (текущий: ${cleaner?['manualBonusTotal'] ?? 0} ₸)',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final cleanerId = idController.text.trim();
                      if (cleanerId.isEmpty) {
                        return;
                      }
                      final currentManualBonus =
                          (cleaner?['manualBonusTotal'] as num?)?.toInt() ?? 0;
                      final bonusToAdd =
                          int.tryParse(manualBonusController.text.trim()) ?? 0;
                      await _data.upsertCleaner(
                        cleanerId: cleanerId,
                        data: {
                          'name': nameController.text.trim(),
                          'fullName': nameController.text.trim(),
                          'phone': phoneController.text.trim(),
                          'clusterName': clusterController.text.trim(),
                          'serviceAreas': serviceAreasController.text
                              .split(',')
                              .map((item) => item.trim())
                              .where((item) => item.isNotEmpty)
                              .toList(),
                          'homeAddress': addressController.text.trim(),
                          'verificationStatus':
                              verificationController.text.trim(),
                          'totalCleanedArea':
                              int.tryParse(areaController.text.trim()) ?? 0,
                          'dailyIncomeOverride':
                              int.tryParse(dailyIncomeController.text.trim()) ??
                                  0,
                          'manualBonusTotal': currentManualBonus + bonusToAdd,
                        },
                      );
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.pop(context);
                    },
                    child: Text('Сохранить'.tr()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openClusterEditor(
    BuildContext context,
    Map<String, dynamic>? cluster,
  ) async {
    final idController = TextEditingController(
      text: (cluster?['id'] ?? '').toString(),
    );
    final nameController = TextEditingController(
      text: (cluster?['name'] ?? '').toString(),
    );
    final latController = TextEditingController(
      text: (cluster?['lat'] ?? '').toString(),
    );
    final lngController = TextEditingController(
      text: (cluster?['lng'] ?? '').toString(),
    );
    final radiusController = TextEditingController(
      text: (cluster?['radiusMeters'] ?? 300).toString(),
    );
    final residentialController = TextEditingController(
      text: (cluster?['residentialComplex'] ?? '').toString(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cluster == null ? 'Новый кластер' : 'Редактирование кластера',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idController,
                  readOnly: cluster != null,
                  decoration: const InputDecoration(labelText: 'ID'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: residentialController,
                  decoration: const InputDecoration(labelText: 'ЖК'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: latController,
                  decoration: const InputDecoration(labelText: 'Широта'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lngController,
                  decoration: const InputDecoration(labelText: 'Долгота'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: radiusController,
                  decoration: const InputDecoration(labelText: 'Радиус (м)'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final clusterId = idController.text.trim();
                      if (clusterId.isEmpty) {
                        return;
                      }
                      await _data.upsertCluster(
                        clusterId: clusterId,
                        data: {
                          'name': nameController.text.trim(),
                          'residentialComplex':
                              residentialController.text.trim(),
                          'lat':
                              double.tryParse(latController.text.trim()) ?? 0,
                          'lng':
                              double.tryParse(lngController.text.trim()) ?? 0,
                          'radiusMeters':
                              int.tryParse(radiusController.text.trim()) ?? 300,
                        },
                      );
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.pop(context);
                    },
                    child: Text('Сохранить'.tr()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHouseEditor(
    BuildContext context,
    Map<String, dynamic>? house,
  ) async {
    final idController = TextEditingController(
      text: (house?['id'] ?? '').toString(),
    );
    final titleController = TextEditingController(
      text: (house?['title'] ?? '').toString(),
    );
    final addressController = TextEditingController(
      text: (house?['address'] ?? '').toString(),
    );
    final residentialController = TextEditingController(
      text: (house?['residentialComplex'] ?? '').toString(),
    );
    final serviceAreaController = TextEditingController(
      text: (house?['serviceArea'] ??
              house?['clusterName'] ??
              house?['residentialComplex'] ??
              '')
          .toString(),
    );
    final clusterController = TextEditingController(
      text: (house?['clusterName'] ?? '').toString(),
    );
    final zoneController = TextEditingController(
      text: (house?['zoneId'] ?? '').toString(),
    );
    final thresholdController = TextEditingController(
      text: (house?['threshold'] ?? 1).toString(),
    );
    final currentUsersController = TextEditingController(
      text: (house?['current_users'] ?? 1).toString(),
    );
    final initialLat = house?['lat'];
    final initialLng = house?['lng'];
    Map<String, double>? housePoint;
    if (initialLat is num && initialLng is num) {
      housePoint = {'lat': initialLat.toDouble(), 'lng': initialLng.toDouble()};
    }
    final zones = await _data.serviceZonesStream().first;
    if (!context.mounted || !mounted) {
      return;
    }
    var selectedZoneId = zoneController.text.trim();
    final zonePolygons = zones
        .map(
          (zone) => {
            'id': (zone['id'] ?? '').toString(),
            'title': (zone['title'] ?? zone['id'] ?? '').toString(),
            'polygon': _geoPolygonFrom(zone['polygon']),
          },
        )
        .where(
          (zone) =>
              (zone['id'] as String).isNotEmpty &&
              (zone['polygon'] as List).length >= 3,
        )
        .toList();
    void applyZone(Map<String, dynamic> zone) {
      final zoneId = (zone['id'] ?? '').toString();
      final title = (zone['title'] ?? zoneId).toString();
      selectedZoneId = zoneId;
      zoneController.text = zoneId;
      serviceAreaController.text = title;
      clusterController.text = title;
    }

    var status = (house?['status'] ?? 'ACTIVE').toString().toUpperCase();
    if (!const ['ACTIVE', 'IN_PROGRESS', 'INACTIVE'].contains(status)) {
      status = 'ACTIVE';
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      house == null ? 'Новый дом' : 'Редактирование дома',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: idController,
                      readOnly: house != null,
                      decoration: const InputDecoration(labelText: 'ID дома'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Адрес'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: residentialController,
                      decoration: const InputDecoration(labelText: 'ЖК'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('house_zone_$selectedZoneId'),
                      initialValue: zones.any(
                        (zone) =>
                            (zone['id'] ?? '').toString() == selectedZoneId,
                      )
                          ? selectedZoneId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Район',
                        helperText:
                            'Выберите район, который был нарисован на карте в разделе Зоны',
                      ),
                      items: [
                        for (final zone in zones)
                          DropdownMenuItem(
                            value: (zone['id'] ?? '').toString(),
                            child: Text(
                              (zone['title'] ?? zone['id']).toString(),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        final zone =
                            zones.cast<Map<String, dynamic>?>().firstWhere(
                                  (item) =>
                                      (item?['id'] ?? '').toString() == value,
                                  orElse: () => null,
                                );
                        if (zone == null) {
                          return;
                        }
                        setSheetState(() => applyZone(zone));
                      },
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(labelText: 'Статус'),
                      items: [
                        DropdownMenuItem(
                          value: 'ACTIVE',
                          child: Text('Активен'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'IN_PROGRESS',
                          child: Text('Подключается'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'INACTIVE',
                          child: Text('Неактивен'.tr()),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => status = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: thresholdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Порог квартир',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: currentUsersController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Текущие заявки/квартиры',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Точка дома на карте'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    OsmPointPicker(
                      point: housePoint,
                      polygons: zonePolygons,
                      selectedPolygonId:
                          selectedZoneId.isEmpty ? null : selectedZoneId,
                      centerLat: housePoint?['lat'] ??
                          ((zones.isNotEmpty ? zones.first['centerLat'] : null)
                                  as num?)
                              ?.toDouble() ??
                          43.2389,
                      centerLng: housePoint?['lng'] ??
                          ((zones.isNotEmpty ? zones.first['centerLng'] : null)
                                  as num?)
                              ?.toDouble() ??
                          76.8897,
                      onChanged: (point) {
                        final zone = _serviceZoneForPoint(
                          lat: point['lat'] ?? 0,
                          lng: point['lng'] ?? 0,
                          zones: zones,
                        );
                        setSheetState(() {
                          housePoint = point;
                          if (zone != null) {
                            applyZone(zone);
                          }
                        });
                        if (zone == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Точка дома не попадает ни в один район'.tr(),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      housePoint == null
                          ? 'Кликните по карте, чтобы поставить точку дома.'
                          : 'Точка выбрана. Район заполнится автоматически, если точка внутри полигона.',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final houseId = idController.text.trim();
                          final address = addressController.text.trim();
                          final point = housePoint;
                          if (point != null) {
                            final zone = _serviceZoneForPoint(
                              lat: point['lat'] ?? 0,
                              lng: point['lng'] ?? 0,
                              zones: zones,
                            );
                            if (zone != null) {
                              applyZone(zone);
                            }
                          }
                          final serviceArea = serviceAreaController.text.trim();
                          if (houseId.isEmpty ||
                              address.isEmpty ||
                              serviceArea.isEmpty ||
                              point == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Заполните ID, адрес и отметьте дом на карте'
                                      .tr(),
                                ),
                              ),
                            );
                            return;
                          }
                          await _data.upsertHouse(
                            houseId: houseId,
                            data: {
                              'title': titleController.text.trim().isEmpty
                                  ? address
                                  : titleController.text.trim(),
                              'address': address,
                              'residentialComplex':
                                  residentialController.text.trim(),
                              'serviceArea': serviceArea,
                              'serviceAreaId': zoneController.text.trim(),
                              'clusterName': clusterController.text.trim(),
                              'zoneId': zoneController.text.trim(),
                              'status': status,
                              'threshold': int.tryParse(
                                    thresholdController.text.trim(),
                                  ) ??
                                  1,
                              'current_users': int.tryParse(
                                    currentUsersController.text.trim(),
                                  ) ??
                                  1,
                              'lat': point['lat'] ?? 0,
                              'lng': point['lng'] ?? 0,
                            },
                          );
                          if (!context.mounted) {
                            return;
                          }
                          Navigator.pop(context);
                        },
                        child: Text('Сохранить'.tr()),
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

  Future<void> _openZoneEditor(
    BuildContext context,
    Map<String, dynamic>? zone,
  ) async {
    final titleController = TextEditingController(
      text: (zone?['title'] ?? '').toString(),
    );
    final cityController = TextEditingController(
      text: (zone?['city'] ?? '').toString(),
    );
    var polygon = _geoPolygonFrom(zone?['polygon']);
    final center = _geoPolygonCenter(polygon);
    final initialCenterLat = center?['lat'] ??
        (zone?['centerLat'] is num
            ? (zone?['centerLat'] as num).toDouble()
            : 43.2389);
    final initialCenterLng = center?['lng'] ??
        (zone?['centerLng'] is num
            ? (zone?['centerLng'] as num).toDouble()
            : 76.8897);
    var saving = false;

    String zoneIdFromTitle(String value) {
      final normalized = value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9а-яё]+', unicode: true), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      return normalized.isEmpty
          ? 'zone_${DateTime.now().millisecondsSinceEpoch}'
          : normalized;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> saveZone() async {
              if (saving) {
                return;
              }
              final zoneId = (zone?['id'] ?? '').toString().trim().isNotEmpty
                  ? (zone?['id'] ?? '').toString().trim()
                  : zoneIdFromTitle(titleController.text);
              final title = titleController.text.trim();
              if (title.isEmpty || polygon.length < 3) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Заполните название и поставьте минимум 3 точки района'
                          .tr(),
                    ),
                  ),
                );
                return;
              }
              setSheetState(() => saving = true);
              try {
                final nextCenter = _geoPolygonCenter(polygon);
                await _data.upsertServiceZone(
                  zoneId: zoneId,
                  data: {
                    'title': title,
                    'city': cityController.text.trim(),
                    'status': 'active',
                    if (nextCenter != null) 'centerLat': nextCenter['lat'],
                    if (nextCenter != null) 'centerLng': nextCenter['lng'],
                    'polygon': polygon,
                  },
                );
                final assignedCount = await _assignExistingHousesToZone({
                  'id': zoneId,
                  'title': title,
                  'polygon': polygon,
                });
                final importResult = await _data.importHousesForServiceZone(
                  zoneId: zoneId,
                );
                if (!context.mounted) {
                  return;
                }
                final importedCount =
                    (importResult['importedCount'] as num?)?.toInt() ?? 0;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Район сохранен. Импортировано адресов: $importedCount. Обновлено домов: $assignedCount'
                          .tr(),
                    ),
                  ),
                );
                Navigator.pop(context);
              } catch (error) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Не удалось сохранить район: $error'.tr()),
                  ),
                );
              } finally {
                if (context.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.92,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 24,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            zone == null
                                ? 'Новая зона покрытия'
                                : 'Редактирование зоны',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: titleController,
                            decoration: const InputDecoration(
                              labelText: 'Название',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: cityController,
                            decoration: const InputDecoration(
                              labelText: 'Город',
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Границы района'.tr(),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          OsmPolygonPicker(
                            points: polygon,
                            centerLat: initialCenterLat,
                            centerLng: initialCenterLng,
                            height: 460,
                            onChanged: (points) {
                              setSheetState(() {
                                polygon = points;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            polygon.length >= 3
                                ? 'Точек в полигоне: ${polygon.length}. Можно добавлять сколько нужно точек по границе района.'
                                : 'Поставьте минимум 3 точки по границе района.',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving ? null : saveZone,
                        child: Text(
                          saving ? 'Сохраняем...' : 'Сохранить зону покрытия',
                        ),
                      ),
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

  DateTime _slotDate(Map<String, dynamic> slot) {
    final value = slot['scheduledFor'];
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.tryParse('${slot['scheduledDateKey'] ?? ''}') ??
        DateTime.now();
  }

  String _slotDateText(Map<String, dynamic> slot) {
    final date = _slotDate(slot);
    return '${date.day}.${date.month}.${date.year} ${(slot['time'] ?? '10:00 - 13:00')}';
  }

  DateTime? _normalizeToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  bool _matchesDateRange(dynamic value) {
    final date = _normalizeToDate(value);
    if (date == null) {
      return _filterStartDate == null && _filterEndDate == null;
    }
    if (_filterStartDate != null && date.isBefore(_filterStartDate!)) {
      return false;
    }
    if (_filterEndDate != null && date.isAfter(_filterEndDate!)) {
      return false;
    }
    return true;
  }

  DateTime? _recordDate(Map<String, dynamic> data) {
    for (final key in const [
      'invoiceRequestedAt',
      'createdAt',
      'registeredAt',
      'submittedAt',
      'requestedAt',
      'paidAt',
      'reviewedAt',
      'resolvedAt',
      'updatedAt',
      'completedAt',
      'scheduledFor',
      'date',
      'scheduledDate',
    ]) {
      final date = _normalizeToDate(data[key]);
      if (date != null) {
        return date;
      }
    }
    return null;
  }

  bool _matchesRecordDateRange(Map<String, dynamic> data) {
    return _matchesDateRange(_recordDate(data));
  }

  List<Map<String, dynamic>> _sortRecordsByDate(
    Iterable<Map<String, dynamic>> items,
  ) {
    final result = items.toList();
    result.sort((a, b) {
      final left = _recordDate(a);
      final right = _recordDate(b);
      final leftMs = left?.millisecondsSinceEpoch ?? 0;
      final rightMs = right?.millisecondsSinceEpoch ?? 0;
      return _dateSortOrder == 'Сначала старые'
          ? leftMs.compareTo(rightMs)
          : rightMs.compareTo(leftMs);
    });
    return result;
  }

  List<Map<String, dynamic>> _sortCustomersByRegistrationDate(
    Iterable<Map<String, dynamic>> items,
  ) {
    final result = items.toList();
    result.sort((a, b) {
      final left = _normalizeToDate(a['createdAt'] ?? a['registeredAt']);
      final right = _normalizeToDate(b['createdAt'] ?? b['registeredAt']);
      final leftMs = left?.millisecondsSinceEpoch ?? 0;
      final rightMs = right?.millisecondsSinceEpoch ?? 0;
      return _dateSortOrder == 'Сначала старые'
          ? leftMs.compareTo(rightMs)
          : rightMs.compareTo(leftMs);
    });
    return result;
  }

  String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  DateTime? _millisToDate(int? millis) {
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _candidateQueueDetailsText(dynamic value) {
    final items = (value as List?)?.whereType<Map>().toList() ?? const [];
    if (items.isEmpty) {
      return '—';
    }
    return items.map((item) {
      final cleanerId = (item['cleanerId'] ?? item['id'] ?? '—').toString();
      final score = item['score'];
      final travel = item['travelMinutes'];
      final fill = item['projectedAreaAfterAssignment'];
      final scoreText = score is num ? score.toStringAsFixed(1) : '—';
      final travelText = travel is num ? '${travel.round()}м' : '—';
      final fillText = fill is num ? '${fill.round()} м²' : '—';
      return '$cleanerId (score $scoreText, дорога $travelText, день $fillText)';
    }).join(' | ');
  }

  Widget _verifications() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.allCleanerVerificationsStream(),
      builder: (context, snapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.cleanersDirectoryStream(),
          builder: (context, cleanersSnapshot) {
            final cleanersById = <String, Map<String, dynamic>>{
              for (final cleaner
                  in (cleanersSnapshot.data ?? const <Map<String, dynamic>>[]))
                (cleaner['id'] ?? '').toString(): cleaner,
            };
            final query = _searchQuery.trim().toLowerCase();
            final filteredVerifications = (snapshot.data ?? []).where((item) {
              final status =
                  (item['status'] ?? 'pending').toString().toLowerCase();
              final cleanerId =
                  item['cleanerId']?.toString() ?? item['id'].toString();
              final cleaner =
                  cleanersById[cleanerId] ?? const <String, dynamic>{};
              if (_statusFilter != 'Все' &&
                  status != _statusFilter.toLowerCase()) {
                return false;
              }
              if (!_matchesRecordDateRange(item)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return '$cleanerId $status ${cleaner['name'] ?? ''} ${cleaner['phone'] ?? ''} ${cleaner['clusterName'] ?? ''}'
                  .toLowerCase()
                  .contains(query);
            });
            final items = _sortRecordsByDate(filteredVerifications);
            final selectedVisibleVerificationIds = items
                .map(
                  (item) =>
                      item['cleanerId']?.toString() ?? item['id'].toString(),
                )
                .where(_selectedVerificationIds.contains)
                .toSet();
            return _sectionScaffold(
              toolbar: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedVisibleVerificationIds.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Выбрано заявок: ${selectedVisibleVerificationIds.length}'
                                  .tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              _bulkActionButton(
                                'Одобрить',
                                () => _bulkReviewVerifications(
                                  selectedVisibleVerificationIds,
                                  'approved',
                                ),
                              ),
                              _bulkActionButton(
                                'Отклонить',
                                () => _bulkReviewVerifications(
                                  selectedVisibleVerificationIds,
                                  'rejected',
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _selectedVerificationIds.removeAll(
                                    selectedVisibleVerificationIds,
                                  );
                                }),
                                child: Text('Снять выбор'.tr()),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      _filterChip(
                        label: 'Все',
                        selected: _statusFilter == 'Все',
                        onTap: () => setState(() => _statusFilter = 'Все'),
                      ),
                      for (final status in ['pending', 'approved', 'rejected'])
                        _filterChip(
                          label: _cleanerVerificationLabel(status),
                          selected: _statusFilter == status,
                          onTap: () => setState(() => _statusFilter = status),
                        ),
                    ],
                  ),
                ],
              ),
              child: items.isEmpty
                  ? _emptyState(
                      'Нет заявок на проверку',
                      'Очередь верификации сейчас пуста.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final cleanerId = item['cleanerId']?.toString() ??
                            item['id'].toString();
                        final cleaner = cleanersById[cleanerId] ??
                            const <String, dynamic>{};
                        final cleanerName =
                            (cleaner['name'] ?? item['name'] ?? cleanerId)
                                .toString();
                        final cleanerPhone =
                            (cleaner['phone'] ?? item['phone'] ?? '—')
                                .toString();
                        final cleanerCluster = (cleaner['clusterName'] ??
                                item['clusterName'] ??
                                '—')
                            .toString();
                        final cleanerStatus =
                            (cleaner['cleanerStatusLabel'] ?? '—').toString();
                        final status = (item['status'] ?? 'pending')
                            .toString()
                            .toLowerCase();
                        final documentUrls = <MapEntry<String, String>>[
                          MapEntry(
                            'Селфи',
                            (item['selfieUrl'] ?? '').toString().trim(),
                          ),
                          MapEntry(
                            'Селфи с удостоверением',
                            (item['selfieWithIdUrl'] ?? '').toString().trim(),
                          ),
                          MapEntry(
                            'ID',
                            (item['idDocumentUrl'] ?? '').toString().trim(),
                          ),
                          MapEntry(
                            'Несудимость',
                            (item['policeClearanceUrl'] ?? '')
                                .toString()
                                .trim(),
                          ),
                          MapEntry(
                            'Психдиспансер',
                            (item['psychDispenserUrl'] ?? '').toString().trim(),
                          ),
                          MapEntry(
                            'Фтизиатрия',
                            (item['phthisiatricianUrl'] ?? '')
                                .toString()
                                .trim(),
                          ),
                          MapEntry(
                            'Прописка',
                            (item['residenceProofUrl'] ?? '').toString().trim(),
                          ),
                        ].where((entry) => entry.value.isNotEmpty).toList();
                        return _entityCard(
                          title: cleanerName,
                          subtitle:
                              'Телефон: $cleanerPhone · Кластер: $cleanerCluster · Статус: $cleanerStatus',
                          badges: [
                            _statusBadge(
                              _cleanerVerificationLabel(status),
                              color: status == 'approved'
                                  ? const Color(0xFF047857)
                                  : status == 'rejected'
                                      ? const Color(0xFFDC2626)
                                      : Color(0xFFD97706),
                            ),
                          ],
                          actions: [
                            Checkbox(
                              value: _selectedVerificationIds.contains(
                                cleanerId,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedVerificationIds.add(cleanerId);
                                  } else {
                                    _selectedVerificationIds.remove(cleanerId);
                                  }
                                });
                              },
                            ),
                            TextButton(
                              onPressed: () => _openVerificationDetails(
                                context,
                                cleanerId: cleanerId,
                                cleaner: cleaner,
                                verification: item,
                                documentUrls: documentUrls,
                              ),
                              child: Text('Открыть'.tr()),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  await _data.reviewCleanerVerification(
                                    cleanerId: cleanerId,
                                    status: value,
                                    rejectionReason: value == 'rejected'
                                        ? 'Документы требуют корректировки'
                                        : null,
                                  );
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Верификация обновлена: ${_cleanerVerificationLabel(value)}'
                                            .tr(),
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Не удалось обновить статус: $e'.tr(),
                                      ),
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'approved',
                                  child: Text('Одобрить'.tr()),
                                ),
                                PopupMenuItem(
                                  value: 'rejected',
                                  child: Text('Отклонить'.tr()),
                                ),
                              ],
                            ),
                          ],
                          body: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _adminInfoChip('Cleaner ID', cleanerId),
                                  _adminInfoChip('Телефон', cleanerPhone),
                                  _adminInfoChip('Кластер', cleanerCluster),
                                ],
                              ),
                              if (documentUrls.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'Документы'.tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _verificationPreviewGrid(
                                  context,
                                  cleanerName: cleanerName,
                                  cleanerId: cleanerId,
                                  items: documentUrls,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _houses() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.housesStream(admin: true),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final filteredHouses = (snapshot.data ?? []).where((house) {
          if (!_matchesRecordDateRange(house)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${house['address'] ?? house['id']} ${house['status'] ?? ''}'
              .toLowerCase()
              .contains(query);
        });
        final items = _sortRecordsByDate(filteredHouses);
        return _sectionScaffold(
          toolbar: Text(
            'Дома и адреса импортируются автоматически после сохранения района на карте.'
                .tr(),
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final house = items[index];
              final current = (house['current_users'] as num?)?.toInt() ?? 0;
              final threshold = (house['threshold'] as num?)?.toInt() ?? 20;
              final houseStatus =
                  (house['status'] ?? 'INACTIVE').toString().toUpperCase();
              return _entityCard(
                title: (house['address'] ?? house['id']).toString(),
                subtitle:
                    'Прогресс подключения: $current из $threshold квартир',
                badges: [
                  _statusBadge(
                    _houseStatusLabel(houseStatus),
                    color: houseStatus == 'ACTIVE'
                        ? const Color(0xFF047857)
                        : const Color(0xFFD97706),
                  ),
                ],
                actions: [
                  TextButton(
                    onPressed: () => _openEntityDetails(
                      context,
                      title: (house['address'] ?? house['id']).toString(),
                      sections: [
                        _detailSection('Подключение', {
                          'Статус': _houseStatusLabel(houseStatus),
                          'Порог': '$threshold квартир',
                          'Текущие заявки': '$current',
                          'Осталось': '${math.max(threshold - current, 0)}',
                        }),
                        _detailSection('Операционные связи', {
                          'Кластер': (house['clusterName'] ?? '—').toString(),
                          'Зона': (house['zoneId'] ?? '—').toString(),
                          'Рабочий район':
                              (house['serviceArea'] ?? '—').toString(),
                        }),
                      ],
                    ),
                    child: Text('Детали'.tr()),
                  ),
                  TextButton.icon(
                    onPressed: () => _openHouseEditor(context, house),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text('Редактировать'.tr()),
                  ),
                  TextButton.icon(
                    onPressed: !_canActivateHouses
                        ? null
                        : () => _data.activateHouseIfThresholdReached(
                              houseId: house['id'].toString(),
                            ),
                    icon: const Icon(Icons.bolt_outlined),
                    label: Text('Проверить активацию'.tr()),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _waitlist() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminWaitlistStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final waitlist = snapshot.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.housesStream(admin: true),
          builder: (context, housesSnapshot) {
            final housesById = {
              for (final house
                  in housesSnapshot.data ?? const <Map<String, dynamic>>[])
                (house['id'] ?? '').toString(): house,
            };
            return FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: _data.adminCustomersByIds(
                waitlist.map((item) => (item['userId'] ?? '').toString()),
              ),
              builder: (context, customersSnapshot) {
                final customers = customersSnapshot.data ??
                    const <String, Map<String, dynamic>>{};
                final filteredWaitlist = waitlist.where((item) {
                  final houseId = (item['houseId'] ?? '').toString();
                  final house =
                      housesById[houseId] ?? const <String, dynamic>{};
                  final customer =
                      customers[(item['userId'] ?? '').toString()] ??
                          const <String, dynamic>{};
                  if (!_matchesRecordDateRange(item)) {
                    return false;
                  }
                  final haystack = [
                    item['id'],
                    item['houseId'],
                    item['userId'],
                    item['source'],
                    item['status'],
                    item['address'],
                    item['residentialComplex'],
                    item['city'],
                    house['address'],
                    house['residentialComplex'],
                    house['city'],
                    customer['name'],
                    customer['phone'],
                  ].join(' ').toLowerCase();
                  return query.isEmpty || haystack.contains(query);
                });
                final docs = _sortRecordsByDate(filteredWaitlist);
                return _sectionScaffold(
                  toolbar: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: !_canManagePolicies
                            ? null
                            : () => _openHouseEditor(context, null),
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: Text('Добавить адрес'.tr()),
                      ),
                      Text(
                        'Заявок: ${docs.length}'.tr(),
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  child: docs.isEmpty
                      ? _emptyState(
                          'Лист ожидания пуст',
                          'Новых заявок пока нет.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = docs[index];
                            final houseId = (item['houseId'] ?? '').toString();
                            final house = housesById[houseId] ??
                                const <String, dynamic>{};
                            final customerId =
                                (item['userId'] ?? '').toString();
                            final customer = customers[customerId] ??
                                const <String, dynamic>{};
                            return _waitlistCard(
                              context: context,
                              item: item,
                              house: house,
                              customer: customer,
                            );
                          },
                        ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _prelaunchBookings() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminPrelaunchBookingsStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final activeCount = rows
            .where((item) => _isActivePrelaunchStatus(_prelaunchStatus(item)))
            .length;
        final canceledCount = rows
            .where((item) => _isCanceledPrelaunchStatus(_prelaunchStatus(item)))
            .length;
        final workedCount = rows
            .where((item) => _isWorkedPrelaunchStatus(_prelaunchStatus(item)))
            .length;
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _data.adminCustomersByIds(
            rows.map((item) => (item['customerId'] ?? '').toString()),
          ),
          builder: (context, customersSnapshot) {
            final customers = customersSnapshot.data ??
                const <String, Map<String, dynamic>>{};
            final filteredPrelaunch = rows.where((item) {
              final customer =
                  customers[(item['customerId'] ?? '').toString()] ??
                      const <String, dynamic>{};
              final form = item['form'] is Map
                  ? Map<String, dynamic>.from(item['form'] as Map)
                  : const <String, dynamic>{};
              if (!_matchesRecordDateRange(item)) {
                return false;
              }
              final haystack = [
                item['id'],
                item['customerId'],
                item['customerName'],
                item['customerPhone'],
                item['desiredDate'],
                item['preferredTime'],
                item['area'],
                form['name'],
                form['phone'],
                customer['name'],
                customer['phone'],
              ].join(' ').toLowerCase();
              return query.isEmpty || haystack.contains(query);
            });
            final docs = _sortRecordsByDate(filteredPrelaunch);
            return _sectionScaffold(
              toolbar: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Активные: $activeCount · Отменены: $canceledCount · Отработаны: $workedCount'
                        .tr(),
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  FilledButton.icon(
                    onPressed: docs.isEmpty
                        ? null
                        : () => _openPrelaunchStartDialog(context),
                    icon: const Icon(Icons.rocket_launch_outlined),
                    label: Text('Назначить старт'.tr()),
                  ),
                ],
              ),
              child: docs.isEmpty
                  ? _emptyState(
                      'Предварительных записей нет',
                      'Когда клиент оставит заявку до запуска, она появится здесь.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = docs[index];
                        final customer =
                            customers[(item['customerId'] ?? '').toString()] ??
                                const <String, dynamic>{};
                        final form = item['form'] is Map
                            ? Map<String, dynamic>.from(item['form'] as Map)
                            : const <String, dynamic>{};
                        final name = _firstText([
                          item['customerName'],
                          form['name'],
                          customer['name'],
                          customer['fullName'],
                        ]);
                        final phone = _firstText([
                          item['customerPhone'],
                          form['phone'],
                          customer['phone'],
                          customer['phoneNumber'],
                        ]);
                        final area = _firstText([
                          item['area'],
                          form['area'],
                          customer['area'],
                        ]);
                        final desiredDate = _firstText([
                          item['desiredDate'],
                          form['desiredDate'],
                        ]);
                        final preferredTime = _firstText([
                          item['preferredTime'],
                          form['preferredTime'],
                        ]);
                        final status = _prelaunchStatus(item);
                        final isWorked = _isWorkedPrelaunchStatus(status);
                        final isCanceled = _isCanceledPrelaunchStatus(status);
                        return _entityCard(
                          title: 'Предзапись №${index + 1}',
                          subtitle: [
                            if (name != '—') name,
                            if (phone != '—') phone,
                            if (desiredDate != '—') desiredDate,
                            if (preferredTime != '—') preferredTime,
                          ].join(' · '),
                          badges: [
                            _statusBadge(
                              _prelaunchStatusLabel(status),
                              color: _prelaunchStatusColor(status),
                            ),
                            if (!isCanceled && !isWorked)
                              _statusBadge(
                                'Оплата после запуска',
                                color: const Color(0xFFD97706),
                              ),
                          ],
                          body: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _miniInfo('Клиент', name),
                              _miniInfo('Телефон', phone),
                              _miniInfo(
                                'Площадь',
                                area == '—' ? '—' : '$area м²',
                              ),
                              _miniInfo('Дата', desiredDate),
                              _miniInfo('Время', preferredTime),
                              _miniInfo(
                                'Создана',
                                _formatAdminDateTime(item['createdAt']),
                              ),
                              _miniInfo(
                                'Статус',
                                _prelaunchStatusLabel(status),
                              ),
                              if (isWorked)
                                _miniInfo(
                                  'Отработано',
                                  _formatAdminDateTime(item['workedAt']),
                                ),
                              _miniInfo(
                                'ID клиента',
                                _firstText([item['customerId']]),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => _openEntityDetails(
                                context,
                                title: 'Предзапись №${index + 1}',
                                sections: [
                                  _detailSection('Заявка', {
                                    'ID заявки': (item['id'] ?? '—').toString(),
                                    'Статус': _prelaunchStatusLabel(status),
                                    'Создана': _formatAdminDateTime(
                                      item['createdAt'],
                                    ),
                                    'Отработано': _formatAdminDateTime(
                                      item['workedAt'],
                                    ),
                                    'Запуск': _formatAdminDateTime(
                                      item['launchDate'],
                                    ),
                                  }),
                                  _detailSection('Клиент', {
                                    'ID клиента': _firstText([
                                      item['customerId'],
                                    ]),
                                    'Имя': name,
                                    'Телефон': phone,
                                  }),
                                  _detailSection('Параметры уборки', {
                                    'Площадь': area == '—' ? '—' : '$area м²',
                                    'Желаемая дата': desiredDate,
                                    'Удобное время': preferredTime,
                                  }),
                                ],
                              ),
                              child: Text('Детали'.tr()),
                            ),
                            if (!isCanceled && !isWorked)
                              FilledButton.tonalIcon(
                                onPressed: () => _markPrelaunchWorked(item),
                                icon: const Icon(Icons.task_alt_outlined),
                                label: Text('Отработано'.tr()),
                              ),
                          ],
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  bool _isCanceledPrelaunchStatus(Object? status) {
    final value = (status ?? '').toString().toLowerCase();
    return value == 'canceled' || value == 'cancelled';
  }

  String _prelaunchStatus(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString().trim().toLowerCase();
    final orderStatus =
        (item['orderStatus'] ?? '').toString().trim().toLowerCase();
    if (_isCanceledPrelaunchStatus(status) ||
        _isCanceledPrelaunchStatus(orderStatus)) {
      return 'canceled';
    }
    if (_isWorkedPrelaunchStatus(status) ||
        _isWorkedPrelaunchStatus(orderStatus)) {
      return 'prelaunch_worked';
    }
    return status.isNotEmpty ? status : orderStatus;
  }

  bool _isWorkedPrelaunchStatus(Object? status) {
    return (status ?? '').toString().toLowerCase() == 'prelaunch_worked';
  }

  bool _isActivePrelaunchStatus(Object? status) {
    return !_isCanceledPrelaunchStatus(status) &&
        !_isWorkedPrelaunchStatus(status);
  }

  String _prelaunchStatusLabel(String status) {
    if (_isCanceledPrelaunchStatus(status)) {
      return 'Отменена';
    }
    if (_isWorkedPrelaunchStatus(status)) {
      return 'Отработана';
    }
    if (status == 'prelaunch_started') {
      return 'Старт назначен';
    }
    return 'Активная';
  }

  Color _prelaunchStatusColor(String status) {
    if (_isCanceledPrelaunchStatus(status)) {
      return const Color(0xFFDC2626);
    }
    if (_isWorkedPrelaunchStatus(status)) {
      return const Color(0xFF16A34A);
    }
    if (status == 'prelaunch_started') {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFFD97706);
  }

  Future<void> _markPrelaunchWorked(Map<String, dynamic> item) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = (item['id'] ?? '').toString();
    try {
      await _data.markPrelaunchBookingWorked(id);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Предварительная запись отработана.'.tr())),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось отметить как отработано: $error'.tr()),
        ),
      );
    }
  }

  Future<void> _openPrelaunchStartDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var selectedDate = DateTime.now();
    final timeController = TextEditingController(text: '10:00');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Назначить старт'.tr()),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выберите дату и время запуска. Всем клиентам из предварительной записи придет уведомление об оплате.'
                      .tr(),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(DateTime.now().year + 2),
                      locale: const Locale('ru'),
                    );
                    if (picked != null) {
                      setModalState(() => selectedDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_dateLabel(selectedDate)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeController,
                  decoration: InputDecoration(
                    labelText: 'Время старта',
                    hintText: 'Например: 10:00',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Начать старт'.tr()),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final count = await _data.startPrelaunchBookings(
        startDate: selectedDate,
        startTime: timeController.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Старт назначен. Уведомлений: $count'.tr())),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось назначить старт: $e'.tr())),
      );
    }
  }

  Widget _waitlistCard({
    required BuildContext context,
    required Map<String, dynamic> item,
    required Map<String, dynamic> house,
    required Map<String, dynamic> customer,
  }) {
    final houseId = (item['houseId'] ?? '').toString();
    final customerId = (item['userId'] ?? '').toString();
    final address = _firstText([
      item['address'],
      item['residentialComplex'],
      house['address'],
      house['residentialComplex'],
      houseId,
    ]);
    final city = _firstText([item['city'], house['city']]);
    final customerName = _firstText([customer['name'], customer['fullName']]);
    final customerPhone = _firstText([
      customer['phone'],
      customer['phoneNumber'],
    ]);
    final status = (item['status'] ?? 'waiting').toString();
    final source = (item['source'] ?? 'app').toString();
    final lat = _numText(item['lat'] ?? house['lat']);
    final lng = _numText(item['lng'] ?? house['lng']);
    final currentUsers = (house['current_users'] as num?)?.toInt() ??
        (house['waitlistCount'] as num?)?.toInt() ??
        1;
    final threshold = (house['threshold'] as num?)?.toInt() ?? 20;
    final prefilledHouse = {
      ...house,
      'id': houseId,
      'title': address,
      'address': address,
      'residentialComplex': _firstText([
        item['residentialComplex'],
        house['residentialComplex'],
        address,
      ]),
      'city': city,
      'status': 'ACTIVE',
      'threshold': threshold,
      'current_users': currentUsers,
      if (item['lat'] != null) 'lat': item['lat'],
      if (item['lng'] != null) 'lng': item['lng'],
    };

    return _entityCard(
      title: address,
      subtitle: [
        if (city != '—') city,
        'Отправил: ${customerName == '—' ? customerId : customerName}',
        if (customerPhone != '—') customerPhone,
      ].join(' · '),
      badges: [
        _statusBadge(
          _waitlistStatusLabel(status),
          color: const Color(0xFFD97706),
        ),
        _statusBadge(
          _waitlistSourceLabel(source),
          color: const Color(0xFF1D4ED8),
        ),
      ],
      body: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _miniInfo('ID заявки', (item['id'] ?? '—').toString()),
          _miniInfo('ID дома', houseId.isEmpty ? '—' : houseId),
          _miniInfo('Создана', _formatAdminDateTime(item['createdAt'])),
          _miniInfo('Площадь', '${item['area'] ?? customer['area'] ?? '—'} м²'),
          _miniInfo(
            'Подъезд',
            _firstText([item['entrance'], customer['entrance']]),
          ),
          _miniInfo(
            'Квартира',
            _firstText([item['apartment'], customer['apartment']]),
          ),
          _miniInfo(
            'Координаты',
            lat == '—' || lng == '—' ? '—' : '$lat, $lng',
          ),
          _miniInfo('Прогресс', '$currentUsers из $threshold'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _openEntityDetails(
            context,
            title: address,
            sections: [
              _detailSection('Заявка', {
                'ID заявки': (item['id'] ?? '—').toString(),
                'Статус': _waitlistStatusLabel(status),
                'Источник': _waitlistSourceLabel(source),
                'Создана': _formatAdminDateTime(item['createdAt']),
                'Обновлена': _formatAdminDateTime(item['updatedAt']),
              }),
              _detailSection('Адрес', {
                'Город': city,
                'Адрес': address,
                'ЖК': _firstText([
                  item['residentialComplex'],
                  house['residentialComplex'],
                ]),
                'ID дома': houseId,
                'Координаты': lat == '—' || lng == '—' ? '—' : '$lat, $lng',
              }),
              _detailSection('Клиент', {
                'ID клиента': customerId,
                'Имя': customerName,
                'Телефон': customerPhone,
                'Подъезд': _firstText([item['entrance'], customer['entrance']]),
                'Квартира': _firstText([
                  item['apartment'],
                  customer['apartment'],
                ]),
                'Площадь': '${item['area'] ?? customer['area'] ?? '—'} м²',
              }),
            ],
          ),
          child: Text('Детали'.tr()),
        ),
        TextButton.icon(
          onPressed: !_canManagePolicies
              ? null
              : () => _openHouseEditor(context, prefilledHouse),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text('Добавить адрес'.tr()),
        ),
        TextButton.icon(
          onPressed: !_canActivateHouses || houseId.isEmpty
              ? null
              : () => _data.activateHouseIfThresholdReached(houseId: houseId),
          icon: const Icon(Icons.bolt_outlined),
          label: Text('Проверить активацию'.tr()),
        ),
      ],
    );
  }

  Future<void> _openCitiesDirectory() async {
    try {
      final cities = await _data.adminCities();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text('Города Казахстана: ${cities.length}'),
        content: SizedBox(width: 480, height: 500, child: ListView.builder(
          itemCount: cities.length,
          itemBuilder: (_, index) => ListTile(
            title: Text((cities[index]['name_ru'] ?? '').toString()),
            subtitle: Text('${cities[index]['name_kk'] ?? ''} · ${cities[index]['region'] ?? ''}'),
          ),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось загрузить города. Попробуйте ещё раз.')));
    }
  }

  Widget _zones() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.serviceZonesStream(),
      builder: (context, snapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.housesStream(admin: true),
          builder: (context, housesSnapshot) {
            final houses =
                housesSnapshot.data ?? const <Map<String, dynamic>>[];
            final housesByZone = <String, int>{};
            for (final house in houses) {
              final keys = <String>{
                (house['zoneId'] ?? '').toString(),
                (house['serviceAreaId'] ?? '').toString(),
              }..removeWhere((item) => item.trim().isEmpty);
              for (final key in keys) {
                housesByZone[key] = (housesByZone[key] ?? 0) + 1;
              }
            }
            final query = _searchQuery.trim().toLowerCase();
            final filteredZones = (snapshot.data ?? []).where((zone) {
              if (!_matchesRecordDateRange(zone)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return '${zone['title'] ?? zone['id']} ${zone['city'] ?? ''} ${zone['status'] ?? ''}'
                  .toLowerCase()
                  .contains(query);
            });
            final items = _sortRecordsByDate(filteredZones);
            return _sectionScaffold(
              toolbar: Wrap(spacing: 12, children: [
                OutlinedButton.icon(
                  onPressed: () => _openZoneEditor(context, null),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text('Добавить зону'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: _openCitiesDirectory,
                  icon: const Icon(Icons.location_city_outlined),
                  label: const Text('Города Казахстана'),
                ),
              ]),
              child: items.isEmpty
                  ? _emptyState('Зоны не найдены', 'Измените строку поиска.')
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final zone = items[index];
                        final zoneId = (zone['id'] ?? '').toString();
                        final polygon = _geoPolygonFrom(zone['polygon']);
                        final actualHouseCount = housesByZone[zoneId] ?? 0;
                        final importedHouseCount =
                            (zone['importedHousesCount'] as num?)?.toInt();
                        final houseCount = actualHouseCount > 0
                            ? actualHouseCount
                            : (importedHouseCount ?? 0);
                        return _entityCard(
                          title: (zone['title'] ?? zone['id']).toString(),
                          subtitle:
                              'Город: ${(zone['city'] ?? '—')} · Статус: ${(zone['status'] ?? 'planned')} · Домов: $houseCount · Точек: ${polygon.length}',
                          actions: [
                            TextButton.icon(
                              onPressed: () => _openZoneEditor(context, zone),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text('Редактировать'.tr()),
                            ),
                            TextButton.icon(
                              onPressed: () => _deleteServiceZone(zone),
                              icon: const Icon(Icons.delete_outline),
                              label: Text('Удалить'.tr()),
                            ),
                          ],
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _referrals() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminReferralStatsStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final filteredReferrals =
            (snapshot.data ?? const <Map<String, dynamic>>[]).where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['id']} ${data['invited'] ?? 0} ${data['registered'] ?? 0} ${data['paid'] ?? 0}'
              .toLowerCase()
              .contains(query);
        });
        final docs = _sortRecordsByDate(filteredReferrals);
        return _sectionScaffold(
          toolbar: Row(
            children: [
              OutlinedButton.icon(
                onPressed: docs.isEmpty ? null : () => _copyReferralsCsv(docs),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text('Копировать CSV'.tr()),
              ),
            ],
          ),
          child: docs.isEmpty
              ? _emptyState(
                  'Реферальные данные не найдены',
                  'Активность появится после приглашений и оплат.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    return _entityCard(
                      title: 'Пользователь ${data['id']}',
                      subtitle:
                          'Приглашено: ${(data['invited'] ?? 0)} · Зарегистрировано: ${(data['registered'] ?? 0)} · Оплатили: ${(data['paid'] ?? 0)} · Бонус: ${(data['bonus'] ?? 0)} ₸',
                      badges: [
                        _statusBadge(
                          'Paid ${(data['paid'] ?? 0)}',
                          color: const Color(0xFF047857),
                        ),
                      ],
                      actions: [
                        TextButton(
                          onPressed: () => _openEntityDetails(
                            context,
                            title: 'Реферальная статистика ${data['id']}',
                            sections: [
                              _detailSection('Итоги', {
                                'Приглашено': '${data['invited'] ?? 0}',
                                'Зарегистрировано':
                                    '${data['registered'] ?? 0}',
                                'Оплатили': '${data['paid'] ?? 0}',
                                'Бонус': '${data['bonus'] ?? 0} ₸',
                              }),
                            ],
                          ),
                          child: Text('Открыть'.tr()),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _areaMismatchReports() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.areaMismatchReportsStream(),
      builder: (context, snapshot) {
        final query = _searchQuery.trim().toLowerCase();
        final filteredAreaReports =
            (snapshot.data ?? const <Map<String, dynamic>>[]).where((data) {
          if ((data['type'] ?? '').toString() == 'quality_area_check') {
            return false;
          }
          if (_statusFilter != 'Все' &&
              (data['status'] ?? 'open').toString() != _statusFilter) {
            return false;
          }
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['id']} ${data['userId']} ${data['customerName']} ${data['customerPhone']} ${data['houseId']} ${data['address']} ${data['difference']}'
              .toLowerCase()
              .contains(query);
        });
        final docs = _sortRecordsByDate(filteredAreaReports);
        final selectedVisibleAreaReportIds = docs
            .map((doc) => (doc['id'] ?? '').toString())
            .where(_selectedAreaReportIds.contains)
            .toSet();
        return _sectionScaffold(
          toolbar: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedVisibleAreaReportIds.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Выбрано кейсов: ${selectedVisibleAreaReportIds.length}'
                              .tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          _bulkActionButton(
                            'Закрыть выбранные',
                            () => _bulkResolveAreaReports(
                              selectedVisibleAreaReportIds,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedAreaReportIds.removeAll(
                                selectedVisibleAreaReportIds,
                              );
                            }),
                            child: Text('Снять выбор'.tr()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  _filterChip(
                    label: 'Все',
                    selected: _statusFilter == 'Все',
                    onTap: () => setState(() => _statusFilter = 'Все'),
                  ),
                  for (final status in ['open', 'resolved'])
                    _filterChip(
                      label: status == 'resolved' ? 'Закрыто' : 'Открыто',
                      selected: _statusFilter == status,
                      onTap: () => setState(() => _statusFilter = status),
                    ),
                ],
              ),
            ],
          ),
          child: docs.isEmpty
              ? _emptyState(
                  'Кейсы по площади не найдены',
                  'Нет открытых или подходящих под фильтр расхождений.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    return _areaMismatchReportCard(context, data);
                  },
                ),
        );
      },
    );
  }

  Widget _areaMismatchReportCard(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final customerId =
        (data['userId'] ?? data['customerId'] ?? '').toString().trim();
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _data.adminCustomersByIds([customerId]),
      builder: (context, snapshot) {
        final customer =
            snapshot.data?[customerId] ?? const <String, dynamic>{};
        final reportId = (data['id'] ?? '').toString();
        final difference = (data['difference'] ?? 0).toString();
        final status = (data['status'] ?? 'open').toString().toLowerCase();
        final type = (data['type'] ?? '').toString();
        final isQualityCheck = type == 'quality_area_check';
        final customerName = _personName(customer, data, prefix: 'customer');
        final customerPhone = _personPhone(customer, data, prefix: 'customer');
        final address = _firstText([
          _customerPrimaryAddress(customer),
          data['address'],
          data['fullAddress'],
        ]);
        final house = _firstText([
          customer['residentialComplex'],
          customer['houseTitle'],
          customer['houseName'],
          data['residentialComplex'],
          data['houseTitle'],
          data['houseName'],
          data['houseId'],
        ]);
        final entrance = _firstText([customer['entrance'], data['entrance']]);
        final apartment = _firstText([
          customer['apartment'],
          data['apartment'],
        ]);
        final requestedDate =
            (data['preferredDate'] ?? data['date'] ?? '—').toString();
        final requestedTime =
            (data['preferredTime'] ?? data['time'] ?? '—').toString();
        final photoUrls = _areaReportPhotoUrls(data);
        return _entityCard(
          title: isQualityCheck
              ? 'Проверка квадратуры: $requestedDate $requestedTime'
              : 'Проверка площади: клиент указал ${(data['initialArea'] ?? 0)} м², проверено ${(data['actualArea'] ?? 0)} м²',
          subtitle: isQualityCheck
              ? '$customerName · $customerPhone · $address'
              : '$customerName · $customerPhone · $house · Отклонение: $difference м²',
          badges: [
            _statusBadge(
              status == 'resolved' ? 'Закрыто' : 'Открыто',
              color: status == 'resolved'
                  ? const Color(0xFF047857)
                  : const Color(0xFFD97706),
            ),
          ],
          actions: [
            Checkbox(
              value: _selectedAreaReportIds.contains(reportId),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedAreaReportIds.add(reportId);
                  } else {
                    _selectedAreaReportIds.remove(reportId);
                  }
                });
              },
            ),
            if (photoUrls.isNotEmpty)
              TextButton.icon(
                onPressed: () => _showAreaReportPhotos(context, photoUrls),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('Фото (${photoUrls.length})'.tr()),
              ),
            TextButton(
              onPressed: () => _openEntityDetails(
                context,
                title: 'Кейс по площади $reportId',
                sections: [
                  if (isQualityCheck)
                    _detailSection('Назначение контроля качества', {
                      'Дата': requestedDate,
                      'Время': requestedTime,
                      'Заказ': (data['orderId'] ?? '—').toString(),
                    }),
                  _detailSection('Сравнение', {
                    'Клиент указал': '${data['initialArea'] ?? 0} м²',
                    'Проверенная площадь': '${data['actualArea'] ?? 0} м²',
                    'Отклонение': '$difference м²',
                    'Статус': status == 'resolved' ? 'Закрыто' : 'Открыто',
                  }),
                  _detailSection('Клиент и дом', {
                    'ФИО клиента': customerName,
                    'Телефон': customerPhone,
                    'Город': _firstText([customer['city'], data['city']]),
                    'Адрес': address,
                    'Дом / ЖК': house,
                    'Подъезд': entrance,
                    'Квартира': apartment,
                    'UID': _firstText([customer['id'], data['userId']]),
                    'Фото': photoUrls.isEmpty
                        ? 'Не загружено'
                        : photoUrls.join('\n'),
                  }),
                ],
              ),
              child: Text('Открыть'.tr()),
            ),
            if (isQualityCheck && status != 'resolved')
              TextButton(
                onPressed: () => _confirmAreaQualityCheck(context, data),
                child: Text('Подтвердить площадь'.tr()),
              ),
            if (status != 'resolved')
              TextButton(
                onPressed: () async {
                  await _resolveAreaMismatchReportWithRecalculation(
                    context,
                    data,
                  );
                },
                child: Text('Закрыть кейс'.tr()),
              ),
          ],
          body: photoUrls.isEmpty
              ? null
              : _areaReportPhotoPreview(photoUrls.first),
        );
      },
    );
  }

  Widget _qualityControlDepartment() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.qualityControlAreaChecksStream(),
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.adminOrdersStream(),
          builder: (context, ordersSnapshot) {
            final ordersById = {
              for (final order
                  in ordersSnapshot.data ?? const <Map<String, dynamic>>[])
                (order['id'] ?? order['orderId'] ?? '').toString(): order,
            };
            final customerIds = reports
                .map(
                  (item) => (item['userId'] ?? item['customerId'] ?? '')
                      .toString()
                      .trim(),
                )
                .where((id) => id.isNotEmpty);
            return FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: _data.adminCustomersByIds(customerIds),
              builder: (context, customersSnapshot) {
                final customers = customersSnapshot.data ??
                    const <String, Map<String, dynamic>>{};
                final query = _searchQuery.trim().toLowerCase();
                final filteredQualityReports = reports.where((report) {
                  if (_statusFilter != 'Все' &&
                      (report['status'] ?? 'open').toString() !=
                          _statusFilter) {
                    return false;
                  }
                  if (!_matchesRecordDateRange(report)) {
                    return false;
                  }
                  final customerId =
                      (report['userId'] ?? report['customerId'] ?? '')
                          .toString();
                  final customer =
                      customers[customerId] ?? const <String, dynamic>{};
                  final orderId = (report['orderId'] ?? '').toString();
                  final order =
                      ordersById[orderId] ?? const <String, dynamic>{};
                  final haystack =
                      '$report $customer $order ${_customerPrimaryAddress(customer)}'
                          .toLowerCase();
                  return query.isEmpty || haystack.contains(query);
                });
                final visible = _sortRecordsByDate(filteredQualityReports);

                return _sectionScaffold(
                  toolbar: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _filterChip(
                        label: 'Все',
                        selected: _statusFilter == 'Все',
                        onTap: () => setState(() => _statusFilter = 'Все'),
                      ),
                      for (final status in ['open', 'resolved'])
                        _filterChip(
                          label:
                              status == 'resolved' ? 'Отработано' : 'Открыто',
                          selected: _statusFilter == status,
                          onTap: () => setState(() => _statusFilter = status),
                        ),
                    ],
                  ),
                  child: snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : visible.isEmpty
                          ? _emptyState(
                              'Заявок нет',
                              'Новые заявки контроля качества появятся здесь после заказа с неподтвержденной площадью.',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final report = visible[index];
                                final customerId = (report['userId'] ??
                                        report['customerId'] ??
                                        '')
                                    .toString();
                                final orderId =
                                    (report['orderId'] ?? '').toString();
                                return _qualityControlCard(
                                  context,
                                  report,
                                  customers[customerId] ??
                                      const <String, dynamic>{},
                                  ordersById[orderId] ??
                                      const <String, dynamic>{},
                                );
                              },
                            ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _qualityControlCard(
    BuildContext context,
    Map<String, dynamic> report,
    Map<String, dynamic> customer,
    Map<String, dynamic> order,
  ) {
    final reportId = (report['id'] ?? '').toString();
    final status = (report['status'] ?? 'open').toString().toLowerCase();
    final name = _firstText([
      customer['fullName'],
      customer['name'],
      customer['displayName'],
      report['customerName'],
    ]);
    final phone = _firstText([
      customer['phone'],
      customer['phoneNumber'],
      report['customerPhone'],
    ]);
    final address = _firstText([
      _customerPrimaryAddress(customer),
      report['address'],
      order['address'],
    ]);
    final orderId = _firstText([
      report['orderId'],
      order['orderId'],
      order['id'],
    ]);
    final date = _firstText([
      report['preferredDate'],
      customer['areaQualityCheckDate'],
    ]);
    final time = _firstText([
      report['preferredTime'],
      customer['areaQualityCheckTime'],
    ]);
    final area = _firstText([
      report['actualArea'],
      customer['area'],
      order['area'],
    ]);
    final packageName = _firstText([
      order['package'],
      order['packageName'],
      order['frequencyLabel'],
    ]);
    return _entityCard(
      title: 'Заявка ОКК: $name',
      subtitle: '$phone · $address',
      badges: [
        _statusBadge(
          status == 'resolved' ? 'Отработано' : 'Открыто',
          color: status == 'resolved'
              ? const Color(0xFF047857)
              : const Color(0xFFD97706),
        ),
        _statusBadge('Проверка: $date $time', color: const Color(0xFF2563EB)),
      ],
      body: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _miniInfo('Телефон', phone),
          _miniInfo('Адрес', address),
          _miniInfo('Площадь', area == '—' ? '—' : '$area м²'),
          _miniInfo('Заказ', orderId),
          _miniInfo('Тариф', packageName),
          _miniInfo(
            'Сумма заказа',
            '${_firstText([order['price'], order['amount']])} ₸',
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: phone == '—'
              ? null
              : () => Clipboard.setData(ClipboardData(text: phone)),
          icon: const Icon(Icons.copy_outlined),
          label: Text('Скопировать телефон'.tr()),
        ),
        TextButton(
          onPressed: () =>
              _openQualityControlDetails(context, report, customer, order),
          child: Text('Все данные'.tr()),
        ),
        if (status != 'resolved')
          TextButton(
            onPressed: () =>
                _confirmAreaQualityCheck(context, report, order: order),
            child: Text('Подтвердить / перерасчитать'.tr()),
          ),
        if (status != 'resolved')
          TextButton(
            onPressed: () => _data.updateAreaMismatchReport(reportId, {
              'reviewStatus': 'call_required',
              'lastAction': 'call_required',
            }),
            child: Text('Нужен звонок'.tr()),
          ),
      ],
    );
  }

  void _openQualityControlDetails(
    BuildContext context,
    Map<String, dynamic> report,
    Map<String, dynamic> customer,
    Map<String, dynamic> order,
  ) {
    final name = _firstText([
      customer['fullName'],
      customer['name'],
      customer['displayName'],
      report['customerName'],
    ]);
    final phone = _firstText([
      customer['phone'],
      customer['phoneNumber'],
      report['customerPhone'],
    ]);
    final address = _firstText([
      _customerPrimaryAddress(customer),
      report['address'],
      order['address'],
    ]);
    final orderId = _firstText([
      report['orderId'],
      order['orderId'],
      order['id'],
    ]);
    _openEntityDetails(
      context,
      title: 'Отдел контроля качества · $name',
      sections: [
        _detailSection('Клиент', {
          'ФИО': name,
          'Телефон': phone,
          'UID': _firstText([
            customer['id'],
            report['userId'],
            report['customerId'],
          ]),
          'Город': _firstText([customer['city'], order['customerCity']]),
          'Адрес': address,
          'Подъезд': _firstText([customer['entrance'], order['entrance']]),
          'Квартира': _firstText([customer['apartment'], order['apartment']]),
          'Текущая площадь': _firstText([
            customer['area'],
            customer['apartmentArea'],
          ]),
          'Статус площади': _firstText([customer['areaStatus']]),
        }),
        _detailSection('Заявка ОКК', {
          'Дата проверки': _firstText([report['preferredDate']]),
          'Время проверки': _firstText([report['preferredTime']]),
          'Заявленная площадь': _firstText([report['initialArea']]),
          'Площадь к проверке': _firstText([report['actualArea']]),
          'Статус': _firstText([report['reviewStatus'], report['status']]),
          'Создано': _formatAdminDateTime(report['createdAt']),
        }),
        _detailSection('Заказ / тариф', {
          'Заказ': orderId,
          'Пакет': _firstText([order['package'], order['packageName']]),
          'Частота': _firstText([order['frequencyLabel']]),
          'Уборок в месяц': _firstText([order['cleaningsPerMonth']]),
          'Период': _firstText([order['billingPeriodMonths']]),
          'Допы': _listText(order['addons']),
          'Сумма': '${_firstText([order['price'], order['amount']])} ₸',
          'Статус оплаты': _firstText([order['paymentStatus']]),
        }),
      ],
    );
  }

  List<String> _areaReportPhotoUrls(Map<String, dynamic> data) {
    final urls = <String>{};

    void add(Object? value) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty ||
          text == 'null' ||
          text.startsWith('storage-error://')) {
        return;
      }
      urls.add(text);
    }

    add(data['areaTechnicalPlanUrl']);
    add(data['technicalPlanUrl']);
    add(data['documentUrl']);
    add(data['photoUrl']);
    final photoUrls = data['photoUrls'];
    if (photoUrls is Iterable) {
      for (final url in photoUrls) {
        add(url);
      }
    }
    return urls.toList();
  }

  Widget _areaReportPhotoPreview(String url) {
    return SizedBox(
      height: 220,
      width: 320,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: buildVerificationDocumentPreview(
          url: url,
          borderRadius: BorderRadius.circular(14),
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  void _showAreaReportPhotos(BuildContext context, List<String> photoUrls) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Фото проверки площади'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PageView(
                    children: photoUrls
                        .map(
                          (url) => buildVerificationDocumentPreview(
                            url: url,
                            borderRadius: BorderRadius.circular(14),
                            fit: BoxFit.contain,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videos() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminVideoContentStream(),
      builder: (context, snapshot) {
        final docs = _withLegalInfoContentDefaults(
          snapshot.data ?? const <Map<String, dynamic>>[],
        );
        final query = _searchQuery.trim().toLowerCase();
        final filteredVideos = docs.where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['title'] ?? data['id']} ${data['category'] ?? ''} ${data['audienceType'] ?? ''}'
              .toLowerCase()
              .contains(query);
        });
        final filtered = _sortRecordsByDate(filteredVideos);
        return _sectionScaffold(
          toolbar: Row(
            children: [
              ElevatedButton.icon(
                onPressed:
                    !_canPublishVideos ? null : () => _openVideoEditor(context),
                icon: const Icon(Icons.add),
                label: Text('Добавить видео'.tr()),
              ),
            ],
          ),
          child: filtered.isEmpty
              ? _emptyState(
                  'Видео не найдены',
                  'Добавьте новый контент или измените поиск.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.6,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final data = filtered[index];
                    final docId = (data['id'] ?? '').toString();
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        color: const Color(0xFFFCFDFE),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusBadge(
                                _audienceLabel(
                                  (data['audienceType'] ?? '—').toString(),
                                ),
                                color: const Color(0xFF1D4ED8),
                              ),
                              if (data['isActive'] == true)
                                _statusBadge(
                                  'Опубликовано',
                                  color: const Color(0xFF047857),
                                ),
                              if (data['isRequired'] == true)
                                _statusBadge(
                                  'Обязательное',
                                  color: const Color(0xFF7C3AED),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            (data['title'] ?? docId).toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (data['description'] ?? 'Описание не задано')
                                .toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Категория: ${(data['category'] ?? '—')}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openVideoEditor(
                                  context,
                                  docId: docId.isEmpty ? null : docId,
                                  existing: data,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _withLegalInfoContentDefaults(
    List<Map<String, dynamic>> docs,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final item in _legalInfoContentDefaults) {
      byKey[(item['key'] ?? item['id']).toString()] = Map<String, dynamic>.from(
        item,
      );
    }
    for (final item in docs) {
      final key = (item['key'] ?? item['id'] ?? '').toString();
      if (key.isEmpty) {
        continue;
      }
      byKey[key] = {...?byKey[key], ...item, 'id': key, 'key': key};
    }
    return byKey.values.toList();
  }

  Map<String, dynamic> _infoContentByKey(
    List<Map<String, dynamic>> docs,
    String key,
  ) {
    return docs.firstWhere(
      (item) => (item['key'] ?? item['id']).toString() == key,
      orElse: () => _legalInfoContentDefaults.firstWhere(
        (item) => (item['key'] ?? item['id']).toString() == key,
      ),
    );
  }

  Widget _infoContent() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminInfoContentStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        int filledRu = 0;
        int filledKk = 0;
        for (final data in docs) {
          final locales = Map<String, dynamic>.from(
            (data['locales'] as Map?) ?? const <String, dynamic>{},
          );
          if ((locales['ru'] ?? data['source'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) {
            filledRu++;
          }
          if ((locales['kk'] ?? '').toString().trim().isNotEmpty) {
            filledKk++;
          }
        }
        final query = _searchQuery.trim().toLowerCase();
        final filtered = docs.where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['id']} ${data['title'] ?? ''} ${data['shortInfo'] ?? ''} ${data['type'] ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList()
          ..sort((a, b) {
            final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
            final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
            return aOrder.compareTo(bOrder);
          });

        return _sectionScaffold(
          toolbar: Row(
            children: [
              OutlinedButton.icon(
                onPressed: !_canEditCatalog
                    ? null
                    : () => _openInfoContentEditor(
                          context,
                          docId: LegalDocumentFallback.offerKey,
                          existing: _infoContentByKey(
                            docs,
                            LegalDocumentFallback.offerKey,
                          ),
                        ),
                icon: const Icon(Icons.description_outlined),
                label: Text('Оферта'.tr()),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: !_canEditCatalog
                    ? null
                    : () => _openInfoContentEditor(
                          context,
                          docId: LegalDocumentFallback.privacyKey,
                          existing: _infoContentByKey(
                            docs,
                            LegalDocumentFallback.privacyKey,
                          ),
                        ),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text('Политика'.tr()),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: !_canEditCatalog
                    ? null
                    : () => _openInfoContentEditor(context),
                icon: const Icon(Icons.add),
                label: Text('Добавить карточку'.tr()),
              ),
            ],
          ),
          child: filtered.isEmpty
              ? _emptyState(
                  'Карточки не найдены',
                  'Добавьте новую карточку или измените поиск.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filtered[index];
                    final docId = (data['id'] ?? '').toString();
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        color: const Color(0xFFFCFDFE),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusBadge(
                                (data['type'] ?? 'info').toString(),
                                color: const Color(0xFF1D4ED8),
                              ),
                              _statusBadge(
                                data['isActive'] == false
                                    ? 'Скрыто'
                                    : 'Активно',
                                color: data['isActive'] == false
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF047857),
                              ),
                              _statusBadge(
                                'sort ${(data['sortOrder'] ?? 999)}',
                                color: const Color(0xFF7C3AED),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            (data['title'] ?? docId).toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'key: $docId',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            (data['shortInfo'] ?? 'Короткое описание не задано')
                                .toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (data['fullInfo'] ?? 'Полная информация не задана')
                                .toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['price'] != null
                                      ? 'Цена: ${data['price']} ₸'
                                      : 'Цена не указана',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: !_canEditCatalog
                                    ? null
                                    : () => _openInfoContentEditor(
                                          context,
                                          docId: docId.isEmpty ? null : docId,
                                          existing: data,
                                        ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _promoBanners() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminPromoBannersStream(),
      builder: (context, snapshot) {
        final banners = snapshot.data ?? const <Map<String, dynamic>>[];

        return _sectionScaffold(
          toolbar: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () =>
                    _openPromoBannerEditor(context, banners: banners),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Добавить баннер'.tr()),
              ),
            ],
          ),
          child: banners.isEmpty
              ? _emptyState(
                  'Баннеров пока нет',
                  'Добавьте акционный баннер для главного экрана клиента.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: banners.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final banner = banners[index];
                    final imageUrl = (banner['imageUrl'] ?? '').toString();
                    final title =
                        (banner['title'] ?? 'Без заголовка').toString();
                    final subtitle = (banner['subtitle'] ?? '').toString();
                    final ctaLabel = (banner['ctaLabel'] ?? '').toString();
                    final route = (banner['route'] ?? '').toString().trim();
                    final externalUrl =
                        (banner['externalUrl'] ?? '').toString().trim();
                    return _entityCard(
                      title: title,
                      subtitle: [
                        if (subtitle.isNotEmpty) subtitle else 'Без описания',
                        if (externalUrl.isNotEmpty) 'Ссылка: $externalUrl',
                        if (externalUrl.isEmpty && route.isNotEmpty)
                          'Страница: $route',
                      ].join('\n'),
                      badges: [
                        _statusBadge(
                          banner['isActive'] == false ? 'Скрыт' : 'Активен',
                          color: banner['isActive'] == false
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF047857),
                        ),
                        _statusBadge(
                          'sort ${(banner['sortOrder'] ?? 999)}',
                          color: const Color(0xFF7C3AED),
                        ),
                      ],
                      actions: [
                        if (imageUrl.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (context) => Dialog(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(imageUrl),
                                  ),
                                ),
                              );
                            },
                            child: Text('Открыть фото'.tr()),
                          ),
                        if (ctaLabel.isNotEmpty)
                          TextButton(
                            onPressed: null,
                            child: Text('CTA: $ctaLabel'),
                          ),
                        TextButton(
                          onPressed: () => _openPromoBannerEditor(
                            context,
                            banners: banners,
                            index: index,
                            existing: banner,
                          ),
                          child: Text('Редактировать'.tr()),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _data.deleteAdminPromoBanner(banner['id'].toString());
                          },
                          child: Text('Удалить'.tr()),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _promotions() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminPromotionsStream(),
      builder: (context, snapshot) {
        final promotions = snapshot.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.adminCustomerPackagesStream(),
          builder: (context, packagesSnapshot) {
            final packages =
                packagesSnapshot.data ?? const <Map<String, dynamic>>[];
            return _sectionScaffold(
              toolbar: ElevatedButton.icon(
                onPressed: !_canManagePolicies
                    ? null
                    : () => _openPromotionEditor(context, packages: packages),
                icon: const Icon(Icons.add),
                label: Text('Создать акцию'.tr()),
              ),
              child: promotions.isEmpty
                  ? _emptyState(
                      'Акций пока нет',
                      'Создайте правило: какой пакет купили и какой бонус начислить.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: promotions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final promo = promotions[index];
                        final id = (promo['id'] ?? '').toString();
                        final packageName = (promo['packageName'] ??
                                promo['packageId'] ??
                                'Любой пакет')
                            .toString();
                        final rewardMode =
                            (promo['rewardMode'] ?? 'fixed').toString();
                        final rewardAmount =
                            (promo['rewardAmount'] as num?)?.toInt() ?? 0;
                        final rewardPercent =
                            (promo['rewardPercent'] as num?)?.toDouble() ?? 0;
                        final rewardLabel = rewardMode == 'percent'
                            ? '${_formatCompactNumber(rewardPercent)}% от оплаты'
                            : '$rewardAmount ₸';
                        final rewardTarget =
                            (promo['rewardTarget'] ?? 'addons').toString();
                        final promoDescription = (promo['shortInfo'] ??
                                promo['description'] ??
                                promo['fullInfo'] ??
                                '')
                            .toString()
                            .trim();
                        final homeBannerImageUrl =
                            (promo['homeBannerImageUrl'] ??
                                    promo['bannerImageUrl'] ??
                                    promo['imageUrl'] ??
                                    '')
                                .toString()
                                .trim();
                        return _entityCard(
                          title: (promo['title'] ?? id).toString(),
                          subtitle:
                              'Пакет: $packageName · Бонус: $rewardLabel · Назначение: ${_promotionRewardTargetLabel(rewardTarget)}',
                          badges: [
                            _statusBadge(
                              promo['isActive'] == false
                                  ? 'Выключена'
                                  : 'Активна',
                              color: promo['isActive'] == false
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF047857),
                            ),
                            _statusBadge(
                              'Лимит ${promo['maxSpendPercent'] ?? 50}%',
                              color: const Color(0xFF1D4ED8),
                            ),
                          ],
                          actions: [
                            if (homeBannerImageUrl.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  showDialog<void>(
                                    context: context,
                                    builder: (context) => Dialog(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          homeBannerImageUrl,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: Text('Фото баннера'.tr()),
                              ),
                            IconButton(
                              tooltip: 'Информация',
                              onPressed: () => _showPromotionInfo(promo),
                              icon: const Icon(Icons.info_outline),
                            ),
                            TextButton(
                              onPressed: !_canManagePolicies
                                  ? null
                                  : () => _openPromotionEditor(
                                        context,
                                        packages: packages,
                                        existing: promo,
                                      ),
                              child: Text('Редактировать'.tr()),
                            ),
                            TextButton(
                              onPressed: !_canManagePolicies
                                  ? null
                                  : () => _deletePromotion(id),
                              child: Text('Удалить'.tr()),
                            ),
                          ],
                          body: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _adminInfoChip('ID', id),
                              _adminInfoChip(
                                'Условие',
                                (promo['packageId'] ?? '').toString().isEmpty
                                    ? 'Любой пакет'
                                    : (promo['packageId'] ?? '').toString(),
                              ),
                              _adminInfoChip(
                                'Повтор',
                                promo['oncePerCustomer'] == false
                                    ? 'Каждая покупка'
                                    : '1 раз на клиента',
                              ),
                              if (promoDescription.isNotEmpty)
                                _adminInfoChip('Описание', promoDescription),
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  Widget _packagesConfig() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminCustomerPackagesStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        final query = _searchQuery.trim().toLowerCase();
        final filtered = docs.where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return '${data['id'] ?? ''} ${data['name'] ?? ''} ${data['frequency'] ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList()
          ..sort((a, b) {
            final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
            final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
            return aOrder.compareTo(bOrder);
          });

        return _sectionScaffold(
          toolbar: Row(
            children: [
              ElevatedButton.icon(
                onPressed:
                    !_canEditCatalog ? null : () => _openPackageEditor(context),
                icon: const Icon(Icons.add),
                label: Text('Добавить пакет'.tr()),
              ),
            ],
          ),
          child: filtered.isEmpty
              ? _emptyState(
                  'Пакеты не найдены',
                  'Добавьте пакет или измените строку поиска.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filtered[index];
                    final docId = (data['id'] ?? '').toString();
                    final cleaningsPerMonth =
                        (data['cleaningsPerMonth'] as num?)?.toInt();
                    final billingPeriodMonths =
                        (data['billingPeriodMonths'] as num?)?.toInt() ?? 1;
                    final discountPercent =
                        (data['discountPercent'] as num?)?.toInt() ?? 0;
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        color: const Color(0xFFFCFDFE),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusBadge(
                                data['isActive'] == false
                                    ? 'Скрыто'
                                    : 'Активно',
                                color: data['isActive'] == false
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF047857),
                              ),
                              _statusBadge(
                                'sort ${(data['sortOrder'] ?? 999)}',
                                color: const Color(0xFF7C3AED),
                              ),
                              if (data['isQuarterly'] == true)
                                _statusBadge(
                                  'Квартальный',
                                  color: const Color(0xFF1D4ED8),
                                ),
                              if (data['popular'] == true)
                                _statusBadge(
                                  'Популярный',
                                  color: const Color(0xFFD97706),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            (data['name'] ?? docId).toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'id: $docId',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                'Частота: ${(data['frequency'] ?? 'Не указана')}',
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              Text(
                                'Цена: ${data['price'] ?? 0} ₸',
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              if (cleaningsPerMonth != null)
                                Text(
                                  'Уборок в месяц: $cleaningsPerMonth'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              Text(
                                'Период: $billingPeriodMonths мес.'.tr(),
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              Text(
                                'Скидка: $discountPercent%'.tr(),
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                          if (data['features'] is List &&
                              (data['features'] as List).isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              (data['features'] as List)
                                  .map((item) => item.toString())
                                  .join(' • '),
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                          if ((data['shortInfo'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              (data['shortInfo'] ?? '').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF475569)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['updatedAt'] == null
                                      ? 'Изменений еще не было'
                                      : 'Пакет доступен для редактирования в админке',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: !_canEditCatalog
                                    ? null
                                    : () => _openPackageEditor(
                                          context,
                                          docId: docId,
                                          existing: data,
                                        ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: !_canEditCatalog
                                    ? null
                                    : () => _deletePackage(docId),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _translationDictionaries() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminTranslationEntriesStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        var filledRu = 0;
        var filledKk = 0;
        for (final data in docs) {
          final locales = Map<String, dynamic>.from(
            (data['locales'] as Map?) ?? const <String, dynamic>{},
          );
          if ((locales['ru'] ?? data['source'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) {
            filledRu++;
          }
          if ((locales['kk'] ?? '').toString().trim().isNotEmpty) {
            filledKk++;
          }
        }
        final query = _searchQuery.trim().toLowerCase();
        final filtered = docs.where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          final source = (data['source'] ?? '').toString();
          final locales = Map<String, dynamic>.from(
            (data['locales'] as Map?) ?? const <String, dynamic>{},
          );
          final currentTranslation =
              (locales[_dictionaryLocale] ?? '').toString().trim();
          if (_dictionaryOnlyMissing && currentTranslation.isNotEmpty) {
            return false;
          }
          final haystack = [
            source,
            ...TranslationController.supportedLocales.map(
              (locale) => (locales[locale] ?? '').toString(),
            ),
          ].join(' ').toLowerCase();
          return query.isEmpty || haystack.contains(query);
        }).toList()
          ..sort((a, b) {
            final aSource = (a['source'] ?? '').toString();
            final bSource = (b['source'] ?? '').toString();
            return aSource.compareTo(bSource);
          });

        return _sectionScaffold(
          toolbar: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: !_canManagePolicies
                    ? null
                    : () => _syncTranslationSources(),
                icon: const Icon(Icons.sync_outlined),
                label: Text('Синхронизировать из кода'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: !_canManagePolicies
                    ? null
                    : () => _openTranslationEditor(context),
                icon: const Icon(Icons.add),
                label: Text('Добавить фразу'.tr()),
              ),
              FilterChip(
                label: Text('Без перевода'.tr()),
                selected: _dictionaryOnlyMissing,
                onSelected: (value) =>
                    setState(() => _dictionaryOnlyMissing = value),
              ),
              ...TranslationController.supportedLocales.map((locale) {
                final selected = locale == _dictionaryLocale;
                return ChoiceChip(
                  label: Text(TranslationController.localeLabel(locale)),
                  selected: selected,
                  onSelected: (_) => setState(() => _dictionaryLocale = locale),
                );
              }),
              _statusBadge(
                'Всего: ${docs.length} · RU: $filledRu · KK: $filledKk',
                color: const Color(0xFF334155),
              ),
            ],
          ),
          child: filtered.isEmpty
              ? _emptyState(
                  'Словарь пока пуст',
                  'Синхронизируйте строки из кода или добавьте фразу вручную.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filtered[index];
                    final locales = Map<String, dynamic>.from(
                      (data['locales'] as Map?) ?? const <String, dynamic>{},
                    );
                    final docId = (data['id'] ?? '').toString();
                    final source = (data['source'] ?? docId).toString();
                    final currentTranslation =
                        (locales[_dictionaryLocale] ?? '').toString().trim();
                    final ruTranslation =
                        (locales['ru'] ?? '').toString().trim();
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        color: const Color(0xFFFCFDFE),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusBadge(
                                TranslationController.localeLabel(
                                  _dictionaryLocale,
                                ),
                                color: const Color(0xFF1D4ED8),
                              ),
                              _statusBadge(
                                currentTranslation.isEmpty
                                    ? 'Нет перевода'
                                    : 'Заполнено',
                                color: currentTranslation.isEmpty
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF047857),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            source,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ru: ${ruTranslation.isEmpty ? source : ruTranslation}',
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_dictionaryLocale.toUpperCase()}: ${currentTranslation.isEmpty ? '—' : currentTranslation}',
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Ключ: $docId'.tr(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: !_canManagePolicies
                                    ? null
                                    : () => _openTranslationEditor(
                                          context,
                                          docId: docId,
                                          existing: data,
                                        ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _policies() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _data.adminPoliciesStream(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: Text('Сумма реферального бонуса'.tr()),
              subtitle: Text('${data['referralBonusAmount'] ?? 2000} ₸'),
            ),
            ListTile(
              title: Text('Акция за покупку пакета'.tr()),
              subtitle: Text(
                data['packagePurchaseBonusEnabled'] == true
                    ? 'Включена • ${data['packagePurchaseBonusAmount'] ?? 10000} ₸ бонусами'
                    : 'Выключена',
              ),
            ),
            ListTile(
              title: Text('Порог активации дома'.tr()),
              subtitle: Text('${data['defaultHouseThreshold'] ?? 20} квартир'),
            ),
            ListTile(
              title: Text('Допуск проверки площади'.tr()),
              subtitle: Text('${data['areaVerificationTolerance'] ?? 0} м²'),
            ),
            ListTile(
              title: Text('Время уборки'.tr()),
              subtitle: Text(
                '${data['cleaningMinutesPerSqm'] ?? 1.6} мин/м² + '
                '${data['cleaningBaseMinutes'] ?? 30} мин • '
                'мин. ${data['cleaningMinMinutes'] ?? 120} мин • '
                'макс. ${data['cleaningMaxMinutes'] ?? 480} мин',
              ),
            ),
            const Divider(),
            ListTile(
              title: Text('Надежная: порог / бонус'.tr()),
              subtitle: Text(
                '${data['cleanerReliableAreaThreshold'] ?? 12000} м² • ${data['cleanerReliableBonusAmount'] ?? 100000} ₸',
              ),
            ),
            ListTile(
              title: Text('Эксперт: порог / бонус'.tr()),
              subtitle: Text(
                '${data['cleanerExpertAreaThreshold'] ?? 30000} м² • ${data['cleanerExpertBonusAmount'] ?? 200000} ₸',
              ),
            ),
            ListTile(
              title: Text('Легенда: порог / бонус'.tr()),
              subtitle: Text(
                '${data['cleanerLegendAreaThreshold'] ?? 65000} м² • ${data['cleanerLegendBonusAmount'] ?? 500000} ₸',
              ),
            ),
            ListTile(
              title: Text('Еженедельный бонус за площадь'.tr()),
              subtitle: Text(
                '${data['cleanerWeeklyAreaThreshold'] ?? 1300} м² • ${data['cleanerWeeklyAreaBonusAmount'] ?? 5000} ₸',
              ),
            ),
            ListTile(
              title: Text('Бонус за доп. услуги'.tr()),
              subtitle: Text(
                '${data['cleanerWeeklyAddonBonusThreshold1'] ?? 30000} ₸ → ${data['cleanerWeeklyAddonBonusAmount1'] ?? 4000} ₸, '
                '${data['cleanerWeeklyAddonBonusThreshold2'] ?? 50000} ₸ → ${data['cleanerWeeklyAddonBonusAmount2'] ?? 6000} ₸',
              ),
            ),
            ListTile(
              title: Text('Кошелек и вывод'.tr()),
              subtitle: Text(
                'Тариф ${data['cleanerSqmRate'] ?? 60} ₸/м² • '
                'План ${data['cleanerDailyIncome'] ?? 13500} ₸/день • '
                'Недельный вывод ${data['cleanerWeeklyCashoutPercent'] ?? 30}% • '
                'Раз в ${data['cleanerFullCashoutCooldownDays'] ?? 30} дней',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: !_canManagePolicies
                  ? null
                  : () => _openPoliciesEditor(context, data),
              child: Text('Редактировать политики'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionScaffold({Widget? toolbar, required Widget child}) {
    return Column(
      children: [
        if (toolbar != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Align(alignment: Alignment.centerLeft, child: toolbar),
          ),
        Expanded(child: child),
      ],
    );
  }

  Widget _listMetricCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Stream<List<Map<String, dynamic>>> stream,
    required int Function(List<Map<String, dynamic>>) countBuilder,
    Color accent = const Color(0xFF1D4ED8),
  }) {
    return SizedBox(
      width: 260,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          final count = countBuilder(items);
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08111827),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(height: 18),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dashboardPanel({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _simpleAdminList({
    required List<_AdminListItem> items,
    required String emptyText,
  }) {
    if (items.isEmpty) {
      return _emptyState('Пусто', emptyText, compact: true);
    }
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.trailing != null) ...[
                      const SizedBox(width: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: item.trailing!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _entityCard({
    required String title,
    required String subtitle,
    List<Widget> badges = const [],
    List<Widget> actions = const [],
    Widget? body,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              if (badges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Wrap(spacing: 8, runSpacing: 8, children: badges),
                  ),
                ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
          if (body != null) ...[const SizedBox(height: 14), body],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? const Color(0xFF1D4ED8) : const Color(0xFFF8FAFC),
          border: Border.all(
            color: selected ? const Color(0xFF1D4ED8) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF374151),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String label, {required Color color}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 76),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.10),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _statusLegendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
      ],
    );
  }

  Widget _compactDropdown({
    required String value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      child: DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : items.first,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateFilterButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.event_outlined),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  Widget _bulkActionButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  Widget _signalRow(String title, String subtitle, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF1D4ED8)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle, {bool compact = false}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.inbox_outlined, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFilterDate({required bool isStart}) async {
    final now = DateTime.now();
    final initialDate = isStart
        ? (_filterStartDate ?? now)
        : (_filterEndDate ?? _filterStartDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('ru'),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _filterStartDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        _filterEndDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      }
    });
  }

  Future<void> _openEntityDetails(
    BuildContext context, {
    required String title,
    required List<_DetailSection> sections,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Детали',
      barrierColor: const Color(0x4D0F172A),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 760,
              height: double.infinity,
              margin: const EdgeInsets.only(left: 80),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A0F172A),
                    blurRadius: 24,
                    offset: Offset(-8, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Детальная карточка для проверки и операционных решений.'
                            .tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: sections
                                .map(
                                  (section) => Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                      color: const Color(0xFFF8FAFC),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          section.title,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        ...section.rows.entries.map(
                                          (entry) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 220,
                                                  child: Text(
                                                    entry.key,
                                                    style: const TextStyle(
                                                      color: Color(0xFF6B7280),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    entry.value,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _openVerificationImage(
    BuildContext context, {
    required String title,
    required String url,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: buildVerificationDocumentPreview(
                      url: url,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  url,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bulkUpdateOrders(Set<String> orderIds, String status) async {
    if (orderIds.isEmpty) {
      return;
    }
    try {
      for (final orderId in orderIds) {
        await _data.createAdminAction({
          'type': 'order_status',
          'orderId': orderId,
          'toStatus': status,
        });
      }
      if (!mounted) {
        return;
      }
      setState(() => _selectedOrderIds.removeAll(orderIds));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Статус отправлен на смену: ${_orderStatusLabel(status)} (${orderIds.length})'
                .tr(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сменить статус: $error'.tr())),
      );
    }
  }

  Future<void> _handleSelectedOrdersStatusAction(
    Set<String> orderIds,
    String status,
    List<Map<String, dynamic>> visibleOrders,
    List<Map<String, dynamic>> cleaners,
    List<Map<String, dynamic>> allOrders,
  ) async {
    if (orderIds.isEmpty) {
      return;
    }
    if (status == 'assigned') {
      if (orderIds.length != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Для назначения выберите только один заказ.'.tr()),
          ),
        );
        return;
      }
      final orderId = orderIds.first;
      final order = visibleOrders.firstWhere(
        (item) => (item['id'] ?? item['orderId'] ?? '').toString() == orderId,
        orElse: () => const <String, dynamic>{},
      );
      if (order.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Заказ не найден в текущем списке.'.tr())),
        );
        return;
      }
      final assigned = await _openAssignCleaner(
        context,
        orderId,
        order,
        cleaners,
        allOrders,
      );
      if (!mounted) {
        return;
      }
      if (assigned) {
        setState(() => _selectedOrderIds.remove(orderId));
      }
      return;
    }
    final ordersById = {
      for (final order in visibleOrders)
        (order['id'] ?? order['orderId'] ?? '').toString(): order,
    };
    final withoutCleaner = orderIds.where((orderId) {
      final order = ordersById[orderId];
      if (order == null) {
        return false;
      }
      return (order['cleanerId'] ?? order['assignedCleanerId'] ?? '')
          .toString()
          .trim()
          .isEmpty;
    }).toList();
    if (withoutCleaner.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Сначала назначьте уборщицу. Без уборщицы нельзя поставить статус "${_orderStatusLabel(status)}".'
                .tr(),
          ),
        ),
      );
      return;
    }
    await _bulkUpdateOrders(orderIds, status);
  }

  Future<void> _bulkReviewVerifications(
    Set<String> cleanerIds,
    String status,
  ) async {
    if (cleanerIds.isEmpty) {
      return;
    }
    final normalizedStatus = status.toLowerCase();
    try {
      for (final cleanerId in cleanerIds) {
        await _data.reviewCleanerVerification(
          cleanerId: cleanerId,
          status: normalizedStatus,
          rejectionReason: normalizedStatus == 'rejected'
              ? 'Документы требуют корректировки'
              : null,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обработать заявки: $e'.tr())),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _selectedVerificationIds.removeAll(cleanerIds));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Заявки обработаны: ${_cleanerVerificationLabel(status)} (${cleanerIds.length})'
              .tr(),
        ),
      ),
    );
  }

  Future<void> _bulkResolveAreaReports(Set<String> reportIds) async {
    if (reportIds.isEmpty) {
      return;
    }
    for (final reportId in reportIds) {
      await _data.resolveAreaMismatchReport(reportId);
    }
    if (!mounted) {
      return;
    }
    setState(() => _selectedAreaReportIds.removeAll(reportIds));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Кейсы закрыты: ${reportIds.length}'.tr())),
    );
  }

  Future<Map<String, dynamic>?> _loadAreaReportLinkedOrder(
    Map<String, dynamic> report,
  ) async {
    final orderId =
        (report['orderId'] ?? report['sourceOrderId'] ?? '').toString().trim();
    final customerId =
        (report['userId'] ?? report['customerId'] ?? '').toString().trim();
    if (orderId.isNotEmpty) {
      final orders = await _data.adminOrdersStream().first;
      final matched = orders.cast<Map<String, dynamic>?>().firstWhere(
            (item) =>
                item?['id']?.toString() == orderId ||
                item?['orderId']?.toString() == orderId,
            orElse: () => null,
          );
      if (matched != null) {
        return Map<String, dynamic>.from(matched);
      }
    }
    if (customerId.isEmpty) {
      return null;
    }
    final orders = await _data.adminOrdersStream().first;
    final candidates = orders
        .where(
          (item) =>
              (item['customerId'] ?? item['userId']).toString() == customerId &&
              ((item['paymentStatus'] ?? '').toString().toLowerCase() ==
                      'paid' ||
                  (item['status'] ?? '').toString().toLowerCase() == 'paid' ||
                  (item['orderStatus'] ?? '').toString().toLowerCase() !=
                      'canceled'),
        )
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(
      (a, b) => _firstAdminDateTime(b, const [
        'paidAt',
        'createdAt',
        'updatedAt',
      ]).compareTo(
        _firstAdminDateTime(a, const ['paidAt', 'createdAt', 'updatedAt']),
      ),
    );
    return Map<String, dynamic>.from(candidates.first);
  }

  Future<int> _applyAreaRecalculationForReport(
    Map<String, dynamic> report,
    int actualArea,
  ) async {
    final reportId = (report['id'] ?? '').toString();
    final order = await _loadAreaReportLinkedOrder(report);
    if (order == null || order.isEmpty) {
      return 0;
    }
    final orderId = (order['id'] ?? order['orderId'] ?? '').toString();
    if (orderId.isEmpty) {
      return 0;
    }
    final recalculation = _qualityControlOrderRecalculation(order, actualArea);
    await _data.updateCustomerOrder(orderId, recalculation);
    final amountDue =
        (recalculation['areaAdjustmentAmount'] as num?)?.toInt() ?? 0;
    if (amountDue > 0) {
      await _data.createAreaRecalculationPayment(
        orderId: orderId,
        order: order,
        previousArea: (recalculation['previousArea'] as num?)?.toInt() ?? 0,
        actualArea: actualArea,
        previousPaidAmount:
            (recalculation['previousPaidAmount'] as num?)?.toInt() ?? 0,
        recalculatedAmount:
            (recalculation['areaRecalculatedPrice'] as num?)?.toInt() ?? 0,
        amountDue: amountDue,
        reportId: reportId,
      );
    }
    return amountDue;
  }

  Future<void> _resolveAreaMismatchReportWithRecalculation(
    BuildContext context,
    Map<String, dynamic> report,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reportId = (report['id'] ?? '').toString();
    final userId = (report['userId'] ?? report['customerId'] ?? '').toString();
    final actualArea =
        ((report['actualArea'] ?? report['area']) as num?)?.toInt() ??
            int.tryParse(
              (report['actualArea'] ?? report['area'] ?? '').toString(),
            ) ??
            0;
    if (reportId.isEmpty || userId.isEmpty || actualArea <= 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Укажите корректную площадь.'.tr())),
      );
      return;
    }
    try {
      await _data.confirmApartmentAreaByQualityControl(
        userId: userId,
        actualArea: actualArea,
      );
      final amountDue = await _applyAreaRecalculationForReport(
        report,
        actualArea,
      );
      await _data.resolveAreaMismatchReport(reportId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            amountDue > 0
                ? 'Площадь подтверждена. Создана доплата: $amountDue ₸.'
                : 'Площадь подтверждена.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось закрыть кейс: $e'.tr())),
      );
    }
  }

  Future<void> _confirmAreaQualityCheck(
    BuildContext context,
    Map<String, dynamic> report, {
    Map<String, dynamic>? order,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final reportId = (report['id'] ?? '').toString();
    final userId = (report['userId'] ?? report['customerId'] ?? '').toString();
    final areaController = TextEditingController(
      text: (report['actualArea'] ?? report['initialArea'] ?? '').toString(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Подтвердить квадратуру'.tr()),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report['customerName'] ?? 'Клиент'} · ${report['customerPhone'] ?? 'телефон не указан'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text((report['address'] ?? 'Адрес не указан').toString()),
              const SizedBox(height: 16),
              TextField(
                controller: areaController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Фактическая площадь, м²',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Отмена'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Подтвердить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final actualArea = int.tryParse(areaController.text.trim()) ?? 0;
    if (reportId.isEmpty || userId.isEmpty || actualArea <= 0) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Укажите корректную площадь.'.tr())),
      );
      return;
    }
    try {
      await _data.confirmApartmentAreaByQualityControl(
        userId: userId,
        actualArea: actualArea,
      );
      await _data.updateAreaMismatchReport(reportId, {
        'actualArea': actualArea,
        'difference':
            actualArea - ((report['initialArea'] as num?)?.toInt() ?? 0),
        'reviewStatus': 'verified',
        'confirmedByQualityControl': true,
      });
      final orderId =
          (report['orderId'] ?? order?['orderId'] ?? order?['id'] ?? '')
              .toString();
      if (orderId.isNotEmpty && order != null && order.isNotEmpty) {
        final recalculation = _qualityControlOrderRecalculation(
          order,
          actualArea,
        );
        await _data.updateCustomerOrder(orderId, recalculation);
        final amountDue =
            (recalculation['areaAdjustmentAmount'] as num?)?.toInt() ?? 0;
        if (amountDue > 0) {
          await _data.createAreaRecalculationPayment(
            orderId: orderId,
            order: order,
            previousArea: (recalculation['previousArea'] as num?)?.toInt() ?? 0,
            actualArea: actualArea,
            previousPaidAmount:
                (recalculation['previousPaidAmount'] as num?)?.toInt() ?? 0,
            recalculatedAmount:
                (recalculation['areaRecalculatedPrice'] as num?)?.toInt() ?? 0,
            amountDue: amountDue,
            reportId: reportId,
          );
        }
      }
      await _data.resolveAreaMismatchReport(reportId);
      if (!mounted) return;
      final amountDue = order == null
          ? 0
          : (_qualityControlOrderRecalculation(
              order,
              actualArea,
            )['areaAdjustmentAmount'] as num?)
              ?.toInt();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            amountDue != null && amountDue > 0
                ? 'Площадь подтверждена. Создана доплата: $amountDue ₸.'
                : 'Площадь подтверждена.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось подтвердить площадь: $e'.tr())),
      );
    }
  }

  Map<String, dynamic> _qualityControlOrderRecalculation(
    Map<String, dynamic> order,
    int actualArea,
  ) {
    final previousAreaDouble =
        ((order['area'] ?? order['apartmentArea']) as num?)?.toDouble() ?? 0;
    final previousArea = previousAreaDouble.round();
    final originalPrice = (order['originalPrice'] as num?)?.toDouble() ??
        (order['price'] as num?)?.toDouble() ??
        0;
    final previousPaidAmount = (order['price'] as num?)?.toDouble() ??
        (order['amount'] as num?)?.toDouble() ??
        originalPrice;
    final addonTotal = (order['addonTotalPrice'] as num?)?.toDouble() ?? 0;
    final tierPercent = (order['tierDiscountPercent'] as num?)?.toDouble() ?? 0;
    final referralPercent =
        (order['referralDiscountPercent'] as num?)?.toDouble() ?? 0;
    final bonusApplied = (order['bonusAppliedAmount'] as num?)?.toDouble() ?? 0;

    double recalculatedOriginal = originalPrice;
    if (previousAreaDouble > 0 && originalPrice > addonTotal) {
      final packagePart = originalPrice - addonTotal;
      recalculatedOriginal =
          (packagePart / previousAreaDouble * actualArea) + addonTotal;
    }
    final tierDiscount =
        (recalculatedOriginal * (tierPercent / 100)).roundToDouble();
    final afterTier = (recalculatedOriginal - tierDiscount).clamp(
      0,
      double.infinity,
    );
    final referralDiscount =
        (afterTier * (referralPercent / 100)).roundToDouble();
    final afterReferral = (afterTier - referralDiscount).clamp(
      0,
      double.infinity,
    );
    final finalPrice = (afterReferral - bonusApplied).clamp(0, double.infinity);
    final areaAdjustmentAmount =
        (finalPrice.round() - previousPaidAmount.round()).clamp(0, 1 << 31);
    return {
      'area': actualArea,
      'apartmentArea': actualArea,
      'areaVerified': true,
      'areaStatus': 'VERIFIED',
      'previousArea': previousArea,
      'previousPaidAmount': previousPaidAmount.round(),
      'areaRecalculatedOriginalPrice': recalculatedOriginal.round(),
      'areaRecalculatedTierDiscountAmount': tierDiscount.round(),
      'areaRecalculatedPriceAfterTierDiscount': afterTier.round(),
      'areaRecalculatedReferralDiscountAmount': referralDiscount.round(),
      'areaRecalculatedPriceAfterReferralDiscount': afterReferral.round(),
      'areaRecalculatedPrice': finalPrice.round(),
      'areaAdjustmentAmount': areaAdjustmentAmount,
      'areaAdjustmentPaymentStatus':
          areaAdjustmentAmount > 0 ? 'pending_invoice' : 'not_required',
      'qualityControlRecalculatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _openVerificationDetails(
    BuildContext context, {
    required String cleanerId,
    required Map<String, dynamic> cleaner,
    required Map<String, dynamic> verification,
    required List<MapEntry<String, String>> documentUrls,
  }) async {
    final cleanerName = (cleaner['fullName'] ??
            cleaner['name'] ??
            verification['name'] ??
            cleanerId)
        .toString();
    final cleanerPhone =
        (cleaner['phone'] ?? verification['phone'] ?? '—').toString();
    final cleanerCluster =
        (cleaner['clusterName'] ?? verification['clusterName'] ?? '—')
            .toString();
    final cleanerStatus =
        (cleaner['cleanerStatusLabel'] ?? cleaner['verificationStatus'] ?? '—')
            .toString();
    final cleanerEmail = (cleaner['email'] ?? '—').toString();
    final cleanerAddress =
        (cleaner['homeAddress'] ?? cleaner['address'] ?? '—').toString();
    final cleanerRegisteredAt = _firstAdminDateTime(cleaner, const [
      'registeredAt',
      'createdAt',
      'joinedAt',
      'joinDate',
    ]);
    final documentsSubmittedAt = _firstAdminDateTime(verification, const [
      'documentsSubmittedAt',
      'submittedAt',
      'createdAt',
      'documentsUploadedAt',
      'verificationSubmittedAt',
    ]);
    final reviewedAt = _firstAdminDateTime(verification, const [
      'reviewedAt',
      'updatedAt',
    ]);
    final approvedAt = _firstAdminDateTime(
      {...cleaner, ...verification},
      const ['approvedAt', 'verifiedAt', 'verificationApprovedAt'],
    );
    final status =
        (verification['status'] ?? 'pending').toString().toLowerCase();
    final rejectionReason = (verification['rejectionReason'] ?? '—').toString();

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Верификация $cleanerName'.tr(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Все документы и данные уборщицы собраны в одном окне.'
                                .tr(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusBadge(
                      _cleanerVerificationLabel(status),
                      color: status == 'approved'
                          ? const Color(0xFF047857)
                          : status == 'rejected'
                              ? const Color(0xFFDC2626)
                              : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 340,
                              child: _verificationInfoPanel(
                                title: 'Данные уборщицы',
                                rows: {
                                  'ID': cleanerId,
                                  'Имя': cleanerName,
                                  'Телефон': cleanerPhone,
                                  'Email': cleanerEmail,
                                  'Кластер': cleanerCluster,
                                  'Статус в системе': cleanerStatus,
                                  'Адрес': cleanerAddress,
                                  'Дата регистрации': cleanerRegisteredAt,
                                },
                              ),
                            ),
                            SizedBox(
                              width: 340,
                              child: _verificationInfoPanel(
                                title: 'Ревью заявки',
                                rows: {
                                  'Статус': _cleanerVerificationLabel(status),
                                  'Документы загружены': documentsSubmittedAt,
                                  'Проверили': reviewedAt,
                                  'Подтвердили': approvedAt,
                                  'Причина отказа': rejectionReason,
                                  'Селфи': _presenceLabel(
                                    (verification['selfieUrl'] ?? '')
                                        .toString(),
                                  ),
                                  'ID документ': _presenceLabel(
                                    (verification['idDocumentUrl'] ?? '')
                                        .toString(),
                                  ),
                                  'Прописка': _presenceLabel(
                                    (verification['residenceProofUrl'] ?? '')
                                        .toString(),
                                  ),
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Фото и документы'.tr(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Нажмите на превью, чтобы открыть документ крупно.'
                              .tr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (documentUrls.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: const Color(0xFFF8FAFC),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Text(
                              'Документы пока не загружены.'.tr(),
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          _verificationPreviewGrid(
                            context,
                            cleanerName: cleanerName,
                            cleanerId: cleanerId,
                            items: documentUrls,
                          ),
                      ],
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

  Widget _verificationPreviewGrid(
    BuildContext context, {
    required String cleanerName,
    required String cleanerId,
    required List<MapEntry<String, String>> items,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((entry) {
        return InkWell(
          onTap: () => _openVerificationImage(
            context,
            title: '${entry.key} · $cleanerName',
            url: entry.value,
          ),
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 172,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: buildVerificationDocumentPreview(
                    url: entry.value,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.key,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cleanerId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _verificationInfoPanel({
    required String title,
    required Map<String, String> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: const Color(0xFFF8FAFC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 14),
          ...rows.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 128,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSaveViewDialog(String sectionKey) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Сохранить текущий вид'.tr()),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Название вида',
            hintText: 'Например, Нужны назначения',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(this.context);
              final name = controller.text.trim();
              if (name.isEmpty) {
                return;
              }
              await _data.saveAdminSavedView({
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'name': name,
                'sectionKey': sectionKey,
                'searchQuery': _searchQuery,
                'statusFilter': _statusFilter,
                'clusterFilter': _clusterFilter,
                'cleanerFilter': _cleanerFilter,
                'serviceAreaFilter': _serviceAreaFilter,
                'assignmentStatusFilter': _assignmentStatusFilter,
                'filterStartDate': _filterStartDate?.millisecondsSinceEpoch,
                'filterEndDate': _filterEndDate?.millisecondsSinceEpoch,
                'updatedAt': DateTime.now().millisecondsSinceEpoch,
              });
              if (!mounted) {
                return;
              }
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Вид сохранен'.tr())),
              );
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSavedView(String viewId) async {
    await _data.deleteAdminSavedView(viewId);
  }

  Future<void> _deleteServiceZone(Map<String, dynamic> zone) async {
    final zoneId = (zone['id'] ?? '').toString();
    if (zoneId.isEmpty) {
      return;
    }
    final title = (zone['title'] ?? zoneId).toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить зону покрытия'.tr()),
        content: Text(
          'Удалить зону "$title"? У домов этой зоны будет очищена привязка к району.'
              .tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _data.deleteServiceZone(zoneId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Зона удалена: $title'.tr())));
  }

  Future<void> _deletePackage(String packageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить пакет'.tr()),
        content: Text('Удалить пакет "$packageId" из customer_packages?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _data.deleteAdminPackage(packageId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Пакет удален: $packageId'.tr())));
  }

  Future<void> _deletePromotion(String promotionId) async {
    final normalizedPromotionId = promotionId.trim();
    if (normalizedPromotionId.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить акцию'.tr()),
        content: Text('Удалить акцию "$normalizedPromotionId"?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _data.deleteAdminPromotion(normalizedPromotionId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Акция удалена: $normalizedPromotionId'.tr())),
    );
  }

  Future<void> _showPromotionInfo(Map<String, dynamic> promo) {
    final title = (promo['title'] ?? promo['id'] ?? 'Акция').toString();
    final shortInfo =
        (promo['shortInfo'] ?? promo['description'] ?? '').toString().trim();
    final fullInfo =
        (promo['fullInfo'] ?? promo['longDescription'] ?? '').toString().trim();
    List<String> textList(Object? value) {
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      final text = (value ?? '').toString().trim();
      return text.isEmpty ? const <String>[] : [text];
    }

    final features = textList(promo['features']);
    final exclusions = textList(promo['exclusions']);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shortInfo.isNotEmpty) Text(shortInfo),
                if (fullInfo.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(fullInfo),
                ],
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Что входит'.tr(),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...features.map((item) => Text('• $item')),
                ],
                if (exclusions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Что не входит'.tr(),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...exclusions.map((item) => Text('• $item')),
                ],
                if (shortInfo.isEmpty &&
                    fullInfo.isEmpty &&
                    features.isEmpty &&
                    exclusions.isEmpty)
                  Text('Описание акции пока не заполнено.'.tr()),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCleaner(Map<String, dynamic> cleaner) async {
    final cleanerId = (cleaner['id'] ?? '').toString().trim();
    if (cleanerId.isEmpty) {
      return;
    }
    final title = (cleaner['name'] ?? cleanerId).toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить уборщицу'.tr()),
        content: Text('Удалить уборщицу "$title" из админки?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _data.deleteCleaner(cleanerId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Уборщица удалена: $title'.tr())));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить уборщицу: $error'.tr())),
      );
    }
  }

  Future<void> _syncTranslationSources() async {
    if (!_canManagePolicies) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (kDefaultTranslationSources.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('Список строк пока пуст'.tr())),
      );
      return;
    }

    try {
      await _data.syncAdminTranslationSources();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Словарь синхронизирован: фразы приложения и данные из базы добавлены'
                .tr(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось синхронизировать словарь: $error'.tr()),
        ),
      );
    }
  }

  Future<void> _loadAdminCapabilities() async {
    if ((DebugSession.enabled && DebugSession.uid == 'admin_demo') ||
        AuthService.restoredSessionUid != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _adminRoleLabel = 'Суперадмин';
        _canManagePolicies = true;
        _canPublishVideos = true;
        _canRunPayouts = true;
        _canEditCleaners = true;
        _canEditClusters = true;
        _canEditCatalog = true;
        _canActivateHouses = true;
      });
      return;
    }
  }

  Future<void> _copyOrdersCsv(List<Map<String, dynamic>> docs) {
    return _copyCsv(
      headers: const [
        'order_id',
        'status',
        'payment_status',
        'customer',
        'address',
        'cleaner_id',
        'price',
      ],
      rows: docs.map((data) {
        return [
          (data['id'] ?? '').toString(),
          (data['orderStatus'] ?? '').toString(),
          (data['paymentStatus'] ?? '').toString(),
          (data['customerName'] ?? data['customerId'] ?? '').toString(),
          (data['address'] ?? '').toString(),
          (data['cleanerId'] ?? '').toString(),
          '${data['price'] ?? 0}',
        ];
      }).toList(),
      successMessage: 'CSV по заказам скопирован',
    );
  }

  Future<void> _copyPayoutsCsv(List<Map<String, dynamic>> docs) {
    return _copyCsv(
      headers: const [
        'payout_id',
        'cleaner_id',
        'status',
        'payout_type',
        'kaspi_phone',
        'week_id',
        'gross',
        'tax',
        'net',
      ],
      rows: docs.map((data) {
        return [
          (data['id'] ?? '').toString(),
          (data['cleanerId'] ?? '').toString(),
          (data['status'] ?? '').toString(),
          (data['payoutType'] ?? '').toString(),
          (data['kaspiPhone'] ?? '').toString(),
          (data['weekId'] ?? '').toString(),
          '${data['gross'] ?? 0}',
          '${data['tax'] ?? 0}',
          '${data['net'] ?? 0}',
        ];
      }).toList(),
      successMessage: 'CSV по выплатам скопирован',
    );
  }

  Future<void> _copyReviewsCsv(List<Map<String, dynamic>> reviews) {
    return _copyCsv(
      headers: const [
        'order_id',
        'customer_id',
        'rating',
        'text',
        'positive_traits',
        'negative_traits',
      ],
      rows: reviews
          .map(
            (review) => [
              (review['orderId'] ?? '').toString(),
              (review['customerId'] ?? '').toString(),
              '${review['rating'] ?? 0}',
              (review['text'] ?? '').toString(),
              ((review['positiveTraits'] ?? const []) as List).join('|'),
              ((review['negativeTraits'] ?? const []) as List).join('|'),
            ],
          )
          .toList(),
      successMessage: 'CSV по отзывам скопирован',
    );
  }

  Future<void> _copyChecklistsCsv(List<Map<String, dynamic>> docs) {
    return _copyCsv(
      headers: const [
        'order_id',
        'cleaner_id',
        'completed_tasks',
        'ordered_addons',
        'completed_addons',
        'note',
      ],
      rows: docs.map((doc) {
        final orderedAddons = ((doc['orderedAddons'] ??
                doc['addonsDetailed'] ??
                const []) as List)
            .map((e) {
              if (e is Map) {
                return (e['label'] ?? e['title'] ?? e['name'] ?? e['key'] ?? '')
                    .toString();
              }
              return '$e';
            })
            .where((e) => e.trim().isNotEmpty)
            .join('|');
        return [
          (doc['orderId'] ?? doc['id']).toString(),
          (doc['cleanerId'] ?? '').toString(),
          ((doc['completedTasks'] ?? []) as List).join('|'),
          orderedAddons,
          ((doc['addons'] ?? []) as List).join('|'),
          (doc['note'] ?? '').toString(),
        ];
      }).toList(),
      successMessage: 'CSV по чек-листам скопирован',
    );
  }

  Future<void> _copyReferralsCsv(List<Map<String, dynamic>> docs) {
    return _copyCsv(
      headers: const ['user_id', 'invited', 'registered', 'paid', 'bonus'],
      rows: docs.map((data) {
        return [
          (data['id'] ?? '').toString(),
          '${data['invited'] ?? 0}',
          '${data['registered'] ?? 0}',
          '${data['paid'] ?? 0}',
          '${data['bonus'] ?? 0}',
        ];
      }).toList(),
      successMessage: 'CSV по рефералам скопирован',
    );
  }

  Future<void> _copyCsv({
    required List<String> headers,
    required List<List<String>> rows,
    required String successMessage,
  }) async {
    final csv = [
      headers.map(_csvEscape).join(','),
      ...rows.map((row) => row.map(_csvEscape).join(',')),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  _DetailSection _detailSection(String title, Map<String, String> rows) =>
      _DetailSection(title: title, rows: rows);

  int _sectionIndexByKey(String key) =>
      _sections.indexWhere((section) => section.key == key);

  bool _adminOrderHasAssignedCleaner(Map<String, dynamic> data) {
    return (data['cleanerId'] ?? data['assignedCleanerId'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
  }

  String _adminOrderDisplayStatus(Map<String, dynamic> data) {
    final status = (data['orderStatus'] ?? data['status'] ?? '—').toString();
    if (_adminOrderHasAssignedCleaner(data) &&
        {
          'pending_assignment',
          'searching',
          'pending',
          '—',
          '',
        }.contains(status.toLowerCase())) {
      return 'assigned';
    }
    return status;
  }

  String _adminOrderAssignmentText(Map<String, dynamic> data) {
    if (_adminOrderHasAssignedCleaner(data)) {
      return 'Назначена';
    }
    final status = (data['assignmentStatus'] ?? '').toString().trim();
    return status.isEmpty ? 'Ожидает назначения' : status;
  }

  String _orderStatusLabel(String status) {
    switch (status) {
      case 'pending_assignment':
        return 'Ожидает назначения';
      case 'pending_payment':
        return 'Ожидает оплату';
      case 'assigned':
        return 'Назначен';
      case 'confirmed':
        return 'Подтвержден';
      case 'in_progress':
        return 'В работе';
      case 'completed':
        return 'Завершен';
      case 'canceled':
      case 'cancelled':
        return 'Отменен';
      default:
        return orderStatusLabel(status, fallback: '—');
    }
  }

  Color _orderStatusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF047857);
      case 'canceled':
      case 'cancelled':
        return const Color(0xFFDC2626);
      case 'in_progress':
        return const Color(0xFF1D4ED8);
      case 'confirmed':
      case 'assigned':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFFD97706);
    }
  }

  String _houseStatusLabel(String status) {
    switch (status) {
      case 'ACTIVE':
        return 'Активен';
      case 'IN_PROGRESS':
      case 'ACTIVATING':
        return 'Подключается';
      default:
        return 'Ожидает запуска';
    }
  }

  String _cleanerVerificationLabel(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Одобрено';
      case 'rejected':
        return 'Отклонено';
      default:
        return 'На проверке';
    }
  }

  String _promotionRewardTargetLabel(String value) {
    return switch (value) {
      'all' => 'пакет и допы',
      _ => 'доп. услуги',
    };
  }

  String _formatCompactNumber(num value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _complaintStatusLabel(String status) {
    switch (status) {
      case 'resolved':
        return 'Закрыта';
      case 'compensated':
        return 'Компенсация';
      case 'refund':
        return 'Возврат';
      default:
        return 'Открыта';
    }
  }

  Color _complaintStatusColor(String status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFF047857);
      case 'compensated':
        return const Color(0xFF1D4ED8);
      case 'refund':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFFD97706);
    }
  }

  Color _paymentStatusColor(String status) {
    switch (status) {
      case 'paid':
      case 'success':
        return const Color(0xFF047857);
      case 'invoice_requested':
        return const Color(0xFFD97706);
      case 'failed':
      case 'canceled':
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  Color _payoutStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'paid':
      case 'completed':
        return const Color(0xFF047857);
      case 'rejected':
      case 'failed':
      case 'canceled':
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  String _payoutStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Одобрено';
      case 'paid':
      case 'completed':
        return 'Выплачено';
      case 'rejected':
        return 'Отклонено';
      case 'failed':
        return 'Ошибка';
      case 'requested':
      case 'pending':
        return 'На одобрении';
      default:
        return status.isEmpty ? 'На одобрении' : status;
    }
  }

  String _presenceLabel(String value) => value.isEmpty ? 'Нет' : 'Загружено';

  List<Map<String, double>> _geoPolygonFrom(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, double>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) {
          final lat = item['lat'];
          final lng = item['lng'];
          if (lat is! num || lng is! num) {
            return null;
          }
          return {'lat': lat.toDouble(), 'lng': lng.toDouble()};
        })
        .whereType<Map<String, double>>()
        .toList();
  }

  Map<String, double>? _geoPolygonCenter(List<Map<String, double>> polygon) {
    if (polygon.isEmpty) {
      return null;
    }
    final lat =
        polygon.fold<double>(0, (total, point) => total + (point['lat'] ?? 0)) /
            polygon.length;
    final lng =
        polygon.fold<double>(0, (total, point) => total + (point['lng'] ?? 0)) /
            polygon.length;
    return {'lat': lat, 'lng': lng};
  }

  bool _geoPointInPolygon({
    required double lat,
    required double lng,
    required List<Map<String, double>> polygon,
  }) {
    if (polygon.length < 3) {
      return false;
    }
    var inside = false;
    var j = polygon.length - 1;
    for (var i = 0; i < polygon.length; i += 1) {
      final yi = polygon[i]['lat'] ?? 0;
      final xi = polygon[i]['lng'] ?? 0;
      final yj = polygon[j]['lat'] ?? 0;
      final xj = polygon[j]['lng'] ?? 0;
      final intersects = ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1 : yj - yi) + xi);
      if (intersects) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  Map<String, dynamic>? _serviceZoneForPoint({
    required double lat,
    required double lng,
    required List<Map<String, dynamic>> zones,
  }) {
    for (final zone in zones) {
      final polygon = _geoPolygonFrom(zone['polygon']);
      if (_geoPointInPolygon(lat: lat, lng: lng, polygon: polygon)) {
        return zone;
      }
    }
    return null;
  }

  Future<int> _assignExistingHousesToZone(Map<String, dynamic> zone) async {
    final polygon = _geoPolygonFrom(zone['polygon']);
    if (polygon.length < 3) {
      return 0;
    }
    final zoneId = (zone['id'] ?? '').toString();
    final title = (zone['title'] ?? zoneId).toString();
    final houses = await _data.housesStream(admin: true).first;
    var changed = 0;
    for (final house in houses) {
      final lat = house['lat'];
      final lng = house['lng'];
      if (lat is! num || lng is! num) {
        continue;
      }
      if (!_geoPointInPolygon(
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        polygon: polygon,
      )) {
        continue;
      }
      final houseId = (house['id'] ?? '').toString();
      if (houseId.isEmpty) {
        continue;
      }
      await _data.upsertHouse(
        houseId: houseId,
        data: {
          ...house,
          'zoneId': zoneId,
          'serviceAreaId': zoneId,
          'serviceArea': title,
          'clusterName': title,
        },
      );
      changed += 1;
    }
    return changed;
  }

  Future<void> _openVideoEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final titleController = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final descriptionController = TextEditingController(
      text: (existing?['description'] ?? '').toString(),
    );
    final categoryController = TextEditingController(
      text: (existing?['category'] ?? '').toString(),
    );
    final thumbnailController = TextEditingController(
      text: (existing?['thumbnailUrl'] ?? '').toString(),
    );
    final videoController = TextEditingController(
      text: (existing?['videoUrl'] ?? '').toString(),
    );
    String audienceType = (existing?['audienceType'] ?? 'both').toString();
    bool isActive = existing?['isActive'] != false;
    bool isRequired = existing?['isRequired'] == true;
    bool isNew = existing?['isNew'] != false;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(docId == null ? 'Новое видео' : 'Редактировать видео'),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Заголовок'),
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Категория'),
                ),
                TextField(
                  controller: thumbnailController,
                  decoration: const InputDecoration(
                    labelText: 'Ссылка на превью',
                  ),
                ),
                TextField(
                  controller: videoController,
                  decoration: InputDecoration(labelText: 'Ссылка на видео'),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: audienceType,
                  items: [
                    DropdownMenuItem(
                      value: 'client',
                      child: Text('Клиенты'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'cleaner',
                      child: Text('Уборщицы'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'both',
                      child: Text('Обе роли'.tr()),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setModalState(() => audienceType = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Аудитория'),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    switch (audienceType) {
                      'client' =>
                        'Это видео увидят только клиенты. Уборщицы его не увидят.',
                      'cleaner' =>
                        'Это видео увидят только уборщицы. Клиенты его не увидят.',
                      _ => 'Это видео увидят и клиенты, и уборщицы.',
                    },
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (value) => setModalState(() => isActive = value),
                  title: Text('Активно'.tr()),
                ),
                SwitchListTile(
                  value: isRequired,
                  onChanged: (value) => setModalState(() => isRequired = value),
                  title: Text('Обязательное'.tr()),
                ),
                SwitchListTile(
                  value: isNew,
                  onChanged: (value) => setModalState(() => isNew = value),
                  title: Text('Новое'.tr()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final resolvedId =
                  (docId ?? 'video_${DateTime.now().millisecondsSinceEpoch}')
                      .toString();
              await _data.saveAdminVideo({
                'id': resolvedId,
                'audienceType': audienceType,
                'category': categoryController.text.trim(),
                'title': titleController.text.trim(),
                'description': descriptionController.text.trim(),
                'thumbnailUrl': thumbnailController.text.trim(),
                'videoUrl': videoController.text.trim(),
                'isActive': isActive,
                'isRequired': isRequired,
                'isNew': isNew,
                'version': existing?['version'] ?? 1,
                'publishedAt': FieldValue.serverTimestamp(),
                'createdAt': existing == null
                    ? FieldValue.serverTimestamp()
                    : (existing['createdAt'] ?? FieldValue.serverTimestamp()),
              });
              if (!mounted) return;
              navigator.pop();
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openPromoBannerEditor(
    BuildContext context, {
    required List<Map<String, dynamic>> banners,
    int? index,
    Map<String, dynamic>? existing,
  }) async {
    final titleController = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final subtitleController = TextEditingController(
      text: (existing?['subtitle'] ?? '').toString(),
    );
    final fullInfoController = TextEditingController(
      text: (existing?['fullInfo'] ??
              existing?['longDescription'] ??
              existing?['description'] ??
              '')
          .toString(),
    );
    final imageController = TextEditingController(
      text: (existing?['imageUrl'] ?? '').toString(),
    );
    final ctaLabelController = TextEditingController(
      text: (existing?['ctaLabel'] ?? '').toString(),
    );
    final initialRoute = (existing?['route'] ?? '').toString().trim();
    final routeLooksExternal = initialRoute.startsWith('http://') ||
        initialRoute.startsWith('https://');
    final initialExternalUrl =
        (existing?['externalUrl'] ?? '').toString().trim();
    final externalUrlController = TextEditingController(
      text: initialExternalUrl.isNotEmpty
          ? initialExternalUrl
          : (routeLooksExternal ? initialRoute : ''),
    );
    var targetMode = initialExternalUrl.isNotEmpty ? 'external' : 'route';
    if (routeLooksExternal) {
      targetMode = 'external';
    }
    final targetOptions = [
      ..._promoBannerTargets,
      if (!routeLooksExternal &&
          initialRoute.isNotEmpty &&
          !_promoBannerTargets.any((item) => item['route'] == initialRoute))
        {'label': 'Текущая страница', 'route': initialRoute},
    ];
    var selectedRoute = !routeLooksExternal &&
            targetOptions.any((item) => item['route'] == initialRoute)
        ? initialRoute
        : '';
    final sortOrderController = TextEditingController(
      text: ((existing?['sortOrder'] ?? (banners.length + 1)) as Object)
          .toString(),
    );
    bool isActive = existing?['isActive'] != false;

    var saving = false;
    var uploading = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(index == null ? 'Новый баннер' : 'Редактировать баннер'),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Заголовок'),
                ),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Краткое описание на баннере',
                  ),
                ),
                TextField(
                  controller: fullInfoController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Описание в модальном окне',
                    hintText: 'Что входит, условия, подробности акции',
                  ),
                ),
                TextField(
                  controller: imageController,
                  decoration: const InputDecoration(
                    labelText: 'Ссылка на картинку',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (uploading || saving) return;
                          setDialogState(() => uploading = true);
                          try {
                            final url = await _photoUploadService.pickAndUpload(folder: 'promo_banners', filePrefix: 'banner');
                            if (url != null && context.mounted) setModalState(() => imageController.text = url);
                          } catch (error) {
                            if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(UserErrorMessage.message(error))));
                          } finally {
                            if (dialogContext.mounted) setDialogState(() => uploading = false);
                          }
                        },
                        icon: const Icon(Icons.upload_outlined),
                        label: Text('Загрузить фото'.tr()),
                      ),
                    ),
                  ],
                ),
                if (imageController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageController.text.trim(),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                TextField(
                  controller: ctaLabelController,
                  decoration: const InputDecoration(labelText: 'Текст кнопки'),
                ),
                SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'route',
                      label: Text('Страница'.tr()),
                      icon: Icon(Icons.apps_outlined),
                    ),
                    ButtonSegment<String>(
                      value: 'external',
                      label: Text('Ссылка'.tr()),
                      icon: Icon(Icons.open_in_new),
                    ),
                  ],
                  selected: {targetMode},
                  onSelectionChanged: (value) {
                    setModalState(() => targetMode = value.first);
                  },
                ),
                if (targetMode == 'route') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRoute,
                    decoration: const InputDecoration(
                      labelText: 'Страница приложения',
                    ),
                    items: targetOptions
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item['route'] ?? '',
                            child: Text(item['label'] ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setModalState(() => selectedRoute = value ?? '');
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: externalUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Ссылка на сторонний сайт',
                      hintText: 'https://example.com',
                    ),
                  ),
                ],
                TextField(
                  controller: sortOrderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Порядок'),
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (value) => setModalState(() => isActive = value),
                  title: Text('Активен'.tr()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving || uploading ? null : () => Navigator.pop(dialogContext),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: saving || uploading ? null : () async {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Укажите заголовок баннера.')));
                return;
              }
              setDialogState(() => saving = true);
              final navigator = Navigator.of(dialogContext);
              final rawExternalUrl = externalUrlController.text.trim();
              final externalUrl = rawExternalUrl.isEmpty ||
                      rawExternalUrl.startsWith('http://') ||
                      rawExternalUrl.startsWith('https://')
                  ? rawExternalUrl
                  : 'https://$rawExternalUrl';
              final banner = <String, dynamic>{
                ...?(existing),
                'id': (existing?['id'] ??
                        'banner_${DateTime.now().millisecondsSinceEpoch}')
                    .toString(),
                'title': titleController.text.trim(),
                'subtitle': subtitleController.text.trim(),
                'description': fullInfoController.text.trim(),
                'fullInfo': fullInfoController.text.trim(),
                'imageUrl': imageController.text.trim(),
                'ctaLabel': ctaLabelController.text.trim(),
                'route': targetMode == 'route' ? selectedRoute.trim() : '',
                'externalUrl': targetMode == 'external' ? externalUrl : '',
                'sortOrder':
                    int.tryParse(sortOrderController.text.trim()) ?? 999,
                'isActive': isActive,
              };
              try {
                await _data.saveAdminPromoBanner(banner);
                if (!dialogContext.mounted) return;
                navigator.pop();
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(UserErrorMessage.message(error))));
              } finally {
                if (dialogContext.mounted) setDialogState(() => saving = false);
              }
            },
            child: Text(saving ? 'Сохранение…' : 'Сохранить'.tr()),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _openPromotionEditor(
    BuildContext context, {
    required List<Map<String, dynamic>> packages,
    Map<String, dynamic>? existing,
  }) async {
    final idController = TextEditingController(
      text:
          (existing?['id'] ?? 'promo_${DateTime.now().millisecondsSinceEpoch}')
              .toString(),
    );
    final titleController = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final shortInfoController = TextEditingController(
      text:
          (existing?['shortInfo'] ?? existing?['description'] ?? '').toString(),
    );
    final fullInfoController = TextEditingController(
      text: (existing?['fullInfo'] ?? existing?['longDescription'] ?? '')
          .toString(),
    );
    final homeBannerImageController = TextEditingController(
      text: (existing?['homeBannerImageUrl'] ??
              existing?['bannerImageUrl'] ??
              existing?['imageUrl'] ??
              '')
          .toString(),
    );
    List<String> textList(Object? value) {
      if (value is List) {
        return value.map((item) => item.toString()).toList();
      }
      final text = (value ?? '').toString().trim();
      return text.isEmpty ? const <String>[] : text.split('\n');
    }

    final featuresController = TextEditingController(
      text: textList(existing?['features']).join('\n'),
    );
    final exclusionsController = TextEditingController(
      text: textList(existing?['exclusions']).join('\n'),
    );
    final fixedRewardController = TextEditingController(
      text: '${existing?['rewardAmount'] ?? 15000}',
    );
    final percentRewardController = TextEditingController(
      text: '${existing?['rewardPercent'] ?? 10}',
    );
    final maxSpendController = TextEditingController(
      text: '${existing?['maxSpendPercent'] ?? 50}',
    );
    var packageId = (existing?['packageId'] ?? '').toString();
    var rewardTarget = (existing?['rewardTarget'] ?? 'addons').toString();
    var rewardMode = (existing?['rewardMode'] ?? 'fixed').toString();
    if (rewardMode != 'percent') {
      rewardMode = 'fixed';
    }
    var isActive = existing?['isActive'] != false;
    var oncePerCustomer = existing?['oncePerCustomer'] != false;
    var showBannerTitle = existing?['showBannerTitle'] != false;
    var showBannerShortInfo = existing?['showBannerShortInfo'] != false;
    var showBannerReward = existing?['showBannerReward'] != false;
    var showBannerInfoIcon = existing?['showBannerInfoIcon'] != false;

    var saving = false;
    var uploading = false;
    String? errorText;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedPackageExists = packages.any(
            (item) => (item['id'] ?? '').toString() == packageId,
          );
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null
                        ? 'Новая акция'
                        : 'Редактирование акции',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: idController,
                    readOnly: existing != null,
                    decoration: const InputDecoration(labelText: 'ID акции'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Важная информация',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: shortInfoController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Краткий текст',
                      hintText: 'Короткий текст для главной',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fullInfoController,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Подробное описание',
                      hintText: 'Полный текст важной информации',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: homeBannerImageController,
                    decoration: const InputDecoration(
                      labelText: 'Фото баннера на главной',
                      hintText: 'Ссылка на картинку или загрузите фото ниже',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            if (uploading || saving) return;
                            setSheetState(() { uploading = true; errorText = null; });
                            try {
                              final url = await _photoUploadService.pickAndUpload(folder: 'promotion_home_banners', filePrefix: 'promotion');
                              if (url != null && context.mounted) setSheetState(() => homeBannerImageController.text = url);
                            } catch (error) {
                              if (context.mounted) setSheetState(() => errorText = UserErrorMessage.message(error));
                            } finally {
                              if (context.mounted) setSheetState(() => uploading = false);
                            }
                          },
                          icon: const Icon(Icons.upload_outlined),
                          label: Text('Загрузить фото баннера'.tr()),
                        ),
                      ),
                    ],
                  ),
                  if (homeBannerImageController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        homeBannerImageController.text.trim(),
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Что показывать на главной'.tr(),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SwitchListTile(
                    value: showBannerTitle,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Название'.tr()),
                    onChanged: (value) =>
                        setSheetState(() => showBannerTitle = value),
                  ),
                  SwitchListTile(
                    value: showBannerShortInfo,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Краткий текст'.tr()),
                    onChanged: (value) =>
                        setSheetState(() => showBannerShortInfo = value),
                  ),
                  SwitchListTile(
                    value: showBannerReward,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Бонус / выгода'.tr()),
                    onChanged: (value) =>
                        setSheetState(() => showBannerReward = value),
                  ),
                  SwitchListTile(
                    value: showBannerInfoIcon,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Кнопка информации'.tr()),
                    onChanged: (value) =>
                        setSheetState(() => showBannerInfoIcon = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: featuresController,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Что входит (по одному пункту на строке)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: exclusionsController,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Что не входит (по одному пункту на строке)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPackageExists ? packageId : '',
                    decoration: const InputDecoration(labelText: 'Пакет'),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text('Любой пакет'.tr()),
                      ),
                      ...packages.map(
                        (item) => DropdownMenuItem(
                          value: (item['id'] ?? '').toString(),
                          child: Text(
                            '${item['name'] ?? item['id']} · ${item['price'] ?? 0} ₸',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => packageId = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: rewardTarget,
                    decoration: InputDecoration(labelText: 'Куда дать бонус'),
                    items: [
                      DropdownMenuItem(
                        value: 'addons',
                        child: Text('На доп. услуги'.tr()),
                      ),
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('На пакет и допы'.tr()),
                      ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => rewardTarget = value ?? 'addons'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: rewardMode,
                    decoration: InputDecoration(labelText: 'Тип начисления'),
                    items: [
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text('Фиксированная сумма'.tr()),
                      ),
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text('Процент от оплаты'.tr()),
                      ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => rewardMode = value ?? 'fixed'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rewardMode == 'percent'
                        ? percentRewardController
                        : fixedRewardController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: rewardMode == 'percent'
                          ? 'Процент бонуса, %'
                          : 'Сумма бонуса, ₸',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxSpendController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Максимум оплаты бонусами, %',
                    ),
                  ),
                  SwitchListTile(
                    value: oncePerCustomer,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Начислять один раз на клиента'.tr()),
                    onChanged: (value) =>
                        setSheetState(() => oncePerCustomer = value),
                  ),
                  SwitchListTile(
                    value: isActive,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Акция активна'.tr()),
                    onChanged: (value) => setSheetState(() => isActive = value),
                  ),
                  const SizedBox(height: 16),
                  if (errorText != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(errorText!, style: const TextStyle(color: Colors.red))),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: saving || uploading ? null : () async {
                        final id = idController.text.trim();
                        if (id.isEmpty || titleController.text.trim().isEmpty) {
                          setSheetState(() => errorText = 'Укажите ID и название акции.');
                          return;
                        }
                        setSheetState(() { saving = true; errorText = null; });
                        final selectedPackage = packages.firstWhere(
                          (item) => (item['id'] ?? '').toString() == packageId,
                          orElse: () => const <String, dynamic>{},
                        );
                        try {
                        await _data.saveAdminPromotion({
                          ...?existing,
                          'id': id,
                          'title': titleController.text.trim().isEmpty
                              ? 'Важная информация'
                              : titleController.text.trim(),
                          'shortInfo': shortInfoController.text.trim(),
                          'description': shortInfoController.text.trim(),
                          'fullInfo': fullInfoController.text.trim(),
                          'longDescription': fullInfoController.text.trim(),
                          'homeBannerImageUrl':
                              homeBannerImageController.text.trim(),
                          'bannerImageUrl':
                              homeBannerImageController.text.trim(),
                          'showBannerTitle': showBannerTitle,
                          'showBannerShortInfo': showBannerShortInfo,
                          'showBannerReward': showBannerReward,
                          'showBannerInfoIcon': showBannerInfoIcon,
                          'features': featuresController.text
                              .split('\n')
                              .map((item) => item.trim())
                              .where((item) => item.isNotEmpty)
                              .toList(),
                          'exclusions': exclusionsController.text
                              .split('\n')
                              .map((item) => item.trim())
                              .where((item) => item.isNotEmpty)
                              .toList(),
                          'type': 'package_purchase_bonus',
                          'packageId': packageId,
                          'packageName': packageId.isEmpty
                              ? 'Любой пакет'
                              : (selectedPackage['name'] ?? packageId)
                                  .toString(),
                          'rewardType': 'bonus_points',
                          'rewardTarget': rewardTarget,
                          'rewardMode': rewardMode,
                          'rewardAmount': rewardMode == 'fixed'
                              ? num.tryParse(
                                    fixedRewardController.text.trim().replaceAll(',', '.'),
                                  ) ??
                                  0
                              : 0,
                          'rewardPercent': rewardMode == 'percent'
                              ? double.tryParse(
                                    percentRewardController.text
                                        .trim()
                                        .replaceAll(',', '.'),
                                  ) ??
                                  0
                              : 0,
                          'maxSpendPercent':
                              num.tryParse(maxSpendController.text.trim().replaceAll(',', '.')) ??
                                  50,
                          'oncePerCustomer': oncePerCustomer,
                          'isActive': isActive,
                        });
                        if (context.mounted) Navigator.pop(context);
                        } catch (error) {
                          if (context.mounted) setSheetState(() => errorText = UserErrorMessage.message(error));
                        } finally {
                          if (context.mounted) setSheetState(() => saving = false);
                        }
                      },
                      child: Text(saving ? 'Сохранение…' : 'Сохранить акцию'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPoliciesEditor(
    BuildContext context,
    Map<String, dynamic> existing,
  ) async {
    final referralBonusController = TextEditingController(
      text: '${existing['referralBonusAmount'] ?? 2000}',
    );
    final packagePurchaseBonusController = TextEditingController(
      text: '${existing['packagePurchaseBonusAmount'] ?? 10000}',
    );
    var packagePurchaseBonusEnabled =
        existing['packagePurchaseBonusEnabled'] == true;
    final thresholdController = TextEditingController(
      text: '${existing['defaultHouseThreshold'] ?? 20}',
    );
    final toleranceController = TextEditingController(
      text: '${existing['areaVerificationTolerance'] ?? 0}',
    );
    final cleaningMinutesPerSqmController = TextEditingController(
      text: '${existing['cleaningMinutesPerSqm'] ?? 1.6}',
    );
    final cleaningBaseMinutesController = TextEditingController(
      text: '${existing['cleaningBaseMinutes'] ?? 30}',
    );
    final cleaningMinMinutesController = TextEditingController(
      text: '${existing['cleaningMinMinutes'] ?? 120}',
    );
    final cleaningMaxMinutesController = TextEditingController(
      text: '${existing['cleaningMaxMinutes'] ?? 480}',
    );
    final reliableAreaController = TextEditingController(
      text: '${existing['cleanerReliableAreaThreshold'] ?? 12000}',
    );
    final reliableBonusController = TextEditingController(
      text: '${existing['cleanerReliableBonusAmount'] ?? 100000}',
    );
    final expertAreaController = TextEditingController(
      text: '${existing['cleanerExpertAreaThreshold'] ?? 30000}',
    );
    final expertBonusController = TextEditingController(
      text: '${existing['cleanerExpertBonusAmount'] ?? 200000}',
    );
    final legendAreaController = TextEditingController(
      text: '${existing['cleanerLegendAreaThreshold'] ?? 65000}',
    );
    final legendBonusController = TextEditingController(
      text: '${existing['cleanerLegendBonusAmount'] ?? 500000}',
    );
    final weeklyAreaThresholdController = TextEditingController(
      text: '${existing['cleanerWeeklyAreaThreshold'] ?? 1300}',
    );
    final weeklyAreaBonusController = TextEditingController(
      text: '${existing['cleanerWeeklyAreaBonusAmount'] ?? 5000}',
    );
    final addonThreshold1Controller = TextEditingController(
      text: '${existing['cleanerWeeklyAddonBonusThreshold1'] ?? 30000}',
    );
    final addonBonus1Controller = TextEditingController(
      text: '${existing['cleanerWeeklyAddonBonusAmount1'] ?? 4000}',
    );
    final addonThreshold2Controller = TextEditingController(
      text: '${existing['cleanerWeeklyAddonBonusThreshold2'] ?? 50000}',
    );
    final addonBonus2Controller = TextEditingController(
      text: '${existing['cleanerWeeklyAddonBonusAmount2'] ?? 6000}',
    );
    final dailyIncomeController = TextEditingController(
      text: '${existing['cleanerDailyIncome'] ?? 13500}',
    );
    final sqmRateController = TextEditingController(
      text: '${existing['cleanerSqmRate'] ?? 60}',
    );
    final weeklyCashoutPercentController = TextEditingController(
      text: '${existing['cleanerWeeklyCashoutPercent'] ?? 30}',
    );
    final weeklyCooldownController = TextEditingController(
      text: '${existing['cleanerWeeklyCashoutCooldownDays'] ?? 7}',
    );
    final fullCooldownController = TextEditingController(
      text: '${existing['cleanerFullCashoutCooldownDays'] ?? 30}',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Политики'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: referralBonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Сумма реферального бонуса',
                ),
              ),
              SwitchListTile(
                value: packagePurchaseBonusEnabled,
                onChanged: (value) {
                  packagePurchaseBonusEnabled = value;
                  (context as Element).markNeedsBuild();
                },
                title: Text('Акция: бонус за покупку пакета'.tr()),
                subtitle: Text(
                  'Если включено, после оплаты пакета клиенту начислятся бонусы.'
                      .tr(),
                ),
              ),
              TextField(
                controller: packagePurchaseBonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Акция: сумма бонуса за пакет',
                ),
              ),
              TextField(
                controller: thresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Порог активации дома',
                ),
              ),
              TextField(
                controller: toleranceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Допуск проверки площади',
                ),
              ),
              TextField(
                controller: cleaningMinutesPerSqmController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Время на 1 м², минут',
                  helperText: 'Например: 1.6',
                ),
              ),
              TextField(
                controller: cleaningBaseMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Базовое время на заказ, минут',
                ),
              ),
              TextField(
                controller: cleaningMinMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Минимальная длительность, минут',
                ),
              ),
              TextField(
                controller: cleaningMaxMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Максимальная длительность, минут',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reliableAreaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Надежная: порог м²',
                ),
              ),
              TextField(
                controller: reliableBonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Надежная: бонус'),
              ),
              TextField(
                controller: expertAreaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Эксперт: порог м²',
                ),
              ),
              TextField(
                controller: expertBonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Эксперт: бонус'),
              ),
              TextField(
                controller: legendAreaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Легенда: порог м²',
                ),
              ),
              TextField(
                controller: legendBonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Легенда: бонус'),
              ),
              TextField(
                controller: weeklyAreaThresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Еженедельный бонус: порог м²',
                ),
              ),
              TextField(
                controller: weeklyAreaBonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Еженедельный бонус: сумма',
                ),
              ),
              TextField(
                controller: addonThreshold1Controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Доп. услуги 1: порог',
                ),
              ),
              TextField(
                controller: addonBonus1Controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Доп. услуги 1: бонус',
                ),
              ),
              TextField(
                controller: addonThreshold2Controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Доп. услуги 2: порог',
                ),
              ),
              TextField(
                controller: addonBonus2Controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Доп. услуги 2: бонус',
                ),
              ),
              TextField(
                controller: dailyIncomeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ставка за рабочий день (для плана)',
                ),
              ),
              TextField(
                controller: sqmRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Тариф уборщицы за 1 м²',
                ),
              ),
              TextField(
                controller: weeklyCashoutPercentController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Недельный вывод, %',
                ),
              ),
              TextField(
                controller: weeklyCooldownController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Недельный вывод: каждые N дней',
                ),
              ),
              TextField(
                controller: fullCooldownController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Полный вывод: каждые N дней',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _data.updateAdminPolicies({
                'referralBonusAmount':
                    int.tryParse(referralBonusController.text.trim()) ?? 2000,
                'packagePurchaseBonusEnabled': packagePurchaseBonusEnabled,
                'packagePurchaseBonusAmount':
                    int.tryParse(packagePurchaseBonusController.text.trim()) ??
                        10000,
                'defaultHouseThreshold':
                    int.tryParse(thresholdController.text.trim()) ?? 20,
                'areaVerificationTolerance':
                    int.tryParse(toleranceController.text.trim()) ?? 0,
                'cleaningMinutesPerSqm': double.tryParse(
                      cleaningMinutesPerSqmController.text.trim().replaceAll(
                            ',',
                            '.',
                          ),
                    ) ??
                    1.6,
                'cleaningBaseMinutes':
                    int.tryParse(cleaningBaseMinutesController.text.trim()) ??
                        30,
                'cleaningMinMinutes':
                    int.tryParse(cleaningMinMinutesController.text.trim()) ??
                        120,
                'cleaningMaxMinutes':
                    int.tryParse(cleaningMaxMinutesController.text.trim()) ??
                        480,
                'cleanerReliableAreaThreshold':
                    int.tryParse(reliableAreaController.text.trim()) ?? 12000,
                'cleanerReliableBonusAmount':
                    int.tryParse(reliableBonusController.text.trim()) ?? 100000,
                'cleanerExpertAreaThreshold':
                    int.tryParse(expertAreaController.text.trim()) ?? 30000,
                'cleanerExpertBonusAmount':
                    int.tryParse(expertBonusController.text.trim()) ?? 200000,
                'cleanerLegendAreaThreshold':
                    int.tryParse(legendAreaController.text.trim()) ?? 65000,
                'cleanerLegendBonusAmount':
                    int.tryParse(legendBonusController.text.trim()) ?? 500000,
                'cleanerWeeklyAreaThreshold':
                    int.tryParse(weeklyAreaThresholdController.text.trim()) ??
                        1300,
                'cleanerWeeklyAreaBonusAmount':
                    int.tryParse(weeklyAreaBonusController.text.trim()) ?? 5000,
                'cleanerWeeklyAddonBonusThreshold1':
                    int.tryParse(addonThreshold1Controller.text.trim()) ??
                        30000,
                'cleanerWeeklyAddonBonusAmount1':
                    int.tryParse(addonBonus1Controller.text.trim()) ?? 4000,
                'cleanerWeeklyAddonBonusThreshold2':
                    int.tryParse(addonThreshold2Controller.text.trim()) ??
                        50000,
                'cleanerWeeklyAddonBonusAmount2':
                    int.tryParse(addonBonus2Controller.text.trim()) ?? 6000,
                'cleanerDailyIncome':
                    int.tryParse(dailyIncomeController.text.trim()) ?? 13500,
                'cleanerSqmRate':
                    int.tryParse(sqmRateController.text.trim()) ?? 60,
                'cleanerWeeklyCashoutPercent':
                    int.tryParse(weeklyCashoutPercentController.text.trim()) ??
                        30,
                'cleanerWeeklyCashoutCooldownDays':
                    int.tryParse(weeklyCooldownController.text.trim()) ?? 7,
                'cleanerFullCashoutCooldownDays':
                    int.tryParse(fullCooldownController.text.trim()) ?? 30,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (!mounted) return;
              navigator.pop();
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openInfoContentEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final keyController = TextEditingController(
      text: (docId ?? existing?['key'] ?? '').toString(),
    );
    final titleController = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final shortInfoController = TextEditingController(
      text: (existing?['shortInfo'] ?? '').toString(),
    );
    final fullInfoController = TextEditingController(
      text: (existing?['fullInfo'] ?? '').toString(),
    );
    final priceController = TextEditingController(
      text: existing?['price'] != null ? '${existing?['price']}' : '',
    );
    final sortOrderController = TextEditingController(
      text: '${existing?['sortOrder'] ?? 999}',
    );
    String type = (existing?['type'] ?? 'info').toString();
    bool isActive = existing?['isActive'] != false;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          docId == null ? 'Новая карточка' : 'Редактировать карточку',
        ),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: keyController,
                    enabled: docId == null,
                    decoration: const InputDecoration(labelText: 'Ключ'),
                  ),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Заголовок'),
                  ),
                  TextField(
                    controller: shortInfoController,
                    decoration: const InputDecoration(
                      labelText: 'Короткая информация',
                    ),
                  ),
                  TextField(
                    controller: fullInfoController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(labelText: 'Полная информация'),
                  ),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Цена'),
                  ),
                  TextField(
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Порядок'),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: [
                      DropdownMenuItem(
                        value: 'package',
                        child: Text('Пакет'.tr()),
                      ),
                      DropdownMenuItem(
                        value: 'addon',
                        child: Text('Доп. услуга'.tr()),
                      ),
                      DropdownMenuItem(
                        value: 'ui_text',
                        child: Text('UI текст'.tr()),
                      ),
                      DropdownMenuItem(
                        value: 'legal',
                        child: Text('Правовой документ'.tr()),
                      ),
                      DropdownMenuItem(
                        value: 'info',
                        child: Text('Прочее'.tr()),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => type = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Тип'),
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) => setModalState(() => isActive = value),
                    title: Text('Активно'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final key = keyController.text.trim();
              if (key.isEmpty) {
                return;
              }
              await _data.saveAdminInfoContent({
                'id': key,
                'key': key,
                'title': titleController.text.trim(),
                'shortInfo': shortInfoController.text.trim(),
                'fullInfo': fullInfoController.text.trim(),
                'price': int.tryParse(priceController.text.trim()),
                'sortOrder':
                    int.tryParse(sortOrderController.text.trim()) ?? 999,
                'type': type,
                'isActive': isActive,
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': existing == null
                    ? FieldValue.serverTimestamp()
                    : (existing['createdAt'] ?? FieldValue.serverTimestamp()),
              });
              if (!mounted) return;
              navigator.pop();
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openPackageEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final initial = Map<String, dynamic>.from(existing ?? const {});
    final idController = TextEditingController(text: (docId ?? '').toString());
    final nameController = TextEditingController(
      text: (initial['name'] ?? '').toString(),
    );
    final frequencyController = TextEditingController(
      text: (initial['frequency'] ?? '').toString(),
    );
    final priceController = TextEditingController(
      text: initial['price'] != null ? '${initial['price']}' : '0',
    );
    final sortOrderController = TextEditingController(
      text: '${initial['sortOrder'] ?? 999}',
    );
    final cleaningsController = TextEditingController(
      text: initial['cleaningsPerMonth'] != null
          ? '${initial['cleaningsPerMonth']}'
          : '',
    );
    final billingController = TextEditingController(
      text: '${initial['billingPeriodMonths'] ?? 1}',
    );
    final discountController = TextEditingController(
      text: '${initial['discountPercent'] ?? 0}',
    );
    final featuresController = TextEditingController(
      text: (initial['features'] as List?)
              ?.map((item) => item.toString())
              .join('\n') ??
          '',
    );
    final shortInfoController = TextEditingController(
      text: (initial['shortInfo'] ?? '').toString(),
    );
    final fullInfoController = TextEditingController(
      text: (initial['fullInfo'] ?? '').toString(),
    );
    bool isActive = initial['isActive'] != false;
    bool isPopular = initial['popular'] == true;
    bool isQuarterly = initial['isQuarterly'] == true;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(docId == null ? 'Новый пакет' : 'Редактировать пакет'),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    enabled: docId == null,
                    decoration: const InputDecoration(labelText: 'ID пакета'),
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название пакета',
                    ),
                  ),
                  TextField(
                    controller: frequencyController,
                    decoration: const InputDecoration(
                      labelText: 'Частота / подпись',
                    ),
                  ),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Цена за м² за одну уборку, ₸'),
                  ),
                  TextField(
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Порядок'),
                  ),
                  TextField(
                    controller: cleaningsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Уборок в месяц',
                    ),
                  ),
                  TextField(
                    controller: billingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Период выставления, мес.',
                    ),
                  ),
                  TextField(
                    controller: discountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Скидка, %'),
                  ),
                  TextField(
                    controller: featuresController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Что входит (по строкам)',
                    ),
                  ),
                  TextField(
                    controller: shortInfoController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Короткое описание в окне информации',
                      hintText: 'Например: Информация по пакету',
                    ),
                  ),
                  TextField(
                    controller: fullInfoController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Полное описание',
                      hintText: 'Подробно опишите пакет, условия и ограничения',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) => setModalState(() => isActive = value),
                    title: Text('Активно'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: isPopular,
                    onChanged: (value) =>
                        setModalState(() => isPopular = value),
                    title: Text('Популярный'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: isQuarterly,
                    onChanged: (value) =>
                        setModalState(() => isQuarterly = value),
                    title: Text('Квартальный пакет'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final id = idController.text.trim();
              if (id.isEmpty) {
                return;
              }
              await _data.saveAdminPackage({
                ...initial,
                'id': id,
                'name': nameController.text.trim(),
                'frequency': frequencyController.text.trim(),
                'price': int.tryParse(priceController.text.trim()) ?? 0,
                'sortOrder':
                    int.tryParse(sortOrderController.text.trim()) ?? 999,
                'cleaningsPerMonth': int.tryParse(
                  cleaningsController.text.trim(),
                ),
                'billingPeriodMonths':
                    int.tryParse(billingController.text.trim()) ?? 1,
                'discountPercent':
                    int.tryParse(discountController.text.trim()) ?? 0,
                'features': featuresController.text
                    .split('\n')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(),
                'shortInfo': shortInfoController.text.trim(),
                'fullInfo': fullInfoController.text.trim(),
                'isActive': isActive,
                'popular': isPopular,
                'isQuarterly': isQuarterly,
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': existing == null
                    ? FieldValue.serverTimestamp()
                    : (existing['createdAt'] ?? FieldValue.serverTimestamp()),
              });
              if (!mounted) return;
              navigator.pop();
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _addonCatalog() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminAddonGroupsStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        final query = _searchQuery.trim().toLowerCase();
        final filtered = docs.where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          final items = ((data['items'] ?? const []) as List)
              .map((item) => item.toString())
              .join(' ');
          final haystack =
              '${data['id'] ?? data['key'] ?? ''} ${data['label'] ?? ''} ${data['note'] ?? ''} $items'
                  .toLowerCase();
          return query.isEmpty || haystack.contains(query);
        }).toList();

        return _sectionScaffold(
          toolbar: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: !_canEditCatalog
                    ? null
                    : () => _openAddonGroupEditor(context),
                icon: const Icon(Icons.add),
                label: Text('Добавить группу'.tr()),
              ),
              OutlinedButton.icon(
                onPressed:
                    !_canEditCatalog ? null : () => _syncDefaultAddonCatalog(),
                icon: const Icon(Icons.sync_outlined),
                label: Text('Заполнить по умолчанию'.tr()),
              ),
            ],
          ),
          child: filtered.isEmpty
              ? _emptyState(
                  'Каталог допуслуг пуст',
                  'Добавьте группы вручную или заполните дефолтный каталог.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filtered[index];
                    final docId = (data['id'] ?? data['key'] ?? '').toString();
                    final items = ((data['items'] ?? const []) as List)
                        .whereType<Map>()
                        .map((item) => Map<String, dynamic>.from(item))
                        .toList()
                      ..sort((a, b) {
                        final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
                        final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
                        return aOrder.compareTo(bOrder);
                      });
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        color: const Color(0xFFFCFDFE),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusBadge(
                                data['isActive'] == false
                                    ? 'Скрыто'
                                    : 'Активно',
                                color: data['isActive'] == false
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF047857),
                              ),
                              _statusBadge(
                                '${items.length} позиций',
                                color: const Color(0xFF1D4ED8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            (data['label'] ?? docId).toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          if ((data['note'] ?? '').toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                (data['note'] ?? '').toString(),
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          ...items.map((item) {
                            final key = (item['key'] ?? '').toString();
                            final price = (item['price'] as num?)?.toInt() ?? 0;
                            final duration =
                                (item['durationMinutes'] as num?)?.toInt() ??
                                    15;
                            final infoPreview = [
                              item['shortInfo'],
                              item['description'],
                              item['fullInfo'],
                              item['longDescription'],
                            ]
                                .map(
                                  (value) => (value ?? '').toString().trim(),
                                )
                                .firstWhere(
                                  (value) => value.isNotEmpty,
                                  orElse: () => '',
                                );
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (item['label'] ?? key).toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$price ₸'
                                          ' · $duration мин'
                                          '${item['supportsQuantity'] == true ? ' · количество' : ''}'
                                          '${item['separatePayment'] == true ? ' · отдельно' : ''}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                        if (infoPreview.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            infoPreview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: !_canEditCatalog
                                        ? null
                                        : () => _openAddonItemEditor(
                                              context,
                                              groupId: docId,
                                              groupData: data,
                                              existing: item,
                                            ),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    onPressed: !_canEditCatalog
                                        ? null
                                        : () => _deleteAddonItem(
                                              docId,
                                              data,
                                              key,
                                            ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: !_canEditCatalog
                                    ? null
                                    : () => _openAddonItemEditor(
                                          context,
                                          groupId: docId,
                                          groupData: data,
                                        ),
                                icon: const Icon(Icons.add),
                                label: Text('Добавить позицию'.tr()),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: !_canEditCatalog
                                    ? null
                                    : () => _openAddonGroupEditor(
                                          context,
                                          docId: docId,
                                          existing: data,
                                        ),
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _checklistTemplates() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.adminChecklistTemplatesStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        final query = _searchQuery.trim().toLowerCase();
        final filtered = docs.where((data) {
          if (!_matchesRecordDateRange(data)) {
            return false;
          }
          final items = ((data['items'] ?? const []) as List).join(' ');
          final haystack =
              '${data['id'] ?? data['key'] ?? ''} ${data['title'] ?? ''} ${data['description'] ?? ''} $items'
                  .toLowerCase();
          return query.isEmpty || haystack.contains(query);
        }).toList();
        return _sectionScaffold(
          toolbar: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: !_canEditCatalog
                    ? null
                    : () => _openChecklistTemplateEditor(context),
                icon: const Icon(Icons.add),
                label: Text('Добавить шаблон'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: !_canEditCatalog
                    ? null
                    : () => _syncDefaultChecklistTemplates(),
                icon: const Icon(Icons.sync_outlined),
                label: Text('Заполнить по умолчанию'.tr()),
              ),
            ],
          ),
          child: filtered.isEmpty
              ? _emptyState(
                  'Шаблоны чек-листа пусты',
                  'Добавьте шаблоны вручную или заполните дефолтные.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filtered[index];
                    final docId = (data['id'] ?? data['key'] ?? '').toString();
                    final items = ((data['items'] ?? const []) as List)
                        .map((item) => item.toString())
                        .where((item) => item.trim().isNotEmpty)
                        .toList();
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        color: const Color(0xFFFCFDFE),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusBadge(
                                data['isActive'] == false
                                    ? 'Скрыто'
                                    : 'Активно',
                                color: data['isActive'] == false
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF047857),
                              ),
                              _statusBadge(
                                '${items.length} пунктов',
                                color: const Color(0xFF1D4ED8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            (data['title'] ?? docId).toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          if ((data['description'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                (data['description'] ?? '').toString(),
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            items.join(' • '),
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'id: $docId',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: !_canEditCatalog
                                    ? null
                                    : () => _openChecklistTemplateEditor(
                                          context,
                                          docId: docId,
                                          existing: data,
                                        ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _syncDefaultAddonCatalog() async {
    if (!_canEditCatalog) {
      return;
    }
    await _data.syncDefaultAdminAddonCatalog();
  }

  Future<void> _syncDefaultChecklistTemplates() async {
    if (!_canEditCatalog) {
      return;
    }
    await _data.syncDefaultAdminChecklistTemplates();
  }

  Future<void> _openAddonGroupEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final idController = TextEditingController(text: (docId ?? '').toString());
    final labelController = TextEditingController(
      text: (existing?['label'] ?? '').toString(),
    );
    final noteController = TextEditingController(
      text: (existing?['note'] ?? '').toString(),
    );
    final sortOrderController = TextEditingController(
      text: '${existing?['sortOrder'] ?? 999}',
    );
    bool isActive = existing?['isActive'] != false;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          docId == null ? 'Новая группа допуслуг' : 'Редактировать группу',
        ),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    enabled: docId == null,
                    decoration: const InputDecoration(
                      labelText: 'ID группы',
                      hintText: 'Можно не заполнять, создадим автоматически',
                    ),
                  ),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Подпись / описание',
                    ),
                  ),
                  TextField(
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Порядок'),
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) => setModalState(() => isActive = value),
                    title: Text('Активно'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final key = _adminSlug(
                idController.text,
                fallbackText: labelController.text,
                prefix: 'addon_group',
              );
              await _data.saveAdminAddonGroup({
                'key': key,
                'label': labelController.text.trim(),
                'note': noteController.text.trim(),
                'sortOrder':
                    int.tryParse(sortOrderController.text.trim()) ?? 999,
                'isActive': isActive,
                'items': existing?['items'] ?? const [],
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': existing == null
                    ? FieldValue.serverTimestamp()
                    : (existing['createdAt'] ?? FieldValue.serverTimestamp()),
              });
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Группа доп. услуг сохранена'.tr())),
              );
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddonItemEditor(
    BuildContext context, {
    required String groupId,
    required Map<String, dynamic> groupData,
    Map<String, dynamic>? existing,
  }) async {
    final keyController = TextEditingController(
      text: (existing?['key'] ?? '').toString(),
    );
    final labelController = TextEditingController(
      text: (existing?['label'] ?? '').toString(),
    );
    final noteController = TextEditingController(
      text: (existing?['note'] ?? '').toString(),
    );
    final shortInfoController = TextEditingController(
      text:
          (existing?['shortInfo'] ?? existing?['description'] ?? '').toString(),
    );
    final fullInfoController = TextEditingController(
      text: (existing?['fullInfo'] ?? existing?['longDescription'] ?? '')
          .toString(),
    );
    final featuresController = TextEditingController(
      text: ((existing?['features'] ?? const []) as List)
          .map((item) => item.toString())
          .join('\n'),
    );
    final priceController = TextEditingController(
      text: '${existing?['price'] ?? 0}',
    );
    final durationController = TextEditingController(
      text: '${existing?['durationMinutes'] ?? 15}',
    );
    final sortOrderController = TextEditingController(
      text: '${existing?['sortOrder'] ?? 999}',
    );
    bool isActive = existing?['isActive'] != false;
    bool supportsQuantity = existing?['supportsQuantity'] == true;
    bool separatePayment = existing?['separatePayment'] == true;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null ? 'Новая доп. услуга' : 'Редактировать доп. услугу',
        ),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: keyController,
                    enabled: existing == null,
                    decoration: const InputDecoration(
                      labelText: 'Ключ услуги',
                      hintText: 'Можно не заполнять, создадим автоматически',
                    ),
                  ),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Подсказка / note',
                    ),
                  ),
                  TextField(
                    controller: shortInfoController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Краткая информация',
                      hintText: 'Например: мойка одного стандартного окна',
                    ),
                  ),
                  TextField(
                    controller: fullInfoController,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Подробная информация / размеры',
                      hintText:
                          'Например: какие размеры считаются стандартом, что входит, ограничения.',
                    ),
                  ),
                  TextField(
                    controller: featuresController,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Что входит (по одному пункту на строке)',
                    ),
                  ),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Цена'),
                  ),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Время выполнения, мин',
                      hintText: 'Обязательно учитывается в расписании',
                    ),
                  ),
                  TextField(
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Порядок'),
                  ),
                  SwitchListTile(
                    value: supportsQuantity,
                    onChanged: (value) =>
                        setModalState(() => supportsQuantity = value),
                    title: Text('Поддерживает количество'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: separatePayment,
                    onChanged: (value) =>
                        setModalState(() => separatePayment = value),
                    title: Text('Оплачивается отдельно'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) => setModalState(() => isActive = value),
                    title: Text('Активно'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final key = _adminSlug(
                keyController.text,
                fallbackText: labelController.text,
                prefix: 'addon',
              );
              final durationMinutes =
                  int.tryParse(durationController.text.trim()) ?? 0;
              if (durationMinutes <= 0) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Укажите время доп. услуги больше 0 минут'.tr(),
                    ),
                  ),
                );
                return;
              }
              final items = ((groupData['items'] ?? []) as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
              final noteText = noteController.text.trim();
              final shortInfoText = shortInfoController.text.trim().isEmpty
                  ? noteText
                  : shortInfoController.text.trim();
              final next = <Map<String, dynamic>>[
                ...items.where(
                  (item) => (item['key'] ?? '').toString() != key,
                ),
                {
                  'key': key,
                  'label': labelController.text.trim(),
                  'note': noteText,
                  'shortInfo': shortInfoText,
                  'description': shortInfoText,
                  'fullInfo': fullInfoController.text.trim(),
                  'longDescription': fullInfoController.text.trim(),
                  'features': featuresController.text
                      .split('\n')
                      .map((item) => item.trim())
                      .where((item) => item.isNotEmpty)
                      .toList(),
                  'price': int.tryParse(priceController.text.trim()) ?? 0,
                  'durationMinutes': durationMinutes,
                  'sortOrder':
                      int.tryParse(sortOrderController.text.trim()) ?? 999,
                  'supportsQuantity': supportsQuantity,
                  'separatePayment': separatePayment,
                  'isActive': isActive,
                },
              ]..sort((a, b) {
                  final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 999;
                  final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 999;
                  return aOrder.compareTo(bOrder);
                });
              await _data.saveAdminAddonGroupItems(groupId, next);
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Доп. услуга сохранена'.tr())),
              );
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAddonItem(
    String groupId,
    Map<String, dynamic> groupData,
    String itemKey,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить доп. услугу'.tr()),
        content: Text('Удалить позицию "$itemKey" из группы "$groupId"?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final items = ((groupData['items'] ?? const []) as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['key'] ?? '').toString() != itemKey)
        .toList();
    await _data.saveAdminAddonGroupItems(groupId, items);
  }

  String _adminSlug(
    String raw, {
    required String fallbackText,
    required String prefix,
  }) {
    var source = raw.trim();
    if (source.isEmpty) {
      source = fallbackText.trim();
    }
    var slug = source
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-я0-9]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) {
      slug = '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
    }
    return slug;
  }

  Future<void> _openChecklistTemplateEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final idController = TextEditingController(text: (docId ?? '').toString());
    final titleController = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final descriptionController = TextEditingController(
      text: (existing?['description'] ?? '').toString(),
    );
    final sortOrderController = TextEditingController(
      text: '${existing?['sortOrder'] ?? 999}',
    );
    final itemsController = TextEditingController(
      text: ((existing?['items'] ?? const []) as List)
          .map((item) => item.toString())
          .join('\n'),
    );
    bool isActive = existing?['isActive'] != false;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          docId == null ? 'Новый шаблон чек-листа' : 'Редактировать шаблон',
        ),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    enabled: docId == null,
                    decoration: const InputDecoration(labelText: 'ID шаблона'),
                  ),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Заголовок'),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Описание'),
                  ),
                  TextField(
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Порядок'),
                  ),
                  TextField(
                    controller: itemsController,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Пункты (по одному на строке)',
                    ),
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) => setModalState(() => isActive = value),
                    title: Text('Активно'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final key = idController.text.trim();
              if (key.isEmpty) return;
              await _data.saveAdminChecklistTemplate({
                'key': key,
                'title': titleController.text.trim(),
                'description': descriptionController.text.trim(),
                'sortOrder':
                    int.tryParse(sortOrderController.text.trim()) ?? 999,
                'items': itemsController.text
                    .split('\n')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(),
                'isActive': isActive,
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': existing == null
                    ? FieldValue.serverTimestamp()
                    : (existing['createdAt'] ?? FieldValue.serverTimestamp()),
              });
              if (!mounted) return;
              navigator.pop();
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openTranslationEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final existingLocales = Map<String, dynamic>.from(
      (existing?['locales'] as Map?) ?? const <String, dynamic>{},
    );
    final source = (existing?['source'] ?? '').toString();
    final sourceController = TextEditingController(text: source);
    final ruController = TextEditingController(
      text: (existingLocales['ru'] ?? source).toString(),
    );
    final kkController = TextEditingController(
      text: (existingLocales['kk'] ?? '').toString(),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(docId == null ? 'Новая фраза' : 'Редактировать перевод'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: sourceController,
                  readOnly: docId != null,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Исходный текст',
                    hintText: 'Например, Заказать уборку',
                  ),
                ),
                TextField(
                  controller: ruController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Русский'),
                ),
                TextField(
                  controller: kkController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Қазақша'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final normalizedSource = TranslationController.normalizeSource(
                sourceController.text,
              );
              if (normalizedSource.isEmpty) {
                return;
              }
              final ruValue = ruController.text.trim();
              if (ruValue.isEmpty) {
                showDomlySnackBar(
                  context,
                  title: 'Заполните русский текст',
                  subtitle: 'Русский перевод обязателен для fallback.',
                  type: DomlySnackBarType.error,
                );
                return;
              }
              final key = docId ??
                  TranslationController.translationKey(normalizedSource);
              final locales = <String, dynamic>{
                'ru': ruValue,
                if (kkController.text.trim().isNotEmpty)
                  'kk': kkController.text.trim(),
              };
              await _data.saveAdminTranslation(
                key: key,
                source: normalizedSource,
                locales: locales,
              );
              if (!mounted) {
                return;
              }
              navigator.pop();
            },
            child: Text('Сохранить'.tr()),
          ),
        ],
      ),
    );
  }

  String _audienceLabel(String value) {
    switch (value) {
      case 'client':
        return 'Клиенты';
      case 'cleaner':
        return 'Уборщицы';
      case 'both':
        return 'Обе роли';
      default:
        return value;
    }
  }
}

class _AdminSection {
  const _AdminSection({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;
}

class _AdminListItem {
  const _AdminListItem({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
}

class _AdminReceiptAddon {
  const _AdminReceiptAddon(this.name, {this.price, this.quantity});

  final String name;
  final int? price;
  final int? quantity;
}

class _DetailSection {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;
}
