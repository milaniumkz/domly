import 'package:flutter/material.dart';

class DomlyTutorialTargets {
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
