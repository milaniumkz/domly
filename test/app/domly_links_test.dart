import 'package:flutter_test/flutter_test.dart';
import 'package:domly/app/domly_links.dart';
import 'package:domly/app/app_flavor.dart';

void main() {
  test('customer and Pro links open only the matching application', () {
    expect(DomlyLinks.route(Uri.parse(DomlyLinks.customer), AppFlavor.customer),
        '/client/home');
    expect(DomlyLinks.route(Uri.parse(DomlyLinks.pro), AppFlavor.pro),
        '/cleaner/dashboard');
    expect(DomlyLinks.route(Uri.parse(DomlyLinks.pro), AppFlavor.customer),
        isNull);
    expect(DomlyLinks.route(Uri.parse(DomlyLinks.customer), AppFlavor.pro),
        isNull);
    expect(
        DomlyLinks.route(
            Uri.parse('https://other.example/customer/'), AppFlavor.customer),
        isNull);
  });
  test('deep links preserve protected client and cleaner routes', () {
    expect(
        DomlyLinks.route(Uri.parse('${DomlyLinks.customer}#/client/orders'),
            AppFlavor.customer),
        '/client/orders');
    expect(
        DomlyLinks.route(
            Uri.parse('${DomlyLinks.pro}#/cleaner/training'), AppFlavor.pro),
        '/cleaner/training');
    expect(DomlyLinks.route(Uri.parse('domly://customer'), AppFlavor.customer),
        '/client/home');
    expect(DomlyLinks.route(Uri.parse('domly-pro://pro'), AppFlavor.pro),
        '/cleaner/dashboard');
  });
  test('referral links use customer hosting and encode the code', () {
    final uri = Uri.parse(DomlyLinks.referral('domly-123'));
    expect(uri.host, 'domly.kz');
    expect(uri.path, '/customer/');
    expect(uri.queryParameters['ref'], 'DOMLY-123');
  });
}
