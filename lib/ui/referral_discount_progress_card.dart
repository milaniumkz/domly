import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../theme/domly_palette.dart';
import '../utils/referral_discount_progress.dart';

class ReferralDiscountProgressCard extends StatelessWidget {
  const ReferralDiscountProgressCard(
      {super.key,
      required this.qualifiedCount,
      this.tiers,
      this.onTap,
      this.onInfo});
  final int qualifiedCount;
  final Object? tiers;
  final VoidCallback? onTap, onInfo;
  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);
    TranslationScope.watch(context);
    final data = ReferralDiscountProgress(qualifiedCount, tiers);
    final foreground = DomlyPalette.foreground(const Color(0xFF20382F));
    final muted = DomlyPalette.foreground(const Color(0xFF658170));
    Widget line(String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(value,
            softWrap: true,
            style: TextStyle(color: foreground, fontSize: 14, height: 1.4)));
    return Material(
      color: DomlyPalette.surface(Colors.white),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side:
              BorderSide(color: DomlyPalette.border(const Color(0xFFDEECE3)))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('Прогресс реферальной скидки'.tr(),
                              style: TextStyle(
                                  color: foreground,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      if (onInfo != null)
                        IconButton(
                            onPressed: onInfo,
                            tooltip: 'Информация'.tr(),
                            icon: const Icon(Icons.info_outline))
                    ]),
                    line('Текущая скидка: {discount}%'.tr(params: {
                      'discount':
                          ReferralDiscountProgress.percent(data.currentDiscount)
                    })),
                    line('Засчитано приглашений: {count}'
                        .tr(params: {'count': '${data.count}'})),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                        value: data.progress,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(6),
                        color: const Color(0xFFCF7548),
                        backgroundColor:
                            DomlyPalette.surface(const Color(0xFFE5EFE8))),
                    if (data.maxReached)
                      line('Максимальная скидка {discount}% уже получена'
                          .tr(params: {
                        'discount':
                            ReferralDiscountProgress.percent(data.maxDiscount)
                      }))
                    else if (data.maxDiscount > 0) ...[
                      if (data.nextDiscount != null)
                        line(
                            'До следующего уровня ({discount}%): ещё {count} чел.'
                                .tr(params: {
                          'discount': ReferralDiscountProgress.percent(
                              data.nextDiscount!),
                          'count': '${data.remainingNext}'
                        })),
                      line(
                          'До максимальной скидки ({discount}%): ещё {count} чел.'
                              .tr(params: {
                        'discount':
                            ReferralDiscountProgress.percent(data.maxDiscount),
                        'count': '${data.remainingMax}'
                      })),
                    ] else
                      line('Уровни скидки пока не настроены'.tr()),
                    const SizedBox(height: 12),
                    Text(
                        'Учитываются друзья, оплатившие пакет по вашей ссылке.'
                            .tr(),
                        softWrap: true,
                        style:
                            TextStyle(color: muted, fontSize: 12, height: 1.4)),
                  ]))),
    );
  }
}
