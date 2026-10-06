import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SessionSurface { customer, pro, admin }

class SessionStore {
  SessionStore({SessionSurface? surface}) : _surface = surface;

  final SessionSurface? _surface;
  static SessionSurface activeSurface = SessionSurface.customer;
  static final invalidation = ValueNotifier<int>(0);
  SessionSurface get surface => _surface ?? activeSurface;
  String storageKey(String key) => '${key}_${surface.name}';
  static String appKey(String key) => '${key}_${activeSurface.name}';
  bool acceptsRole(String role) => switch (surface) {
        SessionSurface.customer => role == 'customer',
        SessionSurface.pro => role == 'cleaner',
        SessionSurface.admin => role == 'admin' || role == 'superadmin',
      };

  static const _authKey = 'domly_auth_ok';
  static const _accessTokenKey = 'domly_backend_access_token';
  static const _refreshTokenKey = 'domly_backend_refresh_token';
  static const _userIdKey = 'domly_backend_user_id';
  static const _userRoleKey = 'domly_backend_user_role';
  static const _userPhoneKey = 'domly_backend_user_phone';

  Future<bool> isAuthenticated() async => await backendSession() != null;

  Future<void> setAuthenticated(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey(_authKey), value);
  }

  Future<BackendSession?> backendSession() async {
    final prefs = await SharedPreferences.getInstance();
    final migrationKey = storageKey('domly_legacy_session_checked');
    if (prefs.getBool(migrationKey) != true) {
      await prefs.setBool(migrationKey, true);
      final legacyRole = prefs.getString(_userRoleKey);
      if (prefs.getString(storageKey(_accessTokenKey)) == null &&
          legacyRole != null &&
          acceptsRole(legacyRole)) {
        final access = prefs.getString(_accessTokenKey);
        final refresh = prefs.getString(_refreshTokenKey);
        final userId = prefs.getString(_userIdKey);
        if (access?.isNotEmpty == true &&
            refresh?.isNotEmpty == true &&
            userId?.isNotEmpty == true) {
          await saveBackendSession(BackendSession(
              accessToken: access!,
              refreshToken: refresh!,
              userId: userId!,
              role: legacyRole,
              phone: prefs.getString(_userPhoneKey)));
        }
      }
    }
    final accessToken = prefs.getString(storageKey(_accessTokenKey));
    final refreshToken = prefs.getString(storageKey(_refreshTokenKey));
    final userId = prefs.getString(storageKey(_userIdKey));
    final role = prefs.getString(storageKey(_userRoleKey));
    final phone = prefs.getString(storageKey(_userPhoneKey));
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        role == null ||
        !acceptsRole(role)) return null;
    return BackendSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId,
        role: role,
        phone: phone);
  }

  Future<String?> accessToken() async => (await backendSession())?.accessToken;
  Future<String?> refreshToken() async =>
      (await backendSession())?.refreshToken;

  Future<void> saveBackendSession(BackendSession session) async {
    if (!acceptsRole(session.role))
      throw StateError('Account belongs to a different application');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey('domly_legacy_session_checked'), true);
    await prefs.setBool(storageKey(_authKey), true);
    await prefs.setString(storageKey(_accessTokenKey), session.accessToken);
    await prefs.setString(storageKey(_refreshTokenKey), session.refreshToken);
    await prefs.setString(storageKey(_userIdKey), session.userId);
    await prefs.setString(storageKey(_userRoleKey), session.role);
    if (session.phone?.isNotEmpty == true) {
      await prefs.setString(storageKey(_userPhoneKey), session.phone!);
    } else {
      await prefs.remove(storageKey(_userPhoneKey));
    }
  }

  Future<void> clearBackendSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey('domly_legacy_session_checked'), true);
    for (final key in [
      _authKey,
      _accessTokenKey,
      _refreshTokenKey,
      _userIdKey,
      _userRoleKey,
      _userPhoneKey,
      'domly_authenticated_session',
      'domly_authenticated_session_uid',
      'domly_authenticated_session_secret'
    ]) {
      await prefs.remove(storageKey(key));
    }
    if (surface == activeSurface) invalidation.value++;
  }
}

class BackendSession {
  const BackendSession(
      {required this.accessToken,
      required this.refreshToken,
      required this.userId,
      required this.role,
      this.phone});
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String role;
  final String? phone;
}
