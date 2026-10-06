import 'app/app_config.dart';
import 'app/app_flavor.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  await customerMain();
}

@pragma('vm:entry-point')
Future<void> customerMain() async {
  await bootstrap(_customerConfig);
}

@pragma('vm:entry-point')
Future<void> proMain() async {
  await bootstrap(_proConfig);
}

const _customerConfig = AppConfig(
  flavor: AppFlavor.customer,
  title: 'DOMLY',
  initialRoute: '/auth',
  postAuthRoute: '/client/home',
  deferAuthForCustomerActions: false,
  adminSurface: false,
);

const _proConfig = AppConfig(
  flavor: AppFlavor.pro,
  title: 'Domly Pro',
  initialRoute: '/welcome',
  postAuthRoute: '/cleaner/dashboard',
  deferAuthForCustomerActions: false,
  adminSurface: false,
);
