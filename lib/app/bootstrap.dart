import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../localization/translation_controller.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../ui/domly_loading_screen.dart';
import '../utils/app_logger.dart';
import 'app_brand.dart';
import 'app_config.dart';
import 'app_env.dart';
import 'app_flavor.dart';
import 'domly_app.dart';

Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_BootstrapHost(config: config));
}

class _BootstrapHost extends StatefulWidget {
  const _BootstrapHost({required this.config});

  final AppConfig config;

  @override
  State<_BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends State<_BootstrapHost> {
  AuthController? _authController;
  TranslationController? _translationController;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _authController?.dispose();
    _translationController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final config = widget.config;

    try {
      AppLogger.d('BOOT', 'Flutter bootstrap screen shown');

      await _initializePreferredOrientations();
      AppLogger.d('BOOT', 'Orientations initialized');

      await _initializeFirebase(config);
      AppLogger.d('BOOT', 'Firebase initialized');

      final preferences = await _loadPreferences();
      final translationController = TranslationController(
        preferences: preferences,
      );
      await translationController.init();
      AppLogger.d('BOOT', 'Translations initialized');

      final authService = AuthService(config: config);
      await AuthService.restorePersistedTemporarySession();
      final authController = AuthController(authService, config: config);

      AppLogger.d('BOOT', 'Auth controller created');
      await authController.init().timeout(
        const Duration(seconds: 24),
        onTimeout: () {
          AppLogger.w('AUTH', 'Auth initialization timed out, continuing');
        },
      );
      AppLogger.d(
        'AUTH',
        'Initialized. authenticated=${authController.isAuthenticated}',
      );

      _attachNotificationBootstrap(config);
      AppLogger.d('BOOT', 'Notification bootstrap attached');

      if (!mounted) {
        translationController.dispose();
        return;
      }

      setState(() {
        _authController = authController;
        _translationController = translationController;
      });
      AppLogger.d('BOOT', 'App started');
    } catch (error, stackTrace) {
      AppLogger.e('BOOT', 'Bootstrap failed', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _BootstrapErrorApp(error: _error!);
    }

    final authController = _authController;
    final translationController = _translationController;
    if (authController == null || translationController == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DomlyLoadingScreen(
          logoAsset: domlyLogoAsset(widget.config.flavor),
          title: widget.config.flavor == AppFlavor.pro ? 'Domly Pro' : 'DOMLY',
        ),
      );
    }

    return DomlyApp(
      config: widget.config,
      authController: authController,
      translationController: translationController,
    );
  }
}

Future<void> _initializePreferredOrientations() async {
  if (kIsWeb) {
    return;
  }
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).timeout(const Duration(seconds: 3));
  } catch (error, stackTrace) {
    AppLogger.w('BOOT', 'Failed to lock preferred orientations: $error');
    AppLogger.e('BOOT', 'Preferred orientation error', error, stackTrace);
  }
}

Future<SharedPreferences?> _loadPreferences() async {
  try {
    return await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 5),
    );
  } catch (error, stackTrace) {
    AppLogger.w('BOOT', 'SharedPreferences unavailable: $error');
    AppLogger.e('BOOT', 'SharedPreferences init error', error, stackTrace);
    return null;
  }
}

Future<void> _initializeFirebase(AppConfig config) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.forFlavor(config.flavor),
    ).timeout(const Duration(seconds: 15));
  } on TimeoutException {
    AppLogger.w('BOOT', 'Firebase initialization timed out, continuing anyway');
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') {
      rethrow;
    }
  }
}

void _attachNotificationBootstrap(AppConfig config) {
  String? initializedForUserId;
  Future<void> initializeForResolvedUserId() async {
    final userId =
        AuthService.temporarySessionUid ?? AuthService.restoredSessionUid;
    if (userId == null || initializedForUserId == userId) {
      return;
    }
    initializedForUserId = userId;
    try {
      await NotificationService(
        userId: userId,
        adminSurface: config.adminSurface,
      ).init();
    } catch (_) {
      // Push initialization must not block app startup.
    }
  }

  unawaited(initializeForResolvedUserId());
  AuthService.temporarySessionUidListenable.addListener(() {
    unawaited(initializeForResolvedUserId());
  });
  AuthService.restoredSessionUidListenable.addListener(() {
    unawaited(initializeForResolvedUserId());
  });
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Ошибка запуска приложения'.tr(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Стартовый экран не был открыт из-за ошибки инициализации.'
                      .tr(),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  error.toString(),
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
