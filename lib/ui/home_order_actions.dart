import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../services/backend_api_service.dart';
import '../services/firestore_data_service.dart';
import '../services/payment_link_service.dart';
import '../screens/common/kaspi_invoice_request_dialog.dart';
import '../screens/common/order_payment_retry.dart';
import '../ui/domly_ui.dart';
import '../utils/customer_home_state.dart';
import '../utils/user_error_message.dart';

Future<void> showHomePayment(
    BuildContext context, Map<String, dynamic> order) async {
  if (order['type'] != 'package_purchase') {
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: OrderPaymentRetry(
                    order: order, data: FirestoreDataService.instance))));
    return;
  }
  final amount = (order['payableAmount'] as num? ?? 0).toInt();
  final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text('${'К оплате'.tr()} ${homeAmountLabel(amount)}'),
              content: Text('Выберите способ оплаты'.tr()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, 'kaspi'),
                    child: const Text('Kaspi.kz')),
                TextButton(
                    onPressed: () => Navigator.pop(context, 'bcc'),
                    child: Text('Онлайн-оплата'.tr()))
              ]));
  if (choice == null || !context.mounted) return;
  try {
    final payment = await BackendApiService.instance
        .postMap('/payments/${order['id']}/resume-purchase');
    if (!context.mounted) return;
    if (choice == 'bcc') {
      final session = await PaymentLinkService.runBlocking(context,
          task: () => FirestoreDataService.instance
              .createBccPaymentSession(orderId: payment['id'].toString()));
      if (context.mounted)
        Navigator.pushNamed(context, '/client/online-payment',
            arguments: session);
    } else {
      final phone = await showKaspiInvoiceRequestDialog(context);
      if (phone == null || !context.mounted) return;
      await PaymentLinkService.runBlocking(context,
          task: () => FirestoreDataService.instance.submitKaspiInvoiceRequest(
              orderId: payment['id'].toString(), kaspiPhone: phone));
      if (context.mounted)
        showDomlySnackBar(context,
            title: 'Запрос счёта отправлен',
            subtitle: 'Дождитесь счёта в Kaspi.');
    }
  } catch (error) {
    if (context.mounted)
      showDomlySnackBar(context,
          title: 'Не удалось открыть оплату',
          subtitle: UserErrorMessage.message(error),
          type: DomlySnackBarType.error);
  }
}

Future<void> cancelHomePurchase(
    BuildContext context, Map<String, dynamic> order) async {
  final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text('Отменить покупку?'.tr()),
              content: Text(
                  'Заявка на счёт будет отменена. Вы сможете выбрать новый пакет.'
                      .tr()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Нет'.tr())),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('Да, отменить'.tr()))
              ]));
  if (yes != true || !context.mounted) return;
  try {
    await PaymentLinkService.runBlocking(context,
        task: () => BackendApiService.instance
            .postMap('/payments/${order['id']}/cancel-purchase'));
    if (context.mounted)
      showDomlySnackBar(context,
          title: 'Покупка отменена',
          subtitle: 'Вы можете выбрать новый пакет.');
  } catch (error) {
    if (context.mounted)
      showDomlySnackBar(context,
          title: 'Не удалось отменить покупку',
          subtitle: UserErrorMessage.message(error),
          type: DomlySnackBarType.error);
  }
}

Future<void> showHomeReport(BuildContext context, String orderId) async {
  try {
    final result = await BackendApiService.instance
        .getMap('/orders/$orderId/photo-report');
    if (!context.mounted) return;
    final report = result['report'] as Map?;
    final photos =
        (report?['photo_urls'] as List? ?? []).whereType<String>().toList();
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .85),
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Отчёт об уборке'.tr(),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
                      if (photos.isEmpty)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                                'Фотографии отчёта пока не добавлены'.tr())),
                      ...photos.map((url) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Image.network(url,
                              errorBuilder: (_, __, ___) =>
                                  Text('Не удалось загрузить фото'.tr()))))
                    ]))));
  } catch (error) {
    if (context.mounted)
      showDomlySnackBar(context,
          title: 'Не удалось открыть отчёт',
          subtitle: UserErrorMessage.message(error),
          type: DomlySnackBarType.error);
  }
}
