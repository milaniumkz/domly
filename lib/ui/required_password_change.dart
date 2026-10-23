import '../theme/domly_palette.dart';
import '../localization/translation_controller.dart';
import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../services/session_store.dart';

class RequiredPasswordChange extends StatefulWidget {
  const RequiredPasswordChange({super.key, required this.child});
  final Widget child;
  @override
  State<RequiredPasswordChange> createState() => _RequiredPasswordChangeState();
}

class _RequiredPasswordChangeState extends State<RequiredPasswordChange> {
  final current = TextEditingController(), next = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await BackendApiService.instance.postMap('/auth/password/change',
          body: {'currentPassword': current.text, 'newPassword': next.text});
      await SessionStore().clearBackendSession();
      BackendApiService.passwordChangeRequired.value = false;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);
    return ValueListenableBuilder<bool>(
        valueListenable: BackendApiService.passwordChangeRequired,
        builder: (context, needsChange, _) => needsChange
            ? Scaffold(
                body: Center(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Смените временный пароль'.tr(),
                                      style: TextStyle(fontSize: 24)),
                                  const SizedBox(height: 16),
                                  TextField(
                                      controller: current,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                          labelText: 'Текущий пароль'.tr())),
                                  TextField(
                                      controller: next,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                          labelText:
                                              'Новый пароль — от 12 символов'
                                                  .tr()),
                                      onSubmitted: (_) => save()),
                                  if (error != null)
                                    Text(error!,
                                        style: TextStyle(
                                            color: DomlyPalette.foreground(
                                                Colors.red))),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                      onPressed: busy ? null : save,
                                      child: Text(busy
                                          ? 'Сохранение…'
                                          : 'Сменить пароль и войти заново'))
                                ])))))
            : widget.child);
  }
}
