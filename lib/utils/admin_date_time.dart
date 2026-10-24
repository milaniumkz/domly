import 'backend_compat.dart';
import '../ui/domly_ui.dart';

String formatAdminDateTime(dynamic value) {
  if (value is Timestamp) return domlyDateTimeText(value.toDate().toLocal());
  final date = value is DateTime ? value : DateTime.tryParse((value ?? '').toString());
  return date == null ? '—' : domlyDateTimeText(date.toLocal());
}
