import 'package:domly/screens/client/training_order_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('training always offers today and two following calendar days', () {
    expect(trainingOrderDates(DateTime(2026, 10, 23, 23, 59)), [
      DateTime(2026, 10, 23),
      DateTime(2026, 10, 24),
      DateTime(2026, 10, 25)
    ]);
    expect(trainingOrderDates(DateTime(2026, 12, 31)),
        [DateTime(2026, 12, 31), DateTime(2027, 1, 1), DateTime(2027, 1, 2)]);
    expect(trainingOrderDates(DateTime(2028, 2, 28)),
        [DateTime(2028, 2, 28), DateTime(2028, 2, 29), DateTime(2028, 3, 1)]);
  });
}
