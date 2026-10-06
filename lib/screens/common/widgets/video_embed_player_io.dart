import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildVideoEmbedPlayer({
  required String videoUrl,
  required BorderRadius borderRadius,
}) {
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..loadRequest(Uri.parse(_resolvedPlayerUrl(videoUrl)));

  return ClipRRect(
    borderRadius: borderRadius,
    child: WebViewWidget(controller: controller),
  );
}

String _resolvedPlayerUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) {
    return rawUrl;
  }

  final host = uri.host.toLowerCase();
  if (host.contains('youtube.com')) {
    final videoId = uri.queryParameters['v'];
    if (videoId != null && videoId.isNotEmpty) {
      return 'https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1&rel=0';
    }
  }
  if (host.contains('youtu.be')) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isNotEmpty) {
      return 'https://www.youtube.com/embed/${segments.first}?autoplay=1&playsinline=1&rel=0';
    }
  }

  return rawUrl;
}
