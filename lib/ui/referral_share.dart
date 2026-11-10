import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../localization/translation_controller.dart';

/// Invoke directly from the tap so Safari/Chrome retain user activation.
/// A visible link remains available when the OS cannot open its share sheet.
Future<void> shareReferralLink(BuildContext context, String code) async {
  final normalized = code.trim().toUpperCase();
  if (normalized.isEmpty) return;
  final uri = Uri.https('domly.kz', '/customer/', {'ref': normalized});
  final link = uri.toString();
  final box = context.findRenderObject();
  final rect = box is RenderBox && box.hasSize && !box.size.isEmpty
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(1, 1, 1, 1);
  try {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      await Share.shareUri(uri, sharePositionOrigin: rect);
    } else {
      await Share.share(
        'Присоединяйся к DomLY. Используй мой код: $normalized. $link',
        subject: 'Приглашение в DomLY',
        sharePositionOrigin: rect,
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Приглашение в DomLY'.tr()),
        content: SelectableText(link),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Закрыть'.tr()),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text('Скопировать ссылку'.tr()),
          ),
        ],
      ),
    );
  }
}

/// If prefetch has not finished, offer a fresh tap after loading rather than
/// opening Web Share after a network await (which loses browser activation).
Future<void> prepareReferralShare(
  BuildContext context,
  Future<Map<String, dynamic>> Function() load,
) async {
  try {
    final invite = await load();
    if (!context.mounted) return;
    final code = (invite['referralCode'] ?? '').toString();
    if (code.trim().isEmpty) throw StateError('Referral code unavailable');
    if (!kIsWeb) {
      await shareReferralLink(context, code);
      return;
    }
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text('Приглашение в DomLY'.tr()),
              content: SelectableText(
                  Uri.https('domly.kz', '/customer/', {'ref': code})
                      .toString()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('Закрыть'.tr())),
                TextButton(
                    onPressed: () => shareReferralLink(dialogContext, code),
                    child: Text('Поделиться'.tr())),
              ],
            ));
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Не удалось загрузить ссылку. Попробуйте снова.'.tr())),
      );
  }
}
