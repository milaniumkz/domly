import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../utils/package_availability.dart';
import '../utils/customer_home_state.dart';
import '../theme/domly_palette.dart';

class CustomerPackageBalances extends StatelessWidget {
  const CustomerPackageBalances(
      {super.key,
      required this.packages,
      required this.onOpen,
      required this.onBuy});
  final List<Map<String, dynamic>> packages;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    final paid = paidPackageBalances(packages);
    if (paid.isEmpty) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Мои пакеты'.tr(),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: DomlyPalette.foreground(
                              const Color(0xFF2B4338)))),
                  const SizedBox(height: 8),
                  Text('Общий остаток: {count} уборок'.tr(params: {
                    'count': '${totalAvailablePackageVisits(paid)}'
                  })),
                  ...paid.map((package) {
                    final remaining =
                        availablePackageVisits(package, fallback: 0);
                    final total = package['totalCleanings'] ??
                        package['total_cleanings'] ??
                        package['includedVisits'];
                    final address = (package['address'] ?? '').toString();
                    return ListTile(
                        contentPadding: EdgeInsets.zero,
                        key: ValueKey('package-balance-${package['id']}'),
                        title: Text(
                            '${package['packageName'] ?? package['package'] ?? package['name'] ?? 'Пакет'}'),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Доступно: {left} из {total}'.tr(params: {
                                'left': '$remaining',
                                'total': '$total'
                              })),
                              if (address.isNotEmpty) Text(address),
                              if (isHomePackageFrozen(package))
                                Text('На заморозке'.tr()),
                            ]),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onOpen(package));
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: onBuy,
                      icon: const Icon(Icons.add),
                      label: Text('Купить ещё пакет'.tr())),
                ])));
  }
}
