import 'package:flutter/material.dart';

/// Three columns follow the available panel width, including narrow phones.
class AdminDashboardMetrics extends StatelessWidget {
  const AdminDashboardMetrics({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        const gap = 8.0;
        final width = (size.maxWidth - 2 * gap) / 3;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final child in children) SizedBox(width: width, child: child),
        ]);
      });
}

class AdminDashboardMetricCard extends StatelessWidget {
  const AdminDashboardMetricCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.icon,
      required this.accent,
      this.onTap});
  final String title, subtitle, value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final compact = size.maxWidth < 150;
        return Semantics(
            button: onTap != null,
            onTap: onTap,
            label: '$title: $value. $subtitle',
            excludeSemantics: true,
            child: Tooltip(
                message: '$title: $value\n$subtitle',
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE5E7EB))),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      onTap: onTap,
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 9 : 14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  width: compact ? 28 : 32,
                                  height: compact ? 28 : 32,
                                  decoration: BoxDecoration(
                                      color: accent.withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(9)),
                                  child: Icon(icon,
                                      color: accent, size: compact ? 18 : 22)),
                              const SizedBox(height: 7),
                              SizedBox(
                                  width: double.infinity,
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(value,
                                          style: TextStyle(
                                              fontSize: compact ? 24 : 27,
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  const Color(0xFF111827))))),
                              const SizedBox(height: 5),
                              Text(title,
                                  style: TextStyle(
                                      fontSize: compact ? 12 : 15,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(subtitle,
                                  style: TextStyle(
                                      fontSize: compact ? 10.5 : 13,
                                      color: const Color(0xFF6B7280))),
                            ]),
                      )),
                )));
      });
}
