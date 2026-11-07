import 'package:domly/utils/admin_area_check_data.dart';
import 'package:domly/utils/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending checks with and without documents use the open queue', () {
    for (final document in [null, 'file']) {
      final item = mapAdminAreaCheck({
        'id': 'q',
        'status': 'pending',
        'document_file_id': document,
        'document_url': 'https://example.com/plan.jpg',
        'city': 'Астана',
        'street': 'Тест',
        'house': '1',
        'apartment': '7'
      });
      expect(item['status'], 'open');
      expect(item['reviewStatus'], 'pending');
      expect(item['document_file_id'], document);
      expect(item['document_url'], 'https://example.com/plan.jpg');
      expect(item['address'], 'Астана, Тест, 1, кв. 7');
    }
    for (final s in ['approved', 'rejected', 'cancelled']) {
      expect(mapAdminAreaCheck({'status': s})['status'], 'resolved');
    }
    expect(mapAdminAreaCheck({'status': 'scheduled'})['status'], 'open');
  });
  test('all queue pages loaded; duplicate auto-closures excluded', () async {
    final offsets = <int>[];
    final rows = await loadAdminAreaChecks((offset, limit) async {
      offsets.add(offset);
      expect(limit, 200);
      if (offset == 0)
        return List.generate(200, (i) => {'id': 'q$i', 'status': 'approved'});
      return [
        {
          'id': 'pending-document',
          'status': 'pending',
          'document_file_id': 'file'
        },
        {
          'id': 'duplicate',
          'status': 'cancelled',
          'admin_comment': 'duplicate_auto_closed'
        }
      ];
    });
    expect(offsets, [0, 200]);
    expect(rows.length, 201);
    expect(rows.last['status'], 'open');
  });
  test('area pushes open the review queue on web and native admin', () {
    for (final type in [
      'quality_check',
      'area_quality_check',
      'area_verification'
    ]) {
      expect(adminNotificationRoute({'targetType': type}),
          '/admin/web?section=quality_control');
    }
    expect(adminNotificationRoute({'targetType': 'payment'}),
        '/admin/web?section=payments');
    expect(adminNotificationRoute({'target_type': 'work_schedule'}),
        '/admin/web?section=work_schedules');
  });
}
