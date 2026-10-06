import 'app_flavor.dart';

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.title,
    required this.initialRoute,
    required this.postAuthRoute,
    required this.deferAuthForCustomerActions,
    this.adminSurface = false,
  });

  final AppFlavor flavor;
  final String title;
  final String initialRoute;
  final String postAuthRoute;
  final bool deferAuthForCustomerActions;
  final bool adminSurface;
}
