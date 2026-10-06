import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class OnlinePaymentView extends StatefulWidget {
  const OnlinePaymentView({
    super.key,
    required this.html,
    this.baseUrl,
  });

  final String html;
  final String? baseUrl;

  @override
  State<OnlinePaymentView> createState() => _OnlinePaymentViewState();
}

class _OnlinePaymentViewState extends State<OnlinePaymentView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(
        widget.html,
        baseUrl: widget.baseUrl,
      );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
