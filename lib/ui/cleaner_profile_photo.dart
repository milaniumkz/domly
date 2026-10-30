import 'package:flutter/material.dart';
import '../services/firestore_data_service.dart';
import '../services/photo_upload_service.dart';
import '../localization/translation_controller.dart';
import '../theme/domly_palette.dart';
import 'domly_ui.dart';

class CleanerProfilePhoto extends StatefulWidget {
  const CleanerProfilePhoto(
      {super.key, required this.profile, this.upload, this.submit});
  final Map<String, dynamic> profile;
  final Future<String?> Function()? upload;
  final Future<void> Function(String)? submit;
  @override
  State<CleanerProfilePhoto> createState() => _CleanerProfilePhotoState();
}

class _CleanerProfilePhotoState extends State<CleanerProfilePhoto> {
  bool _uploading = false;
  bool _submitted = false;
  Future<void> _change() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final url = await (widget.upload?.call() ??
          PhotoUploadService()
              .pickAndUpload(folder: 'profile_photos', filePrefix: 'selfie'));
      if (url == null) return;
      await (widget.submit?.call(url) ??
          FirestoreDataService.instance.submitCleanerProfilePhoto(url));
      if (!mounted) return;
      setState(() => _submitted = true);
      showDomlySnackBar(context,
          title: 'Фото отправлено на проверку',
          subtitle: 'После одобрения администратором фото появится в профиле.',
          type: DomlySnackBarType.success);
    } catch (_) {
      if (mounted)
        showDomlySnackBar(context,
            title: 'Не удалось отправить фото',
            subtitle: 'Попробуйте снова.',
            type: DomlySnackBarType.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void didUpdateWidget(covariant CleanerProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile['photoReviewStatus'] == 'pending' &&
        widget.profile['photoReviewStatus'] != 'pending') _submitted = false;
  }

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    final url = (widget.profile['photoUrl'] ?? '').toString();
    final name = (widget.profile['name'] ?? '').toString().trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    final pending =
        _submitted || widget.profile['photoReviewStatus'] == 'pending';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
          button: true,
          label: 'Сменить фото'.tr(),
          child: InkWell(
              onTap: _uploading ? null : _change,
              borderRadius: BorderRadius.circular(36),
              child: ClipOval(
                  child: SizedBox(
                      width: 72,
                      height: 72,
                      child: ColoredBox(
                          color: DomlyPalette.surface(Colors.white),
                          child: url.isEmpty
                              ? Center(child: Text(initials))
                              : Image.network(url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Center(child: Text(initials)))))))),
      TextButton(
          onPressed: _uploading ? null : _change,
          child: Text((_uploading ? 'Отправляем...' : 'Сменить фото').tr(),
              style: const TextStyle(fontSize: 12))),
      if (pending)
        Text('Фото на проверке'.tr(), style: const TextStyle(fontSize: 12)),
      if (!pending && widget.profile['photoReviewStatus'] == 'rejected')
        Text('Фото отклонено. Загрузите другое селфи.'.tr(),
            style: const TextStyle(fontSize: 12)),
    ]);
  }
}
