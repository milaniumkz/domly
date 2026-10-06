import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/order_display.dart';
import '../../localization/translation_controller.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  static const _background = Color(0xFFF2FAF7);
  static const _foreground = Color(0xFF20382F);
  static const _muted = Color(0xFF6C8A7B);
  static const _border = Color(0xFFDDEAE3);
  static const _green = Color(0xFF439F73);

  final _data = FirestoreDataService.instance;

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 2),
      child: ColoredBox(
        color: _background,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.customerPaymentsStream(),
                builder: (context, paymentsSnap) {
                  if (paymentsSnap.hasError) {
                    return const _PaymentHistoryError();
                  }
                  final loading =
                      paymentsSnap.connectionState == ConnectionState.waiting &&
                      !paymentsSnap.hasData;
                  if (loading) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: _green,
                        ),
                      ),
                    );
                  }

                  final payments =
                      (paymentsSnap.data ?? []).where(_isPaymentOrder).toList()
                        ..sort(
                          (a, b) => _paymentDate(b).compareTo(_paymentDate(a)),
                        );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _PaymentHistoryHeader(),
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.only(left: 30),
                          child: Text(
                            'Последние платежи'.tr(),
                            style: TextStyle(
                              color: _foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Padding(
                          padding: EdgeInsets.only(left: 30),
                          child: Text(
                            'Оплачено, ожидает, отклонено'.tr(),
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (payments.isEmpty)
                          const _PaymentEmptyCard()
                        else ...[
                          ...payments.map(
                            (order) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PaymentHistoryCard(order: order),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const _PaymentEmptyCard(),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _isPaymentOrder(Map<String, dynamic> order) {
    final status = (order['paymentStatus'] ?? '').toString().toLowerCase();
    final orderStatus = (order['orderStatus'] ?? '').toString().toLowerCase();
    return status == 'paid' ||
        status == 'invoice_requested' ||
        status == 'initiated' ||
        status == 'failed' ||
        status == 'canceled' ||
        status == 'cancelled' ||
        orderStatus == 'pending_payment';
  }

  static DateTime _paymentDate(Map<String, dynamic> order) {
    final value = order['paidAt'] ?? order['createdAt'] ?? order['date'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _paymentTitle(Map<String, dynamic> order) {
    final status = (order['paymentStatus'] ?? '').toString().toLowerCase();
    final orderStatus = (order['orderStatus'] ?? '').toString().toLowerCase();
    if (status == 'paid') {
      return 'Оплачено';
    }
    if (status == 'invoice_requested' ||
        status == 'initiated' ||
        orderStatus == 'pending_payment') {
      return 'Ожидает счет';
    }
    if (status == 'failed') {
      return 'Отклонено';
    }
    if (status == 'canceled' || status == 'cancelled') {
      return 'Отменено';
    }
    return paymentStatusLabel(status, fallback: 'Ожидает счет');
  }

  static String _paymentSubtitle(Map<String, dynamic> order) {
    final status = (order['paymentStatus'] ?? '').toString().toLowerCase();
    final price =
        (order['price'] as num?)?.toInt() ??
        (order['amount'] as num?)?.toInt() ??
        (order['total'] as num?)?.toInt() ??
        0;
    if (status == 'paid') {
      return '$price ₸ · ${_dateText(_paymentDate(order))}';
    }
    if (status == 'failed') {
      return '$price ₸ · ошибка оплаты';
    }
    if (status == 'canceled' || status == 'cancelled') {
      final packageName =
          (order['package'] ?? order['frequencyLabel'] ?? 'допуслуги')
              .toString()
              .toLowerCase();
      return '$price ₸ · $packageName';
    }
    final packageName = (order['package'] ?? order['frequencyLabel'] ?? 'пакет')
        .toString()
        .toLowerCase();
    return '$price ₸ · $packageName';
  }

  static String _dateText(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) {
      return 'дата не указана';
    }
    return domlyDateText(date);
  }
}

class _PaymentHistoryHeader extends StatelessWidget {
  const _PaymentHistoryHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF439F73), Color(0xFF80D4B0)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -17,
            top: -22,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -49,
            bottom: -75,
            child: Container(
              width: 138,
              height: 138,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 20,
            child: Material(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.maybePop(context),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.arrow_back,
                    color: Color(0xFF2E7D5B),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 52,
            top: 17,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'История плат'.tr(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Все статусы счетов и платежей'.tr(),
                  style: TextStyle(
                    color: Color(0xFFEDFAF2),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _PaymentHistoryScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _PaymentHistoryScreenState._paymentTitle(order),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _PaymentHistoryScreenState._foreground,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _PaymentHistoryScreenState._paymentSubtitle(order),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _PaymentHistoryScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentEmptyCard extends StatelessWidget {
  const _PaymentEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(27, 0, 27, 0),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _PaymentHistoryScreenState._border),
      ),
      child: Text(
        'История пока пуста'.tr(),
        style: TextStyle(
          color: _PaymentHistoryScreenState._foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PaymentHistoryError extends StatelessWidget {
  const _PaymentHistoryError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: DomlyEmptyStateCard(
          icon: Icons.receipt_long_outlined,
          title: 'Не удалось загрузить платежи',
          subtitle: 'Обновите экран и попробуйте снова.',
        ),
      ),
    );
  }
}
