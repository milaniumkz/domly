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
      'isActive': true,
    };
