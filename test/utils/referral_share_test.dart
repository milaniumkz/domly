import 'package:domly/ui/referral_share.dart';
import 'package:domly/utils/package_catalog_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('only renovation or explicitly disabled tariffs exclude addons', () {
    expect(PackageCatalogUtils.allowsAddons({'systemKey': 'post_renovation'}), false);
    expect(PackageCatalogUtils.allowsAddons({'features': {'systemKey': 'post_renovation'}}), false);
    expect(PackageCatalogUtils.allowsAddons({'isSpecial': true, 'name': 'Генеральная уборка'}), true);
    expect(PackageCatalogUtils.allowsAddons({'id': 'single'}), true);
  });

  testWidgets('share sends the referral link and a nonempty iOS popover origin', (tester) async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (value) async { call = value; return 'com.example.share'; });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => shareReferralLink(context, ' domly-123 '), child: const Text('Share')),
    ))));
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(call?.method, 'share');
    expect(call?.arguments['text'], contains('https://domly.kz/customer/?ref=DOMLY-123'));
    expect(call?.arguments['originWidth'], greaterThan(0));
    expect(call?.arguments['originHeight'], greaterThan(0));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('failed share offers a selectable link and explicit copy button', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'unavailable'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => shareReferralLink(context, 'DOMLY-456'), child: const Text('Share')),
    ))));
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
        return null;
      });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('https://domly.kz/customer/?ref=DOMLY-456'), findsOneWidget);
    expect(find.text('Скопировать ссылку'), findsOneWidget);
    await tester.tap(find.text('Скопировать ссылку'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(copied, 'https://domly.kz/customer/?ref=DOMLY-456');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
