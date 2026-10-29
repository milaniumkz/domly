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
