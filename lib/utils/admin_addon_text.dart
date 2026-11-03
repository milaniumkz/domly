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
      if (item.containsKey('fullInfoKk'))
        'fullDescriptionKk': item['fullInfoKk'],
    };

String adminAddonIdentity(Map<String, dynamic> item) =>
    (item['id'] ?? item['key'] ?? '').toString();

bool adminCatalogActive(Map<String, dynamic> item) =>
    (item['isActive'] ?? item['active']) != false;

/// Quantity is an independent option; older rows fall back to their price type.
bool adminAddonSupportsQuantity(Map<String, dynamic> item) =>
    (item['supportsQuantity'] ?? item['supports_quantity']) as bool? ??
    (item['pricingType'] ?? item['pricing_type']) != 'fixed_per_order';

Map<String, dynamic> adminAddonOptionPayload(Map<String, dynamic> item) => {
      'supportsQuantity': adminAddonSupportsQuantity(item),
      if (item.containsKey('features')) 'features': item['features'],
      'paidSeparately': item['separatePayment'] ??
          item['paidSeparately'] ??
          item['paid_separately'] ??
          false,
    };
