class LaunchConfig {
  static final DateTime bookingStartDate = DateTime(2026, 9, 2);

  static DateTime bookingFloor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return today.isBefore(bookingStartDate) ? bookingStartDate : today;
  }

  static DateTime nextBookingDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return today.isBefore(bookingStartDate)
        ? bookingStartDate
        : today.add(const Duration(days: 1));
  }

  static bool isBeforeBookingStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.isBefore(bookingStartDate);
  }
}
