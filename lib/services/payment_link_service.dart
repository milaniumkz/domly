import 'dart:async';

import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

class PaymentLinkService {
  PaymentLinkService._();

  static Future<T> runBlocking<T>(
    BuildContext context, {
    required Future<T> Function() task,
    String message = 'Выполняем операцию...',
  }) async {
    final dialogContextCompleter = Completer<BuildContext>();
    var taskCompleted = false;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        onPopInvokedWithResult: (_, __) {},
        canPop: false,
        child: Builder(
          builder: (_) {
            if (!dialogContextCompleter.isCompleted) {
              dialogContextCompleter.complete(dialogContext);
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (taskCompleted && dialogContext.mounted) {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              }
            });
            return _PaymentBlockingLoader(message: message);
          },
        ),
      ),
    ));

    // Let the dialog route mount before the async task starts. Without this,
    // a fast task can race the modal route and leave the loader stuck.
    await Future<void>.delayed(Duration.zero);

    try {
      return await task();
    } finally {
      taskCompleted = true;
      if (dialogContextCompleter.isCompleted) {
        final dialogContext = await dialogContextCompleter.future;
        if (dialogContext.mounted) {
          Navigator.of(dialogContext, rootNavigator: true).pop();
        }
      }
    }
  }
}

class _PaymentBlockingLoader extends StatelessWidget {
  const _PaymentBlockingLoader({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x660B1020),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFF2D6B4F),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Подождите…'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message.isEmpty
                      ? 'Идёт обработка данных. Пожалуйста, не закрывайте экран.'
                      : '$message Не закрывайте экран.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
