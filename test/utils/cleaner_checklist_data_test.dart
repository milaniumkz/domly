import 'package:domly/utils/cleaner_checklist_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reopening restores checked tasks, unchecked requirements and note', () {
    final data = mapCleanerChecklist('order', {
      'report': {'id': 'report', 'note': 'Домофон 123', 'status': 'open'},
      'items': [
        {'title_ru': 'Вымыть пол', 'checked': true, 'required': true},
        {'title_ru': 'Очистить кухню', 'checked': false, 'required': true},
        {
          'title_ru': 'Доп. услуга: Мытье окон',
          'checked': true,
          'required': true
        },
        {
          'title_ru': 'Дополнительная отметка',
          'checked': true,
          'required': false
        },
      ],
    })!;
    expect(data['completedTasks'],
        ['Вымыть пол', 'Доп. услуга: Мытье окон', 'Дополнительная отметка']);
    expect(data['requiredTasks'],
        ['Вымыть пол', 'Очистить кухню', 'Доп. услуга: Мытье окон']);
    expect(data['addons'], ['Мытье окон']);
    expect(data['note'], 'Домофон 123');
  });
  test('empty backend report remains an empty state', () {
    expect(mapCleanerChecklist('order', {}), isNull);
  });
}
