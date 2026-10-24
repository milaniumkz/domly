import 'dart:async';
import 'package:domly/screens/common/notifications_screen.dart';
import 'package:domly/services/firestore_data_service.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('history keeps total, loads older messages and retains cards while loading', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = StreamController<NotificationHistoryPage>();
    final more = StreamController<NotificationHistoryPage>();
    final limits = <int>[];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: NotificationsScreen(surface: NotificationSurface.client, historySource: (limit) {
        limits.add(limit);
        return limit == 50 ? first.stream : more.stream;
      })));
    final item = <String, dynamic>{'id': 'first', 'title': 'Первое событие', 'body': 'Текст', 'read': false};
    first.add(NotificationHistoryPage(items: [item], total: 51));
    await tester.pumpAndSettle();
    expect(find.text('Всего уведомлений: 51'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Показать ещё'), 200);
    await tester.tap(find.text('Показать ещё'));
    await tester.pump();
    expect(limits, [50, 100]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Всего уведомлений: 51'), findsOneWidget);
    more.add(NotificationHistoryPage(items: [item, {...item, 'id': 'older', 'title': 'Старое событие'}], total: 2));
    await tester.pumpAndSettle();
    expect(find.text('Показать ещё'), findsNothing);
    expect(find.text('Всего уведомлений: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unawaited(first.close());
    unawaited(more.close());
  });
}
