import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../theme/domly_palette.dart';
import 'tutorial_targets.dart';

enum HomeScene {
  empty,
  invoice,
  unpaid,
  failed,
  paid,
  searching,
  assigned,
  cleaning,
  completed,
  cancelled,
  frozen,
  exhausted
}

enum HomeAction {
  packages,
  calculator,
  request,
  cancelPurchase,
  pay,
  retry,
  schedule,
  package,
  usage,
  details,
  reschedule,
  cleaner,
  chat,
  checklist,
  review,
  report,
  cancellation,
  freeze,
  history,
  addons,
  referral
}

class CustomerHomeReference extends StatelessWidget {
  const CustomerHomeReference(
      {super.key,
      required this.scene,
      required this.onAction,
      this.area = '—',
      this.amount = '—',
      this.total = 0,
      this.used = 0,
      this.remaining = 0,
      this.date = '—',
      this.time = '',
      this.freezeDate = '—',
      this.startedAt = '',
      this.cleanerName = '',
      this.cleanerPhotoUrl,
      this.primaryKey,
      this.cardKey,
      this.bookingKey,
      this.navigation});
  final HomeScene scene;
  final void Function(HomeAction) onAction;
  final String area, amount, date, time, freezeDate, startedAt, cleanerName;
  final String? cleanerPhotoUrl;
  final int total, used, remaining;
  final Key? primaryKey, cardKey, bookingKey;
  final Widget? navigation;
  Color get ink => DomlyPalette.foreground(const Color(0xFF082F2B));
  Color get muted => DomlyPalette.foreground(const Color(0xFF667180));

  Widget text(String value,
          {double size = 16, bool bold = false, bool secondary = false}) =>
      Text(value.tr(),
          style: TextStyle(
              color: secondary ? muted : ink,
              fontSize: size,
              height: 1.3,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400));
  Widget gap([double height = 14]) => SizedBox(height: height);
  Widget line() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
          height: 1, color: DomlyPalette.border(const Color(0xFFE1E6E9))));
  Widget info(IconData icon, String label,
          {bool secondary = false, Widget? trailing}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 25, color: ink),
            const SizedBox(width: 16),
            Expanded(child: text(label, secondary: secondary)),
            if (trailing != null) trailing
          ]));
  Widget row(String label, HomeAction action,
          {IconData? icon, String? subtitle}) =>
      InkWell(
          onTap: () => onAction(action),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 25, color: ink),
                  const SizedBox(width: 16)
                ],
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      text(label, size: 15),
                      if (subtitle != null)
                        text(subtitle, size: 12, secondary: true)
                    ])),
                Icon(Icons.chevron_right, size: 20, color: muted)
              ])));
  Widget button(String label, HomeAction action, IconData icon,
          {bool outlined = false, bool primary = true}) =>
      Padding(
          padding: const EdgeInsets.only(top: 14),
          child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  key: primary ? primaryKey : null,
                  onPressed: () => onAction(action),
                  icon: Icon(icon, size: 24),
                  label: Text(label.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: outlined ? ink : Colors.white,
                      backgroundColor: outlined
                          ? Colors.transparent
                          : const Color(0xFFD36842),
                      side: BorderSide(
                          color: outlined ? ink : Colors.transparent),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))))));
  Widget badge(String label, IconData icon, Color bg, Color fg) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.symmetric(vertical: 9),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
              color: DomlyPalette.surface(bg),
              borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: DomlyPalette.foreground(fg)),
            const SizedBox(width: 10),
            Flexible(
                child: Text(label.tr(),
                    style: TextStyle(
                        fontSize: 14, color: DomlyPalette.foreground(fg))))
          ])));
  Widget progress(int count) => HomeVisitProgress(total: total, value: count);
  Widget cleaner() => InkWell(
      onTap: () => onAction(HomeAction.cleaner),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            ClipOval(
                child: SizedBox(
                    width: 52,
                    height: 52,
                    child: cleanerPhotoUrl?.isNotEmpty == true
                        ? Image.network(cleanerPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.person_outline,
                                size: 32,
                                color: ink))
                        : ColoredBox(
                            color:
                                DomlyPalette.surface(const Color(0xFFEAF4EE)),
                            child: Icon(Icons.person_outline,
                                size: 32, color: ink)))),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  text(cleanerName.isEmpty ? 'Исполнитель' : cleanerName,
                      bold: true),
                  text(
                      scene == HomeScene.assigned
                          ? 'Ваш исполнитель'
                          : 'Исполнитель',
                      size: 14,
                      secondary: true)
                ])),
            Icon(Icons.chevron_right, size: 20, color: muted)
          ])));
  Widget panel(List<Widget> children) => Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
          color: DomlyPalette.surface(Colors.white),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: DomlyPalette.border(const Color(0xFFE1E6E9))),
          boxShadow: const [
            BoxShadow(
                color: Color(0x06235B44), blurRadius: 20, offset: Offset(0, 5))
          ]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children));

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);
    const greenBg = Color(0xFFE9F7EC),
        green = Color(0xFF246E40),
        amberBg = Color(0xFFFFF5DF),
        amber = Color(0xFFAA6900);
    final titles = [
      'Начните с чистого дома',
      'Заявка отправлена',
      'Пакет ждёт оплаты',
      'Не удалось оплатить',
      'Запланируйте уборку',
      'Подбираем исполнителя',
      'Ваша уборка назначена',
      'Наводим чистоту',
      'Дома снова чисто',
      'Уборка отменена',
      'Пакет на паузе',
      'Продолжим заботу о доме?'
    ];
    final heading = scene == HomeScene.cleaning || scene == HomeScene.cancelled
        ? 'Текущая уборка'
        : scene == HomeScene.completed
            ? 'Завершённая уборка'
            : scene == HomeScene.frozen
                ? 'Ваш пакет уборок'
                : scene == HomeScene.exhausted
                    ? 'Пакет уборок'
                    : 'Следующая уборка';
    final children = <Widget>[
      Text(heading.tr().toUpperCase(),
          style: TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600)),
      gap(10),
      text(titles[scene.index], size: 28, bold: true),
    ];
    switch (scene) {
      case HomeScene.empty:
        children.addAll([
          gap(10),
          text('Подберите уборку под вашу квартиру.', secondary: true),
          gap(30),
          info(Icons.home_outlined, '${'Квартира'.tr()} · $area м²'),
          button('Выбрать пакет', HomeAction.packages,
              Icons.calendar_today_outlined),
          line(),
          row('Рассчитать стоимость', HomeAction.calculator,
              icon: Icons.calculate_outlined)
        ]);
      case HomeScene.invoice:
        children.addAll([
          badge('Счёт готовится', Icons.access_time, amberBg, amber),
          text(
              'Менеджер выставит счёт. Мы сообщим, когда можно будет оплатить.',
              secondary: true),
          gap(16),
          info(Icons.home_outlined, '${'Квартира'.tr()} · $area м²'),
          button('Посмотреть заявку', HomeAction.request,
              Icons.receipt_long_outlined,
              outlined: true),
          line(),
          row('Отменить заявку', HomeAction.cancelPurchase)
        ]);
      case HomeScene.unpaid:
        children.addAll([
          badge('Не оплачен', Icons.access_time, amberBg, amber),
          text('${'К оплате'.tr()} $amount', size: 23, bold: true),
          gap(8),
          text('Оплатите счёт, чтобы выбрать дату уборки.', secondary: true),
          gap(6),
          info(Icons.home_outlined, '$area м²',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today_outlined, color: ink, size: 22),
                const SizedBox(width: 8),
                text('$total ${'уборки'.tr()}', size: 14)
              ])),
          button('Оплатить', HomeAction.pay, Icons.credit_card),
          line(),
          row('Отменить покупку', HomeAction.cancelPurchase)
        ]);
      case HomeScene.failed:
        children.addAll([
          badge('Счёт отменён', Icons.error_outline, const Color(0xFFFFEEE7),
              const Color(0xFFCA3B1C)),
          text('Оплата не подтверждена. Выберите способ оплаты повторно.',
              secondary: true),
          gap(8),
          text('${'К оплате'.tr()} $amount', size: 23, bold: true),
          info(Icons.home_outlined, '${'Квартира'.tr()} · $area м²'),
          button('Попробовать снова', HomeAction.retry, Icons.credit_card),
          line(),
          row('Отменить покупку', HomeAction.cancelPurchase)
        ]);
      case HomeScene.paid:
        children.addAll([
          badge('Пакет оплачен', Icons.check_circle_outline, greenBg, green),
          info(Icons.home_outlined, '$area м²',
              trailing: Flexible(
                  child: Text('${'Осталось'.tr()} $remaining ${'уборки'.tr()}',
                      style: TextStyle(color: ink, fontSize: 14)))),
          button('Выбрать дату и время', HomeAction.schedule,
              Icons.calendar_today_outlined),
          gap(8),
          text('Исполнителя назначим после выбора даты.',
              size: 12, secondary: true),
          line(),
          row('Мой пакет', HomeAction.package,
              icon: Icons.receipt_long_outlined),
          line(),
          row('${'Использовано'.tr()} $used ${'из'.tr()} $total ${'уборок'.tr()}',
              HomeAction.usage,
              icon: Icons.pie_chart_outline),
          progress(used),
          gap(6)
        ]);
      case HomeScene.searching:
        children.addAll([
          badge('Поиск', Icons.person_search_outlined, greenBg, green),
          info(Icons.calendar_today_outlined, date),
          text(time, secondary: true),
          info(Icons.home_outlined, '${'Квартира'.tr()} · $area м²'),
          text('Дата выбрана. Сообщим, когда назначим исполнителя.',
              secondary: true),
          button(
              'Детали уборки', HomeAction.details, Icons.receipt_long_outlined),
          line(),
          row('Изменить дату', HomeAction.reschedule)
        ]);
      case HomeScene.assigned:
        children.addAll([
          badge('Подтверждена', Icons.check_circle, greenBg, green),
          info(Icons.calendar_today_outlined, date),
          info(Icons.access_time, '$time · $area м²'),
          line(),
          cleaner(),
          button('Детали уборки', HomeAction.details,
              Icons.calendar_today_outlined),
          row('Написать исполнителю', HomeAction.chat,
              icon: Icons.chat_bubble_outline)
        ]);
      case HomeScene.cleaning:
        children.addAll([
          badge('В процессе', Icons.settings_outlined, greenBg, green),
          info(Icons.calendar_today_outlined, '$date · $area м²'),
          line(),
          cleaner(),
          if (startedAt.isNotEmpty)
            info(Icons.access_time, '${'Уборка началась в'.tr()} $startedAt',
                secondary: true),
          button('Посмотреть чек-лист', HomeAction.checklist,
              Icons.format_list_bulleted),
          row('Чат с исполнителем', HomeAction.chat,
              icon: Icons.chat_bubble_outline)
        ]);
      case HomeScene.completed:
        children.addAll([
          badge('Уборка завершена', Icons.check_circle, greenBg, green),
          info(Icons.calendar_today_outlined, '$date · $area м²'),
          line(),
          info(Icons.description_outlined,
              'Посмотрите отчёт и поделитесь впечатлениями.',
              secondary: true),
          button('Оценить уборку', HomeAction.review, Icons.star_border),
          row('Посмотреть отчёт', HomeAction.report,
              icon: Icons.description_outlined)
        ]);
      case HomeScene.cancelled:
        children.addAll([
          badge('Отменена', Icons.block, const Color(0xFFEEF0F3),
              const Color(0xFF4B5563)),
          info(Icons.calendar_today_outlined, '$date · $time', secondary: true),
          line(),
          info(Icons.description_outlined,
              'Посмотрите детали отмены и выберите новую дату.',
              secondary: true),
          gap(16),
          button('Запланировать уборку', HomeAction.schedule,
              Icons.calendar_today_outlined),
          row('Детали отмены', HomeAction.cancellation,
              icon: Icons.receipt_long_outlined)
        ]);
      case HomeScene.frozen:
        children.addAll([
          badge('Заморожен', Icons.ac_unit, const Color(0xFFE6F7FF),
              const Color(0xFF12618C)),
          info(Icons.calendar_today_outlined,
              '${'Заморозка до'.tr()} $freezeDate'),
          line(),
          info(Icons.layers_outlined,
              '${'Осталось'.tr()} $remaining ${'уборки'.tr()}',
              trailing: SizedBox(width: 108, child: progress(remaining))),
          gap(12),
          info(Icons.access_time, 'Срок пакета продлевается на дни заморозки.',
              secondary: true),
          button('Управлять заморозкой', HomeAction.freeze,
              Icons.settings_outlined),
          row('Подробнее о пакете', HomeAction.package,
              icon: Icons.info_outline)
        ]);
      case HomeScene.exhausted:
        children.addAll([
          badge('Пакет использован', Icons.layers_outlined,
              const Color(0xFFEEF0F3), const Color(0xFF4B5563)),
          info(Icons.check_circle_outline,
              '${'Выполнено'.tr()} $used ${'из'.tr()} $total ${'уборок'.tr()}'),
          progress(used),
          line(),
          info(Icons.calendar_today_outlined,
              'Выберите новый пакет для следующих уборок.',
              secondary: true),
          gap(12),
          button(
              'Выбрать новый пакет', HomeAction.packages, Icons.card_giftcard),
          row('История уборок', HomeAction.history,
              icon: Icons.receipt_long_outlined)
        ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KeyedSubtree(key: cardKey, child: panel(children)),
      if (navigation != null) navigation!,
      if ([HomeScene.searching, HomeScene.assigned, HomeScene.cleaning]
          .contains(scene)) ...[
        gap(10),
        KeyedSubtree(
            key: bookingKey,
            child: panel([
              info(Icons.calendar_today_outlined,
                  '${'Осталось'.tr()} $remaining ${'уборки'.tr()}'),
              text('Доступно для записи на другую дату',
                  size: 13, secondary: true),
              button(
                  remaining > 0 ? 'Заказать уборку' : 'Выбрать новый пакет',
                  remaining > 0 ? HomeAction.schedule : HomeAction.packages,
                  Icons.add_task_outlined,
                  primary: false),
              gap(6),
            ])),
      ],
      if (scene == HomeScene.completed) ...[
        gap(10),
        panel([
          row('${'Осталось'.tr()} $remaining ${'уборки'.tr()}',
              HomeAction.package,
              icon: Icons.calendar_today_outlined,
              subtitle:
                  '${'Использовано'.tr()} $used ${'из'.tr()} $total ${'уборок'.tr()}'),
          progress(used),
          line(),
          row('Запланировать следующую', HomeAction.schedule,
              icon: Icons.event_repeat)
        ])
      ]
    ]);
  }
}

class HomeVisitProgress extends StatelessWidget {
  const HomeVisitProgress(
      {super.key, required this.total, required this.value});
  final int total, value;
  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final segments = total.clamp(1, 12);
    final ratio = (value / total).clamp(0.0, 1.0);
    return Semantics(
        label: '${'Использовано'.tr()}: $value / $total',
        child: Row(
            children: List.generate(
                segments,
                (i) => Expanded(
                    child: Padding(
                        padding:
                            EdgeInsets.only(right: i == segments - 1 ? 0 : 6),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                                minHeight: 10,
                                value: (ratio * segments - i).clamp(0.0, 1.0),
                                color: const Color(0xFF439D70),
                                backgroundColor: DomlyPalette.surface(
                                    const Color(0xFFE4E7EB)))))))));
  }
}

class HomeReferenceShortcuts extends StatelessWidget {
  const HomeReferenceShortcuts({super.key, required this.onAction});
  final void Function(HomeAction) onAction;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: _tile(
                'Дополнительные услуги',
                'Химчистка, мытьё окон и многое другое',
                Icons.auto_awesome_outlined,
                HomeAction.addons)),
        const SizedBox(width: 10),
        Expanded(
            child: _tile('Пригласить друга', 'Подарите друзьям чистый дом',
                Icons.card_giftcard, HomeAction.referral))
      ]);
  Widget _tile(
          String title, String subtitle, IconData icon, HomeAction action) =>
      Material(
          color: DomlyPalette.surface(Colors.white),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onAction(action),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(children: [
                    Icon(icon,
                        size: 26,
                        color:
                            DomlyPalette.foreground(const Color(0xFF082F2B))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title.tr(),
                              style: TextStyle(
                                  color: DomlyPalette.foreground(
                                      const Color(0xFF082F2B)),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(subtitle.tr(),
                              style: TextStyle(
                                  color: DomlyPalette.foreground(
                                      const Color(0xFF667180)),
                                  fontSize: 10,
                                  height: 1.35))
                        ])),
                    Icon(Icons.chevron_right,
                        size: 14,
                        color: DomlyPalette.foreground(const Color(0xFF667180)))
                  ]))));
}

class HomeReferenceNavigation extends StatelessWidget {
  const HomeReferenceNavigation({super.key, required this.onNavigate});
  final void Function(String) onNavigate;
  @override
  Widget build(BuildContext context) {
    const labels = ['Главная', 'Заказы', 'Профиль', 'Уведомления', 'Настройки'];
    const routes = [
      '/client/home',
      '/client/orders',
      '/client/profile',
      '/notifications',
      '/client/settings'
    ];
    const icons = [
      Icons.home_outlined,
      Icons.assignment_outlined,
      Icons.person_outline,
      Icons.notifications_none,
      Icons.settings_outlined
    ];
    return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
                color: DomlyPalette.surface(Colors.white),
                borderRadius: BorderRadius.circular(16)),
            child: Row(
                children: List.generate(
                    5,
                    (i) => Expanded(
                        child: InkWell(
                            key:
                                DomlyTutorialTargets.navigationKeys(context)[i],
                            onTap: () => onNavigate(routes[i]),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                    color: i == 0
                                        ? DomlyPalette.surface(
                                            const Color(0xFFFFF2EC))
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icons[i],
                                          size: 25,
                                          color: i == 0
                                              ? const Color(0xFFE9602E)
                                              : DomlyPalette.foreground(
                                                  const Color(0xFF667180))),
                                      const SizedBox(height: 4),
                                      Text(labels[i].tr(),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: i == 0
                                                  ? const Color(0xFFE9602E)
                                                  : DomlyPalette.foreground(
                                                      const Color(0xFF667180))))
                                    ]))))))));
  }
}
