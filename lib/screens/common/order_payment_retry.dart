import '../../services/app_config_service.dart';
import '../../utils/bonus_policy_utils.dart';
import '../../localization/translation_controller.dart';
import 'package:flutter/material.dart';
import '../../services/firestore_data_service.dart';
import '../../services/payment_link_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/user_error_message.dart';
import 'kaspi_invoice_request_dialog.dart';

class OrderPaymentRetry extends StatefulWidget {
  const OrderPaymentRetry({super.key, required this.order, required this.data, this.loadBonusOptions});
  final Map<String, dynamic> order;
  final FirestoreDataService data;
  final Future<Map<String, int>> Function()? loadBonusOptions;
  @override
  State<OrderPaymentRetry> createState() => _OrderPaymentRetryState();
}

class _OrderPaymentRetryState extends State<OrderPaymentRetry> {
  final Set<String> _retryingPayments = {};

  Future<void> _retryOrderPayment(Map<String, dynamic> order) async {
    final id = (order['orderId'] ?? order['id'] ?? '').toString();
    if (!_retryingPayments.add(id)) return;
    try {
      final amount = (order['payableAmount'] as num? ?? 0).toInt();
      final options = widget.loadBonusOptions != null ? await widget.loadBonusOptions!() : {
        'balance': ((await widget.data.customerProfileStream().first)?['bonusPoints'] as num? ?? 0).toInt(),
        'limit': addonBonusSpendLimit(amount, await AppConfigService.instance.promotionsStream().first),
      };
      if (!mounted) return;
      final method = await showPaymentMethodOptionsDialog(context,
          bonusBalance: options['balance'] ?? 0,
          maxBonusToSpend: options['limit'] ?? 0,
          paymentAmount: amount,
          alreadyPaidBonus: (order['bonusSpent'] as num? ?? 0).toInt());
      if (!mounted || method == null) return;
      final bonus = method.method == DomlyPaymentMethod.bonus || method.useBonus
          ? (options['balance'] ?? 0).clamp(0, options['limit'] ?? 0).clamp(0, amount).toInt() : 0;
      String? phone;
      if (method.method == DomlyPaymentMethod.kaspi) {
        phone = await showKaspiInvoiceRequestDialog(context);
        if (!mounted || phone == null) return;
      }
      final result = await PaymentLinkService.runBlocking(context,
          task: () => widget.data.retryOrderPayment(
              orderId: id,
              provider:
                  method.method == DomlyPaymentMethod.online ? 'bcc' : 'kaspi',
              invoicePhone: phone, bonusToSpend: bonus),
          message: 'Создаём новый платёж...');
      if (!mounted) return;
      if ((result['payableAmount'] as num? ?? 0) == 0) {
        showDomlySnackBar(context, title: 'Оплата подтверждена', subtitle: 'Оплачено бонусами', type: DomlySnackBarType.success);
      } else if (method.method == DomlyPaymentMethod.online) {
        final payment = result['payment'] as Map;
        final session = await widget.data
            .createBccPaymentSession(orderId: payment['id'].toString());
        if (!mounted) return;
        Navigator.pushNamed(context, '/client/online-payment',
            arguments: session);
      } else {
        showDomlySnackBar(context,
            title: 'Запрос счёта отправлен',
            subtitle: 'Дождитесь счёта в Kaspi.',
            type: DomlySnackBarType.success);
      }
      setState(() {});
    } catch (error) {
      if (mounted)
        showDomlySnackBar(context,
            title: 'Не удалось повторить оплату',
            subtitle: UserErrorMessage.message(error),
            type: DomlySnackBarType.error);
    } finally {
      _retryingPayments.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.order['latestPaymentStatus'];
    if (![null, 'draft', 'cancelled', 'rejected', 'failed', 'pending'].contains(status) ||
        widget.order['orderStatus'] != 'pending_payment')
      return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text(([null, 'draft', 'pending'].contains(status)
              ? 'Оплата не завершена. Выберите способ оплаты.'
              : 'Счёт отменён или произошла ошибка оплаты. Заказ сохранён. Вы можете выбрать другой способ оплаты.')
          .tr()),
      const SizedBox(height: 8),
      DomlyPrimaryButton(
          label: 'Попробовать снова',
          onPressed: () => _retryOrderPayment(widget.order)),
    ]);
  }
}
