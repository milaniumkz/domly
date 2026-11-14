import 'package:flutter/material.dart';
import '../theme/domly_palette.dart';
import 'domly_ui.dart';

typedef CalculatorPackageQuote = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> package, double area, int visits);

/// Prices are server quotes for the profile area, without optional extras.
class CalculatorPackageOption extends StatefulWidget {
  const CalculatorPackageOption(
      {super.key,
      required this.package,
      required this.area,
      required this.visits,
      required this.selected,
      required this.loadQuote,
      required this.onSelected,
      required this.onInfo,
      this.pricingContext = ''});
  final Map<String, dynamic> package;
  final double area;
  final int visits;
  final bool selected;
  final String pricingContext;
  final CalculatorPackageQuote loadQuote;
  final VoidCallback onSelected;
  final void Function(Map<String, dynamic>? quote) onInfo;

  @override
  State<CalculatorPackageOption> createState() =>
      _CalculatorPackageOptionState();
}

class _CalculatorPackageOptionState extends State<CalculatorPackageOption> {
  Future<Map<String, dynamic>>? _future;
  String _signature(CalculatorPackageOption w) => [
        w.package['id'],
        w.area,
        w.visits,
        w.pricingContext,
        w.package['basePrice'],
        w.package['pricePerM2'],
        w.package['billingPeriodMonths'],
        w.package['discountPercent'],
        w.package['updatedAt']
      ].join('|');
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CalculatorPackageOption old) {
    super.didUpdateWidget(old);
    if (_signature(old) != _signature(widget)) _load();
  }

  void _load() {
    _future = widget.area > 0
        ? Future.sync(
            () => widget.loadQuote(widget.package, widget.area, widget.visits))
        : null;
  }

  String _money(num n) => '${n.round()} ₸';
  String _visits(int n) {
    final last = n % 10, pair = n % 100;
    if (last == 1 && pair != 11) return 'уборка'.tr();
    if (last >= 2 && last <= 4 && (pair < 12 || pair > 14)) {
      return 'уборки'.tr();
    }
    return 'уборок'.tr();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final quote = snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError
            ? snapshot.data
            : null;
        final total = quote?['monthlyPrice'] as num?;
        final count = (quote?['cleaningCount'] as num?)?.toInt() ?? 0;
        final loading =
            widget.area > 0 && snapshot.connectionState != ConnectionState.done;
        return Material(
          color: DomlyPalette.surface(widget.selected
              ? DomlyColors.primary.withValues(alpha: 0.08)
              : DomlyColors.backgroundSoft),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: DomlyPalette.border(widget.selected
                      ? DomlyColors.primary
                      : DomlyColors.border),
                  width: widget.selected ? 1.5 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onSelected,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            (widget.package['name'] ??
                                    widget.package['label'] ??
                                    'Пакет')
                                .toString()
                                .tr(),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: DomlyPalette.foreground(widget.selected
                                    ? DomlyColors.primary
                                    : DomlyColors.foreground))),
                        const SizedBox(height: 6),
                        if (total != null && count > 0) ...[
                          Text(
                              'Итого: {price}'
                                  .tr(params: {'price': _money(total)}),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          Text(
                              "${'{p0} за 1 уборку'.tr(params: {
                                    'p0': _money(total / count)
                                  })} · $count ${_visits(count)}",
                              style: const TextStyle(fontSize: 12)),
                          Text('Без допуслуг'.tr(),
                              style: const TextStyle(fontSize: 11)),
                        ] else if (widget.area <= 0)
                          Text('Заполните площадь в профиле'.tr(),
                              style: const TextStyle(fontSize: 12))
                        else if (loading)
                          Text('Дождитесь расчета стоимости'.tr(),
                              style: const TextStyle(fontSize: 12))
                        else
                          TextButton(
                              onPressed: () => setState(_load),
                              child: Text('Повторить'.tr())),
                      ])),
                  IconButton(
                      tooltip: 'Информация по пакету'.tr(),
                      onPressed: () => widget.onInfo(quote),
                      icon: Icon(Icons.info_outline,
                          color: DomlyPalette.foreground(DomlyColors.primary))),
                  Semantics(
                      selected: widget.selected,
                      child: Icon(
                          widget.selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: DomlyPalette.foreground(widget.selected
                              ? DomlyColors.primary
                              : DomlyColors.border),
                          size: 22)),
                ])),
          ),
        );
      });
}
