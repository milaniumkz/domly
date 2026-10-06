import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_config.dart';
import '../app/debug_session.dart';
import '../app/debug_url_sync.dart';
import '../app/app_flavor.dart';
import 'backend_api_service.dart';
import 'session_store.dart';

class OtpRequestResult {
  const OtpRequestResult({
    required this.codeSent,
    this.signedIn = false,
    this.fallbackCode,
  });

  final bool codeSent;
  final bool signedIn;
  final String? fallbackCode;
}

class AuthService {
  static const String _temporarySessionUidKey = 'domly_temporary_session_uid';
  static const String _authenticatedSessionKey = 'domly_authenticated_session';
  static const String _authenticatedSessionUidKey =
      'domly_authenticated_session_uid';
  static const String _authenticatedSessionSecretKey =
      'domly_authenticated_session_secret';
  AuthService({
    Object? firestore,
    Object? firebaseAuth,
    required AppConfig config,
  }) : _config = config;

  final AppConfig _config;
  static final ValueNotifier<String?> temporarySessionUidListenable =
      ValueNotifier<String?>(null);
  static final ValueNotifier<String?> restoredSessionUidListenable =
      ValueNotifier<String?>(null);
  String? _localFallbackPhone;
  String? _localFallbackCode;
  DateTime? _localFallbackExpiresAt;
  bool get _allowLocalOtpFallback => false;

  static String? get temporarySessionUid => temporarySessionUidListenable.value;
  static String? get restoredSessionUid => restoredSessionUidListenable.value;
  static bool get hasTemporarySession => temporarySessionUid != null;

  static void _setRestoredSessionUid(String? uid) {
    final normalized = uid?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (restoredSessionUidListenable.value == next) {
      return;
    }
    restoredSessionUidListenable.value = next;
  }

  static Future<bool> hasPersistedAuthenticatedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasFlag = prefs.getBool(_authenticatedSessionKey) ?? false;
      final uid = prefs.getString(_authenticatedSessionUidKey)?.trim();
      return hasFlag || (uid != null && uid.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  static Future<String?> persistedAuthenticatedSessionUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_authenticatedSessionUidKey)?.trim();
      return uid == null || uid.isEmpty ? null : uid;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> persistedAuthenticatedSessionSecret() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secret = prefs.getString(_authenticatedSessionSecretKey)?.trim();
      return secret == null || secret.isEmpty ? null : secret;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistAuthenticatedSession(
    bool value, {
    String? uid,
    String? sessionSecret,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_authenticatedSessionKey, true);
        final normalizedUid = uid?.trim();
        if (normalizedUid != null && normalizedUid.isNotEmpty) {
          await prefs.setString(_authenticatedSessionUidKey, normalizedUid);
        }
        final normalizedSecret = sessionSecret?.trim();
        if (normalizedSecret != null && normalizedSecret.isNotEmpty) {
          await prefs.setString(
            _authenticatedSessionSecretKey,
            normalizedSecret,
          );
        }
      } else {
        await prefs.remove(_authenticatedSessionKey);
        await prefs.remove(_authenticatedSessionUidKey);
        await prefs.remove(_authenticatedSessionSecretKey);
      }
    } catch (_) {}
  }

  static Future<void> restorePersistedTemporarySession() async {
    // Migrate away from obsolete offline login. Only backend JWT sessions grant access.
    clearTemporarySession();
  }

  static Future<void> _persistTemporarySessionUid(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalized = uid?.trim();
      if (normalized == null || normalized.isEmpty) {
        await prefs.remove(_temporarySessionUidKey);
      } else {
        await prefs.setString(_temporarySessionUidKey, normalized);
      }
    } catch (_) {}
  }

  Future<void> _ensureLocalPersistence() async {
    return;
  }

  Future<OtpRequestResult> sendOtp(String rawPhone) async {
    final phone = _normalizePhone(rawPhone);
    if (phone == null) {
      throw FlutterError(
        'Введите номер полностью в формате +7 (700) 000-00-00.',
      );
    }

    try {
      final data = await BackendApiService.instance.sendOtp(phone);
      return OtpRequestResult(
        codeSent: data['codeSent'] != false,
        fallbackCode: data['fallbackCode']?.toString(),
      );
    } on BackendApiException catch (e) {
      throw FlutterError(e.message);
    } catch (_) {
      throw FlutterError('Не удалось отправить код.');
    }
  }

  Future<bool> verifyOtp({
    required String rawPhone,
    required String code,
  }) async {
    final phone = _normalizePhone(rawPhone);
    if (phone == null || code.trim().length != 6) {
      return false;
    }

    if (_allowLocalOtpFallback && _canUseLocalFallback(phone, code.trim())) {
      throw FlutterError('Локальный вход отключен. Запросите новый SMS-код.');
    }

    try {
      final role = _config.flavor == AppFlavor.pro ? 'cleaner' : 'customer';
      final data = await BackendApiService.instance.verifyOtp(
        phone: phone,
        code: code.trim(),
        role: role,
      );
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final userId = user['id']?.toString();
      if (userId == null || userId.isEmpty) {
        throw FlutterError('Не удалось выполнить вход.');
      }
      clearTemporarySession();
      _localFallbackPhone = null;
      _localFallbackCode = null;
      _localFallbackExpiresAt = null;
      await _persistAuthenticatedSession(true, uid: userId);
      _setRestoredSessionUid(userId);
      return true;
    } on BackendApiException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 401) {
        return false;
      }
      throw FlutterError(e.message);
    } catch (_) {
      throw FlutterError('Не удалось выполнить вход.');
    }
  }

  OtpRequestResult _issueLocalFallbackCode(String phone) {
    final code = _generateLocalOtpCode();
    _localFallbackPhone = phone;
    _localFallbackCode = code;
    _localFallbackExpiresAt = DateTime.now().add(const Duration(minutes: 10));
    return OtpRequestResult(codeSent: true, fallbackCode: code);
  }

  Future<void> restoreAuthenticatedSession(String uid) async {
    final session = await SessionStore().backendSession();
    if (session == null || session.userId.trim().isEmpty) {
      return;
    }
    try {
      await BackendApiService.instance.me();
      await _persistAuthenticatedSession(true, uid: session.userId);
      _setRestoredSessionUid(session.userId);
    } catch (_) {
      await SessionStore().clearBackendSession();
      await _persistAuthenticatedSession(false);
      _setRestoredSessionUid(null);
    }
  }

  bool _shouldUseLocalOtpFallback(String code, String? message) {
    final normalizedMessage = (message ?? '').trim().toLowerCase();
    return code == 'unavailable' ||
        code == 'internal' ||
        code == 'deadline-exceeded' ||
        normalizedMessage.contains('сервис авторизации временно недоступен') ||
        normalizedMessage.contains('billing is disabled') ||
        normalizedMessage.contains('wappi') ||
        normalizedMessage.contains('otp-delivery-unavailable');
  }

  bool _canUseLocalFallback(String phone, String code) {
    final expiresAt = _localFallbackExpiresAt;
    if (_localFallbackPhone != phone ||
        _localFallbackCode != code ||
        expiresAt == null) {
      return false;
    }
    return DateTime.now().isBefore(expiresAt);
  }

  String _generateLocalOtpCode() {
    final seed = DateTime.now().microsecondsSinceEpoch % 1000000;
    return seed.toString().padLeft(6, '0');
  }

  static void clearTemporarySession() {
    temporarySessionUidListenable.value = null;
    unawaited(_persistTemporarySessionUid(null));
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw FlutterError('Введите логин и пароль.');
    }

    try {
      final phone = _normalizePhone(normalizedEmail) ?? normalizedEmail;
      final data = await BackendApiService.instance.loginWithPassword(
        phone: phone,
        password: password,
      );
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final role = user['role']?.toString();
      final userId = user['id']?.toString();
      final hasAccess = role == 'admin' || role == 'superadmin';
      if (!hasAccess || userId == null || userId.isEmpty) {
        throw FlutterError('У учетной записи нет прав для входа в админку.');
      }
      await _persistAuthenticatedSession(true, uid: userId);
      _setRestoredSessionUid(userId);
    } on BackendApiException catch (e) {
      throw FlutterError(e.message);
    }
  }

  Future<void> signOut() async {
    clearDebugUrlSession(route: _config.adminSurface ? '/admin/web' : '/auth');
    final currentUserId = DebugSession.uid ??
        AuthService.temporarySessionUid ??
        restoredSessionUid;
    clearTemporarySession();
    await _persistAuthenticatedSession(false);
    AuthService._setRestoredSessionUid(null);
    await BackendApiService.instance.logout().catchError((_) {});
    if (currentUserId != null) {
      // FCM remains Firebase transport, but token ownership is stored by backend.
    }
  }

  Future<void> deleteAccount() async {
    await BackendApiService.instance.delete('/me');
    await signOut();
  }

  String? _normalizePhone(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('8')) {
      return '7${digits.substring(1)}';
    }
    if (digits.length == 11 && digits.startsWith('7')) {
      return digits;
    }
    if (digits.length == 10) {
      return '7$digits';
    }
    return null;
  }
}

class AuthController extends ChangeNotifier {
  AuthController(
    this._authService, {
    required AppConfig config,
    Object? firebaseAuth,
  }) : _config = config;

  final AuthService _authService;
  final AppConfig _config;

  VoidCallback? _temporarySessionListener;
  String? _restoredSessionUid;
  String? _restoredSessionRole;
  bool _initialized = false;
  bool _isAdmin = false;
  bool _isManager = false;
  bool _isSuperAdmin = false;

  bool get _isDebugAdminSession =>
      DebugSession.enabled &&
      DebugSession.uid == 'admin_demo' &&
      _config.adminSurface;

  bool get initialized => _initialized;
  bool get isAuthenticated =>
      DebugSession.enabled ||
      _restoredSessionUid != null ||
      AuthService.hasTemporarySession;
  String? get currentUserId =>
      DebugSession.uid ??
      AuthService.temporarySessionUid ??
      _restoredSessionUid;
  bool get isAdmin => _isDebugAdminSession || _isAdmin || _isSuperAdmin;
  bool get isManager => _isManager;
  bool get isSuperAdmin => _isSuperAdmin;
  bool get hasBackofficeAccess => isAdmin || isManager;
  bool get canAccessCustomerSurface =>
      !_config.adminSurface && _config.flavor == AppFlavor.customer;
  bool get canAccessCleanerSurface =>
      !_config.adminSurface && _config.flavor == AppFlavor.pro;

  Future<void> init() async {
    _temporarySessionListener ??= () {
      _initialized = true;
      notifyListeners();
    };
    AuthService.temporarySessionUidListenable.addListener(
      _temporarySessionListener!,
    );
    final backendSession = await SessionStore().backendSession();
    if (backendSession != null) {
      _restoredSessionUid = backendSession.userId;
      _restoredSessionRole = backendSession.role;
      AuthService._setRestoredSessionUid(_restoredSessionUid);
      _applyBackendRole(backendSession.role);
      _initialized = true;
      notifyListeners();
      return;
    }

    try {
      final persistedSession =
          await AuthService.hasPersistedAuthenticatedSession();
      _restoredSessionUid = persistedSession
          ? await AuthService.persistedAuthenticatedSessionUid()
          : null;
      AuthService._setRestoredSessionUid(_restoredSessionUid);
      if (_restoredSessionUid != null) {
        await _authService.restoreAuthenticatedSession(_restoredSessionUid!);
        final session = await SessionStore().backendSession();
        _restoredSessionUid = session?.userId ?? _restoredSessionUid;
        _restoredSessionRole = session?.role;
      }
      await _syncUser(null, keepRestoredSession: persistedSession);
    } catch (_) {
      await _syncUser(null, keepRestoredSession: _restoredSessionUid != null);
    }
  }

  Future<void> refresh() =>
      _syncUser(null, keepRestoredSession: _restoredSessionUid != null);

  Future<OtpRequestResult> sendOtp(String phone) => _authService.sendOtp(phone);

  Future<bool> verifyOtp({required String phone, required String code}) async {
    final ok = await _authService.verifyOtp(rawPhone: phone, code: code);
    if (ok) {
      final session = await SessionStore().backendSession();
      _restoredSessionUid = session?.userId;
      _restoredSessionRole = session?.role;
      AuthService._setRestoredSessionUid(_restoredSessionUid);
      _applyBackendRole(_restoredSessionRole);
      _initialized = true;
      notifyListeners();
    }
    return ok;
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _authService.signInWithEmailPassword(
      email: email,
      password: password,
    );
    final session = await SessionStore().backendSession();
    _restoredSessionUid = session?.userId;
    _restoredSessionRole = session?.role;
    AuthService._setRestoredSessionUid(_restoredSessionUid);
    _applyBackendRole(_restoredSessionRole);
    _initialized = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _restoredSessionUid = null;
    _restoredSessionRole = null;
    AuthService._setRestoredSessionUid(null);
    await _syncUser(null);
  }

  Future<void> deleteAccount() async {
    await _authService.deleteAccount();
    _restoredSessionUid = null;
    _restoredSessionRole = null;
    AuthService._setRestoredSessionUid(null);
    await _syncUser(null);
  }

  void _applyBackendRole(String? role) {
    _isSuperAdmin = role == 'superadmin';
    _isAdmin = _isSuperAdmin || role == 'admin';
    _isManager = false;
  }

  Future<void> _syncUser(
    Object? user, {
    bool keepRestoredSession = false,
  }) async {
    if (!keepRestoredSession) {
      _restoredSessionUid = null;
      _restoredSessionRole = null;
    }
    AuthService._setRestoredSessionUid(_restoredSessionUid);
    _applyBackendRole(_restoredSessionRole);
    _initialized = true;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_temporarySessionListener != null) {
      AuthService.temporarySessionUidListenable.removeListener(
        _temporarySessionListener!,
      );
    }
    super.dispose();
  }
}
