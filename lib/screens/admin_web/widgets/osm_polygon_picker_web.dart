// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class OsmPolygonPicker extends StatefulWidget {
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
  State<OsmPolygonPicker> createState() => _OsmPolygonPickerState();
}

class _OsmPolygonPickerState extends State<OsmPolygonPicker> {
  late final String _viewType;
  late final String _frameId;
  late final html.IFrameElement _frame;
  StreamSubscription<html.MessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();
    _frameId = 'domly-osm-${DateTime.now().microsecondsSinceEpoch}';
    _viewType = 'domly-osm-view-$_frameId';
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
            decoded['type'] != 'domly-zone-polygon' ||
            decoded['id'] != _frameId) {
          return;
        }
        final rawPoints = decoded['points'];
        if (rawPoints is! List) {
          return;
        }
        final points = rawPoints
            .whereType<Map>()
            .map((item) => {
                  'lat': (item['lat'] as num).toDouble(),
                  'lng': (item['lng'] as num).toDouble(),
                })
            .toList();
        widget.onChanged(points);
      } catch (_) {
        return;
      }
    });
  }

  @override
  void didUpdateWidget(covariant OsmPolygonPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.points) != jsonEncode(widget.points)) {
      _postPoints();
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _postPoints() {
    _frame.contentWindow?.postMessage(
      jsonEncode({
        'type': 'domly-set-polygon',
        'id': _frameId,
        'points': widget.points,
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
    final encodedPoints = jsonEncode(widget.points);
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
    .toolbar {
      position: absolute; top: 12px; left: 12px; z-index: 1000;
      display: flex; gap: 8px; flex-wrap: wrap;
    }
    button {
      border: 1px solid #cbd5e1; background: #fff; color: #20382b;
      border-radius: 8px; padding: 8px 10px; font-weight: 700;
      box-shadow: 0 8px 20px rgba(15, 23, 42, .12); cursor: pointer;
    }
    .hint {
      position: absolute; left: 12px; right: 12px; bottom: 12px; z-index: 1000;
      background: rgba(255,255,255,.94); color: #334155; border-radius: 10px;
      padding: 8px 10px; font-size: 13px; box-shadow: 0 8px 20px rgba(15, 23, 42, .12);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <div class="toolbar">
    <button id="undo">Удалить точку</button>
    <button id="clear">Очистить</button>
    <button id="fit">Показать район</button>
  </div>
  <div class="hint">Кликайте по карте по углам района. Минимум 3 точки, для квадрата поставьте 4 точки.</div>
  <script>
    const frameId = "$_frameId";
    let points = $encodedPoints;
    const map = L.map('map', { zoomControl: true }).setView([${widget.centerLat}, ${widget.centerLng}], 12);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);
    let layerGroup = L.layerGroup().addTo(map);
    function normalizePoint(p) {
      return { lat: Number(p.lat), lng: Number(p.lng) };
    }
    function redraw() {
      layerGroup.clearLayers();
      const normalized = points.map(normalizePoint).filter(p => Number.isFinite(p.lat) && Number.isFinite(p.lng));
      normalized.forEach((p, index) => {
        L.marker([p.lat, p.lng]).addTo(layerGroup).bindTooltip(String(index + 1), {permanent: true, direction: 'top'});
      });
      if (normalized.length >= 2) {
        L.polyline(normalized.map(p => [p.lat, p.lng]), {color: '#d8744c', weight: 3}).addTo(layerGroup);
      }
      if (normalized.length >= 3) {
        L.polygon(normalized.map(p => [p.lat, p.lng]), {
          color: '#d8744c', weight: 2, fillColor: '#d8744c', fillOpacity: .18
        }).addTo(layerGroup);
      }
      points = normalized;
    }
    function emit() {
      window.parent.postMessage(JSON.stringify({type: 'domly-zone-polygon', id: frameId, points}), '*');
    }
    function fit() {
      if (points.length === 0) return;
      const bounds = L.latLngBounds(points.map(p => [p.lat, p.lng]));
      map.fitBounds(bounds.pad(.25));
    }
    map.on('click', (event) => {
      points.push({lat: event.latlng.lat, lng: event.latlng.lng});
      redraw();
      emit();
    });
    document.getElementById('undo').onclick = () => {
      points.pop();
      redraw();
      emit();
    };
    document.getElementById('clear').onclick = () => {
      points = [];
      redraw();
      emit();
    };
    document.getElementById('fit').onclick = fit;
    window.addEventListener('message', (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type !== 'domly-set-polygon' || data.id !== frameId) return;
        points = Array.isArray(data.points) ? data.points : [];
        redraw();
        fit();
      } catch (_) {}
    });
    redraw();
    setTimeout(fit, 300);
  </script>
</body>
</html>
''';
  }
}
