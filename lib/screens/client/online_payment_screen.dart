import 'package:flutter/material.dart';

import '../../localization/translation_controller.dart';
import '../../ui/domly_ui.dart';
import 'online_payment_view.dart';

class OnlinePaymentScreen extends StatelessWidget {
  const OnlinePaymentScreen({
    super.key,
    required this.orderId,
    required this.paymentHtml,
    this.actionUrl,
  });

  final String orderId;
  final String paymentHtml;
  final String? actionUrl;

  static OnlinePaymentScreen fromArgs(Object? args) {
    final map = args is Map ? Map<String, dynamic>.from(args) : {};
    return OnlinePaymentScreen(
      orderId: (map['orderId'] ?? '').toString(),
      paymentHtml: (map['paymentHtml'] ?? '').toString(),
      actionUrl: map['actionUrl']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DomlyColors.background,
      appBar: AppBar(
        title: Text('Онлайн-платёж'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/client/orders',
              (route) => false,
            );
          },
        ),
      ),
      body: paymentHtml.trim().isEmpty
          ? Center(
              child: Text(
                'Не удалось открыть оплату'.tr(),
                style: const TextStyle(color: DomlyColors.foreground),
              ),
            )
          : OnlinePaymentView(
              html: paymentHtml,
              baseUrl: actionUrl,
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DomlySecondaryButton(
          label: 'Вернуться к заказам'.tr(),
          onPressed: () {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/client/orders',
              (route) => false,
            );
          },
        ),
      ),
    );
  }
}
