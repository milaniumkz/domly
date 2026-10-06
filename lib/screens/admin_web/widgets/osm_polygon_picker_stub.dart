import 'package:flutter/material.dart';
import '../../../localization/translation_controller.dart';

class OsmPolygonPicker extends StatelessWidget {
  const OsmPolygonPicker({
    super.key,
    required this.points,
    required this.onChanged,
    this.centerLat = 43.2389,
    this.centerLng = 76.8897,
    this.height = 360,
  });

  final List<Map<String, double>> points;
  final ValueChanged<List<Map<String, double>>> onChanged;
  final double centerLat;
  final double centerLng;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        'OSM-карта доступна в web-админке.'.tr(),
        style: TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }
}
