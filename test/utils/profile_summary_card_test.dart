import 'package:domly/screens/client/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile summary is accessible, clickable across its body and grows with text', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 280, child: ProfileSummaryCard(
      height: 120, padding: const EdgeInsets.all(24), onTap: () => taps++,
      child: const Text('Текущая подписка\nПодробности оплаченного пакета\nДлинное название\nДоступные уборки\nСрок действия', style: TextStyle(fontSize: 22)),
    )))));
    expect(tester.getSize(find.byType(ProfileSummaryCard)).height, greaterThan(120));
    await tester.tap(find.textContaining('Текущая подписка'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
