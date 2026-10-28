import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

/// Manual paging only: no timer, no wraparound and no replacement of order IDs.
class HomeCleaningPager extends StatelessWidget {
  const HomeCleaningPager({super.key, required this.index, required this.count,
    required this.onChanged, required this.child});
  final int index, count;
  final ValueChanged<int> onChanged;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    var distance = 0.0;
    return GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onHorizontalDragStart: (_) => distance = 0,
    onHorizontalDragUpdate: (details) => distance += details.delta.dx,
    onHorizontalDragEnd: count < 2 ? null : (details) {
      final velocity = details.primaryVelocity ?? 0;
      final next = index + (distance < -48 || velocity < -80 ? 1 : distance > 48 || velocity > 80 ? -1 : 0);
      if (next != index && next >= 0 && next < count) onChanged(next);
    },
    child: child,
  );
  }
}

class HomeCleaningPageIndicator extends StatelessWidget {
  const HomeCleaningPageIndicator({super.key, required this.index,
    required this.count, required this.onChanged});
  final int index, count;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(tooltip: 'Предыдущая уборка'.tr(), icon: const Icon(Icons.chevron_left),
        onPressed: index > 0 ? () => onChanged(index - 1) : null),
      Text('Уборка {current} из {total}'.tr(params: {
        'current': '${index + 1}', 'total': '$count'})),
      IconButton(tooltip: 'Следующая уборка'.tr(), icon: const Icon(Icons.chevron_right),
        onPressed: index + 1 < count ? () => onChanged(index + 1) : null),
    ]);
}
