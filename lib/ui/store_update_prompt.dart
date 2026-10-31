import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

/// Store availability is checked asynchronously and never blocks app startup.
class StoreUpdatePrompt extends StatefulWidget {
  const StoreUpdatePrompt({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.enabled = true,
    this.upgrader,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool enabled;
  final Upgrader? upgrader;

  @override
  State<StoreUpdatePrompt> createState() => _StoreUpdatePromptState();
}

class _StoreUpdatePromptState extends State<StoreUpdatePrompt> {
  Upgrader? _upgrader;

  @override
  void dispose() {
    _upgrader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return widget.child;
    }
    final upgrader = _upgrader ??= widget.upgrader ??
        Upgrader(
          countryCode: 'KZ',
          languageCode: Localizations.localeOf(context).languageCode,
          durationUntilAlertAgain: const Duration(days: 1),
        );
    return _NavigatorUpgradeAlert(
      upgrader: upgrader,
      navigatorKey: widget.navigatorKey,
      dialogStyle: defaultTargetPlatform == TargetPlatform.iOS
          ? UpgradeDialogStyle.cupertino
          : UpgradeDialogStyle.material,
      showIgnore: false,
      showReleaseNotes: false,
      child: widget.child,
    );
  }
}

// MaterialApp.builder sits above Navigator. Dialogs need its overlay context.
class _NavigatorUpgradeAlert extends UpgradeAlert {
  _NavigatorUpgradeAlert({
    required super.upgrader,
    required super.navigatorKey,
    required super.dialogStyle,
    required super.showIgnore,
    required super.showReleaseNotes,
    required super.child,
  });

  @override
  UpgradeAlertState createState() => _NavigatorUpgradeAlertState();
}

class _NavigatorUpgradeAlertState extends UpgradeAlertState {
  @override
  void checkVersion({required BuildContext context}) {
    final overlayContext = widget.navigatorKey?.currentState?.overlay?.context;
    if (overlayContext != null) {
      super.checkVersion(context: overlayContext);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) checkVersion(context: this.context);
      });
    }
  }
}
