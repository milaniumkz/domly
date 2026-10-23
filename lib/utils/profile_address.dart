/// Preserve the selected building when displaying or reopening an address.
String profileAddressText(Map<String, dynamic> profile) {
  String value(String key) => (profile[key] ?? '').toString().trim();
  final complex = value('residentialComplex');
  var address = value('address');
  final building = [value('street'), value('house')]
      .where((part) => part.isNotEmpty).join(' ');
  if ((address.isEmpty || address == complex) && building.isNotEmpty) {
    address = building;
  }
  if (complex.isEmpty) return address;
  if (address.isEmpty || address.toLowerCase().contains(complex.toLowerCase())) {
    return address.isEmpty ? complex : address;
  }
  return '$complex, $address';
}
