import 'package:domly/ui/order_addon_price.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'unit prices are visible before selection and totals change with quantity',
      (tester) async {
    var quantity = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      OrderAddonPrice(unitPrice: 3000, quantity: quantity),
                      TextButton(
                          onPressed: () => setState(() => quantity++),
                          child: const Text('+')),
                    ])))));
    expect(find.text('Цена: 3 000 ₸ за единицу'), findsOneWidget);
    expect(find.textContaining('Итого:'), findsNothing);
    await tester.tap(find.text('+'));
    await tester.pump();
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('Итого: 6 000 ₸'), findsOneWidget);
  });
  testWidgets(
      'specialist services have no invoice price; area rates show their unit',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(children: [
      OrderAddonPrice(unitPrice: 50000, quantity: 2, separatePayment: true),
      OrderAddonPrice(
          unitPrice: 200, quantity: 2, pricingType: 'per_m2', area: 67),
    ]))));
    expect(find.text('Оплата отдельно по факту'), findsOneWidget);
    expect(find.textContaining('50 000'), findsNothing);
    expect(find.text('Цена: 200 ₸ за м²'), findsOneWidget);
    expect(find.text('Итого: 26 800 ₸'), findsOneWidget);
  });
}
