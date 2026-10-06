import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../localization/translation_controller.dart';

class OsmPointPicker extends StatefulWidget {
  const OsmPointPicker({
    super.key,
    required this.onChanged,
    this.point,
    this.centerLat = 43.2389,
    this.centerLng = 76.8897,
    this.height = 320,
    this.polygons = const <Map<String, dynamic>>[],
    this.selectedPolygonId,
  });

  final Map<String, double>? point;
  final ValueChanged<Map<String, double>> onChanged;
  final double centerLat;
  final double centerLng;
  final double height;
  final List<Map<String, dynamic>> polygons;
  final String? selectedPolygonId;

  @override
  State<OsmPointPicker> createState() => _OsmPointPickerState();
}

class _OsmPointPickerState extends State<OsmPointPicker> {
  late final WebViewController _controller;
  Map<String, double>? _selected;
  late double _centerLat;
  late double _centerLng;

  @override
  void initState() {
    super.initState();
    _selected = widget.point;
    _centerLat = widget.point?['lat'] ?? widget.centerLat;
    _centerLng = widget.point?['lng'] ?? widget.centerLng;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'DomlyPoint',
        onMessageReceived: (message) {
          try {
            final decoded = jsonDecode(message.message);
            if (decoded is! Map) {
              return;
            }
            final lat = decoded['lat'];
            final lng = decoded['lng'];
            if (lat is! num || lng is! num) {
              return;
            }
            final next = {'lat': lat.toDouble(), 'lng': lng.toDouble()};
            setState(() => _selected = next);
            widget.onChanged(next);
          } catch (_) {
            return;
          }
        },
      )
      ..loadHtmlString(_html(_centerLat, _centerLng, _selected));
    _moveToUserLocation();
  }

  @override
  void didUpdateWidget(covariant OsmPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.point;
    if (next != null &&
        (next['lat'] != _selected?['lat'] ||
            next['lng'] != _selected?['lng'])) {
      _selected = next;
      _controller.runJavaScript('setPoint(${jsonEncode(next)}, false);');
      _controller.runJavaScript(
        'map.setView([${next['lat']}, ${next['lng']}], 16);',
      );
    }
  }

  Future<void> _moveToUserLocation() async {
    if (_selected != null) {
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) {
        return;
      }
      final lat = position.latitude;
      final lng = position.longitude;
      setState(() {
        _centerLat = lat;
        _centerLng = lng;
      });
      await _controller.runJavaScript('map.setView([$lat, $lng], 16);');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Text(
                    'Нажмите на карту, чтобы отметить точку дома.'.tr(),
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _html(double centerLat, double centerLng, Map<String, double>? point) {
    final encodedPoint = jsonEncode(point);
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    html, body, #map { height: 100%; width: 100%; margin: 0; }
    body { font-family: Inter, Arial, sans-serif; background: #f8fafc; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    let point = $encodedPoint;
    const initialCenter = point && Number.isFinite(Number(point.lat)) && Number.isFinite(Number(point.lng))
      ? [Number(point.lat), Number(point.lng)]
      : [$centerLat, $centerLng];
    const map = L.map('map', { zoomControl: true }).setView(initialCenter, point ? 16 : 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);
    let marker = null;
    function setPoint(next, shouldEmit) {
      point = next;
      if (marker) marker.remove();
      if (point && Number.isFinite(Number(point.lat)) && Number.isFinite(Number(point.lng))) {
        marker = L.marker([Number(point.lat), Number(point.lng)]).addTo(map);
      }
      if (shouldEmit && point && window.DomlyPoint) {
        DomlyPoint.postMessage(JSON.stringify({
          lat: Number(point.lat),
          lng: Number(point.lng)
        }));
      }
    }
    map.on('click', (event) => {
      setPoint({lat: event.latlng.lat, lng: event.latlng.lng}, true);
    });
    setPoint(point, false);
  </script>
</body>
</html>
''';
  }
}
