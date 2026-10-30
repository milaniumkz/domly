import 'dart:async';

import 'package:domly/screens/common/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('cleaner review does not block customer review; own review does',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final reviews = StreamController<List<Map<String, dynamic>>>.broadcast();
    await tester.pumpWidget(MaterialApp(
        home: ReviewScreen(orderId: 'order-1', reviews: reviews.stream)));
    await tester.pumpAndSettle();
    final cleanerReview = <String, dynamic>{
      'id': 'cleaner-review',
      'orderId': 'order-1',
      'authorRole': 'cleaner',
      'rating': 2,
      'text': 'Оценка заказчика уборщицей',
    };
    reviews.add([cleanerReview]);
    await tester.pumpAndSettle();
    expect(
        find.text('Ваш отзыв сохранен и уже учтен в системе.'), findsNothing);
    expect(find.text('Отправить отзыв'), findsOneWidget);
    expect(find.text('Оценка заказчика уборщицей'), findsNothing);

    reviews.add([
      cleanerReview,
      {
        'id': 'customer-review',
        'orderId': 'order-1',
        'authorRole': 'customer',
        'rating': 5,
        'text': 'Спасибо за уборку',
      }
    ]);
    await tester.pumpAndSettle();
    expect(
        find.text('Ваш отзыв сохранен и уже учтен в системе.'), findsOneWidget);
    expect(find.text('Спасибо за уборку'), findsOneWidget);
    expect(find.text('Отправить отзыв'), findsNothing);
    expect(find.text('Оценка заказчика уборщицей'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await reviews.close();
  });
}
