/// Format structured fields once; commas and quotation marks are separators,
/// never a reason to shorten apartment numbers.
String _addressKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'''[\s,.;:'"«»]+'''), '');
String cleanAddressPart(Object? value) => (value ?? '')
    .toString()
    .trim()
    .replaceAll(RegExp(r'''^[\s,;'"«»]+|[\s,;'"«»]+$'''), '');

String addressSummary(Map<String, dynamic> data) {
  final city = cleanAddressPart(data['city']);
  final street = cleanAddressPart(data['street']);
  final house = cleanAddressPart(data['house']);
  final apartment = cleanAddressPart(data['apartment']);
  final complex = cleanAddressPart(
      data['residentialComplex'] ?? data['residential_complex']);
  var address = street.isNotEmpty && house.isNotEmpty
      ? [city, street, house, if (apartment.isNotEmpty) 'кв. $apartment']
          .where((p) => p.isNotEmpty)
          .join(', ')
      : cleanAddressPart(
          data['address'] ?? data['homeAddress'] ?? data['fullAddress']);
  if (complex.isNotEmpty &&
      !_addressKey(address).contains(_addressKey(complex))) {
    // Old profiles sometimes stored the building address as the complex name.
    final building = [street, house].where((p) => p.isNotEmpty).join(' ');
    if (building.isEmpty ||
        !_addressKey(complex).contains(_addressKey(building))) {
      address = address.isEmpty ? complex : '$complex, $address';
    }
  }
  return address;
}

bool addressTextContains(String value,String part) => part.trim().isNotEmpty && _addressKey(value).contains(_addressKey(part));
