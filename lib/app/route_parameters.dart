import 'package:flutter/widgets.dart';

/// Keep query arguments when the navigator matches a protected route by path.
RouteSettings routeWithQueryArguments(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '');
  if (uri == null || uri.queryParameters.isEmpty) return settings;
  return RouteSettings(
    name: uri.path,
    arguments: <String, dynamic>{
      ...uri.queryParameters,
      if (settings.arguments is Map)
        ...Map<String, dynamic>.from(settings.arguments as Map),
    },
  );
}

/// Restore a protected route while auth startup temporarily rewrites the URL.
RouteSettings restoreBootRouteArguments(
    RouteSettings settings, RouteSettings boot) {
  final current = routeWithQueryArguments(settings);
  final initial = routeWithQueryArguments(boot);
  if (current.name != initial.name || initial.arguments is! Map) return current;
  return RouteSettings(name: current.name, arguments: <String, dynamic>{
    ...Map<String, dynamic>.from(initial.arguments as Map),
    if (current.arguments is Map)
      ...Map<String, dynamic>.from(current.arguments as Map),
  });
}

/// Only route identifiers belong in browser history; never serialize user data.
String routeUrlWithArguments(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '/') ?? Uri(path: '/');
  final query = <String, String>{...uri.queryParameters};
  const identifiers = {
    'orderId',
    'slotId',
    'id',
    'subscriptionId',
    'customerPackageId',
    'houseId',
    'videoId',
    'chatId',
    'section',
  };
  if (settings.arguments is Map) {
    for (final entry in (settings.arguments as Map).entries) {
      if (identifiers.contains(entry.key) &&
          entry.value is String &&
          (entry.value as String).isNotEmpty) {
        query[entry.key as String] = entry.value as String;
      }
    }
  }
  return uri.replace(queryParameters: query.isEmpty ? null : query).toString();
}
