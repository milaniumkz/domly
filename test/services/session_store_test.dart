import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domly/services/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  BackendSession session(String role) => BackendSession(
      accessToken: role,
      refreshToken: 'refresh-$role',
      userId: role,
      role: role);
  test('three application sessions coexist and logout affects only one',
      () async {
    final customer = SessionStore(surface: SessionSurface.customer);
    final pro = SessionStore(surface: SessionSurface.pro);
    final admin = SessionStore(surface: SessionSurface.admin);
    await customer.saveBackendSession(session('customer'));
    await pro.saveBackendSession(session('cleaner'));
    await admin.saveBackendSession(session('superadmin'));
    expect(await customer.accessToken(), 'customer');
    expect(await pro.accessToken(), 'cleaner');
    expect(await admin.accessToken(), 'superadmin');
    await admin.clearBackendSession();
    expect(await admin.backendSession(), isNull);
    expect(await customer.accessToken(), 'customer');
    expect(await pro.accessToken(), 'cleaner');
  });
  test(
      'legacy admin session cannot become customer and cannot resurrect after logout',
      () async {
    SharedPreferences.setMockInitialValues({
      'domly_backend_access_token': 'old',
      'domly_backend_refresh_token': 'refresh',
      'domly_backend_user_id': 'admin',
      'domly_backend_user_role': 'superadmin',
    });
    final customer = SessionStore(surface: SessionSurface.customer);
    final admin = SessionStore(surface: SessionSurface.admin);
    expect(await customer.backendSession(), isNull);
    expect(await admin.accessToken(), 'old');
    await admin.clearBackendSession();
    expect(await admin.backendSession(), isNull);
    await expectLater(
        customer.saveBackendSession(session('superadmin')), throwsStateError);
  });
}
