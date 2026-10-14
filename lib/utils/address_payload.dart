Map<String, String> streetAndHouse(Map<String, dynamic> address) {
  final explicitStreet = (address['street'] ?? '').toString().trim();
  final explicitHouse = (address['house'] ?? '')
      .toString()
      .trim()
      .replaceAll(RegExp(r'/\s*,\s*'), '/');
  if (explicitStreet.isNotEmpty && explicitHouse.isNotEmpty)
    return {'street': explicitStreet, 'house': explicitHouse};
  final line = (address['address'] ?? address['addressLine'] ?? '')
      .toString()
      .trim()
      .replaceAll(RegExp(r'/\s*,\s*'), '/');
  final matched = RegExp(
          r'^(.*?)[,\s]+(?:д(?:ом)?\.?\s*)?(\d+[0-9А-Яа-яA-Za-z/-]*)(?:\s*,\s*[^\d].*)?$')
      .firstMatch(line);
  return {
    'street': explicitStreet.isNotEmpty
        ? explicitStreet
        : (matched?.group(1) ?? line).trim(),
    'house': explicitHouse.isNotEmpty ? explicitHouse : matched?.group(2) ?? ''
  };
}
