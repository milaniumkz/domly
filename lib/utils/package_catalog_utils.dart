class PackageCatalogUtils {
  const PackageCatalogUtils._();
  static const List<int> _allowedMonthlyVisits = [1, 2, 4, 8];

  static num? numValue(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value.trim().replaceAll(',', '.'));
    }
    return null;
  }

  static bool isQuarterlyPackage(Map<String, dynamic>? package) {
    if (package == null) {
      return false;
    }
    if (package['isQuarterly'] == true) {
      return true;
    }
    final id = (package['id'] ?? '').toString().toLowerCase();
    final source =
        '${package['frequency'] ?? ''} ${package['name'] ?? ''}'.toLowerCase();
    return id.contains('quarter') || source.contains('кварт');
  }

  static bool isSpecialPackage(Map<String, dynamic>? package) {
    if (package == null) {
      return false;
    }
    if (package['isSpecial'] == true) {
      return true;
    }
    final id = (package['id'] ?? '').toString().toLowerCase();
    final source = '${package['name'] ?? ''} ${package['frequency'] ?? ''}'
        .toString()
        .toLowerCase();
    return id.contains('general') ||
        id.contains('renovation') ||
        source.contains('генераль') ||
        source.contains('ремонт');
  }

  static int cleaningsPerMonth(
    Map<String, dynamic>? package, {
    int quarterlyVisitsPerMonth = 2,
  }) {
    if (package == null || isSpecialPackage(package)) {
      return 1;
    }
    if (isQuarterlyPackage(package)) {
      return quarterlyVisitsPerMonth;
    }

    final id = (package['id'] ?? package['packageId'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (id == 'premium') {
      return 8;
    }
    if (id == 'standard') {
      return 4;
    }
    if (id == 'basic') {
      return 2;
    }
    if (id == 'single') {
      return 1;
    }

    final explicit = numValue(package['cleaningsPerMonth'])?.toInt();
    if (explicit != null && _allowedMonthlyVisits.contains(explicit)) {
      return explicit;
    }

    final legacyNumeric = numValue(package['frequency'])?.toInt();
    if (legacyNumeric != null &&
        _allowedMonthlyVisits.contains(legacyNumeric)) {
      return legacyNumeric;
    }

    final source =
        '${package['frequency'] ?? ''} ${package['name'] ?? ''}'.toLowerCase();
    if (source.contains('8 раз')) {
      return 8;
    }
    if (source.contains('4 раз') || source.contains('раз в неделю')) {
      return 4;
    }
    if (source.contains('2 раз')) {
      return 2;
    }
    return 1;
  }

  static int billingPeriodMonths(Map<String, dynamic>? package) {
    if (package == null) {
      return 1;
    }
    if (isQuarterlyPackage(package)) {
      final explicitQuarter = numValue(package['billingPeriodMonths'])?.toInt();
      if (explicitQuarter != null && explicitQuarter >= 3) {
        return explicitQuarter;
      }
      return 3;
    }
    final explicit = numValue(package['billingPeriodMonths'])?.toInt();
    if (explicit != null && explicit > 0) {
      return explicit;
    }
    return 1;
  }

  static double discountRate(Map<String, dynamic>? package) {
    if (package == null) {
      return 0;
    }

    final percent = numValue(package['discountPercent'])?.toDouble();
    if (percent != null && percent > 0) {
      return percent > 1 ? percent / 100 : percent;
    }

    final legacy = numValue(package['discount'])?.toDouble();
    if (legacy != null && legacy > 0) {
      return legacy > 1 ? legacy / 100 : legacy;
    }

    return isQuarterlyPackage(package) ? 0.10 : 0;
  }

  static String frequencyLabel(
    Map<String, dynamic>? package, {
    int quarterlyVisitsPerMonth = 2,
  }) {
    if (package == null) {
      return 'Разовая';
    }
    if (isQuarterlyPackage(package)) {
      return '3 месяца';
    }
    final visits = cleaningsPerMonth(
      package,
      quarterlyVisitsPerMonth: quarterlyVisitsPerMonth,
    );
    if (isSpecialPackage(package) || visits <= 1) {
      return 'Разовая';
    }
    return '$visits раза в месяц';
  }

  static String displayName(
    Map<String, dynamic>? package, {
    int quarterlyVisitsPerMonth = 2,
  }) {
    if (package == null) {
      return 'Пакет';
    }
    if (isQuarterlyPackage(package)) {
      return 'Квартальный пакет';
    }
    if (isSpecialPackage(package)) {
      final rawName =
          (package['name'] ?? package['title'] ?? '').toString().trim();
      return rawName.isEmpty ? 'Спецпакет' : rawName;
    }

    final visits = cleaningsPerMonth(
      package,
      quarterlyVisitsPerMonth: quarterlyVisitsPerMonth,
    );
    switch (visits) {
      case 1:
        return 'Разовый пакет';
      case 2:
        return '2 раза в месяц';
      case 4:
        return '4 раза в месяц';
      case 8:
        return '8 раз в месяц';
      default:
        final rawName =
            (package['name'] ?? package['title'] ?? '').toString().trim();
        return rawName.isEmpty ? 'Пакет' : rawName;
    }
  }
}
