import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../app/app_env.dart';

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
  static const _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const _reverseEndpoint = 'https://nominatim.openstreetmap.org/reverse';
  static const _yandexSuggestEndpoint =
      'https://suggest-maps.yandex.ru/v1/suggest';
  static const _yandexGeocoderEndpoint = 'https://geocode-maps.yandex.ru/v1/';

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
    final normalized = _normalizeCityQuery(query);
    if (normalized.isEmpty) {
      return _kazakhstanCities.take(8).toList();
    }
    final items = _kazakhstanCities.where((city) {
      final value = _normalizeCityQuery(city);
      final latin = _latinCityQuery(city);
      return value.startsWith(normalized) ||
          value.contains(normalized) ||
          latin.startsWith(normalized) ||
          latin.contains(normalized);
    }).toList();
    items.sort((a, b) {
      final left = _normalizeCityQuery(a).startsWith(normalized) ||
              _latinCityQuery(a).startsWith(normalized)
          ? 0
          : 1;
      final right = _normalizeCityQuery(b).startsWith(normalized) ||
              _latinCityQuery(b).startsWith(normalized)
          ? 0
          : 1;
      if (left != right) {
        return left.compareTo(right);
      }
      return a.compareTo(b);
    });
    return items.take(12).toList();
  }

  Future<List<AddressSuggestion>> search(
    String query, {
    AddressSearchBias? bias,
    String city = '',
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) {
      return const <AddressSuggestion>[];
    }
    final normalizedCity = _normalizeCityQuery(city);
    final scopedQuery =
        normalizedCity.isEmpty || _queryContainsCity(normalized, city)
            ? normalized
            : '$normalized, $city';

    final items = _rankAndFilter(
      normalized,
      await _searchOsm(scopedQuery, bias: bias, city: city),
      bias: bias,
      city: city,
    );
    if (items.length < 4) {
      final yandexItems =
          await _searchYandex(scopedQuery, bias: bias, city: city);
      if (yandexItems.isNotEmpty) {
        items.addAll(_rankAndFilter(
          normalized,
          yandexItems,
          bias: bias,
          city: city,
        ));
      }
    }

    return _dedupeAndSort(normalized, items, bias: bias, city: city)
        .take(10)
        .toList();
  }

  Future<AddressSuggestion?> reverse(double lat, double lng) async {
    final osm = await _reverseOsm(lat, lng);
    if (osm != null) {
      return osm;
    }
    return _reverseYandex(lat, lng);
  }

  Future<AddressSuggestion> withResolvedCoordinates(
    AddressSuggestion suggestion,
  ) async {
    if (!suggestion.needsCoordinateLookup) {
      return suggestion;
    }
    return await _geocodeYandexText(suggestion.fullText) ?? suggestion;
  }

  Future<List<AddressSuggestion>> _searchOsm(
    String normalized, {
    AddressSearchBias? bias,
    String city = '',
  }) async {
    final seen = <String>{};
    final items = <AddressSuggestion>[];
    try {
      for (final variant in _queryVariants(normalized)) {
        final params = <String, String>{
          'q': city.trim().isEmpty || _queryContainsCity(variant, city)
              ? '$variant, Казахстан'
              : '$variant, $city, Казахстан',
          'format': 'jsonv2',
          'addressdetails': '1',
          'namedetails': '1',
          'limit': '12',
          'countrycodes': 'kz',
          'accept-language': 'ru',
        };
        if (bias != null) {
          params.addAll(_viewboxParams(bias));
        }
        final uri = Uri.parse(_endpoint).replace(queryParameters: params);
        final response = await http.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Accept-Language': 'ru',
          },
        ).timeout(const Duration(seconds: 7));
        if (response.statusCode != 200) {
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          continue;
        }
        for (final raw in decoded) {
          if (raw is! Map) {
            continue;
          }
          final item = Map<String, dynamic>.from(raw);
          if (!_isOsmAddressCandidate(item)) {
            continue;
          }
          final suggestion = _mapSuggestion(normalized, item, bias: bias);
          final dedupeKey =
              '${suggestion.placeId}|${suggestion.fullText}'.toLowerCase();
          if (suggestion.title.trim().isEmpty || seen.contains(dedupeKey)) {
            continue;
          }
          seen.add(dedupeKey);
          items.add(suggestion);
        }
      }
    } catch (_) {
      return const <AddressSuggestion>[];
    }
    return items;
  }

  Future<List<AddressSuggestion>> _searchYandex(
    String query, {
    AddressSearchBias? bias,
    String city = '',
  }) async {
    final apiKey = AppEnv.yandexGeosuggestApiKey.trim();
    if (apiKey.isEmpty) {
      return const <AddressSuggestion>[];
    }
    try {
      final params = <String, String>{
        'apikey': apiKey,
        'text': city.trim().isEmpty || _queryContainsCity(query, city)
            ? '$query, Казахстан'
            : '$query, $city, Казахстан',
        'lang': 'ru_RU',
        'types': 'geo',
        'print_address': '1',
        'attrs': 'uri',
        'results': '10',
      };
      if (bias != null) {
        params['ll'] = '${bias.lng},${bias.lat}';
        params['spn'] = '${bias.radiusKm / 55},${bias.radiusKm / 55}';
      }
      final uri =
          Uri.parse(_yandexSuggestEndpoint).replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        return const <AddressSuggestion>[];
      }
      final decoded = jsonDecode(response.body);
      final rawItems = decoded is Map ? decoded['results'] : null;
      if (rawItems is! List) {
        return const <AddressSuggestion>[];
      }
      final items = <AddressSuggestion>[];
      final seen = <String>{};
      for (final raw in rawItems) {
        if (raw is! Map) {
          continue;
        }
        if (!_isYandexAddressCandidate(Map<String, dynamic>.from(raw))) {
          continue;
        }
        final suggestion = _mapYandexSuggest(
          Map<String, dynamic>.from(raw),
          bias: bias,
        );
        if (!_suggestionLooksAddressOnly(suggestion)) {
          continue;
        }
        final key =
            '${suggestion.placeId}|${suggestion.fullText}'.toLowerCase();
        if (suggestion.title.isEmpty || seen.contains(key)) {
          continue;
        }
        seen.add(key);
        items.add(suggestion);
      }
      return items;
    } catch (_) {
      return const <AddressSuggestion>[];
    }
  }

  Future<AddressSuggestion?> _reverseOsm(double lat, double lng) async {
    try {
      final uri = Uri.parse(_reverseEndpoint).replace(queryParameters: {
        'format': 'jsonv2',
        'addressdetails': '1',
        'lat': lat.toStringAsFixed(7),
        'lon': lng.toStringAsFixed(7),
        'accept-language': 'ru',
      });
      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Accept-Language': 'ru',
        },
      ).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return null;
      }
      final item = Map<String, dynamic>.from(decoded);
      final suggestion = _mapSuggestion('', item);
      if (suggestion.fullText.trim().isEmpty) {
        return null;
      }
      return suggestion;
    } catch (_) {
      return null;
    }
  }

  Future<AddressSuggestion?> _reverseYandex(double lat, double lng) async {
    final apiKey = AppEnv.yandexGeocoderApiKey.trim();
    if (apiKey.isEmpty) {
      return null;
    }
    try {
      final uri = Uri.parse(_yandexGeocoderEndpoint).replace(queryParameters: {
        'apikey': apiKey,
        'geocode': '${lng.toStringAsFixed(7)},${lat.toStringAsFixed(7)}',
        'format': 'json',
        'lang': 'ru_RU',
        'kind': 'house',
        'results': '1',
      });
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      final decodedMap =
          decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
      final responseMap = Map<String, dynamic>.from(
        decodedMap['response'] as Map? ?? const {},
      );
      final collectionMap = Map<String, dynamic>.from(
        responseMap['GeoObjectCollection'] as Map? ?? const {},
      );
      final members = collectionMap['featureMember'];
      if (members is! List || members.isEmpty || members.first is! Map) {
        return null;
      }
      return _mapYandexGeoObject(
        Map<String, dynamic>.from(members.first['GeoObject'] as Map? ?? {}),
        fallbackLat: lat,
        fallbackLng: lng,
      );
    } catch (_) {
      return null;
    }
  }

  AddressSuggestion _mapYandexSuggest(
    Map<String, dynamic> item, {
    AddressSearchBias? bias,
  }) {
    final title = _firstNonEmpty([
      _nestedText(item, 'title', 'text'),
      _nestedText(item, 'subtitle', 'text'),
    ]);
    final subtitle = _firstNonEmpty([
      _nestedText(item, 'subtitle', 'text'),
      _nestedText(item, 'address', 'formatted_address'),
    ]);
    final uri = _firstNonEmpty([item['uri'], item['id'], title]);
    return AddressSuggestion(
      title: title,
      subtitle: subtitle == title ? '' : subtitle,
      placeId: 'yandex:$uri',
      residentialComplex: _looksLikeResidentialComplex(title)
          ? _normalizeResidentialComplexName(title)
          : '',
      addressLine: subtitle,
      lat: null,
      lng: null,
      city: _cityFromText(subtitle),
      searchText: _joinNonEmpty([
        title,
        subtitle,
        _nestedText(item, 'address', 'formatted_address'),
        item['tags'],
      ], separator: ' '),
      distanceMeters: null,
    );
  }

  AddressSuggestion _mapYandexGeoObject(
    Map<String, dynamic> geoObject, {
    double? fallbackLat,
    double? fallbackLng,
  }) {
    final meta = Map<String, dynamic>.from(
      _nestedMap(geoObject, 'metaDataProperty', 'GeocoderMetaData'),
    );
    final address =
        Map<String, dynamic>.from(meta['Address'] as Map? ?? const {});
    final components =
        (address['Components'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    String component(String kind) {
      for (final item in components) {
        if ((item['kind'] ?? '').toString() == kind) {
          return (item['name'] ?? '').toString().trim();
        }
      }
      return '';
    }

    final pointText = _nestedText(geoObject, 'Point', 'pos');
    final pointParts = pointText.split(RegExp(r'\s+'));
    final lng = pointParts.length >= 2
        ? double.tryParse(pointParts[0]) ?? fallbackLng
        : fallbackLng;
    final lat = pointParts.length >= 2
        ? double.tryParse(pointParts[1]) ?? fallbackLat
        : fallbackLat;
    final street = component('street');
    final house = component('house');
    final locality = _firstNonEmpty([
      component('locality'),
      component('province'),
      component('area'),
    ]);
    final addressLine = _firstNonEmpty([
      address['formatted'],
      _joinNonEmpty([street, house], separator: ' '),
      geoObject['name'],
      geoObject['description'],
    ]);
    final title = _firstNonEmpty([
      _joinNonEmpty([street, house], separator: ' '),
      geoObject['name'],
      addressLine,
    ]);
    final subtitle = _joinNonEmpty(
      [
        if (title != addressLine) addressLine,
        locality,
      ],
      separator: ', ',
    );
    return AddressSuggestion(
      title: title,
      subtitle: subtitle,
      placeId: _firstNonEmpty([geoObject['uri'], geoObject['id'], addressLine]),
      addressLine: addressLine,
      city: locality,
      searchText: _joinNonEmpty([
        title,
        subtitle,
        addressLine,
        street,
        house,
        locality,
      ], separator: ' '),
      lat: lat,
      lng: lng,
    );
  }

  Future<AddressSuggestion?> _geocodeYandexText(String query) async {
    final apiKey = AppEnv.yandexGeocoderApiKey.trim();
    if (apiKey.isEmpty || query.trim().isEmpty) {
      return null;
    }
    try {
      final uri = Uri.parse(_yandexGeocoderEndpoint).replace(queryParameters: {
        'apikey': apiKey,
        'geocode': '${query.trim()}, Казахстан',
        'format': 'json',
        'lang': 'ru_RU',
        'results': '1',
      });
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      final decodedMap =
          decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
      final responseMap = Map<String, dynamic>.from(
        decodedMap['response'] as Map? ?? const {},
      );
      final collectionMap = Map<String, dynamic>.from(
        responseMap['GeoObjectCollection'] as Map? ?? const {},
      );
      final members = collectionMap['featureMember'];
      if (members is! List || members.isEmpty || members.first is! Map) {
        return null;
      }
      return _mapYandexGeoObject(
        Map<String, dynamic>.from(members.first['GeoObject'] as Map? ?? {}),
      );
    } catch (_) {
      return null;
    }
  }

  String _cityFromText(String value) {
    final normalized = _normalizeCityQuery(value);
    for (final city in _kazakhstanCities) {
      final cityValue = _normalizeCityQuery(city);
      if (normalized.contains(cityValue)) {
        return city;
      }
    }
    return '';
  }

  Map<String, dynamic> _nestedMap(
    Map<String, dynamic> source,
    String first,
    String second,
  ) {
    final outer = source[first];
    if (outer is! Map) {
      return const {};
    }
    final inner = outer[second];
    if (inner is! Map) {
      return const {};
    }
    return Map<String, dynamic>.from(inner);
  }

  String _nestedText(
    Map<String, dynamic> source,
    String first,
    String second,
  ) {
    final outer = source[first];
    if (outer is! Map) {
      return '';
    }
    return (outer[second] ?? '').toString().trim();
  }

  List<String> _queryVariants(String query) {
    final variants = <String>[query];
    final withoutNoise = _normalizeSearchText(query)
        .split(' ')
        .where(
            (token) => token.isNotEmpty && !_streetNoiseWords.contains(token))
        .join(' ');
    if (withoutNoise.isNotEmpty && withoutNoise != query.trim()) {
      variants.add(withoutNoise);
    }
    final lower = query.toLowerCase();
    if (!lower.startsWith('жк ') && !lower.contains('жилой комплекс')) {
      variants.add('ЖК $query');
      variants.add('жилой комплекс $query');
    }
    return variants.toSet().toList();
  }

  Map<String, String> _viewboxParams(AddressSearchBias bias) {
    final latDelta = bias.radiusKm / 111;
    final lngDelta = bias.radiusKm /
        (111 * math.cos(bias.lat * math.pi / 180).abs().clamp(0.25, 1));
    return {
      'viewbox': [
        (bias.lng - lngDelta).toStringAsFixed(6),
        (bias.lat + latDelta).toStringAsFixed(6),
        (bias.lng + lngDelta).toStringAsFixed(6),
        (bias.lat - latDelta).toStringAsFixed(6),
      ].join(','),
      'bounded': '0',
    };
  }

  AddressSuggestion _mapSuggestion(
    String query,
    Map<String, dynamic> item, {
    AddressSearchBias? bias,
  }) {
    final address =
        Map<String, dynamic>.from(item['address'] as Map? ?? const {});
    final namedetails =
        Map<String, dynamic>.from(item['namedetails'] as Map? ?? const {});
    final displayName = (item['display_name'] ?? '').toString().trim();
    final primaryTitle = _firstNonEmpty([
      namedetails['name:ru'],
      namedetails['official_name:ru'],
      item['name'],
      namedetails['name'],
      displayName.split(',').isNotEmpty ? displayName.split(',').first : '',
    ]);
    final complexName = _extractResidentialComplex(
      query: query,
      primaryTitle: primaryTitle,
      address: address,
      namedetails: namedetails,
    );
    final title = complexName.isNotEmpty ? complexName : primaryTitle;
    final subtitle = _buildSubtitle(
      displayName: displayName,
      title: title,
      address: address,
    );
    final city = _extractCity(address);
    final placeId = [
      item['osm_type']?.toString(),
      item['osm_id']?.toString(),
      item['place_id']?.toString(),
    ].where((part) => part != null && part.isNotEmpty).join(':');
    final lat = double.tryParse((item['lat'] ?? '').toString());
    final lng = double.tryParse((item['lon'] ?? '').toString());

    return AddressSuggestion(
      title: title,
      subtitle: subtitle,
      placeId: placeId.isEmpty ? displayName : placeId,
      residentialComplex: complexName,
      addressLine: subtitle,
      isResidentialComplex: complexName.isNotEmpty,
      lat: lat,
      lng: lng,
      distanceMeters: _distanceMeters(lat, lng, bias),
      city: city,
      searchText: _joinNonEmpty([
        primaryTitle,
        complexName,
        subtitle,
        displayName,
        address['road'],
        address['house_number'],
        address['residential'],
        namedetails['name:ru'],
        namedetails['name:kk'],
        namedetails['name'],
      ], separator: ' '),
    );
  }

  List<AddressSuggestion> _rankAndFilter(
    String query,
    List<AddressSuggestion> items, {
    AddressSearchBias? bias,
    String city = '',
  }) {
    return _dedupeAndSort(
      query,
      items
          .where((item) => _matchesCity(item, city))
          .where((item) => _matchesAddressQuery(query, item))
          .toList(),
      bias: bias,
      city: city,
    );
  }

  List<AddressSuggestion> _dedupeAndSort(
    String query,
    List<AddressSuggestion> items, {
    AddressSearchBias? bias,
    String city = '',
  }) {
    final seen = <String>{};
    final deduped = <AddressSuggestion>[];
    for (final item in items) {
      final key = _normalizeSearchText(
        '${item.title}|${item.subtitle}|${item.lat?.toStringAsFixed(5)}|'
        '${item.lng?.toStringAsFixed(5)}',
      );
      if (seen.add(key)) {
        deduped.add(item);
      }
    }
    deduped.sort((a, b) => _scoreSuggestion(query, b, bias: bias)
        .compareTo(_scoreSuggestion(query, a, bias: bias)));
    return deduped;
  }

  bool _queryContainsCity(String query, String city) {
    final normalizedCity = _normalizeCityQuery(city);
    if (normalizedCity.isEmpty) {
      return true;
    }
    return _normalizeCityQuery(query).contains(normalizedCity);
  }

  bool _matchesCity(AddressSuggestion item, String city) {
    final normalizedCity = _normalizeCityQuery(city);
    if (normalizedCity.isEmpty) {
      return true;
    }
    final itemCity = _normalizeCityQuery(item.city);
    if (itemCity.isNotEmpty) {
      return itemCity == normalizedCity || itemCity.contains(normalizedCity);
    }
    return _normalizeCityQuery(
            '${item.subtitle} ${item.addressLine} ${item.searchText}')
        .contains(normalizedCity);
  }

  bool _isOsmAddressCandidate(Map<String, dynamic> item) {
    final address =
        Map<String, dynamic>.from(item['address'] as Map? ?? const {});
    final category = (item['category'] ?? item['class'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final type = (item['type'] ?? item['addresstype'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final title = _firstNonEmpty([
      item['name'],
      item['display_name']?.toString().split(',').first,
    ]);
    const blockedCategories = {
      'amenity',
      'shop',
      'tourism',
      'leisure',
      'office',
      'craft',
      'healthcare',
      'historic',
      'natural',
    };
    if (blockedCategories.contains(category)) {
      return false;
    }
    if (_looksLikeBusinessName(title) && !_looksLikeAddressTitle(title)) {
      return false;
    }
    const allowedTypes = {
      'house',
      'building',
      'apartments',
      'residential',
      'road',
      'street',
      'pedestrian',
      'primary',
      'secondary',
      'tertiary',
      'unclassified',
      'living_street',
      'service',
    };
    if (allowedTypes.contains(type) || category == 'highway') {
      return true;
    }
    return [
      address['road'],
      address['street'],
      address['pedestrian'],
      address['house_number'],
      address['residential'],
      address['building'],
    ].any((value) => (value ?? '').toString().trim().isNotEmpty);
  }

  bool _isYandexAddressCandidate(Map<String, dynamic> item) {
    final title = _nestedText(item, 'title', 'text');
    final subtitle = _nestedText(item, 'subtitle', 'text');
    final formattedAddress = _nestedText(item, 'address', 'formatted_address');
    final tags = [
      item['tags'],
      title,
      subtitle,
      formattedAddress,
    ].join(' ').toLowerCase();
    const blocked = [
      'biz',
      'business',
      'company',
      'organization',
      'org',
      'shop',
      'food',
      'cafe',
      'restaurant',
      'hotel',
      'pharmacy',
      'fuel',
      'atm',
      'кафе',
      'ресторан',
      'магазин',
      'супермаркет',
      'аптека',
      'банк',
      'школа',
      'садик',
      'детский сад',
      'трц',
      'тд',
      'бц',
      'тоо',
      'ип',
      'отель',
      'гостиница',
      'салон',
      'студия',
      'клиника',
      'поликлиника',
      'бар',
      'кофейня',
      'азс',
      'автомойка',
      'сервис',
      'терминал',
      'банкомат',
      'офис',
      'рынок',
      'фитнес',
    ];
    if (blocked.any(tags.contains)) {
      return false;
    }
    if (_looksLikeAddressTitle(title)) {
      return true;
    }
    const allowedTags = [
      'house',
      'street',
      'district',
      'locality',
      'province',
      'residential',
      'toponym',
      'address',
    ];
    return allowedTags.any(tags.contains) && !_looksLikeBusinessName(title);
  }

  bool _suggestionLooksAddressOnly(AddressSuggestion item) {
    if (_looksLikeBusinessName(item.title) &&
        !_looksLikeAddressTitle(item.title)) {
      return false;
    }
    return _looksLikeAddressTitle(item.title) ||
        _looksLikeAddressTitle(item.addressLine) ||
        _looksLikeAddressTitle(item.residentialComplex);
  }

  bool _looksLikeAddressTitle(String value) {
    final normalized = _normalizeSearchText(value);
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains('жк') ||
        normalized.contains('жилой комплекс') ||
        normalized.split(' ').any(_isNumberToken) ||
        RegExp(
          r'\b(улица|ул|проспект|пр|переулок|пер|кошеси|көшесі|коше|көше|дангылы|даңғылы|street|avenue|road|st|ave)\b',
        ).hasMatch(normalized);
  }

  bool _looksLikeBusinessName(String value) {
    final normalized = _normalizeSearchText(value);
    if (normalized.isEmpty) {
      return false;
    }
    const businessWords = [
      'кафе',
      'ресторан',
      'бар',
      'кофейня',
      'магазин',
      'супермаркет',
      'маркет',
      'аптека',
      'банк',
      'школа',
      'садик',
      'детский сад',
      'трц',
      'тд',
      'бц',
      'тоо',
      'ип',
      'отель',
      'гостиница',
      'салон',
      'студия',
      'клиника',
      'поликлиника',
      'азс',
      'автомойка',
      'сервис',
      'терминал',
      'банкомат',
      'офис',
      'рынок',
      'фитнес',
      'restaurant',
      'cafe',
      'shop',
      'store',
      'market',
      'pharmacy',
      'hotel',
      'office',
      'bank',
      'school',
      'clinic',
      'fitness',
    ];
    return businessWords.any(normalized.contains);
  }

  String _extractCity(Map<String, dynamic> address) {
    return _firstNonEmpty([
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['county'],
      address['state'],
    ]);
  }

  String _extractResidentialComplex({
    required String query,
    required String primaryTitle,
    required Map<String, dynamic> address,
    required Map<String, dynamic> namedetails,
  }) {
    final residential = _firstNonEmpty([
      address['residential'],
      namedetails['official_name:ru'],
      namedetails['name:ru'],
      itemOrNull(namedetails, 'brand:ru'),
    ]);
    if (_looksLikeResidentialComplex(residential)) {
      return _normalizeResidentialComplexName(residential);
    }
    if (query.toLowerCase().contains('жк') &&
        _looksLikeShortComplexName(primaryTitle)) {
      return _normalizeResidentialComplexName(primaryTitle);
    }
    if (_looksLikeShortComplexName(primaryTitle) &&
        _containsNormalized(primaryTitle, query) &&
        !_looksLikeStreet(primaryTitle)) {
      return _normalizeResidentialComplexName(primaryTitle);
    }
    return '';
  }

  String _buildSubtitle({
    required String displayName,
    required String title,
    required Map<String, dynamic> address,
  }) {
    final street = _firstNonEmpty([
      _joinNonEmpty([
        address['road'],
        address['house_number'],
      ], separator: ' '),
      address['pedestrian'],
      address['street'],
    ]);
    final locality = _firstNonEmpty([
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['state'],
    ]);
    final district = _firstNonEmpty([
      address['suburb'],
      address['neighbourhood'],
      address['quarter'],
      address['city_district'],
    ]);
    final subtitle = _joinNonEmpty(
      [street, district, locality],
      separator: ', ',
    );
    if (subtitle.isNotEmpty) {
      return subtitle == title ? '' : subtitle;
    }
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '';
    }
    if (parts.first == title) {
      parts.removeAt(0);
    }
    return parts.join(', ');
  }

  int _scoreSuggestion(
    String query,
    AddressSuggestion item, {
    AddressSearchBias? bias,
  }) {
    final normalizedQuery = _normalizeSearchText(query);
    final queryTokens = _queryTokens(query);
    final title = _normalizeSearchText(item.title);
    final subtitle = _normalizeSearchText(item.subtitle);
    final searchText = _normalizeSearchText(
      '${item.title} ${item.subtitle} ${item.residentialComplex} '
      '${item.addressLine} ${item.city} ${item.searchText}',
    );
    var score = 0;
    if (item.isResidentialComplex) {
      score += 80;
    }
    if (title.startsWith(normalizedQuery)) {
      score += 60;
    } else if (title.contains(normalizedQuery)) {
      score += 35;
    }
    if (subtitle.contains(normalizedQuery)) {
      score += 15;
    }
    final matchedTokens =
        queryTokens.where((token) => searchText.contains(token)).length;
    score += matchedTokens * 35;
    if (queryTokens.isNotEmpty && matchedTokens == queryTokens.length) {
      score += 90;
    }
    if (_hasNumberToken(queryTokens) &&
        !_hasMatchingNumber(queryTokens, item)) {
      score -= 120;
    }
    if (!_matchesAddressQuery(query, item)) {
      score -= 500;
    }
    if (title.contains('жк')) {
      score += 20;
    }
    if (bias != null && item.distanceMeters != null) {
      final distanceKm = item.distanceMeters! / 1000;
      if (distanceKm <= 2) {
        score += 80;
      } else if (distanceKm <= 5) {
        score += 55;
      } else if (distanceKm <= 12) {
        score += 35;
      } else if (distanceKm <= 25) {
        score += 10;
      } else {
        score -= distanceKm.clamp(0, 80).round();
      }
    }
    return score;
  }

  bool _matchesAddressQuery(String query, AddressSuggestion item) {
    final tokens = _queryTokens(query);
    if (tokens.isEmpty) {
      return true;
    }
    final haystack = _normalizeSearchText(
      '${item.title} ${item.subtitle} ${item.residentialComplex} '
      '${item.addressLine} ${item.city} ${item.searchText}',
    );
    final textTokens = haystack.split(' ').where((t) => t.length > 1).toList();
    final textTokenSet = textTokens.toSet();
    for (final token in tokens) {
      if (_isNumberToken(token)) {
        if (!textTokenSet.contains(token)) {
          return false;
        }
        continue;
      }
      if (haystack.contains(token)) {
        continue;
      }
      final maxDistance = token.length <= 4 ? 1 : 2;
      final similar = textTokens.any(
        (target) => _tokenLooksLikePart(token, target, maxDistance),
      );
      if (!similar) {
        return false;
      }
    }
    return true;
  }

  Set<String> _queryTokens(String value) {
    return _normalizeSearchText(value)
        .split(' ')
        .where((token) => token.length > 1)
        .where((token) => !_streetNoiseWords.contains(token))
        .toSet();
  }

  bool _hasNumberToken(Set<String> tokens) => tokens.any(_isNumberToken);

  bool _hasMatchingNumber(Set<String> tokens, AddressSuggestion item) {
    final haystack = _normalizeSearchText(
      '${item.title} ${item.subtitle} ${item.addressLine} ${item.searchText}',
    ).split(' ').toSet();
    return tokens.where(_isNumberToken).any(haystack.contains);
  }

  bool _isNumberToken(String token) =>
      RegExp(r'^\d+[a-zа-я]?$').hasMatch(token);

  bool _tokenLooksLikePart(String query, String target, int maxDistance) {
    if ((query.length - target.length).abs() <= maxDistance &&
        _editDistance(query, target) <= maxDistance) {
      return true;
    }
    if (query.length < 3 || target.length <= query.length) {
      return false;
    }
    for (var index = 0; index <= target.length - query.length; index += 1) {
      final part = target.substring(index, index + query.length);
      if (_editDistance(query, part) <= maxDistance) {
        return true;
      }
    }
    return false;
  }

  int _editDistance(String a, String b) {
    if (a == b) return 0;
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i += 1) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
      for (var j = 0; j < b.length; j += 1) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((left, right) => left < right ? left : right);
      }
      previous = current;
    }
    return previous.last;
  }

  int? _distanceMeters(double? lat, double? lng, AddressSearchBias? bias) {
    if (lat == null || lng == null || bias == null) {
      return null;
    }
    const earthRadius = 6371000.0;
    final dLat = _degreesToRadians(lat - bias.lat);
    final dLng = _degreesToRadians(lng - bias.lng);
    final lat1 = _degreesToRadians(bias.lat);
    final lat2 = _degreesToRadians(lat);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return (earthRadius * c).round();
  }

  double _degreesToRadians(double value) => value * math.pi / 180;

  String _normalizeResidentialComplexName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('жк ') || lower.contains('жилой комплекс')) {
      return trimmed;
    }
    return 'ЖК $trimmed';
  }

  bool _looksLikeResidentialComplex(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.startsWith('жк ') ||
        normalized.contains('жилой комплекс') ||
        (_looksLikeShortComplexName(value) && !_looksLikeStreet(value));
  }

  bool _looksLikeShortComplexName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length < 3 || trimmed.length > 80) {
      return false;
    }
    return !trimmed.contains(',');
  }

  bool _looksLikeStreet(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('улиц') ||
        normalized.contains('ул.') ||
        normalized.contains('просп') ||
        normalized.contains('пр-т') ||
        normalized.contains('микрорайон') ||
        normalized.contains('мкр') ||
        normalized.contains('шоссе') ||
        normalized.contains('переул') ||
        normalized.contains('бульвар');
  }

  bool _containsNormalized(String source, String query) {
    return _normalize(source).contains(_normalize(query));
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  static const Set<String> _streetNoiseWords = {
    'улица',
    'ул',
    'проспект',
    'пр',
    'просп',
    'переулок',
    'пер',
    'жк',
    'жилой',
    'комплекс',
    'кошеси',
    'көшесі',
    'коше',
    'көше',
    'дангылы',
    'даңғылы',
    'батыр',
    'батыра',
    'батыров',
  };

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('ә', 'а')
        .replaceAll('ғ', 'г')
        .replaceAll('қ', 'к')
        .replaceAll('ң', 'н')
        .replaceAll('ө', 'о')
        .replaceAll('ұ', 'у')
        .replaceAll('ү', 'у')
        .replaceAll('һ', 'х')
        .replaceAll('і', 'и')
        .replaceAll('ы', 'и')
        .replaceAll('й', 'и')
        .replaceAll('жилой комплекс', 'жк')
        .replaceAll(RegExp(r'\b(улица|ул|проспект|пр|переулок|пер)\b'), ' ')
        .replaceAll(
            RegExp(r'\b(кошеси|көшесі|коше|көше|дангылы|даңғылы)\b'), ' ')
        .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeCityQuery(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-яәіңғүұқөһ0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _latinCityQuery(String value) {
    const map = {
      'а': 'a',
      'ә': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'ғ': 'g',
      'д': 'd',
      'е': 'e',
      'ё': 'e',
      'ж': 'zh',
      'з': 'z',
      'и': 'i',
      'і': 'i',
      'й': 'i',
      'к': 'k',
      'қ': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'ң': 'n',
      'о': 'o',
      'ө': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ұ': 'u',
      'ү': 'u',
      'ф': 'f',
      'х': 'h',
      'һ': 'h',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'sh',
      'ы': 'y',
      'э': 'e',
      'ю': 'yu',
      'я': 'ya',
    };
    final buffer = StringBuffer();
    for (final rune in _normalizeCityQuery(value).runes) {
      final char = String.fromCharCode(rune);
      buffer.write(map[char] ?? char);
    }
    return buffer.toString();
  }

  String _firstNonEmpty(List<Object?> items) {
    for (final item in items) {
      final text = (item ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _joinNonEmpty(List<Object?> parts, {required String separator}) {
    return parts
        .map((part) => (part ?? '').toString().trim())
        .where((part) => part.isNotEmpty)
        .join(separator);
  }

  Object? itemOrNull(Map<String, dynamic> map, String key) {
    return map.containsKey(key) ? map[key] : null;
  }
}
