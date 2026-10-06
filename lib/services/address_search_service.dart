import 'backend_api_service.dart';

class AddressSearchBias {
  const AddressSearchBias({
    required this.lat,
    required this.lng,
    this.radiusKm = 12,
  });

  final double lat;
  final double lng;
  final double radiusKm;
}

class AddressSuggestion {
  const AddressSuggestion({
    required this.title,
    required this.subtitle,
    required this.placeId,
    this.residentialComplex = '',
    this.addressLine = '',
    this.isResidentialComplex = false,
    this.lat,
    this.lng,
    this.distanceMeters,
    this.city = '',
    this.searchText = '',
  });

  final String title;
  final String subtitle;
  final String placeId;
  final String residentialComplex;
  final String addressLine;
  final bool isResidentialComplex;
  final double? lat;
  final double? lng;
  final int? distanceMeters;
  final String city;
  final String searchText;

  String get fullText => subtitle.isEmpty ? title : '$title, $subtitle';
  String get selectionText =>
      residentialComplex.trim().isNotEmpty ? residentialComplex : fullText;
  String get addressText =>
      addressLine.trim().isNotEmpty ? addressLine : fullText;
  bool get needsCoordinateLookup =>
      placeId.startsWith('yandex:') && (lat == null || lng == null);
}

class AddressSearchService {
  AddressSearchService._();
  static final AddressSearchService instance = AddressSearchService._();
  static const List<String> _kazakhstanCities = [
    'Абай',
    'Акколь',
    'Аксай',
    'Аксу',
    'Актау',
    'Актобе',
    'Алга',
    'Алматы',
    'Алтай',
    'Аральск',
    'Аркалык',
    'Арыс',
    'Астана',
    'Атбасар',
    'Атырау',
    'Аягоз',
    'Байконыр',
    'Балхаш',
    'Ерейментау',
    'Есик',
    'Жанаозен',
    'Жаркент',
    'Жезказган',
    'Жетысай',
    'Зайсан',
    'Кандыагаш',
    'Караганда',
    'Кентау',
    'Кокшетау',
    'Конаев',
    'Костанай',
    'Кульсары',
    'Кызылорда',
    'Лисаковск',
    'Павлодар',
    'Петропавловск',
    'Риддер',
    'Рудный',
    'Сарань',
    'Сарканд',
    'Сарыагаш',
    'Сатпаев',
    'Семей',
    'Степногорск',
    'Талгар',
    'Талдыкорган',
    'Тараз',
    'Темиртау',
    'Туркестан',
    'Уральск',
    'Усть-Каменогорск',
    'Ушарал',
    'Шардара',
    'Шахтинск',
    'Шемонаиха',
    'Шу',
    'Шымкент',
    'Экибастуз',
  ];

  List<String> searchCities(String query) {
    final normalized = query.trim().toLowerCase();
    return _kazakhstanCities
        .where((city) => city.toLowerCase().contains(normalized))
        .take(10)
        .toList();
  }

  AddressSuggestion _map(Map<String, dynamic> row) {
    double? number(dynamic value) => double.tryParse('$value');
    final street = (row['street'] ?? '').toString();
    final house = (row['house'] ?? '').toString();
    final address = [street, house].where((part) => part.isNotEmpty).join(' ');
    return AddressSuggestion(
        title: address.isEmpty ? (row['label'] ?? '').toString() : address,
        subtitle: (row['city'] ?? '').toString(),
        addressLine: address,
        placeId: (row['id'] ?? '${row['source']}:${row['lat']},${row['lng']}')
            .toString(),
        residentialComplex: (row['residentialComplex'] ?? '').toString(),
        city: (row['city'] ?? '').toString(),
        lat: number(row['lat']),
        lng: number(row['lng']),
        distanceMeters: number(row['distanceKm']) == null
            ? null
            : (number(row['distanceKm'])! * 1000).round());
  }

  Future<List<AddressSuggestion>> search(String query,
      {AddressSearchBias? bias, String city = ''}) async {
    if (query.trim().length < 2) return [];
    final data = await BackendApiService.instance
        .getMap('/geo/address-suggestions', authenticated: false, query: {
      'search': query.trim(),
      'city': city,
      'lat': bias?.lat.toString(),
      'lng': bias?.lng.toString(),
      'radiusKm': bias?.radiusKm.toString()
    });
    return (data['suggestions'] as List? ?? [])
        .whereType<Map>()
        .map((row) => _map(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<AddressSuggestion?> reverse(double lat, double lng) async {
    final data = await BackendApiService.instance.getMap('/geo/reverse',
        authenticated: false, query: {'lat': '$lat', 'lng': '$lng'});
    final row = data['suggestion'];
    return row is Map ? _map(Map<String, dynamic>.from(row)) : null;
  }

  Future<AddressSuggestion> withResolvedCoordinates(
          AddressSuggestion suggestion) async =>
      suggestion;
}
