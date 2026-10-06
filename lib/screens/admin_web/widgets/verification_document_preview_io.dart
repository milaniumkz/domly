import 'package:flutter/material.dart';
import '../../../localization/translation_controller.dart';

Widget buildVerificationDocumentPreview({
  required String url,
  required BorderRadius borderRadius,
  BoxFit fit = BoxFit.cover,
}) {
  return ClipRRect(
    borderRadius: borderRadius,
    child: Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const _VerificationPreviewFallback(),
    ),
  );
}

class _VerificationPreviewFallback extends StatelessWidget {
  const _VerificationPreviewFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: Color(0xFF9CA3AF),
          ),
          SizedBox(height: 8),
          Text(
            'Не удалось загрузить превью'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
