/// App-wide logging and error handling
/// Replaces print() with structured logging

import 'package:flutter/foundation.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class AppLogger {
  AppLogger._();

  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.error;

  /// Set minimum log level (release mode defaults to info)
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Debug log - only in debug mode
  static void d(String tag, String message, [Object? error]) {
    if (_minLevel.index > LogLevel.debug.index) return;
    _log('DEBUG', tag, message, error);
  }

  /// Info log
  static void i(String tag, String message, [Object? error]) {
    if (_minLevel.index > LogLevel.info.index) return;
    _log('INFO', tag, message, error);
  }

  /// Warning log
  static void w(String tag, String message, [Object? error]) {
    if (_minLevel.index > LogLevel.warning.index) return;
    _log('WARN', tag, message, error);
  }

  /// Error log - always shown
  static void e(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', tag, message, error);
    if (stackTrace != null && kDebugMode) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static void _log(String level, String tag, String message, [Object? error]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final errorStr = error != null ? ' | $error' : '';
    final log = '[$timestamp] [$level] [$tag] $message$errorStr';

    // In release mode, errors could be sent to Crashlytics/Sentry
    if (level == 'ERROR' && !kDebugMode) {
      // TODO: Send to Crashlytics when integrated
      // FirebaseCrashlytics.instance.recordError(error, stackTrace);
    }

    if (kDebugMode || level == 'ERROR') {
      debugPrint(log);
    }
  }
}

/// Structured error types for the app
class AppException implements Exception {
  final String code;
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;

  const AppException({
    required this.code,
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'AppException($code): $message';
}

/// Specific error types
class PaymentException extends AppException {
  const PaymentException({
    required String message,
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          code: 'PAYMENT_ERROR',
          message: message,
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

class NetworkException extends AppException {
  const NetworkException({
    required String message,
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          code: 'NETWORK_ERROR',
          message: message,
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

class ValidationException extends AppException {
  const ValidationException({
    required String message,
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          code: 'VALIDATION_ERROR',
          message: message,
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

class AuthException extends AppException {
  const AuthException({
    required String message,
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          code: 'AUTH_ERROR',
          message: message,
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

/// Safe execution wrapper with automatic logging
Future<T?> safeExecute<T>({
  required Future<T> Function() action,
  String tag = 'App',
  String? errorMessage,
  T? fallback,
}) async {
  try {
    return await action();
  } on AppException catch (e) {
    AppLogger.e(tag, e.message, e);
    return fallback;
  } catch (e, stackTrace) {
    AppLogger.e(tag, errorMessage ?? e.toString(), e, stackTrace);
    return fallback;
  }
}
