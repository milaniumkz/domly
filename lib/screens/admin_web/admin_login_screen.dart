import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../localization/translation_controller.dart';
import '../../ui/domly_ui.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({
    super.key,
    required this.title,
    this.initialErrorText,
  });

  final String title;
  final String? initialErrorText;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _errorText = widget.initialErrorText;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetUnauthorizedSessionIfNeeded();
    });
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final authController = AppScope.of(context).authController;
      await authController.signInWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await authController.refresh();
      if (!mounted) {
        return;
      }
      if (!authController.hasBackofficeAccess) {
        setState(() {
          _errorText = 'У учетной записи нет прав для входа в админку.';
        });
        return;
      }
      Navigator.of(context).pushNamedAndRemoveUntil('/admin/web', (_) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString().replaceFirst('FlutterError: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signOutCurrentSession() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await AppScope.of(context).authController.signOut();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetUnauthorizedSessionIfNeeded() async {
    final authController = AppScope.of(context).authController;
    if (!authController.isAuthenticated || authController.hasBackofficeAccess) {
      return;
    }
    await authController.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _errorText = 'Старая сессия сброшена. Войдите под админским аккаунтом.';
    });
    Navigator.of(context).pushNamedAndRemoveUntil('/admin/web', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [DomlyColors.primary, DomlyColors.accent],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x292D6B4F),
                        blurRadius: 32,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(1.2),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(31),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        children: [
                          const DomlyLanguageSwitcher(),
                          const SizedBox(height: 12),
                          Image.asset('assets/logo.png',
                              width: 148, height: 148),
                          const SizedBox(height: 8),
                          Text(
                            widget.title.tr(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: DomlyColors.foreground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Вход для сотрудников и администраторов.'.tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              color: DomlyColors.muted,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Логин'.tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: DomlyColors.foreground.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: 'admin@domly.kz',
                              prefixIcon: const Icon(Icons.alternate_email),
                              filled: true,
                              fillColor: DomlyColors.backgroundSoft,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: DomlyColors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: DomlyColors.buttonPrimary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() => _errorText = null),
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Пароль'.tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: DomlyColors.foreground.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: 'Введите пароль'.tr(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscure = !_obscure;
                                  });
                                },
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              filled: true,
                              fillColor: DomlyColors.backgroundSoft,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: DomlyColors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: DomlyColors.buttonPrimary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _loading ? null : _submit(),
                            onChanged: (_) => setState(() => _errorText = null),
                          ),
                          const SizedBox(height: 20),
                          DomlyPrimaryButton(
                            label: 'Войти'.tr(),
                            icon: Icons.login,
                            isLoading: _loading,
                            onPressed: _loading ? null : _submit,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loading ? null : _signOutCurrentSession,
                            child: Text('Сбросить текущую сессию'.tr()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: DomlyColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
