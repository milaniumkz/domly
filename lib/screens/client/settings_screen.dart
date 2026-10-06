import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/auth_gate.dart';
import '../../localization/translation_controller.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../ui/first_run_tutorial.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _background = Color(0xFFF2FAF7);
  static const _foreground = Color(0xFF20382F);
  static const _muted = Color(0xFF6C8A7B);
  static const _border = Color(0xFFDDEAE3);
  static const _green = Color(0xFF4EA16C);
  static const _button = Color(0xFFC86A4A);

  final _data = FirestoreDataService.instance;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;

  @override
  Widget build(BuildContext context) {
    final authController = AppScope.of(context).authController;
    final isAuthenticated = authController.isAuthenticated;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.customerSettingsStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyClientBottomNav(currentIndex: 4),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: DomlyEmptyStateCard(
                    icon: Icons.settings_outlined,
                    title: 'Не удалось загрузить настройки',
                    subtitle: 'Обновите экран и попробуйте снова.',
                  ),
                ),
              ),
            ),
          );
        }

        final settings = snap.data ?? <String, dynamic>{};
        final push = settings['pushNotifications'] == true ||
            settings['notifications'] == true;
        final sound =
            settings['sound'] == true || settings['emailNotifications'] == true;
        final vibration =
            settings['vibration'] == true || settings['notifications'] == true;
        final darkMode = settings['darkMode'] == true;
        final animations = settings['animations'] != false;
        final translationController =
            AppScope.of(context).translationController;
        final language =
            TranslationController.localeLabel(translationController.localeCode);

        return DomlyShell(
          bottomNavigationBar: const DomlyClientBottomNav(currentIndex: 4),
          child: ColoredBox(
            color: _background,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 118),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SettingsHeader(),
                        const SizedBox(height: 22),
                        _SettingsSection(
                          title: 'Оформление',
                          subtitle: 'Параметры интерфейса',
                          height: 170,
                          children: [
                            _SettingsOptionTile(
                              title: 'Тема',
                              subtitle: darkMode ? 'Темная' : 'Светлая',
                              indicator: _SettingsTileIndicator.chevron,
                              onTap: () => _save({'darkMode': !darkMode}),
                            ),
                            const SizedBox(height: 8),
                            _SettingsOptionTile(
                              title: 'Анимации',
                              subtitle: animations ? 'Включены' : 'Выключены',
                              indicator: _SettingsTileIndicator.chevron,
                              onTap: () => _save({'animations': !animations}),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _SettingsSection(
                          title: 'Язык',
                          subtitle: 'Русский по умолчанию',
                          height: 120,
                          children: [
                            _SettingsOptionTile(
                              title: 'Язык приложения',
                              subtitle: language,
                              indicator: _SettingsTileIndicator.chevron,
                              onTap: () => _showLanguagePicker(language),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _SettingsSection(
                          title: 'Уведомления',
                          subtitle: 'Push, звук, вибрация',
                          height: 230,
                          children: [
                            _SettingsOptionTile(
                              title: 'Push-уведомления',
                              subtitle: push ? 'Включены' : 'Выключены',
                              indicator: _SettingsTileIndicator.dot,
                              active: push,
                              onTap: () => _save({
                                'pushNotifications': !push,
                                'notifications': !push,
                              }),
                            ),
                            const SizedBox(height: 6),
                            _SettingsOptionTile(
                              title: 'Звук',
                              subtitle: sound ? 'Включен' : 'Выключен',
                              indicator: _SettingsTileIndicator.dot,
                              active: sound,
                              onTap: () => _save({
                                'sound': !sound,
                                'emailNotifications': !sound,
                              }),
                            ),
                            const SizedBox(height: 6),
                            _SettingsOptionTile(
                              title: 'Вибрация',
                              subtitle: vibration ? 'Включена' : 'Выключена',
                              indicator: _SettingsTileIndicator.dot,
                              active: vibration,
                              onTap: () => _save({'vibration': !vibration}),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _SettingsSection(
                          title: 'Обучение',
                          subtitle: 'Пошаговые подсказки по приложению',
                          height: 120,
                          children: [
                            _SettingsOptionTile(
                              title: 'Пройти обучение',
                              subtitle: 'Покажем кнопки и основные действия',
                              indicator: _SettingsTileIndicator.chevron,
                              onTap: _showTutorial,
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        const _AboutAppCard(),
                        const SizedBox(height: 24),
                        if (isAuthenticated)
                          _LogoutButton(
                            label: _isSigningOut
                                ? 'Выходим...'
                                : 'Выйти из аккаунта',
                            loading: _isSigningOut,
                            onTap: () async {
                              if (_isSigningOut) {
                                return;
                              }
                              setState(() {
                                _isSigningOut = true;
                              });
                              final navigator = Navigator.of(context);
                              await authController.signOut().timeout(
                                    const Duration(seconds: 5),
                                    onTimeout: () {},
                                  );
                              if (!mounted) {
                                return;
                              }
                              navigator.pushNamedAndRemoveUntil(
                                '/auth',
                                (_) => false,
                              );
                            },
                          )
                        else
                          _LogoutButton(
                            label: 'Войти в аккаунт',
                            loading: false,
                            onTap: () async {
                              await AuthGate.ensureAuthorized(context);
                            },
                          ),
                        if (isAuthenticated) ...[
                          const SizedBox(height: 12),
                          _LogoutButton(
                            label: _isDeletingAccount
                                ? 'Удаляем...'
                                : 'Удалить аккаунт',
                            loading: _isDeletingAccount,
                            danger: true,
                            onTap: _deleteAccount,
                          ),
                        ],
                        const SizedBox(height: 92),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLanguagePicker(String current) async {
    final translationController = AppScope.of(context).translationController;
    final next = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Язык приложения'.tr(),
                  style: TextStyle(
                    color: _foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...const ['Русский', 'Қазақша'].map(
                  (language) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LanguageChoice(
                      label: language,
                      selected: language == current,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (next != null && next != current) {
      if (!mounted) {
        return;
      }
      await translationController.setLocale(_localeCodeForLanguage(next));
      await _save({'language': next});
    }
  }

  String _localeCodeForLanguage(String language) {
    return switch (language) {
      'Қазақша' => 'kk',
      _ => 'ru',
    };
  }

  Future<void> _save(Map<String, dynamic> data) async {
    await _data.updateCustomerSettings(data);
  }

  Future<void> _showTutorial() async {
    final scope = AppScope.of(context);
    await DomlyFirstRunTutorial.show(context, flavor: scope.config.flavor);
  }

  Future<void> _deleteAccount() async {
    if (_isDeletingAccount) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Удалить аккаунт?'.tr()),
            content: Text(
              'Аккаунт будет удалён с этого устройства. Это действие нельзя отменить.'
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
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _isDeletingAccount = true;
    });
    final navigator = Navigator.of(context);
    try {
      await AppScope.of(context).authController.deleteAccount();
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
    } catch (error) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось удалить аккаунт',
        subtitle: error.toString(),
        type: DomlySnackBarType.error,
      );
      setState(() {
        _isDeletingAccount = false;
      });
    }
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF439F73), Color(0xFF80D4B0)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -17,
            top: -22,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -49,
            bottom: -75,
            child: Container(
              width: 138,
              height: 138,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 20,
            child: Material(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.maybePop(context),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.arrow_back,
                    color: Color(0xFF2E7D5B),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 52,
            top: 17,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Настройки'.tr(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Внешний вид, язык и уведомления'.tr(),
                  style: TextStyle(
                    color: Color(0xFFEDFAF2),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.height,
    required this.children,
  });

  final String title;
  final String subtitle;
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(25, 10, 52, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _SettingsScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _SettingsScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: _SettingsScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

enum _SettingsTileIndicator { chevron, dot }

class _SettingsOptionTile extends StatelessWidget {
  const _SettingsOptionTile({
    required this.title,
    required this.subtitle,
    required this.indicator,
    required this.onTap,
    this.active = true,
  });

  final String title;
  final String subtitle;
  final _SettingsTileIndicator indicator;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 44,
          padding: const EdgeInsets.fromLTRB(18, 5, 12, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _SettingsScreenState._border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _SettingsScreenState._foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _SettingsScreenState._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (indicator == _SettingsTileIndicator.chevron)
                const Text(
                  '›',
                  style: TextStyle(
                    color: _SettingsScreenState._green,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: active
                        ? _SettingsScreenState._green
                        : _SettingsScreenState._border,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutAppCard extends StatelessWidget {
  const _AboutAppCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.fromLTRB(33, 8, 24, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _SettingsScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'О приложении'.tr(),
            style: TextStyle(
              color: _SettingsScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Версия и поддержка'.tr(),
            style: TextStyle(
              color: _SettingsScreenState._muted,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Domly 1.0.0',
            style: TextStyle(
              color: _SettingsScreenState._foreground,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: danger ? const Color(0xFFB84545) : _SettingsScreenState._button,
        borderRadius: BorderRadius.circular(14),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return _SettingsOptionTile(
      title: label,
      subtitle: selected ? 'Выбран' : 'Нажмите, чтобы выбрать',
      indicator: _SettingsTileIndicator.chevron,
      onTap: () => Navigator.pop(context, label),
    );
  }
}
