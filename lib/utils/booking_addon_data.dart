List<String> bookingAddonIds(Map<String, dynamic> selection) {
  final ids = <String>{};
  for (final key in ['addonsDetailed', 'newAddonsDetailed']) {
    for (final item in (selection[key] as List? ?? const []).whereType<Map>()) {
      final id = (item['id'] ?? item['addonId'] ?? '').toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }
  }
  return ids.toList();
}

bool addonPaidSeparately(Map item) =>
    (item['separatePayment'] ??
        item['separate'] ??
        item['paidSeparately'] ??
        item['paid_separately']) ==
    true;

int billableBookingAddonsAmount(Iterable<Map> items) =>
    items.fold<int>(0, (total, item) {
      if (addonPaidSeparately(item)) return total;
      final price = num.tryParse('${item['price'] ?? 0}') ?? 0;
      final quantity = num.tryParse('${item['quantity'] ?? 1}') ?? 1;
      return total + (price * quantity).round();
    });
