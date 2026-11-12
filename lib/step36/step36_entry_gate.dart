import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_gate.dart';

/// Put Step36EntryGate at MaterialApp.home, after Supabase.initialize().
///
/// This wrapper leaves your working AuthGate untouched. After the intro,
/// AuthGate owns signed-out forms and verifies every signed-in role.
class Step36EntryGate extends StatefulWidget {
  const Step36EntryGate({super.key});

  @override
  State<Step36EntryGate> createState() => _Step36EntryGateState();
}

class _Step36EntryGateState extends State<Step36EntryGate> {
  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _introTimer;
  bool _introPlaying = true;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _hasSession = _supabase.auth.currentSession != null;

    _introTimer = Timer(Duration(milliseconds: _hasSession ? 700 : 1900), () {
      if (mounted) setState(() => _introPlaying = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _introTimer?.cancel();
      _introPlaying = false;
    }
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget destination;
    if (_introPlaying) {
      destination = const _Step36Splash(key: ValueKey('intro'));
    } else {
      destination = const AuthGate(key: ValueKey('auth-gate'));
    }

    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      reverseDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: destination,
    );
  }
}

class _Step36Splash extends StatefulWidget {
  const _Step36Splash({super.key});

  @override
  State<_Step36Splash> createState() => _Step36SplashState();
}

class _Step36SplashState extends State<_Step36Splash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1550),
      vsync: this,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.63, curve: Curves.easeOut),
    );
    _scale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF105C2B);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Image.asset(
                        'assets/community_market_welcome.png',
                        height: MediaQuery.sizeOf(context).height * 0.34,
                        width: 325,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _fade,
                      child: const Column(
                        children: [
                          Text(
                            'Community Marketplace',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: green,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.1,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'Discover local. Connect directly.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF738477),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _fade,
                    child: const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF91BC6B),
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
  }
}
