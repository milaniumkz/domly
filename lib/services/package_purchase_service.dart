import 'backend_api_service.dart';

bool canCancelPendingPayment(Map<String, dynamic> order) {
  final status = (order['orderStatus'] ?? order['status'] ?? '').toString();
  final payment = (order['paymentStatus'] ?? '').toString();
  return !{'completed', 'cancelled', 'canceled'}.contains(status) &&
      !{'paid', 'success', 'refunded'}.contains(payment);
}

Future<Map<String, dynamic>> cancelUnpaidPackage(
    BackendApiService api, String paymentId) {
  if (paymentId.trim().isEmpty) throw ArgumentError('paymentId');
  return api
      .postMap('/payments/${Uri.encodeComponent(paymentId)}/cancel-purchase');
}
