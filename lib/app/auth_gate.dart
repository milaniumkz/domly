import 'package:flutter/material.dart';

import 'app_scope.dart';

class AuthGate {
  static Future<bool> ensureAuthorized(BuildContext context) async {
    final authController = AppScope.of(context).authController;
    if (authController.isAuthenticated) {
      return true;
    }

    final result = await Navigator.pushNamed(
      context,
      '/auth',
      arguments: const {
        'popOnSuccess': true,
      },
    );
    return result == true;
  }
}
