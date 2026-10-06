import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../localization/translation_controller.dart';
import '../services/firestore_data_service.dart';
import '../utils/user_error_message.dart';
import 'tutorial_targets.dart';

export '../localization/translation_controller.dart';

class DomlyColors {
  static const background = Color(0xFFFCFFFD);
  static const backgroundSoft = Color(0xFFF2FAF4);
  static const backgroundSoft2 = Color(0xFFE8F5EC);
  static const card = Colors.white;
  static const primary = Color(0xFF3D8A63);
  static const primaryDark = Color(0xFF2D6B4F);
  static const accent = Color(0xFF8FD0AE);
  static const buttonPrimary = Color(0xFFC56F4B);
  static const buttonPrimaryDark = Color(0xFFA75736);
  static const buttonAccent = Color(0xFFE8B29D);
  static const buttonSoft = Color(0xFFF7E3DA);
  static const foreground = Color(0xFF20382B);
  static const muted = Color(0xFF5E7B69);
  static const border = Color(0x263D8A63);
  static const danger = Color(0xFFD32F2F);
}

enum DomlySnackBarType { success, error, info }

class DomlyLanguageSwitcher extends StatelessWidget {
  const DomlyLanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).translationController;
    final current = controller.localeCode;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DomlyColors.backgroundSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DomlyColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DomlyLanguageChip(
              label: 'Рус',
              selected: current == 'ru',
              onTap: () => controller.setLocale('ru'),
            ),
            _DomlyLanguageChip(
              label: 'Қаз',
              selected: current == 'kk',
              onTap: () => controller.setLocale('kk'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DomlyLanguageChip extends StatelessWidget {
  const _DomlyLanguageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DomlyColors.buttonPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : DomlyColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

void showDomlySnackBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  DomlySnackBarType type = DomlySnackBarType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final normalizedTitle = type == DomlySnackBarType.error
      ? UserErrorMessage.title('$title ${subtitle ?? ''}', fallback: title)
      : title;
  final normalizedSubtitle = type == DomlySnackBarType.error
      ? UserErrorMessage.message(
          '$title ${subtitle ?? ''}',
          fallback: subtitle ?? 'Попробуйте ещё раз.',
        )
      : subtitle;
  if (type == DomlySnackBarType.error &&
      UserErrorMessage.isAuthError('$title ${subtitle ?? ''}')) {
    _redirectToAuth(context);
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        duration: duration,
        content: _DomlySnackBarCard(
          title: normalizedTitle,
          subtitle: normalizedSubtitle,
          type: type,
        ),
      ),
    );
}

void _redirectToAuth(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) {
      return;
    }
    try {
      final scope = AppScope.of(context);
      await scope.authController.signOut();
      if (!context.mounted) {
        return;
      }
      final route = scope.config.adminSurface ? '/admin/web' : '/auth';
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } catch (_) {}
  });
}

class _DomlySnackBarCard extends StatelessWidget {
  const _DomlySnackBarCard({
    required this.title,
    required this.subtitle,
    required this.type,
  });

  final String title;
  final String? subtitle;
  final DomlySnackBarType type;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    final backgroundColor = switch (type) {
      DomlySnackBarType.success => const Color(0xFF1F4D33),
      DomlySnackBarType.error => const Color(0xFFFEECEC),
      DomlySnackBarType.info => const Color(0xFFE8F2FF),
    };
    final borderColor = switch (type) {
      DomlySnackBarType.error => const Color(0xFFDB4A4A),
      _ => Colors.transparent,
    };
    final titleColor = switch (type) {
      DomlySnackBarType.success => Colors.white,
      DomlySnackBarType.error => const Color(0xFFDB4A4A),
      DomlySnackBarType.info => const Color(0xFF477DD1),
    };
    final subtitleColor = switch (type) {
      DomlySnackBarType.success => const Color(0xFFDEF2E6),
      _ => DomlyColors.foreground,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
          if (hasSubtitle) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!.tr(),
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: subtitleColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DomlyShell extends StatelessWidget {
  const DomlyShell({
    super.key,
    required this.child,
    this.bottomNavigationBar,
    this.showBackButton,
  });

  final Widget child;
  final Widget? bottomNavigationBar;
  final bool? showBackButton;

  @override
  Widget build(BuildContext context) {
    final shouldShowBackButton =
        showBackButton ?? _shouldShowShellBackButton(context);
    return Scaffold(
      backgroundColor: DomlyColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth > 430 ? 430.0 : constraints.maxWidth;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  DomlyColors.background,
                  DomlyColors.backgroundSoft,
                  DomlyColors.backgroundSoft2,
                ],
              ),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Stack(
                  children: [
                    child,
                    if (shouldShowBackButton) const _DomlyShellBackButton(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }

  static bool _shouldShowShellBackButton(BuildContext context) {
    final routeName = ModalRoute.of(context)?.settings.name ?? '';
    if (routeName.isEmpty) {
      return Navigator.of(context).canPop();
    }
    const rootRoutes = {
      '/',
      '/welcome',
      '/auth',
      '/client/home',
      '/client/orders',
      '/client/profile',
      '/client/settings',
      '/cleaner/dashboard',
      '/cleaner/calendar',
      '/cleaner/orders',
      '/cleaner/messages',
      '/cleaner/profile',
      '/admin',
      '/admin/web',
    };
    return !rootRoutes.contains(routeName);
  }
}

class _DomlyShellBackButton extends StatelessWidget {
  const _DomlyShellBackButton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 0, 0),
        child: Material(
          color: Colors.white.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: 8,
          shadowColor: Colors.black26,
          child: IconButton(
            tooltip: 'Назад'.tr(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: DomlyColors.foreground,
              size: 20,
            ),
            onPressed: () => _goBack(context),
          ),
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final routeName = ModalRoute.of(context)?.settings.name ?? '';
    final fallbackRoute = routeName.startsWith('/cleaner/')
        ? '/cleaner/dashboard'
        : routeName.startsWith('/admin')
            ? '/admin/web'
            : '/client/home';
    navigator.pushReplacementNamed(fallbackRoute);
  }
}

class DomlyClientBottomNav extends StatelessWidget {
  const DomlyClientBottomNav({
    super.key,
    required this.currentIndex,
  });

  final int currentIndex;

  static const _routes = <String>[
    '/client/home',
    '/client/orders',
    '/client/profile',
    '/notifications',
    '/client/settings',
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreDataService.instance.userUnreadActivityCountStream(),
      initialData: 0,
      builder: (context, snapshot) {
        return _DomlyBottomNavBar(
          currentIndex: currentIndex,
          items: [
            _DomlyNavItem(
              label: 'Главная',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              targetKey: DomlyTutorialTargets.clientBottomNav[0],
            ),
            _DomlyNavItem(
              label: 'Заказы',
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              targetKey: DomlyTutorialTargets.clientBottomNav[1],
            ),
            _DomlyNavItem(
              label: 'Профиль',
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              targetKey: DomlyTutorialTargets.clientBottomNav[2],
            ),
            _DomlyNavItem(
              label: 'Уведомления',
              icon: Icons.notifications_none,
              selectedIcon: Icons.notifications,
              badgeCount: snapshot.data ?? 0,
              targetKey: DomlyTutorialTargets.clientBottomNav[3],
            ),
            _DomlyNavItem(
              label: 'Настройки',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              targetKey: DomlyTutorialTargets.clientBottomNav[4],
            ),
          ],
          onSelected: (index) {
            if (index == currentIndex) {
              return;
            }
            Navigator.pushReplacementNamed(context, _routes[index]);
          },
        );
      },
    );
  }
}

class DomlyCleanerBottomNav extends StatelessWidget {
  const DomlyCleanerBottomNav({
    super.key,
    required this.currentIndex,
  });

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: data.userChatSummariesStream(),
      builder: (context, snapshot) {
        final unread =
            (snapshot.data ?? const <Map<String, dynamic>>[]).fold<int>(
          0,
          (total, item) =>
              total + ((item['unreadCount'] as num?)?.toInt() ?? 0),
        );
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: data.cleanerScheduleSlotsStream(),
          builder: (context, slotSnapshot) {
            final calendarAlerts =
                (slotSnapshot.data ?? const <Map<String, dynamic>>[])
                    .where((slot) {
              final status = (slot['status'] ?? '').toString();
              return status == 'assigned' ||
                  status == 'confirmed' ||
                  status == 'rescheduled';
            }).length;
            return _DomlyBottomNavBar(
              currentIndex: currentIndex,
              items: [
                _DomlyNavItem(
                  label: 'Главная',
                  icon: Icons.dashboard_outlined,
                  selectedIcon: Icons.dashboard,
                  targetKey: DomlyTutorialTargets.cleanerBottomNav[0],
                ),
                _DomlyNavItem(
                  label: 'Календарь',
                  icon: Icons.calendar_today_outlined,
                  selectedIcon: Icons.calendar_today,
                  badgeCount: calendarAlerts,
                  targetKey: DomlyTutorialTargets.cleanerBottomNav[1],
                ),
                _DomlyNavItem(
                  label: 'Заказы',
                  icon: Icons.receipt_long_outlined,
                  selectedIcon: Icons.receipt_long,
                  targetKey: DomlyTutorialTargets.cleanerBottomNav[2],
                ),
                _DomlyNavItem(
                  label: 'Сообщения',
                  icon: Icons.chat_bubble_outline,
                  selectedIcon: Icons.chat_bubble,
                  badgeCount: unread,
                  targetKey: DomlyTutorialTargets.cleanerBottomNav[3],
                ),
                _DomlyNavItem(
                  label: 'Профиль',
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  targetKey: DomlyTutorialTargets.cleanerBottomNav[4],
                ),
              ],
              onSelected: (index) {
                if (index == currentIndex) {
                  return;
                }
                final route = switch (index) {
                  0 => '/cleaner/dashboard',
                  1 => '/cleaner/calendar',
                  2 => '/cleaner/orders',
                  3 => '/cleaner/messages',
                  _ => '/cleaner/profile',
                };
                Navigator.of(context).pushReplacementNamed(route);
              },
            );
          },
        );
      },
    );
  }
}

class _DomlyNavItem {
  const _DomlyNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badgeCount = 0,
    this.targetKey,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badgeCount;
  final GlobalKey? targetKey;
}

class _DomlyBottomNavBar extends StatelessWidget {
  const _DomlyBottomNavBar({
    required this.currentIndex,
    required this.items,
    required this.onSelected,
  });

  final int currentIndex;
  final List<_DomlyNavItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sideInset = screenWidth <= 380 ? 10.0 : 16.0;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(sideInset, 0, sideInset, 10),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(430, screenWidth - sideInset * 2),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: DomlyColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x122D6B4F),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final selected = index == currentIndex;
                  return Expanded(
                    key: item.targetKey,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onSelected(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            decoration: BoxDecoration(
                              color: selected
                                  ? DomlyColors.buttonSoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        selected
                                            ? item.selectedIcon
                                            : item.icon,
                                        size: 19,
                                        color: selected
                                            ? DomlyColors.buttonPrimary
                                            : DomlyColors.muted,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.label.tr(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: items.length >= 5 ? 9 : 10,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? DomlyColors.foreground
                                              : DomlyColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.badgeCount > 0)
                                  Positioned(
                                    top: 3,
                                    right: 6,
                                    child: _navBadge(item.badgeCount),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _navBadge(int count) {
  return Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: const BoxDecoration(
      color: DomlyColors.danger,
      shape: BoxShape.circle,
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class DomlyHeader extends StatelessWidget {
  const DomlyHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DomlyColors.primary, DomlyColors.accent],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F2D6B4F),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -18,
            right: -10,
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -28,
            left: -14,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class DomlyCard extends StatelessWidget {
  const DomlyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.border,
    this.color = DomlyColors.card,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final BoxBorder? border;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: border ?? Border.all(color: DomlyColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x142D6B4F),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DomlyIconBadge extends StatelessWidget {
  const DomlyIconBadge({
    super.key,
    required this.icon,
    this.size = 48,
    this.colors = const [DomlyColors.buttonPrimary, DomlyColors.buttonAccent],
  });

  final IconData icon;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2D6B4F),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

class DomlyStatusChip extends StatelessWidget {
  const DomlyStatusChip({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? DomlyColors.buttonPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.tr(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DomlyColors.foreground,
        ),
      ),
    );
  }
}

class DomlySectionTitle extends StatelessWidget {
  const DomlySectionTitle({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onAction,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  actionLabel!.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DomlyColors.foreground,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

typedef DomlyButtonCallback = FutureOr<void> Function();

class DomlyPrimaryButton extends StatefulWidget {
  const DomlyPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final DomlyButtonCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  State<DomlyPrimaryButton> createState() => _DomlyPrimaryButtonState();
}

class _DomlyPrimaryButtonState extends State<DomlyPrimaryButton> {
  bool _isPressed = false;
  bool _isPending = false;

  Future<void> _handlePressed() async {
    final onPressed = widget.onPressed;
    if (onPressed == null || widget.isLoading || _isPending) {
      return;
    }

    setState(() {
      _isPending = true;
      _isPressed = false;
    });

    try {
      await Future.sync(onPressed);
    } finally {
      if (mounted) {
        setState(() {
          _isPending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = widget.isLoading || _isPending;
    final enabled = widget.onPressed != null && !showLoading;
    return SizedBox(
      width: double.infinity,
      child: AnimatedScale(
        scale: _isPressed && enabled ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _handlePressed : null,
          onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel:
              enabled ? () => setState(() => _isPressed = false) : null,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                gradient: enabled
                    ? LinearGradient(
                        colors: _isPressed
                            ? [
                                DomlyColors.buttonPrimaryDark,
                                DomlyColors.buttonPrimary,
                              ]
                            : [
                                DomlyColors.buttonPrimary,
                                DomlyColors.buttonAccent,
                              ],
                      )
                    : null,
                color: enabled ? null : DomlyColors.border,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                boxShadow: enabled && !_isPressed
                    ? const [
                        BoxShadow(
                          color: Color(0x24A75736),
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (showLoading)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              enabled ? Colors.white : DomlyColors.muted,
                            ),
                          ),
                        )
                      else if (widget.icon != null)
                        Icon(
                          widget.icon,
                          color: enabled ? Colors.white : DomlyColors.muted,
                          size: 18,
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          widget.label.tr(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: enabled ? Colors.white : DomlyColors.muted,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DomlySecondaryButton extends StatefulWidget {
  const DomlySecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.foregroundColor = DomlyColors.buttonPrimary,
    this.isLoading = false,
  });

  final String label;
  final DomlyButtonCallback? onPressed;
  final IconData? icon;
  final Color foregroundColor;
  final bool isLoading;

  @override
  State<DomlySecondaryButton> createState() => _DomlySecondaryButtonState();
}

class _DomlySecondaryButtonState extends State<DomlySecondaryButton> {
  bool _isPressed = false;
  bool _isPending = false;

  Future<void> _handlePressed() async {
    final onPressed = widget.onPressed;
    if (onPressed == null || widget.isLoading || _isPending) {
      return;
    }

    setState(() {
      _isPending = true;
      _isPressed = false;
    });

    try {
      await Future.sync(onPressed);
    } finally {
      if (mounted) {
        setState(() {
          _isPending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = widget.isLoading || _isPending;
    final enabled = widget.onPressed != null && !showLoading;
    return AnimatedScale(
      scale: _isPressed && enabled ? 0.985 : 1,
      duration: const Duration(milliseconds: 110),
      child: Listener(
        onPointerDown:
            enabled ? (_) => setState(() => _isPressed = true) : null,
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: OutlinedButton(
          onPressed: enabled ? _handlePressed : null,
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
            ),
            side: WidgetStateProperty.all(
              BorderSide(color: widget.foregroundColor.withValues(alpha: 0.20)),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            foregroundColor: WidgetStateProperty.all(widget.foregroundColor),
            backgroundColor: WidgetStateProperty.all(
              widget.foregroundColor.withValues(
                alpha: _isPressed ? 0.12 : 0.04,
              ),
            ),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return widget.foregroundColor.withValues(alpha: 0.10);
              }
              if (states.contains(WidgetState.hovered)) {
                return widget.foregroundColor.withValues(alpha: 0.05);
              }
              return null;
            }),
            splashFactory: InkRipple.splashFactory,
            animationDuration: const Duration(milliseconds: 140),
          ),
          child: _DomlySecondaryButtonContent(
            label: widget.label,
            icon: widget.icon,
            foregroundColor: widget.foregroundColor,
            isLoading: showLoading,
            enabled: enabled,
          ),
        ),
      ),
    );
  }
}

class _DomlySecondaryButtonContent extends StatelessWidget {
  const _DomlySecondaryButtonContent({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.isLoading,
    required this.enabled,
  });

  final String label;
  final IconData? icon;
  final Color foregroundColor;
  final bool isLoading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(
                enabled ? foregroundColor : DomlyColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (!isLoading && icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: enabled ? foregroundColor : DomlyColors.muted,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label.tr(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.2),
          ),
        ),
      ],
    );
  }
}

Widget domlyTopIconButton({
  required IconData icon,
  required VoidCallback onPressed,
  Color foreground = Colors.white,
  Color background = const Color(0x33FFFFFF),
}) {
  return Material(
    color: background,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onPressed,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, color: foreground, size: 17),
      ),
    ),
  );
}

Widget domlyTopBadgeIconButton({
  required IconData icon,
  required VoidCallback onPressed,
  int badgeCount = 0,
  Color foreground = Colors.white,
  Color background = const Color(0x33FFFFFF),
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      domlyTopIconButton(
        icon: icon,
        onPressed: onPressed,
        foreground: foreground,
        background: background,
      ),
      if (badgeCount > 0)
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: DomlyColors.danger,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              badgeCount > 9 ? '9+' : '$badgeCount',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
    ],
  );
}

const List<String> _domlyMonthNamesGenitive = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String domlyDateText(DateTime date) {
  final day = date.day.toString();
  final month = _domlyMonthNamesGenitive[date.month - 1];
  return '$day $month ${date.year}';
}

String domlyDateTimeText(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${domlyDateText(date)} $hour:$minute';
}

class DomlyStickyActionBar extends StatelessWidget {
  const DomlyStickyActionBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DomlyColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DomlyEmptyStateCard extends StatelessWidget {
  const DomlyEmptyStateCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DomlyCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: DomlyColors.backgroundSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              icon,
              color: DomlyColors.buttonPrimary,
              size: 24,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: DomlyColors.muted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
