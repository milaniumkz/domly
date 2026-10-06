import 'package:url_launcher/url_launcher.dart';

class CallService {
  static Future<bool> callPhone(String phone) async {
    final normalized = normalizePhoneForCall(phone);
    if (normalized.isEmpty) {
      return false;
    }
    final uri = Uri.parse('tel:$normalized');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return true;
      }
    } catch (_) {
      // Fall through to platform default mode below.
    }
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  static String normalizePhoneForCall(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }

    if (digitsOnly.length == 10) {
      return '+7$digitsOnly';
    }

    if (digitsOnly.length == 11) {
      if (digitsOnly.startsWith('8')) {
        return '+7${digitsOnly.substring(1)}';
      }
      if (digitsOnly.startsWith('7')) {
        return '+$digitsOnly';
      }
    }

    if (digitsOnly.length > 11 && digitsOnly.startsWith('7')) {
      return '+$digitsOnly';
    }

    if (trimmed.startsWith('+')) {
      return '+$digitsOnly';
    }

    return digitsOnly;
  }
}
