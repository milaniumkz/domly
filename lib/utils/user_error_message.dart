class UserErrorMessage {
  const UserErrorMessage._();

  static bool isAuthError(Object? error) {
    final code = _errorCode(error);
    if (code != null && _authCodes.contains(code)) return true;
    final text = _raw(error).toLowerCase();
    return text.contains('unauthorized') ||
        text.contains('unauthenticated') ||
        text.contains('authentication required') ||
        text.contains('permission-denied') ||
        text.contains('permission denied') ||
        text.contains('missing or insufficient permissions') ||
        text.contains('401');
  }

  static String title(
    Object? error, {
    String fallback = 'Не удалось выполнить',
  }) {
    if (isAuthError(error)) return 'Нужно войти заново';
    final text = _raw(error).toLowerCase();
    if (text.contains('unavailable') || text.contains('deadline-exceeded')) {
      return 'Сервис временно недоступен';
    }
    if (text.contains('invalid-argument')) return 'Проверьте данные';
    return fallback;
  }

  static String message(
    Object? error, {
    String fallback = 'Попробуйте ещё раз.',
  }) {
    if (isAuthError(error)) {
      return 'Сессия истекла. Войдите в приложение заново.';
    }
    final code = _errorCode(error);
    if (code != null) {
      return _fromCode(code, _errorMessage(error), fallback);
    }

    var text = _raw(error)
        .replaceFirst('FlutterError: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
        .replaceAll(RegExp(r'#\d+\s+.*'), '')
        .trim();
    final lower = text.toLowerCase();
    if (lower.contains('keyboard') ||
        lower.contains('клавиатур') ||
        lower.contains('textinput')) {
      return 'Не удалось отправить данные. Закройте клавиатуру и нажмите кнопку ещё раз.';
    }
    if (lower.contains('customerid required') ||
        lower.contains('userid required') ||
        lower.contains('orderid required')) {
      return 'Сессия истекла. Войдите в приложение заново.';
    }
    if (lower.contains('not your order') || lower.contains('access denied')) {
      return 'Нет доступа к этому заказу. Обновите экран.';
    }
    if (lower.contains('bad request') || lower.contains('invalid argument')) {
      return 'Проверьте заполненные данные и попробуйте ещё раз.';
    }
    if (lower.contains('internal')) {
      return 'Сервис временно недоступен. Попробуйте позже.';
    }
    if (lower.contains('resource-exhausted')) {
      return 'Слишком много запросов. Попробуйте позже.';
    }
    if (lower.contains('unavailable')) {
      return 'Нет связи с сервером. Попробуйте позже.';
    }
    if (text.length > 160 ||
        lower.contains('package:') ||
        lower.contains('cloudfunctionshostapi')) {
      return fallback;
    }
    return text.isEmpty ? fallback : text;
  }

  static String _fromCode(String code, String? rawMessage, String fallback) {
    final message = (rawMessage ?? '').trim();
    switch (code) {
      case 'permission-denied':
      case 'unauthenticated':
      case 'unauthorized':
        return 'Сессия истекла. Войдите в приложение заново.';
      case 'invalid-argument':
        return message.isNotEmpty &&
                message.length <= 120 &&
                !_looksTechnical(message)
            ? message
            : 'Проверьте заполненные данные.';
      case 'resource-exhausted':
        return 'Слишком много запросов. Попробуйте позже.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'Нет связи с сервером. Попробуйте позже.';
      case 'internal':
        return 'Сервис временно недоступен. Попробуйте позже.';
      default:
        return message.isNotEmpty &&
                message.length <= 120 &&
                !_looksTechnical(message)
            ? message
            : fallback;
    }
  }

  static String _raw(Object? error) => (error ?? '').toString();

  static String? _errorCode(Object? error) {
    try {
      final dynamic value = error;
      final code = value.code?.toString().trim();
      return code == null || code.isEmpty ? null : code;
    } catch (_) {
      return null;
    }
  }

  static String? _errorMessage(Object? error) {
    try {
      final dynamic value = error;
      return value.message?.toString();
    } catch (_) {
      return null;
    }
  }

  static bool _looksTechnical(String message) {
    final lower = message.toLowerCase();
    return lower.contains('firebase') ||
        lower.contains('package:') ||
        lower.contains('cloudfunctionshostapi') ||
        lower.contains('customerid required') ||
        lower.contains('orderid required') ||
        lower.contains('keyboard') ||
        lower.contains('textinput');
  }

  static const _authCodes = {
    'permission-denied',
    'unauthenticated',
    'unauthorized',
    'user-token-expired',
    'user-disabled',
    'invalid-user-token',
  };
}
