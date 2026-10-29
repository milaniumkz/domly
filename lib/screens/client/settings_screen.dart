import '../../theme/domly_palette.dart';
import '../../services/ui_preferences.dart';
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
  static Color get _background =>
      UiPreferences.instance.darkMode ? Color(0xFF121C17) : Color(0xFFF2FAF7);
  static Color get _foreground =>
      UiPreferences.instance.darkMode ? Colors.white : Color(0xFF20382F);
  static Color get _muted =>
      UiPreferences.instance.darkMode ? Color(0xFFBDCEBF) : Color(0xFF6C8A7B);
  static Color get _border =>
      UiPreferences.instance.darkMode ? Color(0xFF3B5242) : Color(0xFFDDEAE3);
  static final _green = Color(0xFF4EA16C);
  static final _button = Color(0xFFC86A4A);

  final _data = FirestoreDataService.instance;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    UiPreferences.instance.addListener(_refreshAppearance);
  }

  void _refreshAppearance() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    UiPreferences.instance.removeListener(_refreshAppearance);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);

    final authController = AppScope.of(context).authController;
    final isAuthenticated = authController.isAuthenticated;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.customerSettingsStream(),
      builder: (context, snap) {
        TranslationScope.watch(context);
        if (snap.hasError) {
          return DomlyShell(
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
        final darkMode = UiPreferences.instance.darkMode;
        final animations = UiPreferences.instance.animations;
        final translationController =
            AppScope.of(context).translationController;
        final language =
            TranslationController.localeLabel(translationController.localeCode);

        return DomlyShell(
          bottomNavigationBar: DomlyClientBottomNav(currentIndex: 4),
          child: ColoredBox(
            color: DomlyPalette.background(_background),
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 390),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(15, 0, 15, 118),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SettingsHeader(),
                        SizedBox(height: 22),
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
                            SizedBox(height: 8),
                            _SettingsOptionTile(
                              title: 'Анимации',
                              subtitle: animations ? 'Включены' : 'Выключены',
                              indicator: _SettingsTileIndicator.chevron,
                              onTap: () => _save({'animations': !animations}),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
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
                        SizedBox(height: 10),
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
                            SizedBox(height: 6),
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
                            SizedBox(height: 6),
                            _SettingsOptionTile(
                              title: 'Вибрация',
                              subtitle: vibration ? 'Включена' : 'Выключена',
                              indicator: _SettingsTileIndicator.dot,
                              active: vibration,
                              onTap: () => _save({'vibration': !vibration}),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
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
                        SizedBox(height: 10),
                        _SettingsSection(
                          title: 'Помощь',
                          subtitle: 'Вопросы по заказам и оплате',
                          height: 120,
                          children: [
                            _SettingsOptionTile(
                              title: 'Помощник DomLY',
                              subtitle: 'Открыть чат',
                              indicator: _SettingsTileIndicator.chevron,
                              onTap: _openAssistant,
                            ),
                          ],
                        ),
                        SizedBox(height: 26),
                        _AboutAppCard(),
                        SizedBox(height: 24),
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
                                    Duration(seconds: 5),
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
                          SizedBox(height: 12),
                          _LogoutButton(
                            label: _isDeletingAccount
                                ? 'Удаляем...'
                                : 'Удалить аккаунт',
                            loading: _isDeletingAccount,
                            danger: true,
                            onTap: _deleteAccount,
                          ),
                        ],
                        SizedBox(height: 92),
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
      backgroundColor: DomlyPalette.surface(Colors.transparent),
      builder: (context) {
        TranslationScope.watch(context);
        return SafeArea(
          child: Container(
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: UiPreferences.instance.darkMode
                  ? Color(0xFF203127)
                  : Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Язык приложения'.tr(),
                  style: TextStyle(
                    color: DomlyPalette.foreground(_foreground),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12),
                ...['Русский', 'Қазақша'].map(
                  (language) => Padding(
                    padding: EdgeInsets.only(bottom: 8),
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

  Future<void> _openAssistant() async {
    if (!await AuthGate.ensureAuthorized(context) || !mounted) return;
    try {
      final chatId = await _data.createOrOpenAssistantChat();
      if (!mounted) return;
      Navigator.pushNamed(context, '/chat', arguments: {'chatId': chatId});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
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
  _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);

    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DomlyPalette.surface(Color(0xFF439F73)),
            DomlyPalette.surface(Color(0xFF80D4B0))
          ],
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
                color:
                    DomlyPalette.surface(Colors.white.withValues(alpha: 0.08)),
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
                color:
                    DomlyPalette.surface(Colors.white.withValues(alpha: 0.08)),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 17,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Настройки'.tr(),
                  style: TextStyle(
                    color: UiPreferences.instance.darkMode
                        ? Color(0xFF203127)
                        : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Внешний вид, язык и уведомления'.tr(),
                  style: TextStyle(
                    color: DomlyPalette.foreground(Color(0xFFEDFAF2)),
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
  _SettingsSection({
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
    DomlyPalette.watch(context);

    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(25, 10, 52, 16),
      decoration: BoxDecoration(
        color:
            UiPreferences.instance.darkMode ? Color(0xFF203127) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: DomlyPalette.border(_SettingsScreenState._border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.tr(),
            style: TextStyle(
              color: DomlyPalette.foreground(_SettingsScreenState._foreground),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 5),
          Text(
            subtitle.tr(),
            style: TextStyle(
              color: DomlyPalette.foreground(_SettingsScreenState._muted),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

enum _SettingsTileIndicator { chevron, dot }

class _SettingsOptionTile extends StatelessWidget {
  _SettingsOptionTile({
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
    DomlyPalette.watch(context);

    return Material(
      color: UiPreferences.instance.darkMode ? Color(0xFF203127) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 44,
          padding: EdgeInsets.fromLTRB(18, 5, 12, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: DomlyPalette.border(_SettingsScreenState._border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: DomlyPalette.foreground(
                            _SettingsScreenState._foreground),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: DomlyPalette.foreground(
                            _SettingsScreenState._muted),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (indicator == _SettingsTileIndicator.chevron)
                Text(
                  '›',
                  style: TextStyle(
                    color: DomlyPalette.foreground(_SettingsScreenState._green),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: DomlyPalette.surface(active
                        ? _SettingsScreenState._green
                        : _SettingsScreenState._border),
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
  _AboutAppCard();

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);

    return Container(
      height: 70,
      padding: EdgeInsets.fromLTRB(33, 8, 24, 8),
      decoration: BoxDecoration(
        color:
            UiPreferences.instance.darkMode ? Color(0xFF203127) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: DomlyPalette.border(_SettingsScreenState._border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'О приложении'.tr(),
            style: TextStyle(
              color: DomlyPalette.foreground(_SettingsScreenState._foreground),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Версия и поддержка'.tr(),
            style: TextStyle(
              color: DomlyPalette.foreground(_SettingsScreenState._muted),
              fontSize: 12,
            ),
          ),
          SizedBox(height: 3),
          Text(
            "DomLY 1.0.0".tr(),
            style: TextStyle(
              color: DomlyPalette.foreground(_SettingsScreenState._foreground),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  _LogoutButton({
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
    DomlyPalette.watch(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: DomlyPalette.surface(
            danger ? Color(0xFFB84545) : _SettingsScreenState._button),
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
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: UiPreferences.instance.darkMode
                            ? Color(0xFF203127)
                            : Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  Text(
                    label.tr(),
                    style: TextStyle(
                      color: UiPreferences.instance.darkMode
                          ? Color(0xFF203127)
                          : Colors.white,
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
  _LanguageChoice({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);

    return _SettingsOptionTile(
      title: label,
      subtitle: selected ? 'Выбран' : 'Нажмите, чтобы выбрать',
      indicator: _SettingsTileIndicator.chevron,
      onTap: () => Navigator.pop(context, label),
    );
  }
}
