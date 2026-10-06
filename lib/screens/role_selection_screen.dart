import 'package:flutter/material.dart';

import '../app/app_brand.dart';
import '../app/app_scope.dart';
import '../ui/domly_ui.dart';
import '../localization/translation_controller.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? _selectedRole;

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
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
              const SizedBox(height: 18),
              Text(
                'Выберите роль'.tr(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: DomlyColors.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Как вы хотите использовать Domly?'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: DomlyColors.muted,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: _buildRoleCard(
                        symbol: '👤',
                        title: 'Я клиент',
                        description: 'Заказать уборку квартиры',
                        role: 'client',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 220,
                      child: _buildRoleCard(
                        symbol: '🧹',
                        title: 'Я уборщица',
                        description: 'Найти работу и зарабатывать',
                        role: 'cleaner',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DomlyPrimaryButton(
                label: 'Продолжить',
                onPressed: _selectedRole == null
                    ? null
                    : () {
                        if (_selectedRole == 'client') {
                          Navigator.pushReplacementNamed(
                            context,
                            '/client/home',
                          );
                        } else {
                          Navigator.pushReplacementNamed(
                            context,
                            '/cleaner/dashboard',
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String symbol,
    required String title,
    required String description,
    required String role,
  }) {
    final isSelected = _selectedRole == role;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? DomlyColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? DomlyColors.primary : DomlyColors.border,
            width: 1.2,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: DomlyColors.primary.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : DomlyColors.backgroundSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  symbol,
                  style: TextStyle(
                    fontSize: 24,
                    color: isSelected
                        ? DomlyColors.buttonPrimary
                        : DomlyColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : DomlyColors.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.9)
                    : DomlyColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
