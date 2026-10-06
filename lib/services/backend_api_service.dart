import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../app/app_env.dart';
import 'session_store.dart';

class BackendApiException implements Exception {
  const BackendApiException({
    required this.code,
    required this.message,
    required this.statusCode,
  });

  final String code;
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class BackendApiService {
  BackendApiService._();

  static final BackendApiService instance = BackendApiService._();

  final http.Client _client = http.Client();
  final SessionStore _sessionStore = SessionStore();
  Future<void>? _refreshInFlight;

  Uri _uri(String path, [Map<String, String?>? query]) {
    final base = AppEnv.backendBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalizedPath');
    final cleanQuery = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && value.isNotEmpty) {
        cleanQuery[key] = value;
      }
    });
    return cleanQuery.isEmpty ? uri : uri.replace(queryParameters: cleanQuery);
  }

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, String?>? query,
    bool authenticated = true,
  }) async {
    final data = await _request(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, String?>? query,
    bool authenticated = true,
  }) async {
    final data = await _request(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> postMap(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final data = await _request(
      'POST',
      path,
      body: body,
      authenticated: authenticated,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> patchMap(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final data = await _request(
      'PATCH',
      path,
      body: body,
      authenticated: authenticated,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> delete(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    await _request('DELETE', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> uploadFile({
    required String path,
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const <String, String>{},
  }) async {
    final token = await _sessionStore.accessToken();
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: _mediaType(contentType),
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decodeResponse(response);
    return Map<String, dynamic>.from(data as Map);
  }

  MediaType _mediaType(String contentType) {
    final parts = contentType.split('/');
    if (parts.length != 2) return MediaType('application', 'octet-stream');
    return MediaType(parts[0], parts[1]);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String?>? query,
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retryOnUnauthorized = true,
  }) async {
    final token = authenticated ? await _sessionStore.accessToken() : null;
    final response = await _send(
      method,
      path,
      query: query,
      body: body,
      token: token,
    );

    if (response.statusCode == 401 && authenticated && retryOnUnauthorized) {
      await _refreshSession();
      return _request(
        method,
        path,
        query: query,
        body: body,
        authenticated: authenticated,
        retryOnUnauthorized: false,
      );
    }

    return _decodeResponse(response);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Map<String, dynamic>? body,
    String? token,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    final uri = _uri(path, query);
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return _client.delete(uri, headers: headers, body: encodedBody);
      default:
        throw ArgumentError.value(method, 'method');
    }
  }

  dynamic _decodeResponse(http.Response response) {
    final rawBody = utf8.decode(response.bodyBytes);
    dynamic decoded;
    if (rawBody.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(rawBody);
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = decoded is Map ? decoded : const <String, dynamic>{};
      throw BackendApiException(
        code: (map['code'] ?? 'http_${response.statusCode}').toString(),
        message: _messageFrom(map, fallback: 'Сервис временно недоступен.'),
        statusCode: response.statusCode,
      );
    }

    if (decoded is Map && decoded['ok'] == false) {
      throw BackendApiException(
        code: (decoded['code'] ?? 'backend_error').toString(),
        message: _messageFrom(
          decoded,
          fallback: 'Не удалось выполнить запрос.',
        ),
        statusCode: response.statusCode,
      );
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded ?? <String, dynamic>{};
  }

  String _messageFrom(Map<dynamic, dynamic> map, {required String fallback}) {
    for (final key in const ['messageRu', 'message', 'error']) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  Future<void> _refreshSession() async {
    final current = _refreshInFlight;
    if (current != null) {
      return current;
    }
    final completer = Completer<void>();
    _refreshInFlight = completer.future;
    try {
      final refreshToken = await _sessionStore.refreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        await _sessionStore.clearBackendSession();
        throw const BackendApiException(
          code: 'unauthenticated',
          message: 'Войдите в аккаунт заново.',
          statusCode: 401,
        );
      }
      final response = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      await _saveAuthData(data);
      completer.complete();
    } catch (error, stackTrace) {
      await _sessionStore.clearBackendSession();
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<Map<String, dynamic>> sendOtp(String phone) {
    return postMap(
      '/auth/otp/request',
      body: {'phone': phone},
      authenticated: false,
    );
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
    required String role,
  }) async {
    final data = await postMap(
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code, 'role': role},
      authenticated: false,
    );
    await _saveAuthData(data);
    return data;
  }

  Future<Map<String, dynamic>> loginWithPassword({
    required String phone,
    required String password,
  }) async {
    final data = await postMap(
      '/auth/password/login',
      body: {'phone': phone, 'password': password},
      authenticated: false,
    );
    await _saveAuthData(data);
    return data;
  }

  Future<Map<String, dynamic>> me() => getMap('/me');

  Future<void> logout({String? deviceToken}) async {
    final refreshToken = await _sessionStore.refreshToken();
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await postMap(
          '/auth/logout',
          body: {
            'refreshToken': refreshToken,
            if (deviceToken != null && deviceToken.isNotEmpty)
              'deviceToken': deviceToken,
          },
        );
      }
    } finally {
      await _sessionStore.clearBackendSession();
    }
  }

  Future<void> saveDeviceToken({
    required String platform,
    required String token,
    required String role,
  }) async {
    await postMap(
      '/me/device-tokens',
      body: {'platform': platform, 'token': token, 'role': role},
    );
  }

  Future<void> _saveAuthData(Map<String, dynamic> data) async {
    final user = Map<String, dynamic>.from(data['user'] as Map);
    await _sessionStore.saveBackendSession(
      BackendSession(
        accessToken: data['accessToken'].toString(),
        refreshToken: data['refreshToken'].toString(),
        userId: user['id'].toString(),
        role: user['role'].toString(),
        phone: user['phone']?.toString(),
      ),
    );
  }
}
