import '../utils/stable_polling_stream.dart';
import 'backend_api_service.dart';

/// The badge needs a count, not a second copy of the user's notification history.
Stream<int> notificationCountStream(BackendApiService api,
    {required bool Function() isCurrentUser}) => stablePollingStream(() async {
  if (!isCurrentUser()) return 0;
  final result = await api.getMap('/notifications/unread-count');
  if (!isCurrentUser()) return 0;
  final value = result['count'];
  return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}, interval: const Duration(seconds: 2), refresh: api.dataRevision);
