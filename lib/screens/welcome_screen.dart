import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_brand.dart';
import '../app/app_scope.dart';
import '../ui/domly_ui.dart';
import '../localization/translation_controller.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.title,
    required this.nextRoute,
  });

  final String title;
  final String nextRoute;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _floatAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.5, curve: Curves.easeIn),
    );
    _floatAnimation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _navigationTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, widget.nextRoute);
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      child: Stack(
        children: [
          Positioned(
            top: 90,
            left: 32,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: DomlyColors.buttonPrimary.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 90,
            right: 20,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: DomlyColors.accent.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 26),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Text(
                    'DOMLY',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DomlyColors.foreground,
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final scale = 0.82 + (_scaleAnimation.value * 0.18);
                        return Transform.translate(
                          offset: Offset(0, _floatAnimation.value - 8),
                          child: Transform.scale(scale: scale, child: child),
                        );
                      },
                      child: Container(
                        width: 144,
                        height: 144,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: ClipOval(
                          child: SizedBox(
                            width: 78,
                            height: 78,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: Image.asset(
                                domlyLogoAsset(
                                  AppScope.of(context).config.flavor,
                                ),
                                width: 96,
                                height: 96,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: 70, right: 70),
                        child: SizedBox(
                          width: 250,
                          child: Text(
                            'Чистота и комфорт по подписке'.tr(),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: DomlyColors.foreground,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            DomlyColors.buttonPrimary),
                      ),
                    ),
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
