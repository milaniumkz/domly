import 'package:flutter/material.dart';
import '../theme/domly_palette.dart';

/// The date and status each get the full card width, including large text.
class CleaningScheduleSummary extends StatelessWidget {
  const CleaningScheduleSummary(
      {super.key,
      required this.dateText,
      required this.status,
      this.fontSize = 27});
  final String dateText;
  final Widget status;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateText,
              softWrap: true,
              style: TextStyle(
                  color: DomlyPalette.foreground(const Color(0xFF2B4338)),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
          const SizedBox(height: 8),
          status,
        ],
      );
}
