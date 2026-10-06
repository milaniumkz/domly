import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class ClusterMapScreen extends StatelessWidget {
  const ClusterMapScreen({super.key});

  static final FirestoreDataService _data = FirestoreDataService.instance;

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      child: SafeArea(
        child: Column(
          children: [
            DomlyHeader(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  domlyTopIconButton(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Карта покрытия'.tr(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Показывает активные, подключаемые и планируемые дома.'
                              .tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: DomlyCard(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _LegendDot(color: Colors.green, label: 'Активно'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _LegendDot(
                          color: Colors.orange, label: 'Подключается'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child:
                          _LegendDot(color: Colors.blue, label: 'Планируется'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.serviceZonesStream(),
                builder: (context, zonesSnapshot) {
                  if (zonesSnapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Center(
                        child: DomlyEmptyStateCard(
                          icon: Icons.map_outlined,
                          title: 'Не удалось загрузить карту',
                          subtitle: 'Обновите экран и попробуйте снова.',
                        ),
                      ),
                    );
                  }
                  if (zonesSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !zonesSnapshot.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              DomlyColors.primary),
                        ),
                      ),
                    );
                  }
                  final zones =
                      zonesSnapshot.data ?? const <Map<String, dynamic>>[];
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _data.housesStream(),
                    builder: (context, housesSnapshot) {
                      if (housesSnapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: Center(
                            child: DomlyEmptyStateCard(
                              icon: Icons.map_outlined,
                              title: 'Не удалось загрузить карту',
                              subtitle: 'Обновите экран и попробуйте снова.',
                            ),
                          ),
                        );
                      }
                      if (housesSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          !housesSnapshot.hasData) {
                        return const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  DomlyColors.primary),
                            ),
                          ),
                        );
                      }
                      final houses =
                          housesSnapshot.data ?? const <Map<String, dynamic>>[];
                      final markers = <Marker>{};

                      for (final d in zones) {
                        final lat = (d['centerLat'] as num?)?.toDouble();
                        final lng = (d['centerLng'] as num?)?.toDouble();
                        if (lat == null || lng == null) {
                          continue;
                        }
                        final zoneStatus =
                            (d['status'] ?? 'planned').toString().toLowerCase();
                        markers.add(
                          Marker(
                            markerId: MarkerId((d['id'] ?? 'zone').toString()),
                            position: LatLng(lat, lng),
                            infoWindow: InfoWindow(
                              title: (d['title'] ?? 'Зона').toString(),
                              snippet: 'Статус: ${(d['status'] ?? 'planned')}',
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              zoneStatus == 'active'
                                  ? BitmapDescriptor.hueGreen
                                  : zoneStatus == 'activating'
                                      ? BitmapDescriptor.hueOrange
                                      : BitmapDescriptor.hueAzure,
                            ),
                          ),
                        );
                      }

                      for (final d in houses) {
                        final lat = (d['lat'] as num?)?.toDouble();
                        final lng = (d['lng'] as num?)?.toDouble();
                        if (lat == null || lng == null) {
                          continue;
                        }
                        final houseStatus = (d['status'] ?? 'INACTIVE')
                            .toString()
                            .toLowerCase();
                        markers.add(
                          Marker(
                            markerId: MarkerId('house_${(d['id'] ?? 'house')}'),
                            position: LatLng(lat, lng),
                            infoWindow: InfoWindow(
                              title:
                                  (d['address'] ?? d['id'] ?? 'Дом').toString(),
                              snippet:
                                  'Статус: ${(d['status'] ?? 'INACTIVE')} · ${(d['current_users'] ?? 0)}/${(d['threshold'] ?? 20)}',
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              houseStatus == 'active'
                                  ? BitmapDescriptor.hueGreen
                                  : houseStatus == 'in_progress'
                                      ? BitmapDescriptor.hueOrange
                                      : BitmapDescriptor.hueAzure,
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: GoogleMap(
                            initialCameraPosition: const CameraPosition(
                              target: LatLng(51.1694, 71.4491),
                              zoom: 11,
                            ),
                            markers: markers,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: DomlyColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}
