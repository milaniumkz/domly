bool paymentMatchesTab(String status, String tab) {
  final value = status.trim().toLowerCase();
  final category = switch (value) {
    'paid' || 'success' || 'completed' => 'paid',
    'cancelled' || 'canceled' || 'expired' || 'refunded' => 'cancelled',
    'failed' || 'rejected' || 'error' => 'errors',
    _ => 'waiting',
  };
  return tab == 'all' || tab == category;
}
