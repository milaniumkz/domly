import 'package:domly/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallService.normalizePhoneForCall', () {
    test('keeps Kazakhstan number with country code', () {
      expect(
        CallService.normalizePhoneForCall('77753550539'),
        '+77753550539',
      );
    });

    test('converts local mobile number to +7', () {
      expect(
        CallService.normalizePhoneForCall('775 355 05 39'),
        '+77753550539',
      );
    });

    test('converts 8 prefix to Kazakhstan country code', () {
      expect(
        CallService.normalizePhoneForCall('8 (775) 355-05-39'),
        '+77753550539',
      );
    });

    test('keeps formatted plus number as e164', () {
      expect(
        CallService.normalizePhoneForCall('+7 (775) 355-05-39'),
        '+77753550539',
      );
    });
  });
}
