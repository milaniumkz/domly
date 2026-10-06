// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void syncAppUrlRoute(String? route) {
  final normalizedRoute = (route ?? '').trim();
  if (normalizedRoute.isEmpty || !normalizedRoute.startsWith('/')) {
    return;
  }
  final params = Map<String, String>.from(Uri.base.queryParameters)
    ..remove('boot_route');
  final uri = Uri.base.replace(
    queryParameters: params.isEmpty ? null : params,
    fragment: _buildFragment(normalizedRoute),
  );
  if (uri.toString() == html.window.location.href) {
    return;
  }
  html.window.history.replaceState(null, '', uri.toString());
}

void syncDebugUrlRoute(String route) {
  final normalizedRoute = route.trim();
  if (normalizedRoute.isEmpty) {
    return;
  }
  final params = Map<String, String>.from(Uri.base.queryParameters)
    ..remove('boot_route')
    ..remove('debug_route');
  final fragment = _buildFragment(
    normalizedRoute.startsWith('/') ? normalizedRoute : '/$normalizedRoute',
  );
  final uri = Uri.base.replace(
    queryParameters: params.isEmpty ? null : params,
    fragment: fragment,
  );
  if (uri.toString() == html.window.location.href) {
    return;
  }
  html.window.history.replaceState(null, '', uri.toString());
}

String _buildFragment(String route) {
  final fragmentQuery = <String, String>{};
  final params = Map<String, String>.from(Uri.base.queryParameters)
    ..remove('boot_route');
  for (final entry in params.entries) {
    if (entry.key.startsWith('debug_')) {
      fragmentQuery[entry.key] = entry.value;
    }
  }
  return fragmentQuery.isEmpty
      ? route
      : Uri(path: route, queryParameters: fragmentQuery).toString();
}

void clearDebugUrlSession({String? route}) {
  final params = Map<String, String>.from(Uri.base.queryParameters)
    ..remove('boot_route')
    ..removeWhere((key, _) => key.startsWith('debug_'));
  final nextRoute = (route ?? '').trim();
  final nextFragment = nextRoute.isEmpty
      ? null
      : (nextRoute.startsWith('/') ? nextRoute : '/$nextRoute');
  final uri = Uri.base.replace(
    queryParameters: params.isEmpty ? null : params,
    fragment: nextFragment,
  );
  if (uri.toString() == html.window.location.href) {
    return;
  }
  html.window.history.replaceState(null, '', uri.toString());
}
