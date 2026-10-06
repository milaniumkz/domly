import 'app_flavor.dart';

String domlyLogoAsset(AppFlavor flavor) {
  return flavor == AppFlavor.pro ? 'assets/logo_pro.png' : 'assets/logo.png';
}
