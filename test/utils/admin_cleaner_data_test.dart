import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/admin_cleaner_data.dart';

void main() {
  test('admin uses real name, verification status and latest document URL', () {
    final row = mapAdminCleaner({
      'id': 'cleaner-id',
      'full_name': 'Анна',
      'status': 'approved',
      'verification_status': 'pending',
      'documents': [
        {'type': 'selfieUrl', 'url': 'https://example.com/latest'},
        {'type': 'selfieUrl', 'url': 'https://example.com/older'}
      ]
    });
    expect(row['name'], 'Анна');
    expect(row['cleanerId'], 'cleaner-id');
    expect(row['verificationStatus'], 'pending');
    expect(row['selfieUrl'], 'https://example.com/latest');
  });
}
