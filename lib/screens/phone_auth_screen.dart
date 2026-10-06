import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_brand.dart';
import '../app/app_scope.dart';
import '../localization/translation_controller.dart';
import 'common/legal_document_screen.dart';
import '../services/firestore_data_service.dart';
import '../ui/domly_ui.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({
    super.key,
    required this.title,
    required this.postAuthRoute,
    this.postAuthArguments,
    this.popOnSuccess = false,
  });

  final String title;
  final String postAuthRoute;
  final Object? postAuthArguments;
  final bool popOnSuccess;

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _codeFocusNodes = List.generate(6, (_) => FocusNode());

  String _step = 'phone';
  bool _isLoading = false;
  bool _acceptedTerms = false;
  String? _errorText;
  String? _fallbackCode;

  @override
  void initState() {
    super.initState();
    _phoneController.text = '+7 ';
    _phoneController.selection = TextSelection.collapsed(
      offset: _phoneController.text.length,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final node in _codeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_acceptedTerms) {
      setState(() {
        _errorText =
            'Поставьте галочку согласия с условиями, чтобы получить код.'.tr();
      });
      return;
    }
    if (!_hasValidPhone) {
      setState(() {
        _errorText =
            'Введите номер полностью в формате +7 (700) 000-00-00.'.tr();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _fallbackCode = null;
    });

    try {
      final result = await AppScope.of(context)
          .authController
          .sendOtp(_phoneController.text);
      if (!mounted) {
        return;
      }
      if (result.signedIn) {
        await _completeAuth();
        return;
      }
      setState(() {
        _step = 'code';
        _fallbackCode = result.fallbackCode;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = _presentableError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _enteredCode;
    if (code.length != 6) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final authController = AppScope.of(context).authController;
      final ok = await authController.verifyOtp(
        phone: _phoneController.text,
        code: code,
      );

      if (!mounted) {
        return;
      }

      if (!ok) {
        setState(() {
          _errorText = 'Неверный код или истек срок действия.'.tr();
        });
        return;
      }

      await _completeAuth();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = _presentableError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.title == 'Domly Pro'
        ? 'Вход в Domly Pro'.tr()
        : 'Вход в {title}'.tr(params: {'title': widget.title});

    return DomlyShell(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  44,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: Colors.white,
                    border: Border.all(
                      color: DomlyColors.primary.withValues(alpha: 0.36),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x142D6B4F),
                        blurRadius: 26,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(27),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const DomlyLanguageSwitcher(),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          child: _step == 'phone'
                              ? _buildPhoneStep(titleText)
                              : _buildCodeStep(),
                        ),
                      ],
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

  Widget _buildPhoneStep(String titleText) {
    return Column(
      key: const ValueKey('phone'),
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: ClipOval(
            child: SizedBox(
              width: 62,
              height: 62,
              child: FittedBox(
                fit: BoxFit.cover,
                child: Image.asset(
                  domlyLogoAsset(AppScope.of(context).config.flavor),
                  width: 78,
                  height: 78,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          titleText,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Чистота и комфорт по подписке.'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: DomlyColors.muted),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Номер телефона'.tr(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DomlyColors.foreground.withValues(alpha: 0.9),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [_PhoneMaskFormatter()],
          decoration: InputDecoration(
            hintText: '+7 (700) 000-00-00',
            prefixIcon: const Icon(Icons.phone_outlined),
            suffixIcon: _hasValidPhone
                ? const Icon(Icons.check_circle,
                    color: DomlyColors.buttonPrimary)
                : null,
            filled: true,
            fillColor: DomlyColors.backgroundSoft,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: DomlyColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(
                  color: DomlyColors.buttonPrimary, width: 1.5),
            ),
          ),
          onChanged: (_) => setState(() => _errorText = null),
        ),
        const SizedBox(height: 14),
        _buildTermsConsent(),
        const SizedBox(height: 18),
        DomlyPrimaryButton(
          label: _isLoading ? 'Отправляем...'.tr() : 'Получить код'.tr(),
          onPressed: _isLoading || !_acceptedTerms ? null : _sendCode,
        ),
        if (!_hasValidPhone) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Введите номер полностью, чтобы получить код.'.tr(),
              style: const TextStyle(
                fontSize: 12,
                color: DomlyColors.muted,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DomlyColors.backgroundSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chat_outlined,
                  size: 18, color: DomlyColors.buttonPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Код подтверждения будет отправлен на указанный номер WhatsApp.'
                      .tr(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: DomlyColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsConsent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
      decoration: BoxDecoration(
        color: DomlyColors.backgroundSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _acceptedTerms
              ? DomlyColors.primary.withValues(alpha: 0.45)
              : DomlyColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _acceptedTerms,
            activeColor: DomlyColors.buttonPrimary,
            onChanged: (value) {
              setState(() {
                _acceptedTerms = value ?? false;
                if (_acceptedTerms) {
                  _errorText = null;
                }
              });
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Я принимаю условия сервиса, '.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                      height: 1.35,
                    ),
                  ),
                  _TermsLink(
                    label: 'договор оферты'.tr(),
                    routeName: LegalDocumentScreen.offerRoute,
                  ),
                  Text(
                    ' и '.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                      height: 1.35,
                    ),
                  ),
                  _TermsLink(
                    label: 'политику конфиденциальности'.tr(),
                    routeName: LegalDocumentScreen.privacyRoute,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep() {
    return Column(
      key: const ValueKey('code'),
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: DomlyColors.buttonPrimary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.check,
            size: 24,
            color: DomlyColors.buttonPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Введите код'.tr(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DomlyColors.foreground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _fallbackCode != null
              ? 'Сервис отправки недоступен. Временный код показан ниже.'.tr()
              : 'Код отправлен на номер {phone}'
                  .tr(params: {'phone': _formattedPhone}),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: DomlyColors.muted),
        ),
        if (_fallbackCode != null) ...[
          const SizedBox(height: 12),
          Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F1ED),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Код: {code}'.tr(params: {'code': _fallbackCode ?? ''}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 46,
                height: 56,
                child: TextField(
                  controller: _codeControllers[index],
                  focusNode: _codeFocusNodes[index],
                  autofocus: index == 0,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(1),
                  ],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: DomlyColors.backgroundSoft,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: DomlyColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: DomlyColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                          color: DomlyColors.buttonPrimary, width: 1.5),
                    ),
                  ),
                  onChanged: (value) => _onCodeChanged(index, value),
                  onTap: () =>
                      _codeControllers[index].selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _codeControllers[index].text.length,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 18),
        _authTextAction(
          label: 'Изменить номер телефона'.tr(),
          onTap: _isLoading
              ? null
              : () {
                  setState(() {
                    _step = 'phone';
                    _errorText = null;
                    _clearCode();
                  });
                },
        ),
        const SizedBox(height: 4),
        _authTextAction(
          label: 'Отправить код повторно'.tr(),
          onTap: _isLoading ? null : _sendCode,
        ),
      ],
    );
  }

  Widget _authTextAction({
    required String label,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isEnabled
                  ? DomlyColors.buttonPrimary
                  : DomlyColors.buttonPrimary.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }

  void _onCodeChanged(int index, String value) {
    if (value.isNotEmpty && index < _codeFocusNodes.length - 1) {
      _codeFocusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _codeFocusNodes[index - 1].requestFocus();
    }
    setState(() => _errorText = null);
    if (_enteredCode.length == 6) {
      _verifyCode();
    }
  }

  void _clearCode() {
    for (final controller in _codeControllers) {
      controller.clear();
    }
  }

  bool get _hasValidPhone =>
      _normalizePhone(_phoneController.text).length == 11;

  String get _formattedPhone => _phoneController.text.trim();

  String get _enteredCode => _codeControllers.map((e) => e.text).join();

  String? get _pendingReferralCode {
    final value = Uri.base.queryParameters['ref']?.trim().toUpperCase();
    if (value == null ||
        value.isEmpty ||
        widget.postAuthRoute.startsWith('/cleaner')) {
      return null;
    }
    return value;
  }

  Future<void> _completeAuth() async {
    final authController = AppScope.of(context).authController;
    await authController.refresh();
    final prefs = await SharedPreferences.getInstance();
    final pendingReferralCode =
        _pendingReferralCode ?? prefs.getString('domly_pending_referral');
    if (pendingReferralCode != null) {
      try {
        await FirestoreDataService.instance.applyReferralCodeIfMissing(
          pendingReferralCode,
        );
        await prefs.remove('domly_pending_referral');
      } catch (_) {
        // Referral code application is non-blocking for auth completion.
      }
    }
    if (!mounted) {
      return;
    }

    if (widget.popOnSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      widget.postAuthRoute,
      arguments: widget.postAuthArguments,
    );
  }

  String _normalizePhone(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('8')) {
      return '7${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '7$digits';
    }
    return digits;
  }

  String _presentableError(Object error) {
    final raw = error.toString().replaceFirst('FlutterError: ', '').trim();
    final normalized = raw.toLowerCase();
    if (raw.isEmpty ||
        normalized == 'internal' ||
        normalized.endsWith(' internal') ||
        normalized.contains('[firebase_functions/internal]') ||
        normalized.contains('internal error')) {
      return 'Сервис авторизации временно недоступен. Попробуйте позже.'.tr();
    }
    return raw;
  }
}

class _TermsLink extends StatelessWidget {
  const _TermsLink({
    required this.label,
    required this.routeName,
  });

  final String label;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(context).pushNamed(routeName),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: DomlyColors.buttonPrimary,
            decoration: TextDecoration.underline,
            decorationColor: DomlyColors.buttonPrimary,
          ),
        ),
      ),
    );
  }
}

class _PhoneMaskFormatter extends TextInputFormatter {
  static const String _prefix = '+7 ';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var normalized = digits;

    if (normalized.startsWith('8')) {
      normalized = '7${normalized.substring(1)}';
    }
    if (normalized.startsWith('7')) {
      normalized = normalized.substring(1);
    }
    if (normalized.length > 10) {
      normalized = normalized.substring(0, 10);
    }

    final formatted = _format(normalized);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _format(String digits) {
    if (digits.isEmpty) {
      return _prefix;
    }
    final buffer = StringBuffer(_prefix);
    for (var i = 0; i < digits.length; i++) {
      if (i == 0) {
        buffer.write('(');
      } else if (i == 3) {
        buffer.write(') ');
      } else if (i == 6 || i == 8) {
        buffer.write('-');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
