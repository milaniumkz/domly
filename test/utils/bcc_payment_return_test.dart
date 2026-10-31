import 'package:domly/utils/bcc_payment_return.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes the server return after bank verification', () {
    expect(
        isBccPaymentReturn(
            'https://domly.kz/customer/?bcc_return=1#/client/payment-history'),
        isTrue);
    expect(
        isBccPaymentReturn('https://domly.kz/customer?bcc_return=1'), isTrue);
  });

  test('does not intercept bank verification or unrelated navigation', () {
    for (final url in [
      'https://domly.kz/api/v1/payments/bcc/return?paymentId=example',
      'https://3dsecure.bcc.kz/webview',
      'https://domly.kz/customer/',
      'https://domly.kz/customer/?bcc_return=0',
      'https://domly.kz.evil.example/customer/?bcc_return=1',
      'http://domly.kz/customer/?bcc_return=1',
      'https://domly.kz:8443/customer/?bcc_return=1',
      'https://domly.kz/admin/?bcc_return=1',
    ]) {
      expect(isBccPaymentReturn(url), isFalse, reason: url);
    }
  });
}
