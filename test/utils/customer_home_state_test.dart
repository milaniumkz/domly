import 'package:domly/utils/customer_home_state.dart';
import 'package:domly/screens/client/area_confirmation_screen.dart';
import 'package:domly/ui/cleaning_schedule_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing and invalid dates never become January 1', () {
    for (final data in <Map<String, dynamic>>[
      {},
      {'date': ''},
      {'scheduledFor': 'invalid'},
      {'type': 'package_purchase', 'scheduledFor': ''}
    ]) {
      expect(scheduledCleaningDate(data), isNull);
      expect(cleaningDateLabel(data), 'Дата не выбрана');
    }
    expect(scheduledCleaningDate({'scheduledFor': '', 'date': '2026-10-23'}),
        DateTime(2026, 10, 23));
    expect(cleaningDateLabel({'date': '2026-10-23'}), contains('23'));
  });
  test('an assigned quality visit does not mean a document was submitted', () {
    expect(areaConfirmationStatus({'areaStatus': 'UNVERIFIED'}),
        'Не подтверждена');
    expect(
        areaConfirmationStatus(
            {'qualityStatus': 'scheduled', 'areaProofSubmitted': false}),
        'Не подтверждена');
    expect(areaConfirmationStatus({'areaProofSubmitted': true}), 'На проверке');
    expect(
        areaConfirmationStatus(
            {'areaVerified': true, 'areaProofSubmitted': true}),
        'Подтверждено');
  });
  for (final width in [320.0, 393.0]) {
    for (final date in ['23 октября 2026', '2026 жылғы 23 қазан']) {
      testWidgets('complete date at width $width: $date', (tester) async {

        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Center(
                    child: SizedBox(
          width: width - 98,
          child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: CleaningScheduleSummary(
                  dateText: date, status: const Text('Ожидает оплату'))),
        )))));
        expect(tester.takeException(), isNull);
        final text = tester.widget<Text>(find.text(date));
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(tester.getTopLeft(find.text('Ожидает оплату')).dy,
            greaterThan(tester.getBottomLeft(find.text(date)).dy));
      });
    }
  }
  for (final state in [0, 1, 2]) {
    testWidgets('area form opens with true document state $state',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: AreaConfirmationScreen(
        configStream:
            Stream.value({'uploadEnabled': true, 'techPlanRequired': false}),
        profileStream: Stream.value({
          'area': 100,
          'areaVerified': state == 2,
          'areaProofSubmitted': state == 1
        }),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
          find.text(['Не подтверждена', 'На проверке', 'Подтверждено'][state]),
          findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Подтвердить площадь'),
          findsOneWidget);
      expect(
          tester
              .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Подтвердить площадь'))
              .onPressed,
          isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
