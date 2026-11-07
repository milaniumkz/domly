import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../localization/translation_controller.dart';
import '../utils/admin_area_check_data.dart';
import '../screens/admin_web/widgets/verification_document_preview.dart';

/// Documents remain readable after an area request has been resolved.
class AdminAreaPlan extends StatelessWidget {
  const AdminAreaPlan({super.key, required this.report, required this.onView});
  final Map<String, dynamic> report;
  final ValueChanged<List<String>> onView;

  @override
  Widget build(BuildContext context) {
    final urls = areaPlanUrls(report);
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Техплан квартиры'.tr(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (report['bot_document_url'] != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Техплан, проверенный ботом'.tr())),
        SizedBox(
            height: 320,
            child: buildVerificationDocumentPreview(
                url: urls.first,
                borderRadius: BorderRadius.circular(14),
                fit: BoxFit.contain)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 8, children: [
          TextButton.icon(
              onPressed: () => onView(urls),
              icon: const Icon(Icons.zoom_in),
              label: Text('Увеличить'.tr())),
          TextButton.icon(
              onPressed: () async {
                try {
                  if (await launchUrl(Uri.parse(urls.first),
                      mode: LaunchMode.externalApplication)) {
                    return;
                  }
                } catch (_) {}
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Не удалось открыть документ'.tr())));
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text('Открыть оригинал'.tr())),
        ]),
      ]),
    );
  }
}
