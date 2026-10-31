import 'package:domly/localization/translation_controller.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/bcc_payment_return.dart';

class OnlinePaymentView extends StatefulWidget {
  const OnlinePaymentView({
    super.key,
    required this.html,
    this.baseUrl,
    this.onReturned,
  });

  final String html;
  final String? baseUrl;
  final VoidCallback? onReturned;

  @override
  State<OnlinePaymentView> createState() => _OnlinePaymentViewState();
}

class _OnlinePaymentViewState extends State<OnlinePaymentView> {
  late final WebViewController _controller;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.isMainFrame && isBccPaymentReturn(request.url)) {
            if (!_returned && mounted) {
              _returned = true;
              widget.onReturned?.call();
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(
        widget.html,
        baseUrl: widget.baseUrl,
      );
  }

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    return WebViewWidget(controller: _controller);
  }
}
