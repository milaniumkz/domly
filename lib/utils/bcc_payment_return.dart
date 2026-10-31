/// Recognizes the server redirect after BCC has checked the payment.
/// The return itself is not proof of a successful payment.
bool isBccPaymentReturn(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'domly.kz' &&
      (!uri.hasPort || uri.port == 443) &&
      (uri.path == '/customer' || uri.path == '/customer/') &&
      uri.queryParameters['bcc_return'] == '1';
}
