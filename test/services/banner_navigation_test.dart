import 'package:domly/screens/client/client_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) async => false;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }
}

void main() {
  late _Launcher launcher;
  setUp(() {
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });
  Future<void> showBanner(
      WidgetTester tester, Map<String, dynamic> values) async {
    await tester.pumpWidget(MaterialApp(
      routes: {'/test': (_) => const Scaffold(body: Text('Destination'))},
      home: Scaffold(
          body: SizedBox(
              width: 360,
              height: 148,
              child: PromoBannerCard(banner: {
                'title': 'Banner',
                'description': 'Banner details',
                ...values,
              }))),
    ));
    await tester.tap(find.byType(PromoBannerCard));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'external link takes priority over banner content without preflight',
      (tester) async {
    await showBanner(tester,
        {'externalUrl': ' https://example.com/promo?a=1 ', 'route': '/test'});
    expect(launcher.urls, ['https://example.com/promo?a=1']);
    expect(find.text('Banner details'), findsNothing);
  });
  testWidgets('internal route takes priority over banner content',
      (tester) async {
    await showBanner(tester, {'route': '/test'});
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Banner details'), findsNothing);
  });
  testWidgets('invalid destination does not launch or substitute a modal',
      (tester) async {
    await showBanner(tester, {'externalUrl': 'javascript:alert(1)'});
    expect(launcher.urls, isEmpty);
    expect(find.text('Banner details'), findsNothing);
    expect(find.text('Не удалось открыть ссылку. Попробуйте позже.'),
        findsOneWidget);
  });
  testWidgets('banner without destination retains details modal',
      (tester) async {
    await showBanner(tester, {});
    expect(find.text('Banner details'), findsOneWidget);
    expect(launcher.urls, isEmpty);
  });
}
