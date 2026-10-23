/// Read the server's saved quote, including its approved area recalculation.
/// Never recompute prices from today's catalog for an existing purchase.
int? storedPackagePrice(Map<String, dynamic> package) {
  final config = package['purchase_config'];
  final value = config is Map ? config['monthlyPrice'] : null;
  final amount = value is num ? value : num.tryParse('$value');
  return amount != null && amount.isFinite && amount >= 0
      ? amount.round()
      : null;
}
