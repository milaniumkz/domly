import 'app_flavor.dart';

class DomlyLinks {
  static const customer = 'https://domly.kz/customer/';
  static const pro = 'https://domly.kz/pro/';
  static String referral(String code) =>
      '$customer?ref=${Uri.encodeQueryComponent(code.trim().toUpperCase())}';

  static String? route(Uri uri, AppFlavor flavor) {
    if (uri.scheme == 'https' && uri.host != 'domly.kz') return null;
    if (!['https', 'domly', 'domly-pro'].contains(uri.scheme)) return null;
    final isPro = uri.scheme == 'domly-pro' || uri.path.startsWith('/pro');
    if (isPro != (flavor == AppFlavor.pro)) return null;
    final route =
        uri.fragment.startsWith('/') ? Uri.parse(uri.fragment).path : uri.path;
    final prefix = isPro ? '/cleaner/' : '/client/';
    if (route.startsWith(prefix)) return route;
    return isPro ? '/cleaner/dashboard' : '/client/home';
  }
}
