import 'package:domly/models/order_addon_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('existing order cards retain separately paid catalogue flag and content', () {
    final item = OrderAddonItem.fromConfig({
      'key': 'mattress', 'label': 'Химчистка матрасов',
      'separatePayment': true, 'supportsQuantity': true,
      'description': 'Первый абзац\nВторой абзац', 'durationMinutes': 25,
    });
    expect(item.separatePayment, true);
    expect(item.key, 'mattress');
    expect(item.label, 'Химчистка матрасов');
    expect(item.infoText, 'Первый абзац\nВторой абзац');
    expect(item.supportsQuantity, true);
    expect(item.durationMinutes, 25);
  });
  test('turning off separate payment overrides an older alias', () {
    expect(OrderAddonItem.fromConfig({'separate': true}).separatePayment, true);
    expect(OrderAddonItem.fromConfig({'separatePayment': false, 'separate': true}).separatePayment, false);
    expect(OrderAddonItem.fromConfig({}).separatePayment, false);
  });
}
