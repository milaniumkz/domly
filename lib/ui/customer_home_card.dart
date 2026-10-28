import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../theme/domly_palette.dart';

/// Presentation only: every action is supplied by the existing home controller.
class CustomerHomeCard extends StatelessWidget {
  const CustomerHomeCard(
      {super.key,
      required this.title,
      required this.status,
      required this.description,
      this.icon = Icons.cleaning_services_outlined,
      this.metadata = const [],
      this.planName,
      this.used,
      this.total,
      this.primaryLabel,
      this.onPrimary,
      this.onDetails,
      this.onCancel,
      this.detailsLabel = 'Детали',
      this.primaryKey,
      this.footer});
  final String title, status, description, detailsLabel;
  final IconData icon;
  final List<String> metadata;
  final String? planName, primaryLabel;
  final int? used, total;
  final VoidCallback? onPrimary, onDetails, onCancel;
  final Widget? footer;
  final Key? primaryKey;

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);
    final ink = DomlyPalette.foreground(const Color(0xFF203E31));
    final muted = DomlyPalette.foreground(const Color(0xFF657C70));
    final accent = DomlyPalette.foreground(const Color(0xFFBE6846));
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: DomlyPalette.surface(Colors.white),
        border: Border.all(color: DomlyPalette.border(const Color(0xFFE1EBE3))),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A254333), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: DomlyPalette.surface(const Color(0xFFEDF5EF)),
                  borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: ink, size: 24)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title.tr(),
                    style: TextStyle(
                        color: ink,
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 9),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: DomlyPalette.surface(const Color(0xFFF4EEE6)),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(status.tr(),
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
              ])),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 17),
          Text(description.tr(),
              style: TextStyle(color: muted, fontSize: 15, height: 1.45)),
        ],
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
              spacing: 12,
              runSpacing: 8,
              children: metadata
                  .map((text) => Text(text.tr(),
                      style: TextStyle(
                          color: ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)))
                  .toList()),
        ],
        if (onPrimary != null && primaryLabel != null) ...[
          const SizedBox(height: 20),
          FilledButton(
              key: primaryKey,
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC57450),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              child: Text(primaryLabel!.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
        ],
        if (planName != null || onDetails != null || total != null) ...[
          const SizedBox(height: 20),
          Divider(
              height: 1, color: DomlyPalette.border(const Color(0xFFE3ECE5))),
          const SizedBox(height: 8),
          if (planName != null)
            Text(planName!.tr(),
                style: TextStyle(
                    color: ink, fontSize: 15, fontWeight: FontWeight.w600)),
          if (total != null && total! > 0 && used != null) ...[
            const SizedBox(height: 10),
            Semantics(
                label: '${'Использовано'.tr()}: $used / $total',
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: (used! / total!).clamp(0, 1),
                        minHeight: 5,
                        color: const Color(0xFF65A486),
                        backgroundColor:
                            DomlyPalette.surface(const Color(0xFFEDF3EE))))),
            const SizedBox(height: 8),
            Text('${'Использовано'.tr()}: $used / $total',
                style: TextStyle(color: muted, fontSize: 13)),
          ],
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 16, children: [
            if (onDetails != null)
              TextButton(onPressed: onDetails, child: Text(detailsLabel.tr())),
            if (onCancel != null)
              TextButton(onPressed: onCancel, child: Text('Отменить'.tr())),
          ]),
        ],
        if (footer != null) footer!,
      ]),
    );
  }
}
