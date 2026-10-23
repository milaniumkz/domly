import '../localization/translation_controller.dart';
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
    this.street = '',
    this.house = '',
    this.isResidentialComplex = false,
    this.lat,
    this.lng,
    this.distanceMeters,
    this.city = '',
    this.searchText = '',
  });

  factory AddressSuggestion.fromBackend(Map<String, dynamic> row) {
    double? number(dynamic value) => double.tryParse('$value');
    final street = (row['street'] ?? '').toString();
    final house = (row['house'] ?? '').toString();
    final address = [street, house].where((part) => part.isNotEmpty).join(' ');
    final complex =
        (row['residentialComplex'] ?? row['residential_complex_ru'] ?? '')
            .toString()
            .trim();
    return AddressSuggestion(
        title: complex.isNotEmpty
            ? complex
            : address.isEmpty
                ? (row['label'] ?? '').toString()
                : address,
        subtitle: complex.isNotEmpty
            ? [address, row['city']]
                .where((v) => v != null && v.toString().isNotEmpty)
                .join(', ')
            : (row['city'] ?? '').toString(),
        addressLine: address,
        street: street,
        house: house,
        placeId: (row['id'] ?? '${row['source']}:${row['lat']},${row['lng']}')
            .toString(),
        residentialComplex: complex,
        isResidentialComplex: complex.isNotEmpty,
        city: (row['city'] ?? '').toString(),
        lat: number(row['lat']),
        lng: number(row['lng']),
        distanceMeters: number(row['distanceKm']) == null
            ? null
            : (number(row['distanceKm'])! * 1000).round());
  }

  final String title;
  final String subtitle;
  final String placeId;
  final String residentialComplex;
  final String addressLine;
  final String street;
  final String house;
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
  Future<List<String>> searchCities(String query) async {
    final rows = await BackendApiService.instance.getList(
      '/geo/cities',
      authenticated: false,
      query: {'search': query.trim(), 'limit': '10'},
    );
    return rows.map((row) => (row['name_ru'] ?? '').toString()).toList();
  }

  Future<List<AddressSuggestion>> search(String query,
      {AddressSearchBias? bias, String city = ''}) async {
    if (query.trim().length < 2) return [];
    final data = await BackendApiService.instance
        .getMap('/geo/address-suggestions', authenticated: false, query: {
      'search': query.trim(),
      'lang': TranslationController.active?.localeCode ?? 'ru',
      'city': city,
      'lat': bias?.lat.toString(),
      'lng': bias?.lng.toString(),
      'radiusKm': bias?.radiusKm.toString()
    });
    return (data['suggestions'] as List? ?? [])
        .whereType<Map>()
        .map((row) =>
            AddressSuggestion.fromBackend(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<AddressSuggestion?> reverse(double lat, double lng) async {
    final data = await BackendApiService.instance
        .getMap('/geo/reverse', authenticated: false, query: {
      'lat': '$lat',
      'lng': '$lng',
      'lang': TranslationController.active?.localeCode ?? 'ru'
    });
    final row = data['suggestion'];
    return row is Map
        ? AddressSuggestion.fromBackend(Map<String, dynamic>.from(row))
        : null;
  }

  Future<AddressSuggestion> withResolvedCoordinates(
          AddressSuggestion suggestion) async =>
      suggestion;
}
