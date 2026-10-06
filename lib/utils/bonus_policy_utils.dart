int addonBonusSpendPercent(List<Map<String, dynamic>> promotions) {
  var percent = 50;
  for (final promotion in promotions) {
    if (promotion['isActive'] == false) {
      continue;
    }
    final target = (promotion['rewardTarget'] ?? 'addons').toString();
    if (target != 'addons' && target != 'all') {
      continue;
    }
    final value = (promotion['maxSpendPercent'] as num?)?.toInt() ?? 50;
    if (value > percent) {
      percent = value;
    }
  }
  return percent.clamp(0, 100).toInt();
}

int addonBonusSpendLimit(
  int amount,
  List<Map<String, dynamic>> promotions,
) {
  final percent = addonBonusSpendPercent(promotions);
  return (amount * percent / 100).floor();
}
