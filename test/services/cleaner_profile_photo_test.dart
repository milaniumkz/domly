import 'dart:async';
import 'package:domly/ui/cleaner_profile_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('photo button uploads once and shows pending moderation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final done = Completer<void>();
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CleanerProfilePhoto(
                profile: const {'name': 'Анара'},
                upload: () async => 'new-selfie',
                submit: (url) {
                  expect(url, 'new-selfie');
                  submitted++;
                  return done.future;
                }))));
    expect(find.text('Сменить фото'), findsOneWidget);
    await tester.tap(find.text('Сменить фото'));
    await tester.pump();
    expect(submitted, 1);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Фото на проверке'), findsOneWidget);
    expect(find.text('Фото отправлено на проверку'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
