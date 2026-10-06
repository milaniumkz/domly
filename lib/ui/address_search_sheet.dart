import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/address_search_service.dart';
import 'domly_ui.dart';
import '../localization/translation_controller.dart';

Future<AddressSuggestion?> showAddressSearchSheet(
  BuildContext context, {
  required String initialQuery,
  String title = 'Выберите адрес',
  List<AddressSuggestion> seedSuggestions = const <AddressSuggestion>[],
  bool restrictToSeedSuggestions = false,
  bool allowManualEntry = true,
  String saveButtonLabel = 'Сохранить адрес',
}) {
  return showModalBottomSheet<AddressSuggestion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AddressSearchSheet(
      initialQuery: initialQuery,
      title: title,
      seedSuggestions: seedSuggestions,
      restrictToSeedSuggestions: restrictToSeedSuggestions,
      allowManualEntry: allowManualEntry,
      saveButtonLabel: saveButtonLabel,
    ),
  );
}

class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet({
    required this.initialQuery,
    required this.title,
    required this.seedSuggestions,
    required this.restrictToSeedSuggestions,
    required this.allowManualEntry,
    required this.saveButtonLabel,
  });

  final String initialQuery;
  final String title;
  final List<AddressSuggestion> seedSuggestions;
  final bool restrictToSeedSuggestions;
  final bool allowManualEntry;
  final String saveButtonLabel;

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final _service = AddressSearchService.instance;
  late final TextEditingController _controller;
  List<AddressSuggestion> _suggestions = const <AddressSuggestion>[];
  bool _loading = false;
  bool _locationLoading = false;
  String _locationStatus = 'Ищем рядом с вами';
  AddressSearchBias? _searchBias;
  String _detectedCity = '';
  int _requestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    unawaited(_resolveLocation());
    if (widget.initialQuery.trim().length >= 2) {
      _searchNow(widget.initialQuery);
    } else if (widget.seedSuggestions.isNotEmpty) {
      _suggestions = _filterSeedSuggestions(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SizedBox(
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Адрес'.tr(),
              style: TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(
                labelText: 'ЖК или адрес рядом',
                suffixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _searchBias == null
                      ? Icons.near_me_disabled_outlined
                      : Icons.near_me_outlined,
                  size: 16,
                  color: _searchBias == null
                      ? DomlyColors.muted
                      : DomlyColors.buttonPrimary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _locationStatus,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
                  ),
                ),
                if (_locationLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: _resolveLocation,
                    child: Text('Обновить'.tr()),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.allowManualEntry) ...[
              DomlySecondaryButton(
                label: widget.saveButtonLabel,
                onPressed: _controller.text.trim().isEmpty
                    ? null
                    : () {
                        final value = _controller.text.trim();
                        Navigator.pop(
                          context,
                          AddressSuggestion(
                            title: value,
                            subtitle: '',
                            placeId: value,
                          ),
                        );
                      },
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _suggestions.isEmpty
                      ? Center(
                          child: Text(
                            'Подходящие варианты появятся после ввода адреса.'
                                .tr(),
                            style: TextStyle(color: DomlyColors.muted),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Результаты поиска'.tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: DomlyColors.foreground,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView.separated(
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _suggestions[index];
                                  return Material(
                                    color: DomlyColors.backgroundSoft,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () async {
                                        final resolved = await _service
                                            .withResolvedCoordinates(item);
                                        if (!context.mounted) {
                                          return;
                                        }
                                        Navigator.pop(context, resolved);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.location_on_outlined,
                                              color: DomlyColors.buttonPrimary,
                                            ),
                                            SizedBox(
                                              width: 230,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: DomlyColors
                                                              .foreground,
                                                        ),
                                                      ),
                                                      if (item
                                                          .isResidentialComplex)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 3,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: DomlyColors
                                                                .buttonPrimary
                                                                .withValues(
                                                                    alpha:
                                                                        0.12),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        999),
                                                          ),
                                                          child: Text(
                                                            'ЖК'.tr(),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: DomlyColors
                                                                  .buttonPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (item
                                                      .subtitle.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      item.subtitle,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            DomlyColors.muted,
                                                      ),
                                                    ),
                                                  ],
                                                  if (item.distanceMeters !=
                                                      null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _formatDistance(
                                                        item.distanceMeters!,
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: DomlyColors
                                                            .buttonPrimary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _search(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (widget.restrictToSeedSuggestions) {
      setState(() {
        _loading = false;
        _suggestions = _filterSeedSuggestions(query);
      });
      return;
    }
    if (query.length < 2) {
      setState(() {
        _loading = false;
        _suggestions = _filterSeedSuggestions(query);
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 280),
      () => _searchNow(query),
    );
  }

  Future<void> _searchNow(String value) async {
    final query = value.trim();
    final requestId = ++_requestId;
    if (widget.restrictToSeedSuggestions) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _suggestions = _filterSeedSuggestions(query);
      });
      return;
    }
    if (query.length < 2) {
      setState(() {
        _loading = false;
        _suggestions = _filterSeedSuggestions(query);
      });
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final items = await _service.search(
        query,
        bias: _searchBias,
        city: _detectedCity,
      );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _loading = false;
        final local = _filterSeedSuggestions(query);
        final seen = <String>{};
        final merged = <AddressSuggestion>[];
        for (final item in [...local, ...items]) {
          final key = '${item.placeId}|${item.fullText}'.toLowerCase();
          if (seen.add(key)) {
            merged.add(item);
          }
        }
        _suggestions = merged;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _loading = false;
        _suggestions = const <AddressSuggestion>[];
      });
    }
  }

  Future<void> _resolveLocation() async {
    if (_locationLoading) {
      return;
    }
    setState(() {
      _locationLoading = true;
      _locationStatus = 'Определяем местоположение для поиска рядом';
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!enabled) {
        _setLocationFallback('Геолокация выключена, ищем по Казахстану');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setLocationFallback('Нет доступа к геолокации, ищем по Казахстану');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      final city = await _service
          .reverse(position.latitude, position.longitude)
          .then((item) => item?.city.trim() ?? '')
          .timeout(const Duration(seconds: 5), onTimeout: () => '');
      if (!mounted) {
        return;
      }
      setState(() {
        _searchBias = AddressSearchBias(
          lat: position.latitude,
          lng: position.longitude,
        );
        _detectedCity = city;
        _locationLoading = false;
        _locationStatus = city.isEmpty
            ? 'Показываем адреса и ЖК рядом с вами'
            : 'Ищем адреса только в городе $city';
      });
      final query = _controller.text.trim();
      if (query.length >= 2) {
        unawaited(_searchNow(query));
      }
    } catch (_) {
      _setLocationFallback(
          'Не удалось определить геолокацию, ищем по Казахстану');
    }
  }

  List<AddressSuggestion> _filterSeedSuggestions(String query) {
    final normalized = _normalize(query);
    final looseQuery = _normalizeLoose(query);
    final queryTokens =
        normalized.split(' ').where((token) => token.length > 1).toList();
    final items = widget.seedSuggestions.where((item) {
      if (normalized.isEmpty) {
        return true;
      }
      final complexText = _normalize(
        '${item.residentialComplex} ${item.title}',
      );
      final looseComplexText = _normalizeLoose(complexText);
      final haystack = _normalize(
        '${item.title} ${item.subtitle} ${item.residentialComplex} '
        '${item.addressLine} ${item.city} ${item.searchText}',
      );
      final looseHaystack = _normalizeLoose(haystack);
      final complexMatched = complexText.contains(normalized) ||
          looseComplexText.contains(looseQuery) ||
          queryTokens.every((token) => complexText.contains(token));
      return complexMatched ||
          haystack.contains(normalized) ||
          looseHaystack.contains(looseQuery) ||
          _looksSimilar(query, haystack);
    }).toList();
    items.sort((a, b) {
      final aText = _normalize('${a.title} ${a.subtitle}');
      final bText = _normalize('${b.title} ${b.subtitle}');
      final aComplex = _normalize('${a.residentialComplex} ${a.title}');
      final bComplex = _normalize('${b.residentialComplex} ${b.title}');
      final aComplexMatch =
          normalized.isNotEmpty && aComplex.contains(normalized);
      final bComplexMatch =
          normalized.isNotEmpty && bComplex.contains(normalized);
      if (aComplexMatch != bComplexMatch) {
        return aComplexMatch ? -1 : 1;
      }
      final aStarts = normalized.isNotEmpty && aText.startsWith(normalized);
      final bStarts = normalized.isNotEmpty && bText.startsWith(normalized);
      if (aStarts != bStarts) {
        return aStarts ? -1 : 1;
      }
      return a.fullText.compareTo(b.fullText);
    });
    return items.take(20).toList();
  }

  String _normalize(String value) {
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
        .replaceAll('жилой комплекс', 'жк')
        .replaceAll(RegExp(r'\b(улица|ул|проспект|пр|переулок|пер)\b'), ' ')
        .replaceAll(
            RegExp(r'\b(кошеси|көшесі|коше|көше|дангылы|даңғылы)\b'), ' ')
        .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeLoose(String value) =>
      _normalize(value).replaceAll('ы', 'и');

  bool _isNumberToken(String token) =>
      RegExp(r'^\d+[a-zа-я]?$').hasMatch(token);

  int _editDistance(String a, String b) {
    if (a == b) return 0;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
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

  bool _looksSimilar(String query, String haystack) {
    final queryTokens = _normalizeLoose(query)
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    final haystackTokens = _normalizeLoose(haystack)
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    final numberMatched = queryTokens
        .where(_isNumberToken)
        .any(haystackTokens.where(_isNumberToken).contains);
    if (!numberMatched) return false;
    for (final queryToken
        in queryTokens.where((token) => !_isNumberToken(token))) {
      for (final houseToken
          in haystackTokens.where((token) => !_isNumberToken(token))) {
        final maxDistance =
            queryToken.length <= 4 || houseToken.length <= 4 ? 2 : 3;
        if (_tokenLooksLikePart(queryToken, houseToken, maxDistance)) {
          return true;
        }
      }
    }
    return false;
  }

  void _setLocationFallback(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _searchBias = null;
      _locationLoading = false;
      _locationStatus = message;
    });
  }

  String _formatDistance(int meters) {
    if (meters < 1000) {
      return '$meters м от вас';
    }
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} км от вас';
  }
}
