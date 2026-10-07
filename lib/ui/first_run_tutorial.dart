import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_flavor.dart';
import '../localization/translation_controller.dart';
import 'domly_ui.dart';
import 'tutorial_targets.dart';

class DomlyFirstRunTutorial {
  static const _version = 5;

  static String storageKey({
    required AppFlavor flavor,
    required String userId,
  }) =>
      'domly_first_run_tutorial_${flavor.name}_${userId}_v$_version';

  static Future<bool> wasShown({
    required AppFlavor flavor,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(storageKey(flavor: flavor, userId: userId)) ?? false;
  }

  static Future<void> markShown({
    required AppFlavor flavor,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey(flavor: flavor, userId: userId), true);
  }

  static Future<void> show(
    BuildContext context, {
    required AppFlavor flavor,
  }) async {
    final steps = flavor == AppFlavor.pro ? _cleanerSteps : _clientSteps;
    final navigator = Navigator.of(context);
    final title = flavor == AppFlavor.pro
        ? 'Как работать в Domly Pro'
        : 'Как пользоваться Domly';
    final subtitle = flavor == AppFlavor.pro
        ? 'Короткое обучение по заказам, календарю, чату и профилю.'
        : 'Короткое обучение по заказу уборки, оплате и уведомлениям.';
    if (flavor != AppFlavor.pro && navigator.mounted) {
      await navigator.pushNamed('/client/training-order');
      if (!navigator.mounted) {
        return;
      }
    }

    var index = 0;
    String? currentRoute;
    while (index >= 0 && index < steps.length && navigator.mounted) {
      final step = steps[index];
      if (currentRoute != step.routeName) {
        navigator.pushNamedAndRemoveUntil(step.routeName, (_) => false);
        currentRoute = step.routeName;
      }
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!navigator.mounted) {
        return;
      }
      if (step.targetKey != null) {
        for (var attempt = 0;
            attempt < 30 &&
                step.targetKey!.currentContext == null &&
                navigator.mounted;
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (step.targetKey!.currentContext == null) {
          index++;
          continue;
        }
      }
      final targetContext = step.targetKey?.currentContext;
      if (targetContext != null) {
        if (!targetContext.mounted) {
          return;
        }
        // ignore: use_build_context_synchronously
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 260),
          alignment: 0.35,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      final action = await showDialog<_TutorialAction>(
        // ignore: use_build_context_synchronously
        context: navigator.context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        builder: (context) => _DomlyCoachTutorial(
          title: title,
          subtitle: subtitle,
          step: step,
          index: index,
          total: steps.length,
        ),
      );
      if (action == _TutorialAction.back) {
        index--;
      } else if (action == _TutorialAction.next) {
        index++;
      } else {
        return;
      }
    }
  }

  static final _clientSteps = [
    _TutorialStep(
      icon: Icons.auto_awesome,
      title: 'Заказать уборку',
      body:
          'После обучения реальный заказ начинается с этой кнопки. Дальше приложение считает сумму и ищет свободную уборщицу.',
      target: _TutorialTarget.primaryAction,
      routeName: '/client/home',
      targetKey: DomlyTutorialTargets.clientOrderButton,
    ),
    _TutorialStep(
      icon: Icons.calendar_month_outlined,
      title: 'Предварительная запись',
      body:
          'Эта кнопка нужна для заявки до запуска или без немедленной оплаты.',
      target: _TutorialTarget.prelaunch,
      routeName: '/client/home',
      targetKey: DomlyTutorialTargets.clientPrelaunchButton,
    ),
    _TutorialStep(
      icon: Icons.campaign_outlined,
      title: 'Важная информация',
      body: 'Баннеры открывают подробности акций и важных сообщений.',
      target: _TutorialTarget.infoBanner,
      routeName: '/client/home',
      targetKey: DomlyTutorialTargets.clientInfoBanner,
    ),
    _TutorialStep(
      icon: Icons.inventory_2_outlined,
      title: 'Пакеты и калькулятор',
      body: 'Здесь можно выбрать пакет или рассчитать стоимость по квадратуре.',
      target: _TutorialTarget.secondaryActions,
      routeName: '/client/home',
      targetKey: DomlyTutorialTargets.clientPackageActions,
    ),
    _TutorialStep(
      icon: Icons.receipt_long_outlined,
      title: 'Заказы',
      body:
          'Здесь вы увидите активные уборки, покупки пакетов, детали, чат и чек-лист.',
      target: _TutorialTarget.bottomNav,
      routeName: '/client/orders',
      navIndex: 1,
      targetKey: DomlyTutorialTargets.clientBottomNav[1],
    ),
    _TutorialStep(
      icon: Icons.notifications_none,
      title: 'Уведомления',
      body: 'В этой вкладке будут отображаться уведомления.',
      target: _TutorialTarget.bottomNav,
      routeName: '/notifications',
      navIndex: 3,
      targetKey: DomlyTutorialTargets.clientBottomNav[3],
    ),
    _TutorialStep(
      icon: Icons.person_outline,
      title: 'Профиль',
      body:
          'В профиле хранятся адрес, площадь, бонусы, рейтинг и история оплат.',
      target: _TutorialTarget.bottomNav,
      routeName: '/client/profile',
      navIndex: 2,
      targetKey: DomlyTutorialTargets.clientBottomNav[2],
    ),
    _TutorialStep(
      icon: Icons.settings_outlined,
      title: 'Настройки',
      body: 'Здесь вы можете настроить уведомления и заново пройти обучение.',
      target: _TutorialTarget.bottomNav,
      routeName: '/client/settings',
      navIndex: 4,
      targetKey: DomlyTutorialTargets.clientBottomNav[4],
    ),
  ];

  static final _cleanerSteps = [
    _TutorialStep(
      icon: Icons.dashboard_outlined,
      title: 'Главная',
      body:
          'Это главный экран уборщицы: баланс, ближайшие визиты и статус работы.',
      target: _TutorialTarget.bottomNav,
      routeName: '/cleaner/dashboard',
      navIndex: 0,
      targetKey: DomlyTutorialTargets.cleanerBottomNav[0],
    ),
    _TutorialStep(
      icon: Icons.receipt_long_outlined,
      title: 'Новые заказы',
      body:
          'Нажмите «Заказы», чтобы принимать или отклонять новые предложения.',
      target: _TutorialTarget.bottomNav,
      routeName: '/cleaner/orders',
      navIndex: 2,
      targetKey: DomlyTutorialTargets.cleanerBottomNav[2],
    ),
    _TutorialStep(
      icon: Icons.calendar_today_outlined,
      title: 'Календарь',
      body: 'Календарь показывает занятость и подтвержденные визиты по дням.',
      target: _TutorialTarget.bottomNav,
      routeName: '/cleaner/calendar',
      navIndex: 1,
      targetKey: DomlyTutorialTargets.cleanerBottomNav[1],
    ),
    const _TutorialStep(
      icon: Icons.fact_check_outlined,
      title: 'Чек-лист',
      body:
          'В заказе откройте чек-лист и отмечайте выполненные пункты. Клиент увидит отметки.',
      target: _TutorialTarget.middle,
      routeName: '/cleaner/orders',
      navIndex: 2,
    ),
    _TutorialStep(
      icon: Icons.chat_bubble_outline,
      title: 'Чат и связь',
      body: 'Сообщения и звонок доступны из нижнего меню и карточки заказа.',
      target: _TutorialTarget.bottomNav,
      routeName: '/cleaner/messages',
      navIndex: 3,
      targetKey: DomlyTutorialTargets.cleanerBottomNav[3],
    ),
    const _TutorialStep(
      icon: Icons.photo_camera_outlined,
      title: 'Фото и жалобы',
      body:
          'Фотоотчеты и жалобы прикрепляются к заказу, чтобы админ видел историю.',
      target: _TutorialTarget.middle,
      routeName: '/cleaner/orders',
      navIndex: 2,
    ),
    _TutorialStep(
      icon: Icons.person_outline,
      title: 'Профиль',
      body:
          'В профиле заполняются документы, районы, звук уведомлений, выплаты и рейтинг.',
      target: _TutorialTarget.bottomNav,
      routeName: '/cleaner/profile',
      navIndex: 4,
      targetKey: DomlyTutorialTargets.cleanerBottomNav[4],
    ),
  ];
}

enum _TutorialAction { back, next, skip }

enum _TutorialTarget {
  top,
  middle,
  primaryAction,
  prelaunch,
  infoBanner,
  secondaryActions,
  bottomNav,
}

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.target,
    required this.routeName,
    this.navIndex,
    this.targetKey,
  });

  final IconData icon;
  final String title;
  final String body;
  final _TutorialTarget target;
  final String routeName;
  final int? navIndex;
  final GlobalKey? targetKey;
}

class _DomlyCoachTutorial extends StatefulWidget {
  const _DomlyCoachTutorial({
    required this.title,
    required this.subtitle,
    required this.step,
    required this.index,
    required this.total,
  });

  final String title;
  final String subtitle;
  final _TutorialStep step;
  final int index;
  final int total;

  @override
  State<_DomlyCoachTutorial> createState() => _DomlyCoachTutorialState();
}

class _DomlyCoachTutorialState extends State<_DomlyCoachTutorial> {
  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final isLast = widget.index == widget.total - 1;
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final targetRect = _targetRect(size, safe, step);
    final bubbleAbove = targetRect.center.dy > size.height * 0.55;
    final bubbleWidth = (size.width - 32).clamp(280.0, 390.0);
    final bubbleTop = bubbleAbove
        ? (targetRect.top - 246).clamp(safe.top + 12, size.height - 260)
        : (targetRect.bottom + 18).clamp(safe.top + 12, size.height - 260);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CoachOverlayPainter(targetRect),
            ),
          ),
          Positioned.fromRect(
            rect: targetRect,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('tutorial-highlight'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ),
          Positioned(
            left: (size.width - bubbleWidth) / 2,
            top: bubbleTop.toDouble(),
            width: bubbleWidth,
            child: _CoachBubble(
              title: widget.title,
              subtitle: widget.subtitle,
              step: step,
              index: widget.index,
              total: widget.total,
              isLast: isLast,
              bubbleAboveTarget: bubbleAbove,
              onSkip: () => Navigator.pop(context, _TutorialAction.skip),
              onBack: widget.index == 0
                  ? null
                  : () => Navigator.pop(context, _TutorialAction.back),
              onNext: () => Navigator.pop(context, _TutorialAction.next),
            ),
          ),
        ],
      ),
    );
  }

  Rect _targetRect(Size size, EdgeInsets safe, _TutorialStep step) {
    final keyRect = _rectForKey(step.targetKey);
    if (keyRect != null) {
      final inflate = step.target == _TutorialTarget.bottomNav ? 4.0 : 6.0;
      return keyRect.inflate(inflate);
    }
    final target = step.target;
    final horizontal = (size.width * 0.055).clamp(18.0, 28.0);
    final contentWidth = size.width - horizontal * 2;
    final bottomSafe = safe.bottom + 12;
    if (target == _TutorialTarget.bottomNav && widget.step.navIndex != null) {
      final navWidth = contentWidth / 5;
      return Rect.fromLTWH(
        horizontal + navWidth * widget.step.navIndex!,
        size.height - bottomSafe - 82,
        navWidth,
        74,
      );
    }
    switch (target) {
      case _TutorialTarget.top:
        return Rect.fromLTWH(
          horizontal,
          safe.top + 18,
          contentWidth,
          (size.height * 0.18).clamp(110.0, 170.0),
        );
      case _TutorialTarget.middle:
        return Rect.fromLTWH(
          horizontal,
          size.height * 0.30,
          contentWidth,
          (size.height * 0.24).clamp(150.0, 220.0),
        );
      case _TutorialTarget.primaryAction:
        return Rect.fromLTWH(
          horizontal,
          size.height * 0.54,
          contentWidth,
          62,
        );
      case _TutorialTarget.prelaunch:
        return Rect.fromLTWH(
          horizontal,
          size.height * 0.625,
          contentWidth,
          54,
        );
      case _TutorialTarget.infoBanner:
        return Rect.fromLTWH(
          horizontal,
          size.height * 0.69,
          contentWidth,
          88,
        );
      case _TutorialTarget.secondaryActions:
        return Rect.fromLTWH(
          horizontal,
          size.height * 0.58,
          contentWidth,
          102,
        );
      case _TutorialTarget.bottomNav:
        return Rect.fromLTWH(
          horizontal,
          size.height - bottomSafe - 82,
          contentWidth,
          74,
        );
    }
  }

  Rect? _rectForKey(GlobalKey? key) {
    final targetContext = key?.currentContext;
    if (targetContext == null) {
      return null;
    }
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final overlay = context.findRenderObject();
    final origin = overlay is RenderBox && overlay.attached && overlay.hasSize
        ? overlay.localToGlobal(Offset.zero)
        : Offset.zero;
    return (renderObject.localToGlobal(Offset.zero) - origin) &
        renderObject.size;
  }
}

class _CoachBubble extends StatelessWidget {
  const _CoachBubble({
    required this.title,
    required this.subtitle,
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.bubbleAboveTarget,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  final String title;
  final String subtitle;
  final _TutorialStep step;
  final int index;
  final int total;
  final bool isLast;
  final bool bubbleAboveTarget;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!bubbleAboveTarget) const _CoachArrow(pointsDown: false),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DomlyIconBadge(
                    icon: step.icon,
                    size: 44,
                    colors: const [
                      DomlyColors.primary,
                      DomlyColors.accent,
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title.tr(),
                          style: const TextStyle(
                            color: DomlyColors.foreground,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${index + 1} из $total'.tr(),
                          style: const TextStyle(
                            color: DomlyColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Пропустить'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: onSkip,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                step.body.tr(),
                style: const TextStyle(
                  color: DomlyColors.muted,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(
                  total,
                  (dotIndex) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: dotIndex <= index
                            ? DomlyColors.buttonPrimary
                            : DomlyColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: onSkip,
                    child: Text('Пропустить'.tr()),
                  ),
                  if (onBack != null)
                    TextButton(
                      onPressed: onBack,
                      child: Text('Назад'.tr()),
                    ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DomlyColors.buttonPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: onNext,
                    child: Text(isLast ? 'Понятно'.tr() : 'Далее'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (bubbleAboveTarget) const _CoachArrow(pointsDown: true),
      ],
    );
  }
}

class _CoachArrow extends StatelessWidget {
  const _CoachArrow({required this.pointsDown});

  final bool pointsDown;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: pointsDown ? 3.14159 : 0,
      child: CustomPaint(
        size: const Size(34, 18),
        painter: _CoachArrowPainter(),
      ),
    );
  }
}

class _CoachArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CoachOverlayPainter extends CustomPainter {
  const _CoachOverlayPainter(this.targetRect);

  final Rect targetRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect.inflate(6),
          const Radius.circular(28),
        ),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlayPath,
      Paint()..color = const Color(0xB3000000),
    );
  }

  @override
  bool shouldRepaint(covariant _CoachOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}
