import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';

/// Returns the exact catalogue revision the customer agreed to. No payment is
/// created by opening or dismissing this dialog.
Future<String?> showPackageConsentDialog(
  BuildContext context,
  Map<String, dynamic> package,
) async {
  final version = (package['consentVersion'] ?? '').toString();
  final info = (package['importantInfo'] ?? '').toString().trim();
  if (version.isEmpty || info.isEmpty) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => PackageConsentDialog(package: package),
  );
}

class PackageConsentDialog extends StatefulWidget {
  const PackageConsentDialog({super.key, required this.package});
  final Map<String, dynamic> package;
  @override
  State<PackageConsentDialog> createState() => _PackageConsentDialogState();
}

class _PackageConsentDialogState extends State<PackageConsentDialog> {
  bool _agreed = false;
  @override
  Widget build(BuildContext context) {
    final package = widget.package;
    final items = (package['features'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    return AlertDialog(
      title: Text('Важная информация'.tr()),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((package['name'] ?? '').toString(),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text((package['importantInfo'] ?? '').toString()),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Что входит в уборку'.tr(),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('• $item'),
                    )),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreed,
                onChanged: (value) => setState(() => _agreed = value == true),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Я согласен'.tr()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr())),
        ElevatedButton(
          onPressed: _agreed
              ? () =>
                  Navigator.pop(context, package['consentVersion'].toString())
              : null,
          child: Text('Далее'.tr()),
        ),
      ],
    );
  }
}
