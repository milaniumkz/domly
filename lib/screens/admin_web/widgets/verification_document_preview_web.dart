// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

Widget buildVerificationDocumentPreview({
  required String url,
  required BorderRadius borderRadius,
  BoxFit fit = BoxFit.cover,
}) {
  final sourceUrl = url.trim();
  final viewType =
      'domly-verification-doc-${sourceUrl.hashCode}-${fit.name.hashCode}';

  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = sourceUrl
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#F8FAFC';
    iframe.allowFullscreen = true;
    return iframe;
  });

  return ClipRRect(
    borderRadius: borderRadius,
    child: HtmlElementView(viewType: viewType),
  );
}
