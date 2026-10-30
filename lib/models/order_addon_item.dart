class OrderAddonItem {
  const OrderAddonItem({
    required this.key,
    required this.label,
    this.supportsQuantity = false,
    this.note,
    this.shortInfo,
    this.fullInfo,
    this.features = const <String>[],
    this.separatePayment = false,
    this.durationMinutes = 15,
    this.pricingType = 'fixed',
  });

  final String key;
  final String label;
  final bool supportsQuantity;
  final String? note;
  final String? shortInfo;
  final String? fullInfo;
  final List<String> features;
  final bool separatePayment;
  final int durationMinutes;
  final String pricingType;

  factory OrderAddonItem.fromConfig(Map<String, dynamic> item) {
    String? text(dynamic value) =>
        (value ?? '').toString().trim().isEmpty ? null : value.toString();
    final key = (item['key'] ?? '').toString();
    return OrderAddonItem(
      key: key,
      label: (item['label'] ?? key).toString(),
      supportsQuantity: item['supportsQuantity'] == true,
      note: text(item['note']),
      shortInfo: text(item['shortInfo'] ??
          item['description'] ??
          item['note'] ??
          item['hint'] ??
          item['prompt']),
      fullInfo: text(item['fullInfo'] ?? item['longDescription']),
      features: item['features'] is List
          ? (item['features'] as List)
              .map((v) => v.toString())
              .where((v) => v.trim().isNotEmpty)
              .toList()
          : const [],
      separatePayment: (item['separatePayment'] ?? item['separate']) == true,
      durationMinutes: (item['durationMinutes'] as num?)?.toInt() ?? 15,
      pricingType:
          (item['pricingType'] ?? item['pricing_type'] ?? 'fixed').toString(),
    );
  }

  String? get infoText => shortInfo ?? note;
}
