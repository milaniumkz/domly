import 'package:domly/localization/translation_controller.dart';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/material.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _submitTopLevelForm());
  }

  String _decodeHtml(String value) {
    final element = html.SpanElement()..innerHtml = value;
    return element.text ?? value;
  }

  void _submitTopLevelForm() {
    final actionMatch =
        RegExp(r'<form[^>]*action="([^"]+)"').firstMatch(widget.html);
    final action = widget.baseUrl?.trim().isNotEmpty == true
        ? widget.baseUrl!.trim()
        : _decodeHtml(actionMatch?.group(1) ?? '');
    if (action.isEmpty) {
      return;
    }
    final form = html.FormElement()
      ..method = RegExp(r'<form[^>]*method="get"', caseSensitive: false)
              .hasMatch(widget.html)
          ? 'GET'
          : 'POST'
      ..action = action
      ..target = '_self'
      ..style.display = 'none';
    final inputRegex =
        RegExp(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"[^>]*>');
    for (final match in inputRegex.allMatches(widget.html)) {
      form.children.add(
        html.InputElement()
          ..type = 'hidden'
          ..name = _decodeHtml(match.group(1) ?? '')
          ..value = _decodeHtml(match.group(2) ?? ''),
      );
    }
    html.document.body?.append(form);
    form.submit();
  }

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}
