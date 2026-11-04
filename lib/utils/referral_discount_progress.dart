class ReferralDiscountProgress {
  ReferralDiscountProgress(int qualified, Object? rules) {
    count = qualified < 0 ? 0 : qualified;
    final source = rules is List ? rules : defaults;
    for (final item in source) {
      if (item is! Map) continue;
      final threshold = num.tryParse('${item['count']}');
      final discount = num.tryParse('${item['discount']}');
      if (threshold == null ||
          !threshold.isFinite ||
          discount == null ||
          !discount.isFinite) {
        continue;
      }
      final value = threshold.ceil() < 0 ? 0 : threshold.ceil();
      final percent = discount.clamp(0, 100);
      final index = tiers.indexWhere((t) => t['count'] == value);
      if (index < 0) {
        tiers.add({'count': value, 'discount': percent});
      } else if (percent > tiers[index]['discount']!) {
        tiers[index] = {'count': value, 'discount': percent};
      }
    }
    tiers.sort((a, b) => a['count']!.compareTo(b['count']!));
    for (final tier in tiers) {
      if (tier['count']! <= count && tier['discount']! > currentDiscount) {
        currentDiscount = tier['discount']!;
      }
      if (tier['discount']! > maxDiscount) {
        maxDiscount = tier['discount']!;
        maxCount = tier['count']!.toInt();
      }
    }
    for (final tier in tiers) {
      if (tier['count']! > count && tier['discount']! > currentDiscount) {
        nextCount = tier['count']!.toInt();
        nextDiscount = tier['discount']!;
        break;
      }
    }
  }
  static const defaults = [
    {'count': 5, 'discount': 3},
    {'count': 10, 'discount': 7},
    {'count': 20, 'discount': 10}
  ];
  late final int count;
  final List<Map<String, num>> tiers = [];
  num currentDiscount = 0, maxDiscount = 0;
  int maxCount = 0;
  int? nextCount;
  num? nextDiscount;
  int get remainingNext =>
      nextCount == null ? 0 : (nextCount! - count).clamp(0, nextCount!);
  int get remainingMax => (maxCount - count).clamp(0, maxCount);
  bool get maxReached => maxDiscount > 0 && currentDiscount >= maxDiscount;
  double get progress => maxCount > 0
      ? (count / maxCount).clamp(0.0, 1.0)
      : (maxReached ? 1.0 : 0.0);
  static String percent(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
