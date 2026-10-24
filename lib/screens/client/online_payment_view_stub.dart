import 'package:domly/localization/translation_controller.dart';
import 'package:flutter/material.dart';

class OnlinePaymentView extends StatelessWidget {
  const OnlinePaymentView({
    super.key,
    required this.html,
    this.baseUrl,
  });

  final String html;
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    return const SizedBox.shrink();
  }
}
