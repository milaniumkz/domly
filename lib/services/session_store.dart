import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _authKey = 'domly_auth_ok';
  static const _accessTokenKey = 'domly_backend_access_token';
  static const _refreshTokenKey = 'domly_backend_refresh_token';
  static const _userIdKey = 'domly_backend_user_id';
  static const _userRoleKey = 'domly_backend_user_role';
  static const _userPhoneKey = 'domly_backend_user_phone';

  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_authKey) ?? false;
  }

  Future<void> setAuthenticated(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authKey, value);
  }

  Future<BackendSession?> backendSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessTokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);
    final userId = prefs.getString(_userIdKey);
    final role = prefs.getString(_userRoleKey);
    final phone = prefs.getString(_userPhoneKey);
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        role == null ||
        role.isEmpty) {
      return null;
    }
    return BackendSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId,
      role: role,
      phone: phone,
    );
  }

  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  Future<String?> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> saveBackendSession(BackendSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authKey, true);
    await prefs.setString(_accessTokenKey, session.accessToken);
    await prefs.setString(_refreshTokenKey, session.refreshToken);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_userRoleKey, session.role);
    if (session.phone?.isNotEmpty == true) {
      await prefs.setString(_userPhoneKey, session.phone!);
    } else {
      await prefs.remove(_userPhoneKey);
    }
  }

  Future<void> clearBackendSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_userPhoneKey);
  }
}

class BackendSession {
  const BackendSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.role,
    this.phone,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String role;
  final String? phone;
}
