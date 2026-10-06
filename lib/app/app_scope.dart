import 'package:flutter/widgets.dart';

import 'app_config.dart';
import '../localization/translation_controller.dart';
import '../services/auth_service.dart';

class AppScope extends InheritedNotifier<Listenable> {
  AppScope({
    super.key,
    required this.config,
    required this.authController,
    required this.translationController,
    required super.child,
  }) : super(
            notifier: Listenable.merge([
          authController,
          translationController,
        ]));

  final AppConfig config;
  final AuthController authController;
  final TranslationController translationController;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope == null) {
      throw StateError('AppScope не найден в дереве виджетов.'.tr());
    }
    return scope;
  }
}
