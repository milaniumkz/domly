import 'main.dart' as entrypoints;

@pragma('vm:entry-point')
Future<void> main() async {
  await entrypoints.customerMain();
}
