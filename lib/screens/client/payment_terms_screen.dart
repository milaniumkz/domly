import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../localization/translation_controller.dart';

class PaymentTermsScreen extends StatelessWidget {
  const PaymentTermsScreen({super.key});

  static const String routeName = '/payment-terms';
  static const String siteUrl = 'https://domly.kz';
  static const String successReturnUrl = 'https://domly.kz/payment/success';
  static const String paymentCallbackUrl =
      'https://domly.kz/api/v1/payments/bcc/webhook';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(),
                        SizedBox(height: 24),
                        _TermsSection(
                          title: 'Прием платежей',
                          items: [
                            'DOMLY принимает оплату за пакеты уборки и дополнительные услуги банковской картой через интернет-эквайринг и через Kaspi.kz.',
                            'Стоимость заказа показывается пользователю до перехода к оплате. Оплата считается успешной после подтверждения платежной системой.',
                            'После успешной оплаты пользователь возвращается в раздел заказов приложения.',
                          ],
                        ),
                        _TermsSection(
                          title: 'Возврат платежей',
                          items: [
                            'Возврат возможен при отмене услуги, ошибочном списании или невозможности оказать услугу.',
                            'Заявка на возврат рассматривается администрацией DOMLY. Возврат выполняется тем же способом, которым была произведена оплата, если это поддерживается платежной системой.',
                            'Срок зачисления средств зависит от банка-эмитента карты и правил платежной системы.',
                          ],
                        ),
                        _TermsSection(
                          title: 'Технические ссылки',
                          items: [
                            'Основной домен: $siteUrl',
                            'Страница возврата после оплаты: $successReturnUrl',
                            'Callback для уведомлений платежной системы: $paymentCallbackUrl',
                          ],
                        ),
                        _TermsSection(
                          title: 'Контакты',
                          items: [
                            'По вопросам оплаты, отмены и возврата пользователь может обратиться в поддержку DOMLY через приложение или к администратору сервиса.',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 0, 0),
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                elevation: 8,
                shadowColor: Colors.black26,
                child: IconButton(
                  tooltip: 'Назад',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      navigator.pushReplacementNamed('/client/home');
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DOMLY',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppTheme.primaryGreen,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Условия приема и возврата платежей'.tr(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.darkText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Информация для пользователей и платежного провайдера.'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedText),
        ),
      ],
    );
  }
}

class _TermsSection extends StatelessWidget {
  const _TermsSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.darkText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: CircleAvatar(
                      radius: 3,
                      backgroundColor: AppTheme.primaryTerracotta,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        color: AppTheme.darkText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
