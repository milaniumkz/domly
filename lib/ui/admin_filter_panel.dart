import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

/// Shared toggle; section controls use the same [expanded] value below it.
class AdminFilterPanel extends StatelessWidget {
  const AdminFilterPanel(
      {super.key,
      required this.expanded,
      required this.onChanged,
      required this.child,
      this.activeCount = 0});
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final Widget child;
  final int activeCount;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            expanded: expanded,
            child: OutlinedButton.icon(
              onPressed: () => onChanged(!expanded),
              icon: const Icon(Icons.filter_list_rounded),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                    child:
                        Text((expanded ? 'Скрыть фильтры' : 'Фильтры').tr())),
                if (activeCount > 0) ...[
                  const SizedBox(width: 8),
                  Text('($activeCount)',
                      semanticsLabel: 'Применено фильтров: {count}'
                          .tr(params: {'count': '$activeCount'})),
                ],
                const SizedBox(width: 8),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ]),
            ),
          ),
          AdminFilterContents(
              expanded: expanded,
              child: Padding(
                  padding: const EdgeInsets.only(top: 10), child: child)),
        ],
      );
}

/// Hiding filters must preserve selections and remove hidden keyboard targets.
class AdminFilterContents extends StatelessWidget {
  const AdminFilterContents(
      {super.key, required this.expanded, required this.child});
  final bool expanded;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topLeft,
        child: ExcludeFocus(
            excluding: !expanded,
            child: Offstage(
                offstage: !expanded,
                child: TickerMode(enabled: expanded, child: child))),
      );
}
