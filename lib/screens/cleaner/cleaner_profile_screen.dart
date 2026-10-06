import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../services/address_search_service.dart';
import '../../services/app_config_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/offer_alert_sound.dart';
import '../../ui/address_search_sheet.dart';
import '../../ui/domly_ui.dart';
import '../../ui/first_run_tutorial.dart';
import 'cleaner_bonus_screen.dart';
import 'cleaner_order_history_screen.dart';
import 'cleaner_rating_screen.dart';
import 'cleaner_service_area_notice.dart';
import '../../localization/translation_controller.dart';

class CleanerProfileScreen extends StatelessWidget {
  const CleanerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;
    final config = AppConfigService.instance;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: config.workerBonusConfigStream(),
      builder: (context, configSnap) {
        return StreamBuilder<Map<String, dynamic>?>(
          stream: data.cleanerProfileStream(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const DomlyShell(
                bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: DomlyEmptyStateCard(
                        title: 'Не удалось загрузить профиль',
                        subtitle: 'Обновите экран и попробуйте снова.',
                        icon: Icons.error_outline,
                      ),
                    ),
                  ),
                ),
              );
            }
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const DomlyShell(
                bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
                child: SafeArea(
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        DomlyColors.buttonPrimary,
                      ),
                    ),
                  ),
                ),
              );
            }
            final profile = snap.data ?? <String, dynamic>{};
            final menu = ((profile['menu'] ?? []) as List).cast<Map>();
            final rating = '${profile['rating'] ?? 0}';
            final workStartDate = _workStartDateText(profile);
            final statusLabel =
                (profile['cleanerStatusLabel'] ?? _loyaltyLevel(profile))
                    .toString();
            final nextStatus = (profile['nextCleanerStatus'] ?? '').toString();
            final progressText =
                (profile['cleanerStatusProgressText'] ?? '').toString();
            final verificationStatus =
                (profile['verificationStatus'] ?? 'draft')
                    .toString()
                    .toLowerCase();
            final progress =
                ((profile['cleanerStatusProgress'] as num?)?.toDouble() ?? 0)
                    .clamp(0.0, 1.0);
            final hasServiceAreas = cleanerHasServiceAreas(profile);

            return DomlyShell(
              bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 4),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          DomlyHeader(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: domlyTopIconButton(
                                    icon: Icons.arrow_back,
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Профиль уборщицы'.tr(),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Личные данные и карьера'.tr(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xCCFFFFFF),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _initials((profile['name'] ?? 'Исполнитель')
                                        .toString()),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  (profile['name'] ?? 'Исполнитель').toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    DomlyStatusChip(
                                        label: statusLabel,
                                        color: Colors.white),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.star,
                                        size: 16, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (progressText.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    progressText,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xD9FFFFFF),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -18),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const CleanerOrderHistoryScreen(),
                                            ),
                                          ),
                                          child: _statCard(
                                            value:
                                                '${profile['jobsCount'] ?? 0}',
                                            label: 'История заказов',
                                            icon: Icons.verified_outlined,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const CleanerRatingScreen(),
                                            ),
                                          ),
                                          child: _statCard(
                                            value: rating,
                                            label: 'Рейтинг',
                                            icon: Icons.star,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const CleanerBonusScreen(),
                                            ),
                                          ),
                                          child: _statCard(
                                            value: _bonusDisplayValue(profile),
                                            label: 'Бонусы',
                                            icon: Icons.card_giftcard_outlined,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (!hasServiceAreas) ...[
                                    CleanerServiceAreaNotice(
                                      onPressed: () => _openProfileEditor(
                                        context,
                                        data,
                                        profile,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  _profileSection(
                                    title: 'Личная информация',
                                    children: [
                                      _menuTile(Icons.badge_outlined, 'ФИО *',
                                          (profile['name'] ?? '').toString()),
                                      _divider(),
                                      _menuTile(Icons.phone_outlined, 'Телефон',
                                          (profile['phone'] ?? '').toString()),
                                      _divider(),
                                      _menuTile(
                                          Icons.home_outlined,
                                          'Домашний адрес *',
                                          (profile['homeAddress'] ?? '')
                                              .toString()),
                                      _divider(),
                                      _menuTile(
                                        Icons.map_outlined,
                                        'Рабочие районы *',
                                        _formatServiceAreas(profile),
                                      ),
                                      _divider(),
                                      _menuTile(
                                          Icons.contact_phone_outlined,
                                          'Доп. номер знакомого *',
                                          (profile['emergencyContactPhone'] ??
                                                  '')
                                              .toString()),
                                      _divider(),
                                      _menuTile(
                                          Icons.people_alt_outlined,
                                          'Кем приходится *',
                                          (profile['emergencyContactRelation'] ??
                                                  '')
                                              .toString()),
                                      _divider(),
                                      _menuTile(Icons.mail_outline, 'Email',
                                          (profile['email'] ?? '').toString()),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  DomlySecondaryButton(
                                    label: 'Сменить рабочие районы',
                                    onPressed: () => _openProfileEditor(
                                      context,
                                      data,
                                      profile,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DomlySecondaryButton(
                                    label: 'Редактировать личные данные',
                                    onPressed: () => _openProfileEditor(
                                        context, data, profile),
                                  ),
                                  const SizedBox(height: 10),
                                  DomlySecondaryButton(
                                    label: 'Звук новых заказов',
                                    icon: Icons.volume_up_outlined,
                                    onPressed: () => _openSoundSettingsSheet(
                                      context,
                                      data,
                                      profile,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DomlyPrimaryButton(
                                    label: 'Вывод средств',
                                    icon: Icons.account_balance_wallet_outlined,
                                    onPressed: () => _openPayoutRequestSheet(
                                      context,
                                      data,
                                      profile,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DomlyCard(
                                    color: DomlyColors.backgroundSoft,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Icon(
                                              Icons.calendar_today_outlined,
                                              color: DomlyColors.buttonPrimary),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Дата начала работы'.tr(),
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    color: DomlyColors.muted),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                workStartDate,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: DomlyColors.foreground,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  DomlyCard(
                                    color: DomlyColors.backgroundSoft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Карьерный статус'.tr(),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: DomlyColors.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          statusLabel,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: DomlyColors.foreground,
                                          ),
                                        ),
                                        if (nextStatus.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            child: LinearProgressIndicator(
                                              minHeight: 8,
                                              value: progress,
                                              backgroundColor:
                                                  DomlyColors.border,
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                          Color>(
                                                      DomlyColors.primary),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            progressText,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: DomlyColors.muted,
                                            ),
                                          ),
                                        ] else
                                          Padding(
                                            padding: EdgeInsets.only(top: 8),
                                            child: Text(
                                              'Максимальный статус достигнут.'
                                                  .tr(),
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: DomlyColors.muted,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _profileSection(
                                    title: 'Настройки',
                                    children: [
                                      ListTile(
                                        onTap: () {
                                          final scope = AppScope.of(context);
                                          DomlyFirstRunTutorial.show(
                                            context,
                                            flavor: scope.config.flavor,
                                          );
                                        },
                                        leading: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: DomlyColors.backgroundSoft,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.touch_app_outlined,
                                            color: DomlyColors.buttonPrimary,
                                          ),
                                        ),
                                        title: Text('Пройти обучение'.tr()),
                                        subtitle: Text(
                                          'Покажем кнопки и основные действия'
                                              .tr(),
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                          color: DomlyColors.muted,
                                        ),
                                      ),
                                      if (menu.isNotEmpty) _divider(),
                                      ...menu.map(
                                        (item) => Column(
                                          children: [
                                            ListTile(
                                              onTap: () => _showMenuDetails(
                                                context,
                                                (item['title'] ?? '')
                                                    .toString(),
                                                (item['subtitle'] ?? '')
                                                    .toString(),
                                              ),
                                              leading: Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: DomlyColors
                                                      .backgroundSoft,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
                                                    Icons.settings_outlined,
                                                    color: DomlyColors
                                                        .buttonPrimary),
                                              ),
                                              title: Text((item['title'] ?? '')
                                                  .toString()),
                                              subtitle: Text(
                                                  (item['subtitle'] ?? '')
                                                      .toString()),
                                              trailing: const Icon(
                                                  Icons.chevron_right,
                                                  color: DomlyColors.muted),
                                            ),
                                            if (item != menu.last) _divider(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  DomlyPrimaryButton(
                                    label: verificationStatus == 'approved'
                                        ? 'Данные верификации'
                                        : 'Заполнить верификацию',
                                    onPressed: () => Navigator.pushNamed(
                                      context,
                                      '/cleaner/verification',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DomlySecondaryButton(
                                    label: 'Выйти из аккаунта',
                                    foregroundColor: DomlyColors.danger,
                                    onPressed: () async {
                                      final navigator = Navigator.of(context);
                                      await AppScope.of(context)
                                          .authController
                                          .signOut();
                                      if (!context.mounted) return;
                                      navigator.pushNamedAndRemoveUntil(
                                        '/auth',
                                        (_) => false,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  DomlySecondaryButton(
                                    label: 'Удалить аккаунт',
                                    foregroundColor: DomlyColors.danger,
                                    onPressed: () => _deleteAccount(context),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Удалить аккаунт?'.tr()),
            content: Text(
              'Аккаунт исполнителя будет удалён с этого устройства. Это действие нельзя отменить.'
                  .tr(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('Отмена'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Удалить'.tr()),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    try {
      await AppScope.of(context).authController.deleteAccount();
      if (!context.mounted) return;
      navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
    } catch (error) {
      if (!context.mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось удалить аккаунт',
        subtitle: error.toString(),
        type: DomlySnackBarType.error,
      );
    }
  }

  Widget _statCard(
      {required String value, required String label, required IconData icon}) {
    return DomlyCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Icon(icon, size: 22, color: DomlyColors.buttonPrimary),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileSection(
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.muted,
            ),
          ),
        ),
        DomlyCard(padding: EdgeInsets.zero, child: Column(children: children)),
      ],
    );
  }

  Widget _menuTile(IconData icon, String title, String value) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: DomlyColors.backgroundSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: DomlyColors.buttonPrimary),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: DomlyColors.border);

  void _showMenuDetails(BuildContext context, String title, String subtitle) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle.isEmpty ? 'Данные будут добавлены позже.' : subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: DomlyColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                DomlyPrimaryButton(
                  label: 'Понятно',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSoundSettingsSheet(
    BuildContext context,
    FirestoreDataService data,
    Map<String, dynamic> profile,
  ) async {
    var enabled = profile['offerAlertSoundEnabled'] != false;
    var volume = ((profile['offerAlertSoundVolume'] as num?)?.toDouble() ?? 1)
        .clamp(0.0, 1.0);
    var soundIndex =
        ((profile['offerAlertSoundIndex'] as num?)?.toInt() ?? 0).clamp(0, 20);
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Future<void> save() async {
              setModalState(() => saving = true);
              try {
                await data.updateCleanerProfile({
                  'offerAlertSoundEnabled': enabled,
                  'offerAlertSoundVolume': volume,
                  'offerAlertSoundIndex': soundIndex,
                  'offerAlertSoundName':
                      OfferAlertSound.soundOptions[soundIndex],
                });
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
              } catch (error) {
                if (!sheetContext.mounted) return;
                showDomlySnackBar(
                  sheetContext,
                  title: 'Не удалось сохранить звук',
                  subtitle: '$error',
                  type: DomlySnackBarType.error,
                );
              } finally {
                if (sheetContext.mounted) {
                  setModalState(() => saving = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 12,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Звук новых заказов'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: enabled,
                        onChanged: (value) {
                          setModalState(() => enabled = value);
                          if (!value) {
                            OfferAlertSound.stop();
                          }
                        },
                        title: Text('Включить звук'.tr()),
                        subtitle: Text('Сигнал при новом заказе'.tr()),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Громкость: ${(volume * 100).round()}%'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DomlyColors.foreground,
                        ),
                      ),
                      Slider(
                        value: volume,
                        min: 0,
                        max: 1,
                        divisions: 10,
                        label: '${(volume * 100).round()}%',
                        onChanged: enabled
                            ? (value) => setModalState(() => volume = value)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: soundIndex,
                        decoration: const InputDecoration(labelText: 'Мелодия'),
                        items: [
                          for (var i = 0;
                              i < OfferAlertSound.soundOptions.length;
                              i += 1)
                            DropdownMenuItem<int>(
                              value: i,
                              child: Text(
                                '${i + 1}. ${OfferAlertSound.soundOptions[i]}',
                              ),
                            ),
                        ],
                        onChanged: enabled
                            ? (value) => setModalState(
                                  () => soundIndex = value ?? soundIndex,
                                )
                            : null,
                      ),
                      const SizedBox(height: 14),
                      DomlySecondaryButton(
                        label: 'Проверить звук',
                        icon: Icons.play_arrow,
                        onPressed: enabled
                            ? () {
                                OfferAlertSound.stop();
                                OfferAlertSound.start(
                                  enabled: enabled,
                                  volume: volume,
                                  soundIndex: soundIndex,
                                );
                                Future<void>.delayed(
                                  const Duration(seconds: 3),
                                  OfferAlertSound.stop,
                                );
                              }
                            : null,
                      ),
                      const SizedBox(height: 10),
                      DomlyPrimaryButton(
                        label: 'Сохранить',
                        isLoading: saving,
                        onPressed: saving ? null : save,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    OfferAlertSound.stop();
  }

  Future<void> _openPayoutRequestSheet(
    BuildContext context,
    FirestoreDataService data,
    Map<String, dynamic> profile,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final kaspiController = TextEditingController(
      text: (profile['kaspiPhone'] ?? profile['phone'] ?? '').toString(),
    );
    final amountController = TextEditingController();
    final availableAmount =
        ((profile['availableWithdrawalAmount'] as num?)?.toInt() ?? 0)
            .clamp(0, 1 << 31)
            .toInt();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          var submitting = false;
          String? errorText;
          return StatefulBuilder(
            builder: (sheetContext, setModalState) {
              Future<void> submit() async {
                final phone = kaspiController.text.trim();
                final amountText =
                    amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
                final amount = int.tryParse(amountText) ?? 0;
                if (phone.isEmpty || amount <= 0) {
                  setModalState(() {
                    errorText = phone.isEmpty
                        ? 'Введите номер Kaspi.'
                        : 'Введите сумму вывода больше 0.';
                  });
                  return;
                }
                if (amount > availableAmount) {
                  setModalState(() {
                    errorText = 'Можно вывести не больше $availableAmount ₸.';
                  });
                  return;
                }
                setModalState(() {
                  submitting = true;
                  errorText = null;
                });
                try {
                  await data.requestCleanerManualPayout(
                    kaspiPhone: phone,
                    amount: amount,
                  );
                  if (!sheetContext.mounted) {
                    return;
                  }
                  Navigator.pop(sheetContext);
                  messenger.showSnackBar(
                    SnackBar(
                      content:
                          Text('Заявка на вывод отправлена в админку'.tr()),
                    ),
                  );
                } catch (error) {
                  if (!sheetContext.mounted) {
                    return;
                  }
                  setModalState(() {
                    submitting = false;
                    errorText = _cleanErrorText(error);
                  });
                }
              }

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 8,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Вывод средств'.tr(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Укажите номер Kaspi и сумму. Заявка уйдет администратору на одобрение.'
                              .tr(),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: DomlyColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Доступно к выводу: $availableAmount ₸'.tr(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: kaspiController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Номер Kaspi *',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Сумма к выводу, ₸ *',
                            prefixIcon:
                                Icon(Icons.account_balance_wallet_outlined),
                          ),
                          onSubmitted: (_) => submit(),
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorText!,
                            style: const TextStyle(
                              color: DomlyColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        DomlyPrimaryButton(
                          label: submitting ? 'Отправляем...' : 'Отправить',
                          isLoading: submitting,
                          onPressed: submitting ? null : submit,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      kaspiController.dispose();
      amountController.dispose();
    }
  }

  String _cleanErrorText(Object error) {
    final text = error.toString();
    if (text.startsWith('Bad state: ')) {
      return text.replaceFirst('Bad state: ', '');
    }
    if (text.startsWith('Exception: ')) {
      return text.replaceFirst('Exception: ', '');
    }
    return text;
  }

  Future<void> _openProfileEditor(
    BuildContext context,
    FirestoreDataService data,
    Map<String, dynamic> profile,
  ) async {
    final zones = await data.serviceZonesStream().first;
    final clusters = await data.clustersStream().first;
    final houses = await data.housesStream().first;
    if (!context.mounted) {
      return;
    }
    final zoneOptions = <Map<String, String>>[];
    final zoneIds = <String>{};
    final zoneTitleById = <String, String>{};
    final areaOptions = <String>{};
    if (zones.isNotEmpty) {
      for (final zone in zones) {
        final id = (zone['id'] ?? '').toString().trim();
        final title = (zone['title'] ?? zone['name'] ?? id).toString().trim();
        if (id.isNotEmpty && title.isNotEmpty && !zoneIds.contains(id)) {
          zoneIds.add(id);
          zoneTitleById[id] = title;
          zoneOptions.add({'id': id, 'title': title});
        }
      }
    } else {
      for (final cluster in clusters) {
        for (final value in [
          cluster['name'],
          cluster['residentialComplex'],
          cluster['serviceArea'],
        ]) {
          final text = (value ?? '').toString().trim();
          if (text.isNotEmpty) {
            areaOptions.add(text);
          }
        }
      }
      for (final house in houses) {
        for (final value in [
          house['serviceArea'],
          house['clusterName'],
        ]) {
          final text = (value ?? '').toString().trim();
          if (text.isNotEmpty) {
            areaOptions.add(text);
          }
        }
      }
      if (areaOptions.isEmpty) {
        for (final house in houses) {
          for (final value in [
            house['residentialComplex'],
            house['address'],
          ]) {
            final text = (value ?? '').toString().trim();
            if (text.isNotEmpty) {
              areaOptions.add(text);
            }
          }
        }
      }
    }
    for (final item in ((profile['serviceAreas'] as List?) ?? const [])) {
      final text = item.toString().trim();
      if (text.isNotEmpty && zones.isEmpty) {
        areaOptions.add(text);
      }
    }
    zoneOptions.sort((a, b) => (a['title'] ?? '').compareTo(b['title'] ?? ''));
    final sortedAreaOptions = areaOptions.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selectedServiceAreaIds =
        ((profile['serviceAreaIds'] as List?) ?? const [])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet();
    final selectedServiceAreas =
        ((profile['serviceAreas'] as List?) ?? const [])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet();
    if (zones.isNotEmpty && selectedServiceAreaIds.isEmpty) {
      for (final selectedTitle in selectedServiceAreas) {
        for (final option in zoneOptions) {
          if ((option['title'] ?? '').toLowerCase() ==
              selectedTitle.toLowerCase()) {
            selectedServiceAreaIds.add(option['id'] ?? '');
          }
        }
      }
      selectedServiceAreaIds.removeWhere((item) => item.isEmpty);
    }
    final nameController =
        TextEditingController(text: (profile['name'] ?? '').toString());
    final addressController =
        TextEditingController(text: (profile['homeAddress'] ?? '').toString());
    final emergencyPhoneController = TextEditingController(
      text: (profile['emergencyContactPhone'] ?? '').toString(),
    );
    final emergencyRelationController = TextEditingController(
      text: (profile['emergencyContactRelation'] ?? '').toString(),
    );
    final houseAddressSuggestions = _houseAddressSuggestions(houses);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var saving = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Личные данные'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Все поля обязательны для работы аккаунта исполнителя.'
                          .tr(),
                      style: TextStyle(fontSize: 13, color: DomlyColors.muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(labelText: 'ФИО *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'Домашний адрес *',
                        hintText: 'Введите адрес или нажмите поиск',
                        suffixIcon: IconButton(
                          onPressed: () async {
                            final selected = await showAddressSearchSheet(
                              context,
                              initialQuery: addressController.text.trim(),
                              title: 'Выберите домашний адрес',
                              seedSuggestions: houseAddressSuggestions,
                            );
                            if (selected == null) {
                              return;
                            }
                            addressController.text = selected.fullText;
                          },
                          icon: const Icon(Icons.search),
                          tooltip: 'Найти адрес',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Рабочие районы *'.tr(),
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (zoneOptions.isEmpty && sortedAreaOptions.isEmpty)
                      Text(
                        'Сначала добавьте районы или дома в админке.'.tr(),
                        style:
                            TextStyle(fontSize: 13, color: DomlyColors.muted),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (zoneOptions.isNotEmpty)
                            for (final option in zoneOptions)
                              ChoiceChip(
                                label: Text(option['title'] ?? ''),
                                selected: selectedServiceAreaIds
                                    .contains(option['id']),
                                onSelected: (selected) {
                                  setModalState(() {
                                    final id = option['id'] ?? '';
                                    if (selected) {
                                      selectedServiceAreaIds.add(id);
                                    } else {
                                      selectedServiceAreaIds.remove(id);
                                    }
                                  });
                                },
                              )
                          else
                            for (final area in sortedAreaOptions)
                              ChoiceChip(
                                label: Text(area),
                                selected: selectedServiceAreas.contains(area),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      selectedServiceAreas.add(area);
                                    } else {
                                      selectedServiceAreas.remove(area);
                                    }
                                  });
                                },
                              ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emergencyPhoneController,
                      style: const TextStyle(fontSize: 15),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Доп. номер знакомого *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emergencyRelationController,
                      style: const TextStyle(fontSize: 15),
                      decoration:
                          const InputDecoration(labelText: 'Кем приходится *'),
                    ),
                    const SizedBox(height: 16),
                    DomlyPrimaryButton(
                      label: 'Сохранить',
                      isLoading: saving,
                      onPressed: saving
                          ? null
                          : () async {
                              if (nameController.text.trim().isEmpty ||
                                  addressController.text.trim().isEmpty ||
                                  (zoneOptions.isNotEmpty
                                      ? selectedServiceAreaIds.isEmpty
                                      : selectedServiceAreas.isEmpty) ||
                                  emergencyPhoneController.text
                                      .trim()
                                      .isEmpty ||
                                  emergencyRelationController.text
                                      .trim()
                                      .isEmpty) {
                                showDomlySnackBar(
                                  context,
                                  title: 'Заполните все поля',
                                  subtitle:
                                      'Для сохранения нужны личные данные и рабочие районы.',
                                  type: DomlySnackBarType.error,
                                );
                                return;
                              }
                              setModalState(() => saving = true);
                              try {
                                final selectedAreaIds =
                                    selectedServiceAreaIds.toList()..sort();
                                final selectedAreaTitles = zoneOptions
                                        .isNotEmpty
                                    ? selectedAreaIds
                                        .map((id) => zoneTitleById[id] ?? id)
                                        .where((item) => item.isNotEmpty)
                                        .toList()
                                    : (selectedServiceAreas.toList()..sort());
                                await data.updateCleanerProfile({
                                  'name': nameController.text.trim(),
                                  'fullName': nameController.text.trim(),
                                  'homeAddress': addressController.text.trim(),
                                  'serviceAreas': selectedAreaTitles,
                                  if (zoneOptions.isNotEmpty)
                                    'serviceAreaIds': selectedAreaIds,
                                  'emergencyContactPhone':
                                      emergencyPhoneController.text.trim(),
                                  'emergencyContactRelation':
                                      emergencyRelationController.text.trim(),
                                });
                                if (!context.mounted) return;
                                Navigator.pop(context);
                              } catch (error) {
                                if (!context.mounted) return;
                                showDomlySnackBar(
                                  context,
                                  title: 'Не удалось сохранить данные',
                                  subtitle: '$error',
                                  type: DomlySnackBarType.error,
                                );
                              } finally {
                                if (context.mounted) {
                                  setModalState(() => saving = false);
                                }
                              }
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<AddressSuggestion> _houseAddressSuggestions(
    List<Map<String, dynamic>> houses,
  ) {
    final seen = <String>{};
    final items = <AddressSuggestion>[];
    for (final house in houses) {
      final title = (house['residentialComplex'] ??
              house['title'] ??
              house['address'] ??
              '')
          .toString()
          .trim();
      final address = (house['address'] ?? title).toString().trim();
      final searchText = _houseSearchText(house);
      if (title.isEmpty && address.isEmpty) {
        continue;
      }
      final key = '$title|$address'.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      items.add(
        AddressSuggestion(
          title: title.isEmpty ? address : title,
          subtitle: address == title ? '' : address,
          placeId: (house['id'] ?? key).toString(),
          residentialComplex: title,
          addressLine: address,
          lat: (house['lat'] as num?)?.toDouble(),
          lng: (house['lng'] as num?)?.toDouble(),
          city: (house['city'] ?? '').toString(),
          searchText: searchText,
        ),
      );
    }
    return items;
  }

  String _houseSearchText(Map<String, dynamic> house) {
    final parts = <String>[];
    for (final key in [
      'addressRu',
      'addressKk',
      'titleRu',
      'titleKk',
      'nameRu',
      'nameKk',
      'city',
      'district',
      'street',
    ]) {
      final value = (house[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        parts.add(value);
      }
    }
    final aliases = house['aliases'];
    if (aliases is Iterable) {
      parts.addAll(aliases.map((item) => item.toString().trim()));
    }
    return parts.where((item) => item.isNotEmpty).join(' ');
  }

  String _bonusDisplayValue(Map<String, dynamic> profile) {
    final unlocked = ((profile['unlockedBonusAmount'] as num?)?.toInt() ?? 0) +
        ((profile['manualBonusBalance'] as num?)?.toInt() ?? 0);
    if (unlocked > 0) {
      return '$unlocked ₸';
    }
    return '0 ₸';
  }

  String _formatServiceAreas(Map<String, dynamic> profile) {
    final areas = ((profile['serviceAreas'] as List?) ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (areas.isEmpty) {
      return 'Не выбраны';
    }
    if (areas.length <= 3) {
      return areas.join(', ');
    }
    return '${areas.take(3).join(', ')} +${areas.length - 3}';
  }

  String _workStartDateText(Map<String, dynamic> profile) {
    final explicitJoinDate = (profile['joinDate'] ?? '').toString().trim();
    if (explicitJoinDate.isNotEmpty && explicitJoinDate != 'Январь 2025') {
      return explicitJoinDate;
    }

    for (final key in [
      'registeredAt',
      'createdAt',
      'approvedAt',
      'verifiedAt',
      'updatedAt',
    ]) {
      final parsed = _dateFromAny(profile[key]);
      if (parsed != null) {
        return domlyDateText(parsed.toLocal());
      }
    }
    return 'Дата не указана';
  }

  DateTime? _dateFromAny(dynamic value) {
    if (value == null) {
      return null;
    }
    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue.toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      // Firestore Timestamp has toDate(), plain strings do not.
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.tryParse(value.toString().trim());
  }

  String _loyaltyLevel(Map<String, dynamic> profile) {
    final jobsCount = (profile['jobsCount'] ?? 0) as num;
    if (jobsCount >= 50) {
      return 'Топ';
    }
    if (jobsCount >= 20) {
      return 'Специалист';
    }
    return 'Новичок';
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'DP';
    }
    return parts.take(2).map((e) => e.substring(0, 1).toUpperCase()).join();
  }
}
