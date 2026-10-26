/// Keep editor fields independent; a summary is not a detailed description.
Map<String, dynamic> adminAddonTextFields(Map<String, dynamic> row) => {
  'description': row['description_ru'] ?? '',
  'descriptionKk': row['description_kk'],
  'fullInfo': row['full_description_ru'] ?? '',
  'fullInfoKk': row['full_description_kk'],
};

Map<String, dynamic> adminAddonTextPayload(Map<String, dynamic> item) => {
  'descriptionRu': item['description'] ?? item['shortInfo'],
  'descriptionKk': item['descriptionKk'],
  if (item.containsKey('fullInfo') || item.containsKey('longDescription'))
    'fullDescriptionRu': item['fullInfo'] ?? item['longDescription'],
  if (item.containsKey('fullInfoKk')) 'fullDescriptionKk': item['fullInfoKk'],
};

String adminAddonIdentity(Map<String, dynamic> item) =>
    (item['id'] ?? item['key'] ?? '').toString();

bool adminCatalogActive(Map<String, dynamic> item) =>
    (item['isActive'] ?? item['active']) != false;
