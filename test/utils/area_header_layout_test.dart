import 'package:domly/screens/client/area_confirmation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('area confirmation title fits at width 320 and scale $scale', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const SizedBox(width: 290, child: AreaConfirmationHeader()),
      ))));
      final title = find.text('Подтверждение площади');
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getBottomRight(find.text('Выберите параметры')).dy,
          lessThanOrEqualTo(tester.getBottomRight(find.byType(AreaConfirmationHeader)).dy));
      expect(tester.takeException(), isNull);
    });
  }
}
