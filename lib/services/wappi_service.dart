import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/app_env.dart';

class WappiService {
  bool get isConfigured =>
      AppEnv.wappiToken.isNotEmpty && AppEnv.wappiProfileId.isNotEmpty;

  Future<void> sendOtp({
    required String phoneE164Digits,
    required String code,
  }) async {
    if (!isConfigured) {
      throw const WappiException(
        'Wappi не настроен. Передайте WAPPI_TOKEN и WAPPI_PROFILE_ID.',
      );
    }

    const profileId = AppEnv.wappiProfileId;
    final url = Uri.parse(
      '${AppEnv.wappiBaseUrl}${AppEnv.wappiSendPath}?profile_id=$profileId',
    );

    final payload = {
      'phone': phoneE164Digits,
      'to': phoneE164Digits,
      'chatId': '$phoneE164Digits@c.us',
      'message': 'DOMLY код подтверждения: $code',
      'text': 'DOMLY код подтверждения: $code',
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': AppEnv.wappiToken,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WappiException(
        'Ошибка отправки кода через Wappi: ${response.statusCode}',
      );
    }
  }
}

class WappiException implements Exception {
  const WappiException(this.message);

  final String message;

  @override
  String toString() => message;
}
