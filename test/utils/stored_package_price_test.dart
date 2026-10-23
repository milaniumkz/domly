import 'package:domly/utils/stored_package_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile reads the saved purchase amount instead of showing zero', () {
    expect(
        storedPackagePrice({
          'purchase_config': {'monthlyPrice': 22000}
        }),
        22000);
    expect(
        storedPackagePrice({
          'purchase_config': {'monthlyPrice': '98496'}
        }),
        98496);
  });
  test('approved recalculation uses the updated full package quote', () {
    expect(
        storedPackagePrice({
          'purchase_config': {
            'monthlyPrice': 24200,
            'areaPricingBaseline': {'total': 22000},
            'areaRecalculation': {'totalPrice': 24200, 'delta': 2200},
          }
        }),
        24200);
  });
  test('absent legacy quote does not invent a catalog price', () {
    expect(storedPackagePrice({'base_price': 99999}), isNull);
    expect(
        storedPackagePrice({
          'purchase_config': {'monthlyPrice': 'NaN'}
        }),
        isNull);
  });
}
