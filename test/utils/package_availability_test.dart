import 'package:domly/utils/package_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid four-visit balance survives an already booked one-off cleaning',
      () {
    final old = {'availableCleanings': 0, 'totalCleanings': 1};
    final current = {'availableCleanings': 4, 'totalCleanings': 4};
    expect(availablePackageVisits(old, fallback: 0), 0);
    expect(availablePackageVisits(current, fallback: 0), 4);
  });
  test('server credits are not reduced again by booked or completed visits',
      () {
    expect(availablePackageVisits({'availableCleanings': 3}, fallback: 2), 3);
    expect(
        availablePackageVisits({'available_cleanings': '4'}, fallback: 0), 4);
    expect(availablePackageVisits({}, fallback: 2), 2);
    expect(availablePackageVisits({}, fallback: -1), 0);
  });
  test(
      'new available package replaces finished history but keeps assigned cleaning visible',
      () {
    final paid = {'status': 'active', 'availableCleanings': 4};
    final old = {'status': 'completed'};
    expect(
        preferAvailablePackageOverHistory(paid, old, hasActiveCleaning: false),
        isTrue);
    expect(
        preferAvailablePackageOverHistory(
            {'status': 'active', 'availableCleanings': 0}, old,
            hasActiveCleaning: false),
        isFalse);
    expect(
        preferAvailablePackageOverHistory(paid, {'status': 'assigned'},
            hasActiveCleaning: true),
        isFalse);
    expect(
        preferAvailablePackageOverHistory(paid, {'status': 'pending_payment'},
            hasActiveCleaning: false),
        isFalse);
  });
}
