import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'backend_api_service.dart';

class VerificationUploadService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndUpload({
    required String cleanerId,
    required String type,
  }) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (file == null) {
      return null;
    }

    final baseFolder = switch (type) {
      'selfie' || 'selfie-with-id' => 'cleaner_verification',
      _ => 'cleaner_documents',
    };
    final bytes = await file.readAsBytes();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final data = await BackendApiService.instance.uploadFile(
      path: '/files',
      bytes: bytes,
      filename: '$type-$stamp.jpg',
      contentType: 'image/jpeg',
      fields: {
        'folder': '$baseFolder/$cleanerId',
        'documentType': type,
        'platform': kIsWeb ? 'web' : 'native',
      },
    );
    return (data['public_url'] ?? data['publicUrl'] ?? '').toString();
  }
}
