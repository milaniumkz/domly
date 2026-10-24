import 'package:domly/utils/legal_document_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editing the complete legal document preserves its canonical key and Kazakh text', () {
    final page = adminContentPage({'slug':'public-offer','title_ru':'Оферта','title_kk':'Оферта KK','body_ru':'1. Первый\nТекст\n\n9. Последний\nКонец','body_kk':'Толық мәтін','presentation':{'shortInfo':'Кратко','shortInfoKk':'Қысқаша'},'kind':'offer','active':true});
    expect(page['id'],'legal_offer');
    final payload = contentPagePayload({...page,'fullInfo':'1. Новый\nТекст\n\n9. Последний\nКонец'});
    expect(payload['slug'],'public-offer');
    expect(payload['bodyRu'],'1. Новый\nТекст\n\n9. Последний\nКонец');
    expect(payload['bodyKk'],'Толық мәтін');
    expect((payload['presentation'] as Map)['shortInfo'],'Кратко');
    expect((payload['presentation'] as Map)['shortInfoKk'],'Қысқаша');
  });

  test('Russian and Kazakh legal paragraphs retain separate numbered headings',
      () {
    for (final text in [
      '1. Оплата\nЗаказ оплачивается клиентом.\n\n2. Возврат\nУсловия возврата.',
      '1. Төлем\nТапсырысты клиент төлейді.\n\n2. Қайтару\nҚайтару шарттары.',
    ]) {
      final sections = legalDocumentSections(text);
      expect(sections, hasLength(2));
      expect(sections[0].heading, startsWith('1. '));
      expect(sections[1].heading, startsWith('2. '));
      expect(sections.map((s) => '${s.heading}\n${s.body}').join('\n\n'), text);
    }
  });
  test('regular paragraphs and decimal amounts are not mistaken for headings',
      () {
    final result =
        legalDocumentSections('Стоимость 12.50 KZT.\n\nОбычный абзац.');
    expect(result, hasLength(2));
    expect(result.every((s) => s.heading == null), isTrue);
    expect(result.first.body, 'Стоимость 12.50 KZT.');
  });
  test(
      'editable offer and privacy policy map both languages with original paragraphs',
      () {
    for (final slug in ['public-offer', 'privacy-policy']) {
      final page = legalPageToInfoContent({
        'slug': slug,
        'title_ru': 'Документ',
        'title_kk': 'Құжат',
        'body_ru': '1. Оплата\nУсловия.\n\n2. Возврат\nТекст.',
        'body_kk': '1. Төлем\nШарттар.\n\n2. Қайтару\nМәтін.'
      });
      expect(page['key'],
          slug == 'public-offer' ? 'legal_offer' : 'legal_privacy');
      expect(legalDocumentSections(page['fullInfo'] as String), hasLength(2));
      expect(legalDocumentSections(page['fullInfoKk'] as String), hasLength(2));
      expect(page['titleKk'], 'Құжат');
    }
  });
}
