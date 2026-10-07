// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../services/backend_api_service.dart';

Widget buildVerificationDocumentPreview(
        {required String url,
        required BorderRadius borderRadius,
        BoxFit fit = BoxFit.cover}) =>
    ClipRRect(
        borderRadius: borderRadius,
        child: _ProtectedDocument(url: url, fit: fit));

class _ProtectedDocument extends StatefulWidget {
  const _ProtectedDocument({required this.url, required this.fit});
  final String url;
  final BoxFit fit;
  @override
  State<_ProtectedDocument> createState() => _ProtectedDocumentState();
}

class _ProtectedDocumentState extends State<_ProtectedDocument> {
  late Future<Map<String, dynamic>> _document;
  String? _blobUrl;
  String? _viewType;
  static int _serial = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _document = BackendApiService.instance
        .getMap('/admin/files/preview', query: {'url': widget.url.trim()});
  }

  @override
  void didUpdateWidget(covariant _ProtectedDocument old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _release();
      _load();
    }
  }

  void _release() {
    if (_blobUrl != null) html.Url.revokeObjectUrl(_blobUrl!);
    _blobUrl = null;
    _viewType = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _document,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            if (snapshot.error is BackendApiException &&
                (snapshot.error as BackendApiException).statusCode == 404 &&
                Uri.tryParse(widget.url)?.scheme == 'https') {
              return Image.network(widget.url,
                  fit: widget.fit,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Text('Файл недоступен')));
            }
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Не удалось загрузить документ'),
              TextButton(
                  onPressed: () => setState(_load),
                  child: const Text('Повторить'))
            ]));
          }
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final bytes = base64Decode(snapshot.data!['base64'] as String);
          final mime = (snapshot.data!['mimeType'] ?? '').toString();
          if (mime == 'application/pdf') {
            if (_viewType == null) {
              _blobUrl = html.Url.createObjectUrlFromBlob(
                  html.Blob([bytes], 'application/pdf'));
              _viewType = 'domly-protected-document-${_serial++}';
              final blobUrl = _blobUrl!;
              ui_web.platformViewRegistry.registerViewFactory(
                  _viewType!,
                  (_) => html.IFrameElement()
                    ..src = blobUrl
                    ..style.border = '0'
                    ..style.width = '100%'
                    ..style.height = '100%');
            }
            return HtmlElementView(viewType: _viewType!);
          }
          return Image.memory(bytes,
              fit: widget.fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const Center(
                  child: Text('Формат документа не поддерживается')));
        },
      );
}
