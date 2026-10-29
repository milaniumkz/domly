/// A package purchase is a payment, not a scheduled cleaning visit.
bool isActiveScheduleOrder(Map<String, dynamic> order) {
  if (order['type'] == 'package_purchase' ||
      order['view_kind'] == 'package_purchase') return false;
  const terminal = {'canceled', 'cancelled', 'completed'};
  return !terminal.contains(order['status']) &&
      !terminal.contains(order['orderStatus']);
}

bool canCancelScheduledCleaning(String status) => const {
      'pending_payment',
      'pending_assignment',
      'waiting_cleaner',
      'assigned',
      'confirmed',
    }.contains(status.trim().toLowerCase());
