// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

Widget buildVideoEmbedPlayer({
  required String videoUrl,
  required BorderRadius borderRadius,
}) {
  final sourceUrl = videoUrl.trim();
  final viewType = 'domly-video-${sourceUrl.hashCode}';

  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    if (_isDirectVideo(sourceUrl)) {
      final video = html.VideoElement()
        ..src = sourceUrl
        ..controls = true
        ..autoplay = true
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#000000';
      return video;
    }

    final iframe = html.IFrameElement()
      ..src = _resolvedPlayerUrl(sourceUrl)
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true;
    iframe.allow =
        'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share';
    return iframe;
  });

  return ClipRRect(
    borderRadius: borderRadius,
    child: HtmlElementView(viewType: viewType),
  );
}

bool _isDirectVideo(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.endsWith('.mp4') ||
      path.endsWith('.webm') ||
      path.endsWith('.ogg') ||
      path.endsWith('.mov') ||
      path.endsWith('.m3u8');
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
