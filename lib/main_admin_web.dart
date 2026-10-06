import 'app/app_config.dart';
import 'app/app_flavor.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  await bootstrap(
    const AppConfig(
      flavor: AppFlavor.customer,
      title: 'Domly Admin Web',
      initialRoute: '/admin/web',
      postAuthRoute: '/admin/web',
      deferAuthForCustomerActions: false,
      adminSurface: true,
    ),
  );
}
