Map<String, dynamic> mapBackendBanner(Map<String, dynamic> item) {
  final type = item['target_type'] ?? item['targetType'];
  final target = item['target_value'] ?? item['targetValue'] ?? '';
  return {
    ...item,
    'title': item['title_ru'] ?? item['title'] ?? '',
    'titleKk': item['title_kk'] ?? item['titleKk'],
    'subtitle': item['subtitle_ru'] ?? item['subtitle'] ?? '',
    'description': item['description_ru'] ?? item['description'] ?? '',
    'imageUrl': item['image_url'] ?? item['imageUrl'] ?? '',
    'ctaLabel': item['cta_label_ru'] ?? item['ctaLabel'] ?? '',
    'route': item['route'] ?? (type == 'route' ? target : ''),
    'externalUrl': item['external_url'] ??
        item['externalUrl'] ??
        (type == 'external' ? target : ''),
    'sortOrder': item['sort_order'] ?? item['sortOrder'] ?? 0,
    'isActive': item['active'] ?? item['isActive'] ?? true,
  };
}

Map<String, dynamic> bannerRequestBody(Map<String, dynamic> banner) {
  final route = (banner['route'] ?? '').toString();
  final external = (banner['externalUrl'] ?? '').toString();
  return {
    'titleRu': banner['title'] ?? banner['titleRu'] ?? 'Баннер',
    'titleKk': banner['titleKk'],
    'descriptionRu': banner['description'] ?? banner['descriptionRu'],
    'descriptionKk': banner['descriptionKk'],
    'subtitleRu': banner['subtitle'] ?? '',
    'ctaLabelRu': banner['ctaLabel'] ?? '',
    'imageUrl': banner['imageUrl'] ?? '',
    'imageFileId': banner['imageFileId'] ?? banner['image_file_id'],
    'targetType': external.isNotEmpty
        ? 'external'
        : route.isNotEmpty
            ? 'route'
            : 'modal',
    'targetValue': external.isNotEmpty ? external : route,
    'placement': banner['placement'] == 'home_info'
        ? 'home_top'
        : banner['placement'] ?? 'home_top',
    'sortOrder': banner['sortOrder'] ?? 0,
    'active': banner['isActive'] ?? banner['active'] ?? true,
  };
}
