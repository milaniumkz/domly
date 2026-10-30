/// The backend balance already excludes reserved appointments.
/// Do not deduct those appointments a second time in the client.
int availablePackageVisits(Map<String, dynamic> package,
    {required int fallback}) {
  final raw = package['availableCleanings'] ??
      package['available_cleanings'] ??
      package['remainingCleanings'];
  final parsed = raw is num ? raw : num.tryParse('$raw');
  if (parsed != null && parsed.isFinite)
    return parsed.toInt().clamp(0, 1 << 30);
  return fallback < 0 ? 0 : fallback;
}

bool preferAvailablePackageOverHistory(
    Map<String, dynamic>? package, Map<String, dynamic>? order,
    {required bool hasActiveCleaning}) {
  if (hasActiveCleaning ||
      package == null ||
      package['status'] != 'active' ||
      availablePackageVisits(package, fallback: 0) <= 0) return false;
  return order == null ||
      const {'completed', 'cancelled', 'canceled'}
          .contains(order['orderStatus'] ?? order['status']);
}

/// Purchases remain separate wallets; selecting one must not hide the others.
List<Map<String, dynamic>> paidPackageBalances(
    Iterable<Map<String, dynamic>> packages) {
  final result = <String, Map<String, dynamic>>{};
  var anonymous = 0;
  for (final package in packages) {
    if (!['active', 'frozen'].contains(package['status'])) continue;
    final payment = package['paymentStatus'] ?? package['payment_status'];
    if (payment != null &&
        !['paid', 'payment_confirmed', 'completed', 'success', 'succeeded']
            .contains(payment)) continue;
    final total = package['totalCleanings'] ??
        package['total_cleanings'] ??
        package['includedVisits'] ??
        0;
    if ((num.tryParse('$total') ?? 0) <= 0) continue;
    final id = (package['id'] ??
            package['subscriptionId'] ??
            'anonymous-${anonymous++}')
        .toString();
    result[id] = package;
  }
  return result.values.toList();
}

int totalAvailablePackageVisits(Iterable<Map<String, dynamic>> packages) =>
    paidPackageBalances(packages).fold<int>(0,
        (sum, package) => sum + availablePackageVisits(package, fallback: 0));
