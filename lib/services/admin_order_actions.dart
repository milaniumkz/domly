import 'backend_api_service.dart';

Future<void> changeAdminOrderStatus(
    BackendApiService api, String orderId, String status) async {
  if (orderId.trim().isEmpty) throw ArgumentError('orderId');
  await api.patchMap('/admin/orders/${Uri.encodeComponent(orderId)}', body: {
    'status': status == 'canceled' ? 'cancelled' : status,
  });
}
