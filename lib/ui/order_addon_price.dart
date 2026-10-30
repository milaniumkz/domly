import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../theme/domly_palette.dart';

class OrderAddonPrice extends StatelessWidget {
  const OrderAddonPrice(
      {super.key,
      required this.unitPrice,
      required this.quantity,
      this.pricingType = 'fixed',
      this.area = 0,
      this.separatePayment = false});
  final num? unitPrice;
  final num area;
  final int quantity;
  final String pricingType;
  final bool separatePayment;
  String money(num value) =>
      '${value.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} ₸';
  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    final perArea = ['per_m2', 'per_sqm'].contains(pricingType);
    final label = perArea
        ? 'Цена: {price} за м²'
        : pricingType == 'per_visit'
            ? 'Цена: {price} за уборку'
            : 'Цена: {price} за единицу';
    final total = (unitPrice ?? 0) * quantity * (perArea ? area : 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (separatePayment)
        Text('Оплата отдельно по факту'.tr(),
            style: TextStyle(
                color: DomlyPalette.foreground(const Color(0xFFCF7548)),
                fontSize: 12,
                fontWeight: FontWeight.w700))
      else if (unitPrice == null)
        Text('Цена уточняется'.tr())
      else ...[
        Text(label.tr(params: {'price': money(unitPrice!)}),
            style: TextStyle(
                color: DomlyPalette.foreground(const Color(0xFF2B4338)),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        if (quantity > 0 && (!perArea || area > 0))
          Text('Итого: {price}'.tr(params: {'price': money(total)}),
              style: TextStyle(
                  color: DomlyPalette.foreground(const Color(0xFFCF7548)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}
