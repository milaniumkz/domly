import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/admin_order_data.dart';

void main() {
  test(
      'a reserved team occupies both staff schedules while customer price stays once',
      () {
    final order = <String, dynamic>{
      'id': 'shared-order',
      'cleanerId': null,
      'area': 400,
      'price': 38000,
      'status': 'pending_assignment',
      'team_members': [
        {
          'cleaner_id': 'first',
          'name': 'First',
          'area': '200.00',
          'status': 'accepted'
        },
        {
          'cleaner_id': 'second',
          'name': 'Second',
          'area': '200.00',
          'status': 'offered'
        },
      ],
    };
    final schedule = expandAdminTeamAssignments([order]);
    expect(schedule.map((visit) => visit['cleanerId']), ['first', 'second']);
    expect(schedule.fold<num>(0, (sum, visit) => sum + (visit['area'] as num)),
        400);
    expect(schedule.every((visit) => visit['teamReservation'] == true), isTrue);
    expect(order['area'], 400);
    expect(order['price'], 38000);
    expect(order['cleanerId'], isNull);
  });

  test('a vacant replacement slot does not become a phantom cleaner', () {
    final legacy = <String, dynamic>{'id': 'legacy', 'cleanerId': 'solo'};
    final visits = expandAdminTeamAssignments([
      legacy,
      {
        'id': 'team',
        'team_members': [
          {'cleaner_id': 'retained', 'area': 200},
          {'cleaner_id': null, 'area': 200},
        ],
      }
    ]);
    expect(visits.length, 2);
    expect(identical(visits.first, legacy), isTrue);
    expect(visits.last['cleanerId'], 'retained');
  });
}
