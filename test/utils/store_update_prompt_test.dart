import 'package:domly/ui/store_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

class _StoreUpgrader extends Upgrader {
  _StoreUpgrader(this.available)
      : super(languageCode: 'ru', durationUntilAlertAgain: Duration.zero) {
    installPackageInfo(
      packageInfo: PackageInfo(
        appName: 'DomLY',
        packageName: 'com.domly.customer',
        version: '1.0.14',
        buildNumber: '24',
      ),
    );
  }

  final String? available;

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    updateState(state.copyWith(
      versionInfo: UpgraderVersionInfo(
        installedVersion: Version.parse('1.0.14'),
        appStoreVersion: available == null ? null : Version.parse(available!),
        appStoreListingURL: 'https://example.test/store',
      ),
    ));
    return state.versionInfo;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> show(WidgetTester tester, String? available,
      {bool enabled = true}) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final upgrader = _StoreUpgrader(available);
    await tester.runAsync(() => upgrader.initialize());
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => StoreUpdatePrompt(
        navigatorKey: navigatorKey,
        enabled: enabled,
        upgrader: upgrader,
        child: child!,
      ),
      home: const Scaffold(body: Text('Кабинет')),
    ));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform offers available update and allows postponing',
        (tester) async {
      await show(tester, '1.0.15');
      expect(find.text('Кабинет'), findsOneWidget);
      final update = UpgraderMessages(code: 'ru')
          .message(UpgraderMessage.buttonTitleUpdate)!;
      final later = UpgraderMessages(code: 'ru')
          .message(UpgraderMessage.buttonTitleLater)!;
      expect(find.text(update), findsOneWidget);
      await tester.tap(find.text(later));
      await tester.pumpAndSettle();
      expect(find.text(update), findsNothing);
    }, variant: TargetPlatformVariant({platform}));
  }

  for (final available in ['1.0.14', '1.0.13', null]) {
    testWidgets('no prompt for installed/older/unavailable version $available',
        (tester) async {
      await show(tester, available);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Кабинет'), findsOneWidget);
    });
  }

  testWidgets('disabled surfaces skip update checks', (tester) async {
    await show(tester, '1.0.15', enabled: false);
    expect(find.byWidgetPredicate((widget) => widget is UpgradeAlert),
        findsNothing);
  });
}
