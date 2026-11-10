import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks the store without blocking startup. A confirmed update stays above
/// the app's navigator so redirects and route replacement cannot dismiss it.
class StoreUpdatePrompt extends StatelessWidget {
  const StoreUpdatePrompt({
    super.key,
    required this.child,
    this.enabled = true,
    this.upgrader,
  });

  final Widget child;
  final bool enabled;
  final Upgrader? upgrader;

  @override
  Widget build(BuildContext context) {
    if (!enabled ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return child;
    }
    return _NativeStoreUpdatePrompt(upgrader: upgrader, child: child);
  }
}

class _NativeStoreUpdatePrompt extends StatefulWidget {
  const _NativeStoreUpdatePrompt({required this.upgrader, required this.child});

  final Upgrader? upgrader;
  final Widget child;

  @override
  State<_NativeStoreUpdatePrompt> createState() =>
      _NativeStoreUpdatePromptState();
}

class _NativeStoreUpdatePromptState extends State<_NativeStoreUpdatePrompt> {
  Upgrader? _upgrader;
  UpgraderVersionInfo? _confirmedUpdate;
  bool _openingStore = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_upgrader != null) return;
    final upgrader = _upgrader = widget.upgrader ??
        Upgrader(
          countryCode: 'KZ',
          languageCode: Localizations.localeOf(context).languageCode,
          checkOnResume: true,
        );
    unawaited(
      upgrader.initialize().then<void>(
        (_) {
          if (!mounted) upgrader.dispose();
        },
        onError: (Object error) =>
            debugPrint('Store version check failed: $error'),
      ),
    );
  }

  @override
  void dispose() {
    _upgrader?.dispose();
    super.dispose();
  }

  Future<void> _openStore(Uri listing) async {
    if (_openingStore) return;
    setState(() => _openingStore = true);
    try {
      final openedInStore = defaultTargetPlatform == TargetPlatform.android &&
          await launchUrl(listing,
              mode: LaunchMode.externalNonBrowserApplication);
      if (!openedInStore) {
        await launchUrl(listing, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      debugPrint('Opening the app store failed: $error');
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final upgrader = _upgrader!;
    return StreamBuilder<UpgraderState>(
      stream: upgrader.stateStream,
      initialData: upgrader.state,
      builder: (context, snapshot) {
        final info = snapshot.data?.versionInfo;
        final available = info?.appStoreVersion;
        final installed = info?.installedVersion;
        // A failed refresh must not dismiss an already confirmed update.
        if (available != null && installed != null) {
          _confirmedUpdate = available > installed ? info : null;
        }
        final update = _confirmedUpdate;
        final listing = Uri.tryParse(update?.appStoreListingURL ?? '');
        final showUpdate = update != null &&
            listing != null &&
            const {'https', 'market', 'itms-apps'}.contains(listing.scheme);
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(excluding: showUpdate, child: widget.child),
            if (showUpdate)
              BlockSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ModalBarrier(
                      dismissible: false,
                      color: Colors.black54,
                    ),
                    Center(child: _dialog(context, upgrader, update, listing)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dialog(
    BuildContext context,
    Upgrader upgrader,
    UpgraderVersionInfo update,
    Uri listing,
  ) {
    final messages = upgrader.determineMessages(context);
    final title = Text(messages.message(UpgraderMessage.title)!);
    final body = Text(
      messages
          .message(UpgraderMessage.body)!
          .replaceAll('{{appName}}', upgrader.appName())
          .replaceAll(
            '{{currentAppStoreVersion}}',
            update.appStoreVersion.toString(),
          )
          .replaceAll(
            '{{currentInstalledVersion}}',
            update.installedVersion.toString(),
          ),
    );
    final label = Text(messages.message(UpgraderMessage.buttonTitleUpdate)!);
    final open = _openingStore ? null : () => _openStore(listing);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoAlertDialog(
        title: title,
        content: body,
        actions: [CupertinoDialogAction(onPressed: open, child: label)],
      );
    }
    return AlertDialog(
      title: title,
      content: body,
      actions: [TextButton(onPressed: open, child: label)],
    );
  }
}
