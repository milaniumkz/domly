class LegalDocumentSection {
  const LegalDocumentSection({this.heading, required this.body});
  final String? heading;
  final String body;
}

/// Preserves paragraph boundaries from the editable document in either language.
List<LegalDocumentSection> legalDocumentSections(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .where((paragraph) => paragraph.trim().isNotEmpty)
      .map((paragraph) {
    final lines = paragraph.trim().split('\n');
    final heading = lines.length > 1 &&
        RegExp(r'^\d+(?:\.\d+)*[.)]\s+').hasMatch(lines.first);
    return LegalDocumentSection(
      heading: heading ? lines.first.trim() : null,
      body: (heading ? lines.skip(1) : lines).join('\n').trim(),
    );
  }).toList();
}

Map<String, dynamic> legalPageToInfoContent(Map<String, dynamic> page) => {
      'id': page['slug'],
      'key': page['slug'] == 'public-offer'
          ? 'legal_offer'
          : page['slug'] == 'privacy-policy'
              ? 'legal_privacy'
              : page['slug'],
      'title': page['title_ru'] ?? '',
      'titleKk': page['title_kk'],
      'fullInfo': page['body_ru'] ?? '',
      'fullInfoKk': page['body_kk'],
      'shortInfo': (page['presentation'] as Map?)?['shortInfo'] ?? '',
      'shortInfoKk': (page['presentation'] as Map?)?['shortInfoKk'],
      'isActive': true,
    };

String canonicalContentSlug(String key) => switch (key) {
  'legal_offer' || 'offer' => 'public-offer',
  'legal_privacy' || 'privacy' => 'privacy-policy',
  _ => key,
};

Map<String, dynamic> adminContentPage(Map<String, dynamic> page) {
  final content = legalPageToInfoContent(page);
  return {...page, ...content, 'id': content['key'], 'slug': page['slug'],
    'type': const ['package','addon','banner','promotion','info'].contains(page['kind']) ? page['kind'] : 'info', 'isActive': page['active'] != false};
}

Map<String, dynamic> contentPagePayload(Map<String, dynamic> data) => {
  'slug': canonicalContentSlug((data['key'] ?? data['slug'] ?? data['id'] ?? '').toString()),
  'titleRu': data['title'] ?? data['titleRu'] ?? data['title_ru'] ?? '',
  'titleKk': data['titleKk'] ?? data['title_kk'],
  'bodyRu': data['fullInfo'] ?? data['body'] ?? data['bodyRu'] ?? data['body_ru'] ?? '',
  'bodyKk': data['fullInfoKk'] ?? data['bodyKk'] ?? data['body_kk'],
  'kind': data['kind'] ?? data['type'] ?? 'info',
  'presentation': {...?(data['presentation'] as Map?), 'shortInfo': data['shortInfo'] ?? '', 'shortInfoKk': data['shortInfoKk']},
  'active': data['isActive'] != false && data['active'] != false,
};
