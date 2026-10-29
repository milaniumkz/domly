import 'package:domly/utils/cleaner_checklist_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'server work requirements take precedence over templates and keep addons separate',
      () {
    expect(
        cleanerBaseChecklistTasks(requiredTasks: [
          'Вымыть пол',
          'Доп. услуга: Окна и стекла · Панорама'
        ], templateGroups: [
          {
            'key': 'base_tasks',
            'items': ['Другой список']
          }
        ]),
        ['Вымыть пол']);
  });
  test('standard checklist contains cleaning work before report loads', () {
    final tasks = cleanerBaseChecklistTasks();
    expect(tasks, [
      'Протереть пыль',
      'Пропылесосить',
      'Вымыть пол',
      'Очистить кухню',
      'Очистить санузел'
    ]);
    expect(tasks, isNot(contains('Подписка на 3 месяца')));
    expect(tasks, isNot(contains('Выбор 2, 4 или 8 уборок в месяц')));
    expect(
        cleanerBaseChecklistTasks(templateGroups: [
          {
            'key': 'base_tasks',
            'items': ['Вымыть пол', 'Вымыть пол']
          }
        ]),
        ['Вымыть пол']);
  });

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
