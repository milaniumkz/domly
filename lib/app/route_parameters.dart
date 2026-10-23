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
