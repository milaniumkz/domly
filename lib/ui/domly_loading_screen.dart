import 'package:flutter/material.dart';

import 'domly_ui.dart';
import '../localization/translation_controller.dart';

class DomlyLoadingScreen extends StatelessWidget {
  const DomlyLoadingScreen({
    super.key,
    this.logoAsset = 'assets/logo.png',
    this.title = 'DOMLY',
    this.subtitle = 'Готовим ваш сервис уборки',
  });

  final String logoAsset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DomlyColors.background,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              DomlyColors.background,
              DomlyColors.backgroundSoft,
              DomlyColors.backgroundSoft2,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 245,
                  height: 245,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Image.asset(logoAsset, fit: BoxFit.contain),
                ),
                const SizedBox(height: 22),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DomlyColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 34),
                const SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      DomlyColors.buttonPrimary,
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                Text(
                  'Проверяем профиль, адрес и заказы'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DomlyColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
