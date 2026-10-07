import 'package:flutter/material.dart';

class DomlyTutorialTargets {
  // Each mounted page needs its own keys: covered routes remain mounted
  // while another page is pushed, including throughout its transition.
  static final _navigationKeys = Expando<List<GlobalKey>>();
  static final _navigationRoutes =
      <String, WeakReference<ModalRoute<dynamic>>>{};

  static List<GlobalKey> navigationKeys(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return List.generate(5, (_) => GlobalKey());
    final keys = _navigationKeys[route] ??= List.generate(
      5,
      (index) => GlobalKey(debugLabel: '${route.settings.name}_nav_$index'),
    );
    final name = route.settings.name;
    if (name != null &&
        (route.isCurrent ||
            _navigationRoutes[name]?.target?.isActive != true)) {
      _navigationRoutes[name] = WeakReference(route);
    }
    return keys;
  }

  static GlobalKey? resolveNavigationTarget(
      GlobalKey? target, String routeName) {
    if (target == null) return null;
    var index = clientBottomNav.indexOf(target);
    if (index < 0) index = cleanerBottomNav.indexOf(target);
    if (index < 0) return target;
    final route = _navigationRoutes[routeName]?.target;
    return route == null ? null : _navigationKeys[route]?[index];
  }

  static final clientHomeTop = GlobalKey(debugLabel: 'client_home_top');
  static final clientOrderButton = GlobalKey(debugLabel: 'client_order_button');
  static final clientPrelaunchButton =
      GlobalKey(debugLabel: 'client_prelaunch_button');
  static final clientInfoBanner = GlobalKey(debugLabel: 'client_info_banner');
  static final clientPackageActions =
      GlobalKey(debugLabel: 'client_package_actions');

  static final clientBottomNav = List<GlobalKey>.generate(
    5,
    (index) => GlobalKey(debugLabel: 'client_bottom_nav_$index'),
  );

  static final cleanerBottomNav = List<GlobalKey>.generate(
    5,
    (index) => GlobalKey(debugLabel: 'cleaner_bottom_nav_$index'),
  );
}
