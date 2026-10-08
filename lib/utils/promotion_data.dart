Map<String, dynamic> mapBackendPromotion(Map<String, dynamic> item) {
  final extra = Map<String, dynamic>.from((item['presentation'] as Map?) ?? {});
  final mode = (item['reward_type'] ?? item['rewardMode']) == 'percent'
      ? 'percent'
      : 'fixed';
  final raw = item['reward_value'] ?? 0;
  final value = raw is num ? raw : num.tryParse(raw.toString()) ?? 0;
  return {
    ...item,
    ...extra,
    'id': item['id'],
    'title': item['title_ru'] ?? item['title'] ?? '',
    'titleKk': item['title_kk'],
    'description': item['description_ru'] ?? '',
    'shortInfo': item['description_ru'] ?? '',
    'fullInfo': extra['fullInfo'] ?? item['description_ru'] ?? '',
    'packageId': item['package_id'] ?? '',
    'packageName':
        extra['packageName'] ?? (item['package_id'] ?? 'Любой пакет'),
    'rewardMode': mode,
    'rewardAmount': mode == 'fixed' ? value : 0,
    'rewardPercent': mode == 'percent' ? value : 0,
    'maxSpendPercent': num.tryParse('${item['max_bonus_spend_percent']}') ?? 50,
    'oncePerCustomer': item['once_per_customer'] ?? false,
    'isActive': item['active'] ?? true,
    'startsAt': item['starts_at'],
    'endsAt': item['ends_at'],
  };
}

Map<String, dynamic> promotionRequestBody(Map<String, dynamic> item) {
  final mode = item['rewardMode'] ?? item['rewardType'] ?? 'fixed';
  final packageId = (item['packageId'] ?? '').toString().trim();
  return {
    'titleRu': item['title'] ?? item['titleRu'],
    'titleKk': item['titleKk'],
    'descriptionRu': item['shortInfo'] ?? item['description'] ?? '',
    'descriptionKk': item['descriptionKk'],
    'packageId': packageId.isEmpty ? null : packageId,
    'rewardType': mode,
    'rewardValue': mode == 'percent'
        ? item['rewardPercent'] ?? item['rewardValue'] ?? 0
        : item['rewardAmount'] ?? item['rewardValue'] ?? 0,
    'maxBonusSpendPercent':
        item['maxSpendPercent'] ?? item['maxBonusSpendPercent'] ?? 50,
    'oncePerCustomer': item['oncePerCustomer'] ?? false,
    'active': item['isActive'] ?? item['active'] ?? true,
    'startsAt': item['startsAt']?.toString(),
    'endsAt': item['endsAt']?.toString(),
    'presentation': {
      for (final key in [
        'packageName',
        'fullInfo',
        'homeBannerImageUrl',
        'bannerImageUrl',
        'features',
        'exclusions',
        'rewardTarget',
        'showBannerTitle',
        'showBannerShortInfo',
        'showBannerReward',
        'showBannerInfoIcon'
      ])
        if (item.containsKey(key)) key: item[key],
    },
  };
}
