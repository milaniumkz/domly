import 'package:flutter/material.dart';

import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerServiceAreaNotice extends StatelessWidget {
  const CleanerServiceAreaNotice({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DomlyCard(
      color: const Color(0xFFFFF7ED),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: Color(0xFFF97316),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите рабочие районы'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: DomlyColors.foreground,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Пока районы не выбраны, новые заказы и предложения не будут приходить.'
                          .tr(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: DomlyColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: DomlyPrimaryButton(
              label: 'Выбрать районы',
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

bool cleanerHasServiceAreas(Map<String, dynamic> profile) {
  final areas = ((profile['serviceAreas'] as List?) ?? const [])
      .map((item) => item.toString().trim())
      .any((item) => item.isNotEmpty);
  final areaIds = ((profile['serviceAreaIds'] as List?) ?? const [])
      .map((item) => item.toString().trim())
      .any((item) => item.isNotEmpty);
  return areas || areaIds;
}
