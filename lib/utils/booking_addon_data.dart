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

/// Move only a visit draft: scheduled visits and their extras stay independent.
bool movePendingBookingAddons({
  required String? fromDateKey,
  required String toDateKey,
  required Map<String, String> selectedTimes,
  required Map<String, List<Map<String, dynamic>>> paidByDate,
  required Map<String, List<Map<String, dynamic>>> newByDate,
}) {
  if (fromDateKey == null ||
      fromDateKey == toDateKey ||
      selectedTimes.containsKey(fromDateKey) ||
      selectedTimes.containsKey(toDateKey) ||
      paidByDate.containsKey(toDateKey) ||
      newByDate.containsKey(toDateKey)) {
    return false;
  }
  for (final selections in [paidByDate, newByDate]) {
    final items = selections.remove(fromDateKey);
    if (items != null) {
      selections[toDateKey] =
          items.map((item) => Map<String, dynamic>.from(item)).toList();
    }
  }
  return true;
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
