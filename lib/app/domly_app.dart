import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'boot_route.dart';
import 'debug_session.dart';
import 'debug_url_sync.dart';
import '../screens/client/client_home_screen.dart';
import '../screens/client/calculator_screen.dart';
import '../screens/client/orders_screen.dart';
import '../screens/client/online_payment_screen.dart';
import '../screens/client/package_calendar_screen.dart';
import '../screens/client/package_selection_screen.dart';
import '../screens/client/payment_terms_screen.dart';
import '../screens/client/profile_screen.dart';
import '../screens/client/settings_screen.dart';
import '../screens/client/bonus_screen.dart';
import '../screens/client/house_waitlist_screen.dart';
import '../screens/client/area_confirmation_screen.dart';
import '../screens/client/payment_history_screen.dart';
import '../screens/client/training_order_screen.dart';
import '../screens/admin_web/admin_web_dashboard_screen.dart';
import '../screens/admin_web/admin_login_screen.dart';
import '../screens/common/chat_screen.dart';
import '../screens/common/cluster_map_screen.dart';
import '../screens/common/complaint_screen.dart';
import '../screens/common/legal_document_screen.dart';
import '../screens/common/notifications_screen.dart';
import '../screens/common/photo_report_screen.dart';
import '../screens/common/review_screen.dart';
import '../screens/common/video_detail_screen.dart';
import '../screens/common/video_hub_screen.dart';
import '../screens/cleaner/cleaner_bonus_screen.dart';
import '../screens/cleaner/cleaner_calendar_screen.dart';
import '../screens/cleaner/cleaner_earnings_screen.dart';
import '../screens/cleaner/cleaner_checklist_screen.dart';
import '../screens/cleaner/cleaner_dashboard_screen.dart';
import '../screens/cleaner/cleaner_orders_screen.dart';
import '../screens/cleaner/cleaner_profile_screen.dart';
import '../screens/cleaner/cleaner_verification_screen.dart';
import '../screens/cleaner/cleaner_messages_screen.dart';
import '../screens/phone_auth_screen.dart';
import '../screens/welcome_screen.dart';
import '../localization/translation_controller.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/firestore_data_service.dart';
import '../services/notification_service.dart';
import '../services/offer_alert_sound.dart';
import '../ui/domly_loading_screen.dart';
import '../ui/first_run_tutorial.dart';
import 'app_config.dart';
import 'app_flavor.dart';
import 'app_scope.dart';

class DomlyApp extends StatefulWidget {
  const DomlyApp({
    super.key,
    required this.config,
    required this.authController,
    required this.translationController,
  });

  final AppConfig config;
  final AuthController authController;
  final TranslationController translationController;

  @override
  State<DomlyApp> createState() => _DomlyAppState();
}

class _DomlyAppState extends State<DomlyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _DomlyRouteObserver _routeObserver = _DomlyRouteObserver(
    onRouteChanged: _handleRouteChanged,
  );
  int _authRedirectGeneration = 0;
  bool _authLossRedirectPending = false;
  bool _initialRouteSyncScheduled = false;
  bool _firstRunTutorialScheduled = false;
  bool _firstRunTutorialInFlight = false;
  late bool _lastAuthenticated;
  String? _bootRequestedRoute;
  String? _tutorialHandledForUserId;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSubscription;

  AppConfig get config => widget.config;
  AuthController get authController => widget.authController;
  TranslationController get translationController =>
      widget.translationController;

  @override
  void initState() {
    super.initState();
    _bootRequestedRoute = _incomingRequestedRoute();
    _lastAuthenticated = authController.isAuthenticated;
    authController.addListener(_handleAuthStateChanged);
    _notificationTapSubscription =
        NotificationService.notificationTaps.listen(_handleNotificationTap);
    _scheduleInitialRouteSync();
  }

  @override
  void didUpdateWidget(covariant DomlyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authController != widget.authController) {
      oldWidget.authController.removeListener(_handleAuthStateChanged);
      widget.authController.addListener(_handleAuthStateChanged);
      _scheduleInitialRouteSync();
    }
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    authController.removeListener(_handleAuthStateChanged);
    super.dispose();
  }

  void _handleNotificationTap(Map<String, dynamic> payload) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !authController.isAuthenticated) {
        return;
      }
      final type = (payload['type'] ?? '').toString();
      if (config.adminSurface) {
        final route = (payload['route'] ?? '').toString().trim();
        final targetRoute = route.startsWith('/admin/web')
            ? route
            : type.contains('payment')
                ? '/admin/web?section=payments'
                : '/admin/web';
        syncAppUrlRoute(targetRoute);
        _navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/admin/web',
          (_) => false,
        );
        return;
      }
      if (_isBonusNotificationPayload(payload)) {
        _navigatorKey.currentState?.pushNamed(
          config.flavor == AppFlavor.pro ? '/cleaner/bonus' : '/client/bonus',
        );
        return;
      }
      if (type == 'area_recalculation_payment') {
        _navigatorKey.currentState?.pushNamed('/client/payment-history');
        return;
      }
      final orderId = (payload['orderId'] ??
              payload['chatId'] ??
              payload['slotId'] ??
              payload['scopeId'] ??
              '')
          .toString()
          .trim();
      if (type == 'chat_message' && orderId.isNotEmpty) {
        _navigatorKey.currentState?.pushNamed(
          '/chat',
          arguments: {'orderId': orderId},
        );
        return;
      }
      if (type == 'area_quality_check' || type == 'area_verification') {
        _navigatorKey.currentState?.pushNamed('/client/area-confirmation');
        return;
      }
      if (config.flavor == AppFlavor.pro) {
        _navigatorKey.currentState?.pushNamed('/cleaner/orders');
      } else {
        _navigatorKey.currentState?.pushNamed('/notifications');
      }
    });
  }

  bool _isBonusNotificationPayload(Map<String, dynamic> payload) {
    final searchable = [
      payload['type'],
      payload['reason'],
      payload['title'],
      payload['body'],
    ].join(' ').toLowerCase();
    return searchable.contains('bonus') || searchable.contains('бонус');
  }

  void _handleAuthStateChanged() {
    final becameAuthenticated =
        authController.isAuthenticated && !_lastAuthenticated;
    _lastAuthenticated = authController.isAuthenticated;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final requestedRoute = _requestedRoute();
      final currentRoute = _currentObservedRoute();
      if (authController.isAuthenticated) {
        _authRedirectGeneration++;
        _authLossRedirectPending = false;
        if (becameAuthenticated) {
          _CustomerAddressGateState.resetPromptSession();
        }
        if (currentRoute == '/auth' || currentRoute == '/welcome') {
          final targetRoute = requestedRoute ?? _authenticatedLandingRoute();
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            targetRoute,
            (_) => false,
          );
        }
        _scheduleFirstRunTutorial();
        return;
      }
      if (currentRoute == '/auth') {
        return;
      }
      if (_routeAccess(currentRoute) == _RouteAccess.public) {
        return;
      }
      if (requestedRoute != null && currentRoute == requestedRoute) {
        return;
      }
      _scheduleAuthLossRedirect(currentRoute);
    });
  }

  void _handleRouteChanged(String? routeName) {
    syncAppUrlRoute(_canonicalUrlRoute(routeName));
    _scheduleFirstRunTutorial();
  }

  void _syncCanonicalSurfaceRoute(String? routeName) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      syncAppUrlRoute(_canonicalUrlRoute(routeName));
    });
  }

  String? _canonicalUrlRoute(String? routeName) {
    final normalized = _normalizedRouteName(routeName) ?? '';
    final requestedRouteNormalized = _normalizedRouteName(
          _requestedRoute(),
        ) ??
        '';
    final requestedRoute =
        requestedRouteNormalized.isEmpty ? null : requestedRouteNormalized;
    if (config.adminSurface) {
      if (normalized.isEmpty ||
          normalized == '/' ||
          normalized == '/auth' ||
          normalized == '/welcome') {
        return requestedRoute ?? '/admin/web';
      }
      if (normalized == '/admin/web') {
        return _adminWebRouteWithSection();
      }
      return normalized;
    }

    if (requestedRoute != null &&
        _shouldPreserveRequestedRoute(
          normalizedRoute: normalized,
          requestedRoute: requestedRoute,
        )) {
      return requestedRoute;
    }

    if (requestedRoute != null &&
        requestedRoute != '/auth' &&
        requestedRoute != '/welcome' &&
        (normalized.isEmpty ||
            normalized == '/' ||
            normalized == '/auth' ||
            normalized == '/welcome')) {
      return requestedRoute;
    }

    if (authController.isAuthenticated) {
      if (normalized.isEmpty || normalized == '/') {
        return _authenticatedLandingRoute();
      }
      if (config.flavor == AppFlavor.customer && normalized == '/auth') {
        return config.postAuthRoute;
      }
      if (config.flavor == AppFlavor.pro &&
          (normalized == '/auth' || normalized == '/welcome')) {
        return '/cleaner/dashboard';
      }
    }

    return normalized.isEmpty ? null : normalized;
  }

  String _normalizeCanonicalRouteAlias(String? routeName) {
    final normalized = (routeName ?? '').trim();
    switch (normalized) {
      case '/cleaner':
        return '/cleaner/dashboard';
      case '/training':
        return '/cleaner/training';
      case '/admin':
        return '/admin/web';
      default:
        return normalized;
    }
  }

  bool _shouldPreserveRequestedRoute({
    required String normalizedRoute,
    required String requestedRoute,
  }) {
    if (requestedRoute.isEmpty ||
        requestedRoute == '/auth' ||
        requestedRoute == '/welcome') {
      return false;
    }

    final requestedAccess = _routeAccess(requestedRoute);
    if (requestedAccess == _RouteAccess.public) {
      return false;
    }

    final landingRoute = switch (requestedAccess) {
      _RouteAccess.customer => '/client/home',
      _RouteAccess.cleaner => '/cleaner/dashboard',
      _RouteAccess.admin => '/admin/web',
      _RouteAccess.authenticated || _RouteAccess.public => null,
    };

    if (landingRoute == null || requestedRoute == landingRoute) {
      return false;
    }

    return normalizedRoute.isEmpty ||
        normalizedRoute == '/' ||
        normalizedRoute == '/auth' ||
        normalizedRoute == '/welcome' ||
        normalizedRoute == landingRoute;
  }

  void _scheduleInitialRouteSync() {
    if (_initialRouteSyncScheduled) {
      return;
    }
    _initialRouteSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialRouteSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final debugRoute = DebugSession.route;
      if (DebugSession.enabled && debugRoute != null) {
        syncDebugUrlRoute(debugRoute);
        final currentRoute = _currentObservedRoute();
        if (currentRoute != debugRoute) {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            debugRoute,
            (_) => false,
          );
          return;
        }
      }
      final requestedRoute = _incomingRequestedRoute();
      final preservedRequestedRoute = _requestedRoute();
      if (requestedRoute != null) {
        final currentRoute = _currentObservedRoute();
        final currentAccess = _routeAccess(currentRoute);
        if (currentRoute != requestedRoute &&
            (currentRoute == '/' ||
                currentRoute == '/auth' ||
                currentRoute == '/welcome' ||
                currentRoute == config.initialRoute ||
                currentRoute == config.postAuthRoute ||
                currentAccess == _RouteAccess.public)) {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            requestedRoute,
            (_) => false,
          );
          return;
        }
      }
      if (preservedRequestedRoute != null) {
        syncAppUrlRoute(preservedRequestedRoute);
      }
      if (authController.isAuthenticated) {
        final currentRoute = _currentObservedRoute();
        if (currentRoute == '/auth' || currentRoute == '/welcome') {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            preservedRequestedRoute ?? _authenticatedLandingRoute(),
            (_) => false,
          );
        }
        _scheduleFirstRunTutorial();
      }
    });
  }

  void _scheduleFirstRunTutorial() {
    if (config.adminSurface ||
        !authController.isAuthenticated ||
        _firstRunTutorialScheduled ||
        _firstRunTutorialInFlight) {
      return;
    }
    final userId = authController.currentUserId ??
        AuthService.temporarySessionUid ??
        AuthService.restoredSessionUid;
    if (userId == null ||
        userId.trim().isEmpty ||
        _tutorialHandledForUserId == userId) {
      return;
    }
    final route = _currentObservedRoute();
    if (route == '/auth' || route == '/welcome' || route == '/') {
      return;
    }

    _firstRunTutorialScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 1200), () async {
      _firstRunTutorialScheduled = false;
      if (!mounted || !authController.isAuthenticated) {
        return;
      }
      final currentRoute = _currentObservedRoute();
      final access = _routeAccess(currentRoute);
      if (access == _RouteAccess.public ||
          access == _RouteAccess.admin ||
          currentRoute == '/auth' ||
          currentRoute == '/welcome') {
        return;
      }
      final navigator = _navigatorKey.currentState;
      final context = _navigatorKey.currentContext;
      if (navigator == null || context == null || navigator.canPop()) {
        _scheduleFirstRunTutorial();
        return;
      }
      final alreadyShown = await DomlyFirstRunTutorial.wasShown(
        flavor: config.flavor,
        userId: userId,
      );
      if (!mounted || !context.mounted || alreadyShown) {
        _tutorialHandledForUserId = userId;
        return;
      }
      _firstRunTutorialInFlight = true;
      try {
        await DomlyFirstRunTutorial.show(context, flavor: config.flavor);
        await DomlyFirstRunTutorial.markShown(
          flavor: config.flavor,
          userId: userId,
        );
        _tutorialHandledForUserId = userId;
      } finally {
        _firstRunTutorialInFlight = false;
      }
    });
  }

  String _authenticatedLandingRoute() {
    if (config.flavor == AppFlavor.pro) {
      return '/cleaner/dashboard';
    }
    return config.postAuthRoute;
  }

  String _currentObservedRoute() {
    return _routeObserver.currentRouteName ?? '/';
  }

  String? _requestedRoute() {
    final debugRoute = DebugSession.route;
    if (DebugSession.enabled && debugRoute != null) {
      return debugRoute;
    }
    return _bootRequestedRoute ?? _incomingRequestedRoute();
  }

  String _adminWebRouteWithSection() {
    final fragment = Uri.base.fragment.trim();
    final queryIndex = fragment.indexOf('?');
    if (queryIndex < 0) {
      return '/admin/web';
    }
    final section = Uri.tryParse(fragment)?.queryParameters['section']?.trim();
    return section == null || section.isEmpty
        ? '/admin/web'
        : '/admin/web?section=$section';
  }

  String? _incomingRequestedRoute() {
    if (!kIsWeb) {
      return null;
    }
    final windowBootRoute = readBootRoute();
    if (windowBootRoute != null) {
      return windowBootRoute;
    }
    final debugRoute = DebugSession.route;
    if (DebugSession.enabled && debugRoute != null) {
      return debugRoute;
    }
    final fragment = Uri.base.fragment.trim();
    if (fragment.isEmpty || !fragment.startsWith('/')) {
      return null;
    }
    final queryIndex = fragment.indexOf('?');
    final route =
        (queryIndex == -1 ? fragment : fragment.substring(0, queryIndex))
            .trim();
    if (route.isEmpty) {
      return null;
    }
    return _normalizedRouteName(route);
  }

  void _scheduleAuthLossRedirect(String routeAtLoss) {
    if (_authLossRedirectPending) {
      return;
    }
    _authLossRedirectPending = true;
    final generation = ++_authRedirectGeneration;
    unawaited(_runAuthLossRedirect(routeAtLoss, generation));
  }

  Future<void> _runAuthLossRedirect(
    String routeAtLoss,
    int generation,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted || generation != _authRedirectGeneration) {
      return;
    }
    await authController.refresh();
    if (!mounted || generation != _authRedirectGeneration) {
      return;
    }
    _authLossRedirectPending = false;
    if (authController.isAuthenticated) {
      return;
    }
    final currentRoute = _routeObserver.currentRouteName ?? routeAtLoss;
    final authRoute = config.adminSurface ? '/admin/web' : '/auth';
    if (currentRoute == authRoute) {
      return;
    }
    if (_routeAccess(currentRoute) == _RouteAccess.public) {
      return;
    }
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      authRoute,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final materialInitialRoute = _materialInitialRoute();
    return AnimatedBuilder(
      animation: translationController,
      builder: (context, _) => AppScope(
        config: config,
        authController: authController,
        translationController: translationController,
        child: _CleanerOfferAlertWatcher(
          enabled: config.flavor == AppFlavor.pro,
          authController: authController,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (config.flavor == AppFlavor.pro) {
                OfferAlertSound.prime();
              }
            },
            child: MaterialApp(
              title: config.title,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              navigatorKey: _navigatorKey,
              navigatorObservers: [_routeObserver],
              initialRoute: materialInitialRoute,
              locale: Locale(translationController.localeCode),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: TranslationController.supportedLocales
                  .map(Locale.new)
                  .toList(growable: false),
              onGenerateRoute: _onGenerateRoute,
            ),
          ),
        ),
      ),
    );
  }

  String _materialInitialRoute() {
    final debugRoute = DebugSession.route;
    if (DebugSession.enabled && debugRoute != null) {
      return debugRoute;
    }
    final requestedRoute = _requestedRoute();
    if (requestedRoute != null) {
      return requestedRoute;
    }
    if (authController.isAuthenticated) {
      return _authenticatedLandingRoute();
    }
    return config.initialRoute;
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final page = _buildPage(settings);
    final routeSettings = RouteSettings(
      name: _normalizedRouteName(settings.name),
      arguments: settings.arguments,
    );
    return MaterialPageRoute<void>(
      builder: (_) => page,
      settings: routeSettings,
    );
  }

  Widget _buildPage(RouteSettings settings) {
    final routeName = _normalizedRouteName(settings.name);
    final normalizedSettings = RouteSettings(
      name: routeName,
      arguments: settings.arguments,
    );
    final debugOverride = _debugBootstrapOverride(routeName);
    if (debugOverride != null) {
      final access = _routeAccess(debugOverride);
      return _guarded(
        child: _buildProtectedPage(RouteSettings(name: debugOverride)),
        settings: RouteSettings(name: debugOverride),
        access: access,
      );
    }

    final access = _routeAccess(routeName);
    if (access != _RouteAccess.public) {
      return _guarded(
        child: _buildProtectedPage(normalizedSettings),
        settings: normalizedSettings,
        access: access,
      );
    }

    switch (routeName) {
      case '/':
        return _rootScreen();
      case '/welcome':
        if (!config.adminSurface) {
          if (authController.isAuthenticated) {
            final targetRoute = config.flavor == AppFlavor.pro
                ? '/cleaner/dashboard'
                : config.postAuthRoute;
            final access = _routeAccess(targetRoute);
            return _guarded(
              child: _buildProtectedPage(RouteSettings(name: targetRoute)),
              settings: RouteSettings(name: targetRoute),
              access: access,
            );
          }
          if (config.flavor == AppFlavor.customer) {
            return PhoneAuthScreen(
              title: config.title,
              postAuthRoute: config.postAuthRoute,
            );
          }
        }
        return WelcomeScreen(
          title: config.title,
          nextRoute: _welcomeNextRoute(),
        );
      case '/auth':
        final debugRoute = DebugSession.route;
        if (DebugSession.enabled && debugRoute != null) {
          final access = _routeAccess(debugRoute);
          if (access != _RouteAccess.public) {
            return _guarded(
              child: _buildProtectedPage(RouteSettings(name: debugRoute)),
              settings: RouteSettings(name: debugRoute),
              access: access,
            );
          }
        }
        if (!config.adminSurface && authController.isAuthenticated) {
          final targetRoute = config.flavor == AppFlavor.pro
              ? '/cleaner/dashboard'
              : config.postAuthRoute;
          final access = _routeAccess(targetRoute);
          return _guarded(
            child: _buildProtectedPage(RouteSettings(name: targetRoute)),
            settings: RouteSettings(name: targetRoute),
            access: access,
          );
        }
        final args = _readArgs(settings.arguments);
        if (config.adminSurface) {
          return AdminLoginScreen(title: config.title);
        }
        return PhoneAuthScreen(
          title: config.title,
          postAuthRoute:
              (args['postAuthRoute'] ?? config.postAuthRoute).toString(),
          postAuthArguments: args['postAuthArguments'],
          popOnSuccess: args['popOnSuccess'] == true,
        );
      case '/admin':
        return _forbiddenRouteScreen(
          'Маршрут /admin доступен только авторизованным сотрудникам.'.tr(),
        );
      case '/admin/web':
        return _forbiddenRouteScreen(
          'Маршрут /admin/web доступен только авторизованным сотрудникам.'.tr(),
        );
      case '/map/clusters':
        return const ClusterMapScreen();
      case '/payment-terms':
        return const PaymentTermsScreen();
      case LegalDocumentScreen.offerRoute:
        return LegalDocumentScreen.offer();
      case LegalDocumentScreen.privacyRoute:
        return LegalDocumentScreen.privacy();
      case '/chat':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/complaint':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/photo-report':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/review':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/client/home':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/client/calculator':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/client/bonus':
        return const BonusScreen();
      case '/client/packages':
        return const PackageSelectionScreen();
      case '/client/package-calendar':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/client/training-order':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/client/house-waitlist':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/client/area-confirmation':
        return const AreaConfirmationScreen();
      case '/client/videos':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/cleaner/bonus':
      case '/training':
      case '/cleaner/training':
      case '/cleaner/messages':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      case '/video/detail':
        return _invalidRouteScreen(
            'Приватный маршрут должен открываться через auth-gate'.tr());
      default:
        return _invalidRouteScreen(
          'Раздел не найден: {route}'.tr(
            params: {'route': routeName ?? '—'},
          ),
        );
    }
  }

  String? _debugBootstrapOverride(String? routeName) {
    final debugRoute = DebugSession.route;
    if (!DebugSession.enabled || debugRoute == null) {
      return null;
    }
    if (routeName == debugRoute) {
      return null;
    }
    switch (routeName) {
      case null:
      case '/':
      case '/welcome':
      case '/auth':
      case '/client/home':
      case '/cleaner/dashboard':
        return debugRoute;
      default:
        if (routeName == config.initialRoute ||
            routeName == config.postAuthRoute) {
          return debugRoute;
        }
        return null;
    }
  }

  String _welcomeNextRoute() {
    if (config.adminSurface) {
      return authController.hasBackofficeAccess ? '/admin/web' : '/auth';
    }
    if (config.flavor == AppFlavor.pro) {
      return authController.isAuthenticated ? '/cleaner/dashboard' : '/auth';
    }
    return config.postAuthRoute;
  }

  Map<String, String> _currentFragmentQuery() {
    if (!kIsWeb) {
      return const <String, String>{};
    }
    final fragment = Uri.base.fragment.trim();
    final queryIndex = fragment.indexOf('?');
    if (queryIndex == -1 || queryIndex >= fragment.length - 1) {
      return const <String, String>{};
    }
    return Uri.splitQueryString(fragment.substring(queryIndex + 1));
  }

  String? _currentFragmentDetailId(String routeName) {
    if (!kIsWeb) {
      return null;
    }
    final fragment = Uri.base.fragment.trim();
    if (fragment.isEmpty || !fragment.startsWith('/')) {
      return null;
    }
    final queryIndex = fragment.indexOf('?');
    final route =
        (queryIndex == -1 ? fragment : fragment.substring(0, queryIndex))
            .trim();
    final prefix = '$routeName/';
    if (!route.startsWith(prefix) || route.length <= prefix.length) {
      return null;
    }
    final value = route.substring(prefix.length).split('/').first.trim();
    return value.isEmpty ? null : Uri.decodeComponent(value);
  }

  String? _routeParam(
    RouteSettings settings,
    String key, {
    List<String> aliases = const [],
  }) {
    final names = [key, ...aliases];
    final args = _readArgs(settings.arguments);
    for (final name in names) {
      final value = args[name]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final query = _currentFragmentQuery();
    for (final name in names) {
      final value = query[name]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final routeName = _normalizedRouteName(settings.name) ?? '';
    final detailId = _currentFragmentDetailId(routeName);
    if (detailId != null && detailId.isNotEmpty) {
      return detailId;
    }
    if (DebugSession.enabled &&
        (key == 'orderId' || aliases.contains('orderId'))) {
      final debugOrderId = DebugSession.value('debug_order_id')?.trim();
      if (debugOrderId != null && debugOrderId.isNotEmpty) {
        return debugOrderId;
      }
    }
    return null;
  }

  String? _normalizedRouteName(String? routeName) {
    final normalized = _normalizeCanonicalRouteAlias(routeName);
    const detailRoutes = <String>{
      '/chat',
      '/complaint',
      '/photo-report',
      '/review',
      '/cleaner/checklist',
      '/client/package-calendar',
      '/client/house-waitlist',
      '/video/detail',
    };
    for (final route in detailRoutes) {
      if (normalized.startsWith('$route/')) {
        return route;
      }
    }
    return normalized.isEmpty ? routeName : normalized;
  }

  Widget _rootScreen() {
    final debugRoute = DebugSession.route;
    if (DebugSession.enabled && debugRoute != null) {
      final access = _routeAccess(debugRoute);
      if (access != _RouteAccess.public) {
        return _guarded(
          child: _buildProtectedPage(RouteSettings(name: debugRoute)),
          settings: RouteSettings(name: debugRoute),
          access: access,
        );
      }
    }

    final requestedRoute = _requestedRoute();
    if (requestedRoute != null && requestedRoute != '/') {
      final requestedAccess = _routeAccess(requestedRoute);
      if (requestedAccess != _RouteAccess.public) {
        final canonicalRequestedRoute = _canonicalUrlRoute(requestedRoute);
        if (canonicalRequestedRoute != null) {
          syncAppUrlRoute(canonicalRequestedRoute);
        }
        return _guarded(
          child: _buildProtectedPage(RouteSettings(name: requestedRoute)),
          settings: RouteSettings(name: requestedRoute),
          access: requestedAccess,
        );
      }
    }

    if (config.adminSurface) {
      final requestedAdminRoute = _requestedRoute();
      final adminLoginRoute =
          requestedAdminRoute == '/auth' ? '/auth' : '/admin/web';
      if (!authController.isAuthenticated) {
        syncAppUrlRoute(adminLoginRoute);
        return AdminLoginScreen(title: config.title);
      }
      if (authController.hasBackofficeAccess) {
        syncAppUrlRoute(_adminWebRouteWithSection());
        return const AdminWebDashboardScreen();
      }
      syncAppUrlRoute(adminLoginRoute);
      return AdminLoginScreen(
        title: config.title,
        initialErrorText:
            'У текущей учетной записи нет прав для этого раздела. Войдите под админским аккаунтом.'
                .tr(),
      );
    }

    if (config.flavor == AppFlavor.pro) {
      return authController.isAuthenticated
          ? const CleanerDashboardScreen()
          : PhoneAuthScreen(
              title: config.title,
              postAuthRoute: config.postAuthRoute,
            );
    }

    return authController.isAuthenticated
        ? const ClientHomeScreen()
        : PhoneAuthScreen(
            title: config.title,
            postAuthRoute: config.postAuthRoute,
          );
  }

  Widget _guarded({
    required Widget child,
    required RouteSettings settings,
    required _RouteAccess access,
  }) {
    _syncCanonicalSurfaceRoute(settings.name);
    if (!authController.isAuthenticated) {
      _authRedirectGeneration++;
      _authLossRedirectPending = false;
      final canonicalRequestedRoute = _canonicalUrlRoute(settings.name);
      if (canonicalRequestedRoute != null) {
        syncAppUrlRoute(canonicalRequestedRoute);
      }
      clearBootRoute();
      clearBootRouteUrl();
      if (config.adminSurface) {
        return AdminLoginScreen(title: config.title);
      }
      return PhoneAuthScreen(
        title: config.title,
        postAuthRoute: settings.name ?? config.postAuthRoute,
        postAuthArguments: settings.arguments,
      );
    }

    if (config.adminSurface && !authController.hasBackofficeAccess) {
      clearBootRoute();
      clearBootRouteUrl();
      return AdminLoginScreen(
        title: config.title,
        initialErrorText:
            'У текущей учетной записи нет прав для этого раздела. Войдите под админским аккаунтом.'
                .tr(),
      );
    }

    if (_canAccess(access)) {
      clearBootRoute();
      clearBootRouteUrl();
      final visibleChild = _shouldShowClientNotificationShortcut(settings.name)
          ? _ClientNotificationShortcut(child: child)
          : child;
      if (config.flavor == AppFlavor.customer &&
          access == _RouteAccess.customer &&
          settings.name != '/client/profile' &&
          settings.name != '/client/training-order') {
        return _CustomerAddressGate(child: visibleChild);
      }
      return visibleChild;
    }

    return _forbiddenRouteScreen(
      'У текущей учетной записи нет прав для этого раздела.'.tr(),
    );
  }

  bool _shouldShowClientNotificationShortcut(String? routeName) {
    return false;
  }

  _RouteAccess _routeAccess(String? routeName) {
    final normalizedRoute = _normalizedRouteName(routeName);
    switch (normalizedRoute) {
      case '/map/clusters':
      case '/chat':
      case '/notifications':
        return _RouteAccess.authenticated;
      case '/complaint':
      case '/review':
      case '/client/home':
      case '/client/calculator':
      case '/client/bonus':
      case '/client/orders':
      case '/client/payment-history':
      case '/client/online-payment':
      case '/client/profile':
      case '/client/settings':
      case '/client/packages':
      case '/client/package-calendar':
      case '/client/house-waitlist':
      case '/client/area-confirmation':
      case '/client/videos':
      case '/client/training-order':
        return _RouteAccess.customer;
      case '/photo-report':
      case '/cleaner':
      case '/cleaner/dashboard':
      case '/cleaner/calendar':
      case '/cleaner/earnings':
      case '/cleaner/bonus':
      case '/cleaner/checklist':
      case '/cleaner/profile':
      case '/cleaner/verification':
      case '/cleaner/orders':
      case '/training':
      case '/cleaner/training':
      case '/cleaner/messages':
        return _RouteAccess.cleaner;
      case '/admin':
      case '/admin/web':
        return _RouteAccess.admin;
      case '/video/detail':
        return _RouteAccess.authenticated;
      default:
        return _RouteAccess.public;
    }
  }

  bool _canAccess(_RouteAccess access) {
    switch (access) {
      case _RouteAccess.public:
        return true;
      case _RouteAccess.authenticated:
        return authController.isAuthenticated;
      case _RouteAccess.customer:
        return authController.isAuthenticated &&
            authController.canAccessCustomerSurface;
      case _RouteAccess.cleaner:
        return authController.isAuthenticated &&
            authController.canAccessCleanerSurface;
      case _RouteAccess.admin:
        return authController.isAuthenticated &&
            config.adminSurface &&
            authController.hasBackofficeAccess;
    }
  }

  Widget _buildProtectedPage(RouteSettings settings) {
    switch (settings.name) {
      case '/map/clusters':
        return const ClusterMapScreen();
      case '/chat':
        final orderId = _routeParam(
          settings,
          'orderId',
          aliases: const ['chatId', 'slotId', 'id'],
        );
        if (orderId == null || orderId.isEmpty) {
          return _routeFallbackScreen(
            'Чат откроется из карточки заказа.'.tr(),
          );
        }
        return ChatScreen(
          orderId: orderId,
          senderId: authController.currentUserId ?? '',
          senderRole: config.adminSurface
              ? 'admin'
              : config.flavor == AppFlavor.pro
                  ? 'cleaner'
                  : 'customer',
          readOnly: false,
        );
      case '/complaint':
        final complaintOrderId = _routeParam(
          settings,
          'orderId',
          aliases: const ['slotId', 'id'],
        );
        if (complaintOrderId == null || complaintOrderId.isEmpty) {
          return _routeFallbackScreen(
            'Жалоба открывается из нужного заказа.'.tr(),
          );
        }
        return ComplaintScreen(orderId: complaintOrderId);
      case '/photo-report':
        final photoOrderId = _routeParam(
          settings,
          'orderId',
          aliases: const ['slotId', 'id'],
        );
        if (photoOrderId == null || photoOrderId.isEmpty) {
          return _routeFallbackScreen(
            'Фотоотчет открывается из активной уборки.'.tr(),
          );
        }
        return PhotoReportScreen(orderId: photoOrderId);
      case '/review':
        final reviewOrderId = _routeParam(
          settings,
          'orderId',
          aliases: const ['slotId', 'id'],
        );
        if (reviewOrderId == null || reviewOrderId.isEmpty) {
          return _routeFallbackScreen(
            'Оценка открывается после завершенной уборки.'.tr(),
          );
        }
        return ReviewScreen(orderId: reviewOrderId);
      case '/notifications':
        return NotificationsScreen(
          surface: config.flavor == AppFlavor.pro
              ? NotificationSurface.cleaner
              : NotificationSurface.client,
        );
      case '/client/home':
        return const ClientHomeScreen();
      case '/client/calculator':
        return const CalculatorScreen();
      case '/client/bonus':
        return const BonusScreen();
      case '/client/orders':
        return const OrdersScreen();
      case '/client/online-payment':
        return OnlinePaymentScreen.fromArgs(settings.arguments);
      case '/client/payment-history':
        return const PaymentHistoryScreen();
      case '/client/profile':
        return const ProfileScreen();
      case '/client/settings':
        return const SettingsScreen();
      case '/client/packages':
        return const PackageSelectionScreen();
      case '/client/package-calendar':
        final subscriptionId = _routeParam(
          settings,
          'subscriptionId',
          aliases: const ['orderId', 'id'],
        );
        return _PackageCalendarRouteResolver(
          subscriptionId: subscriptionId,
          invalidRouteScreenBuilder: _routeFallbackScreen,
        );
      case '/client/training-order':
        return const TrainingOrderScreen();
      case '/client/house-waitlist':
        final houseId = _routeParam(
          settings,
          'houseId',
          aliases: const ['id'],
        );
        return _HouseWaitlistRouteResolver(
          houseId: houseId,
          invalidRouteScreenBuilder: _routeFallbackScreen,
        );
      case '/client/area-confirmation':
        return const AreaConfirmationScreen();
      case '/client/videos':
        return VideoHubScreen(
          audienceType: 'client',
          title: 'Полезные видео'.tr(),
          subtitle:
              'Что входит в уборку, как выбрать услугу и как подготовить квартиру.'
                  .tr(),
        );
      case '/cleaner/dashboard':
        return const CleanerDashboardScreen();
      case '/cleaner/calendar':
        return const CleanerCalendarScreen();
      case '/cleaner/earnings':
        return const CleanerEarningsScreen();
      case '/cleaner/bonus':
        return const CleanerBonusScreen();
      case '/cleaner/checklist':
        final checklistOrderId = _routeParam(
          settings,
          'orderId',
          aliases: const ['slotId', 'id'],
        );
        if (checklistOrderId == null || checklistOrderId.isEmpty) {
          return _routeFallbackScreen(
            'Чек-лист открывается из активной уборки.'.tr(),
            targetRoute: '/cleaner/orders',
          );
        }
        return CleanerChecklistScreen(orderId: checklistOrderId);
      case '/cleaner/profile':
        return const CleanerProfileScreen();
      case '/cleaner/verification':
        return const CleanerVerificationScreen();
      case '/cleaner/orders':
        return const CleanerOrdersScreen();
      case '/training':
      case '/cleaner/training':
        return VideoHubScreen(
          audienceType: 'cleaner',
          title: 'Обучение'.tr(),
          subtitle:
              'Стандарты уборки, обучение по услугам и обязательные видео.'
                  .tr(),
        );
      case '/cleaner/messages':
        return const CleanerMessagesScreen();
      case '/admin':
      case '/admin/web':
        return const AdminWebDashboardScreen();
      case '/video/detail':
        final args = _readArgs(settings.arguments);
        final videoId = _routeParam(
          settings,
          'videoId',
          aliases: const ['id'],
        );
        final audienceType = _routeParam(settings, 'audienceType') ??
            args['audienceType']?.toString() ??
            'client';
        if (videoId == null || videoId.isEmpty) {
          return _routeFallbackScreen(
            'Видео открывается из списка обучения.'.tr(),
            targetRoute: config.flavor == AppFlavor.pro
                ? '/cleaner/training'
                : '/client/videos',
          );
        }
        return VideoDetailScreen(
          videoId: videoId,
          audienceType: audienceType,
        );
      default:
        return _invalidRouteScreen(
          'Раздел не найден: {route}'.tr(
            params: {'route': settings.name ?? '—'},
          ),
        );
    }
  }

  Map<String, dynamic> _readArgs(Object? args) {
    if (args is Map<Object?, Object?>) {
      return args.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const {};
  }

  Widget _invalidRouteScreen(String message) {
    return Scaffold(
      appBar: AppBar(title: Text('Ошибка перехода'.tr())),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _routeFallbackScreen(String message, {String? targetRoute}) {
    return _RouteFallbackScreen(
      message: message,
      targetRoute: targetRoute ??
          (config.flavor == AppFlavor.pro
              ? '/cleaner/orders'
              : '/client/orders'),
    );
  }

  Widget _forbiddenRouteScreen(String message) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Доступ ограничен'.tr()),
        actions: config.adminSurface
            ? [
                IconButton(
                  tooltip: 'Выйти'.tr(),
                  onPressed: () async {
                    await authController.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 42,
                color: Colors.black45,
              ),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              if (config.adminSurface) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await authController.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: Text('Выйти и войти заново'.tr()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CleanerOfferAlertWatcher extends StatefulWidget {
  const _CleanerOfferAlertWatcher({
    required this.enabled,
    required this.authController,
    required this.child,
  });

  final bool enabled;
  final AuthController authController;
  final Widget child;

  @override
  State<_CleanerOfferAlertWatcher> createState() =>
      _CleanerOfferAlertWatcherState();
}

class _CleanerOfferAlertWatcherState extends State<_CleanerOfferAlertWatcher>
    with WidgetsBindingObserver {
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  StreamSubscription<Map<String, dynamic>?>? _profileSubscription;
  Timer? _offerExpiryTimer;
  List<Map<String, dynamic>> _latestOffers = const <Map<String, dynamic>>[];
  bool _soundActive = false;
  bool _alertEnabled = true;
  double _alertVolume = 1;
  int _alertSoundIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authController.addListener(_syncSubscription);
    _syncSubscription();
  }

  @override
  void didUpdateWidget(covariant _CleanerOfferAlertWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authController != widget.authController) {
      oldWidget.authController.removeListener(_syncSubscription);
      widget.authController.addListener(_syncSubscription);
    }
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.authController != widget.authController) {
      _syncSubscription();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authController.removeListener(_syncSubscription);
    _subscription?.cancel();
    _profileSubscription?.cancel();
    _offerExpiryTimer?.cancel();
    OfferAlertSound.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OfferAlertSound.prime();
      _handleOffers(_latestOffers);
    }
  }

  void _syncSubscription() {
    final shouldListen =
        widget.enabled && widget.authController.isAuthenticated;
    if (!shouldListen) {
      _subscription?.cancel();
      _subscription = null;
      _profileSubscription?.cancel();
      _profileSubscription = null;
      _offerExpiryTimer?.cancel();
      _offerExpiryTimer = null;
      _latestOffers = const <Map<String, dynamic>>[];
      _setSoundActive(false);
      return;
    }
    _profileSubscription ??= FirestoreDataService.instance
        .cleanerProfileStream()
        .listen(_handleProfile, onError: (_) {});
    _subscription ??= FirestoreDataService.instance
        .cleanerOrderOffersStream()
        .listen(_handleOffers, onError: (_) => _setSoundActive(false));
  }

  void _handleProfile(Map<String, dynamic>? profile) {
    final data = profile ?? const <String, dynamic>{};
    final nextEnabled = data['offerAlertSoundEnabled'] != false;
    final nextVolume =
        ((data['offerAlertSoundVolume'] as num?)?.toDouble() ?? 1)
            .clamp(0.0, 1.0);
    final nextSoundIndex =
        ((data['offerAlertSoundIndex'] as num?)?.toInt() ?? 0).clamp(0, 20);
    final changed = nextEnabled != _alertEnabled ||
        nextVolume != _alertVolume ||
        nextSoundIndex != _alertSoundIndex;
    _alertEnabled = nextEnabled;
    _alertVolume = nextVolume;
    _alertSoundIndex = nextSoundIndex;
    if (!changed || !_soundActive) {
      return;
    }
    OfferAlertSound.stop();
    if (_alertEnabled) {
      OfferAlertSound.start(
        enabled: _alertEnabled,
        volume: _alertVolume,
        soundIndex: _alertSoundIndex,
      );
    }
  }

  void _handleOffers(List<Map<String, dynamic>> offers) {
    _latestOffers = offers;
    final now = DateTime.now();
    final activeOffers = offers.where((offer) {
      final status = (offer['status'] ?? '').toString().toLowerCase();
      if (status.isNotEmpty && status != 'pending') {
        return false;
      }
      final expiresAt = _offerExpiresAt(offer['expiresAt']);
      return expiresAt == null || expiresAt.isAfter(now);
    }).toList(growable: false);
    _scheduleNextOfferExpiryCheck(activeOffers, now);
    _setSoundActive(activeOffers.isNotEmpty);
  }

  void _scheduleNextOfferExpiryCheck(
    List<Map<String, dynamic>> activeOffers,
    DateTime now,
  ) {
    _offerExpiryTimer?.cancel();
    final nextExpiry = activeOffers
        .map((offer) => _offerExpiresAt(offer['expiresAt']))
        .whereType<DateTime>()
        .where((date) => date.isAfter(now))
        .fold<DateTime?>(null, (min, date) {
      if (min == null || date.isBefore(min)) {
        return date;
      }
      return min;
    });
    if (nextExpiry == null) {
      _offerExpiryTimer = null;
      return;
    }
    final delay = nextExpiry.difference(now) + const Duration(seconds: 1);
    _offerExpiryTimer = Timer(delay, () => _handleOffers(_latestOffers));
  }

  DateTime? _offerExpiresAt(Object? value) {
    if (value == null) {
      return null;
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
    } catch (_) {
      return null;
    }
    return null;
  }

  void _setSoundActive(bool active) {
    if (_soundActive == active) {
      return;
    }
    _soundActive = active;
    if (active && _alertEnabled) {
      OfferAlertSound.start(
        enabled: _alertEnabled,
        volume: _alertVolume,
        soundIndex: _alertSoundIndex,
      );
    } else {
      OfferAlertSound.stop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RouteFallbackScreen extends StatefulWidget {
  const _RouteFallbackScreen({
    required this.message,
    required this.targetRoute,
  });

  final String message;
  final String targetRoute;

  @override
  State<_RouteFallbackScreen> createState() => _RouteFallbackScreenState();
}

class _RouteFallbackScreenState extends State<_RouteFallbackScreen> {
  bool _redirectScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_redirectScheduled) {
      return;
    }
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushNamedAndRemoveUntil(
        widget.targetRoute,
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.route_outlined,
                  color: Color(0xFF658170),
                  size: 42,
                ),
                const SizedBox(height: 14),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF2B4338),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamedAndRemoveUntil(
                    widget.targetRoute,
                    (route) => false,
                  ),
                  child: Text('Открыть заказы'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageCalendarRouteResolver extends StatelessWidget {
  const _PackageCalendarRouteResolver({
    required this.subscriptionId,
    required this.invalidRouteScreenBuilder,
  });

  final String? subscriptionId;
  final Widget Function(String message) invalidRouteScreenBuilder;

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

  @override
  Widget build(BuildContext context) {
    final explicitId = subscriptionId?.trim() ?? '';
    if (explicitId.isNotEmpty) {
      return PackageCalendarScreen(subscriptionId: explicitId);
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreDataService.instance.customerSubscriptionsStream(),
      builder: (context, snapshot) {
        final subscriptions = snapshot.data ?? const <Map<String, dynamic>>[];
        final resolved = subscriptions.cast<Map<String, dynamic>?>().firstWhere(
              (item) =>
                  (item?['status'] ?? '').toString().toLowerCase() ==
                      'active' &&
                  _isPaidSubscription(item) &&
                  ((item?['id'] ?? '').toString().trim().isNotEmpty),
              orElse: () => null,
            );
        final resolvedId = (resolved?['id'] ?? '').toString().trim();

        if (resolvedId.isNotEmpty) {
          return PackageCalendarScreen(subscriptionId: resolvedId);
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const DomlyLoadingScreen(
            subtitle: 'Загружаем ваши пакеты',
          );
        }

        return invalidRouteScreenBuilder(
          'Не найдена активная подписка для выбора дат'.tr(),
        );
      },
    );
  }
}

class _HouseWaitlistRouteResolver extends StatelessWidget {
  const _HouseWaitlistRouteResolver({
    required this.houseId,
    required this.invalidRouteScreenBuilder,
  });

  final String? houseId;
  final Widget Function(String message) invalidRouteScreenBuilder;

  @override
  Widget build(BuildContext context) {
    final explicitId = houseId?.trim() ?? '';
    if (explicitId.isNotEmpty) {
      return HouseWaitlistScreen(houseId: explicitId);
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: FirestoreDataService.instance.customerProfileStream(),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const <String, dynamic>{};
        final resolvedId = (profile['houseId'] ?? '').toString().trim();
        if (resolvedId.isNotEmpty) {
          return HouseWaitlistScreen(houseId: resolvedId);
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const DomlyLoadingScreen(
            subtitle: 'Проверяем подключенный дом',
          );
        }

        return invalidRouteScreenBuilder(
          'Не передан houseId для waitlist'.tr(),
        );
      },
    );
  }
}

class _ClientNotificationShortcut extends StatelessWidget {
  const _ClientNotificationShortcut({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 18,
          child: StreamBuilder<int>(
            stream:
                FirestoreDataService.instance.userUnreadActivityCountStream(),
            initialData: 0,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Material(
                color: Colors.white.withValues(alpha: 0.96),
                shape: const CircleBorder(),
                elevation: 6,
                shadowColor: const Color(0x332D6B4F),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pushNamed(context, '/notifications'),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.notifications_none,
                          color: Color(0xFF496A59),
                          size: 24,
                        ),
                        if (count > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 17,
                                minHeight: 17,
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD36A45),
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
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
    );
  }
}

class _CustomerAddressGate extends StatefulWidget {
  const _CustomerAddressGate({required this.child});

  final Widget child;

  @override
  State<_CustomerAddressGate> createState() => _CustomerAddressGateState();
}

class _CustomerAddressGateState extends State<_CustomerAddressGate> {
  static bool _promptDismissedForSession = false;
  bool _promptInFlight = false;

  static void resetPromptSession() {
    _promptDismissedForSession = false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: FirestoreDataService.instance.customerProfileStream(),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const <String, dynamic>{};
        if (snapshot.hasData &&
            !_hasCustomerAddress(profile) &&
            !_promptInFlight &&
            !_promptDismissedForSession) {
          _promptInFlight = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              _promptInFlight = false;
              return;
            }
            ProfileScreen.openProfileEditor(
              context,
              FirestoreDataService.instance,
              profile,
              requireCompletion: true,
            ).whenComplete(() {
              _promptDismissedForSession = true;
              _promptInFlight = false;
            });
          });
        }

        return widget.child;
      },
    );
  }

  static bool _hasCustomerAddress(Map<String, dynamic> profile) {
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
}

enum _RouteAccess {
  public,
  authenticated,
  customer,
  cleaner,
  admin,
}

class _DomlyRouteObserver extends NavigatorObserver {
  _DomlyRouteObserver({this.onRouteChanged});

  String? currentRouteName;
  final void Function(String? routeName)? onRouteChanged;

  void _setCurrent(Route<dynamic>? route) {
    currentRouteName = route?.settings.name;
    onRouteChanged?.call(currentRouteName);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _setCurrent(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(previousRoute);
    super.didRemove(route, previousRoute);
  }
}
