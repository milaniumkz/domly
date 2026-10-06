// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String? readBootRoute() {
  final rawName = html.window.name;
  final name = rawName?.trim() ?? '';
  const prefix = 'domly_boot_route=';
  if (!name.startsWith(prefix)) {
    return null;
  }
  final route = name.substring(prefix.length).trim();
  if (route.isEmpty || !route.startsWith('/')) {
    return null;
  }
  return route;
}

void clearBootRoute() {
  const prefix = 'domly_boot_route=';
  final rawName = html.window.name;
  final name = rawName ?? '';
  if (name.startsWith(prefix)) {
    html.window.name = '';
  }
}

void clearBootRouteUrl() {
  final uri = Uri.base;
  if (!uri.queryParameters.containsKey('boot_route')) {
    return;
  }
  final params = Map<String, String>.from(uri.queryParameters)
    ..remove('boot_route');
  final next = uri.replace(
    queryParameters: params.isEmpty ? null : params,
  );
  if (next.toString() == html.window.location.href) {
    return;
  }
  html.window.history.replaceState(null, '', next.toString());
}
