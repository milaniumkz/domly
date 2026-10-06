// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

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
  late final String _viewType;
  late final String _frameId;
  late final html.IFrameElement _frame;
  StreamSubscription<html.MessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();
    _frameId = 'domly-osm-point-${DateTime.now().microsecondsSinceEpoch}';
    _viewType = 'domly-osm-point-view-$_frameId';
    _frame = html.IFrameElement()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.borderRadius = '12px'
      ..srcdoc = _html();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    _messageSub = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is! String) {
        return;
      }
      try {
        final decoded = jsonDecode(data);
        if (decoded is! Map ||
            decoded['type'] != 'domly-house-point' ||
            decoded['id'] != _frameId) {
          return;
        }
        final lat = decoded['lat'];
        final lng = decoded['lng'];
        if (lat is! num || lng is! num) {
          return;
        }
        widget.onChanged({'lat': lat.toDouble(), 'lng': lng.toDouble()});
      } catch (_) {
        return;
      }
    });
  }

  @override
  void didUpdateWidget(covariant OsmPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.point) != jsonEncode(widget.point) ||
        jsonEncode(oldWidget.polygons) != jsonEncode(widget.polygons) ||
        oldWidget.selectedPolygonId != widget.selectedPolygonId) {
      _postPoint();
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _postPoint() {
    _frame.contentWindow?.postMessage(
      jsonEncode({
        'type': 'domly-set-house-point',
        'id': _frameId,
        'point': widget.point,
        'polygons': widget.polygons,
        'selectedPolygonId': widget.selectedPolygonId,
      }),
      '*',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }

  String _html() {
    final encodedPoint = jsonEncode(widget.point);
    final encodedPolygons = jsonEncode(widget.polygons);
    final encodedSelectedPolygonId = jsonEncode(widget.selectedPolygonId);
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
    body { font-family: Inter, Arial, sans-serif; }
    .hint {
      position: absolute; left: 12px; right: 12px; bottom: 12px; z-index: 1000;
      background: rgba(255,255,255,.94); color: #334155; border-radius: 10px;
      padding: 8px 10px; font-size: 13px; box-shadow: 0 8px 20px rgba(15, 23, 42, .12);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <div class="hint">Кликните по карте, чтобы поставить точку дома.</div>
  <script>
    const frameId = "$_frameId";
    let point = $encodedPoint;
    let polygons = $encodedPolygons;
    let selectedPolygonId = $encodedSelectedPolygonId;
    const initialCenter = point && Number.isFinite(Number(point.lat)) && Number.isFinite(Number(point.lng))
      ? [Number(point.lat), Number(point.lng)]
      : [${widget.centerLat}, ${widget.centerLng}];
    const map = L.map('map', { zoomControl: true }).setView(initialCenter, point ? 16 : 12);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);
    let marker = null;
    let polygonLayer = L.layerGroup().addTo(map);
    function redrawPolygons() {
      polygonLayer.clearLayers();
      const bounds = [];
      (Array.isArray(polygons) ? polygons : []).forEach((zone) => {
        const points = Array.isArray(zone.polygon) ? zone.polygon : [];
        const latLngs = points
          .map((p) => [Number(p.lat), Number(p.lng)])
          .filter((p) => Number.isFinite(p[0]) && Number.isFinite(p[1]));
        if (latLngs.length < 3) return;
        const selected = String(zone.id || '') === String(selectedPolygonId || '');
        L.polygon(latLngs, {
          color: selected ? '#d8744c' : '#20382b',
          weight: selected ? 4 : 2,
          fillColor: selected ? '#d8744c' : '#20382b',
          fillOpacity: selected ? .18 : .08
        }).addTo(polygonLayer).bindTooltip(String(zone.title || zone.id || 'Район'));
        if (selected) {
          latLngs.forEach((p) => bounds.push(p));
        }
      });
      if (bounds.length > 0) {
        map.fitBounds(L.latLngBounds(bounds).pad(.18));
      }
    }
    function setPoint(next, shouldEmit) {
      point = next;
      if (marker) marker.remove();
      if (point && Number.isFinite(Number(point.lat)) && Number.isFinite(Number(point.lng))) {
        marker = L.marker([Number(point.lat), Number(point.lng)]).addTo(map);
      }
      if (shouldEmit && point) {
        window.parent.postMessage(JSON.stringify({
          type: 'domly-house-point',
          id: frameId,
          lat: Number(point.lat),
          lng: Number(point.lng)
        }), '*');
      }
    }
    map.on('click', (event) => {
      setPoint({lat: event.latlng.lat, lng: event.latlng.lng}, true);
    });
    window.addEventListener('message', (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type !== 'domly-set-house-point' || data.id !== frameId) return;
        setPoint(data.point, false);
        polygons = Array.isArray(data.polygons) ? data.polygons : [];
        selectedPolygonId = data.selectedPolygonId;
        redrawPolygons();
        if (point) map.setView([Number(point.lat), Number(point.lng)], 16);
      } catch (_) {}
    });
    redrawPolygons();
    setPoint(point, false);
    if (!point && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition((position) => {
        map.setView([position.coords.latitude, position.coords.longitude], 16);
      }, () => {}, {enableHighAccuracy: true, timeout: 5000});
    }
  </script>
</body>
</html>
''';
  }
}
