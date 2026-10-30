import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../app/debug_session.dart';
import 'backend_api_service.dart';

class PhotoUploadService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndUpload({
    required String folder,
    required String filePrefix,
  }) async {
    if (kIsWeb && DebugSession.uid == 'cleaner_demo') {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      return 'https://picsum.photos/seed/$filePrefix-$stamp/1200/900';
    }

    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1800,
    );
    if (file == null) {
      return null;
    }

    final bytes = await file.readAsBytes();
    return _uploadBytesToBackend(
      bytes: bytes,
      folder: folder,
      filePrefix: filePrefix,
    );
  }

  Future<String?> pickAndUploadVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    if (await file.length() > 50 * 1024 * 1024)
      throw StateError('Размер видео не должен превышать 50 МБ.');
    final result = await BackendApiService.instance.uploadFile(
        path: '/admin/videos/upload',
        bytes: await file.readAsBytes(),
        filename: file.name,
        contentType: file.name.toLowerCase().endsWith('.webm')
            ? 'video/webm'
            : 'video/mp4');
    return (result['public_url'] ?? '').toString();
  }

  Future<List<String>> pickMultipleAndUpload({
    required String folder,
    required String filePrefix,
    int limit = 5,
  }) async {
    if (limit <= 0) {
      return const <String>[];
    }
    if (kIsWeb && DebugSession.uid == 'cleaner_demo') {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      return List<String>.generate(
        limit,
        (index) =>
            'https://picsum.photos/seed/$filePrefix-$stamp-$index/1200/900',
      );
    }

    final files = await _picker.pickMultiImage(
      imageQuality: 80,
      maxWidth: 1800,
    );
    if (files.isEmpty) {
      return const <String>[];
    }

    final selected = files.take(limit).toList();
    final uploaded = <String>[];
    for (var i = 0; i < selected.length; i++) {
      final file = selected[i];
      final bytes = await file.readAsBytes();
      uploaded.add(
        await _uploadBytesToBackend(
          bytes: bytes,
          folder: folder,
          filePrefix: '$filePrefix-$i',
        ),
      );
    }
    return uploaded;
  }

  Future<String> _uploadBytesToBackend({
    required Uint8List bytes,
    required String folder,
    required String filePrefix,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final data = await BackendApiService.instance.uploadFile(
      path: '/files',
      bytes: bytes,
      filename: '$filePrefix-$stamp.jpg',
      contentType: 'image/jpeg',
      fields: {'folder': folder},
    );
    final url =
        (data['public_url'] ?? data['publicUrl'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw StateError('Сервис не вернул ссылку на фото.');
    }
    return url;
  }
}
