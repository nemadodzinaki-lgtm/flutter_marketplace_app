import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onRegister});

  final VoidCallback onRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _resetting = false;
  bool _showPassword = false;
  bool _isLoading = false;

  static const Color primaryGreen = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.auth.signInWithPassword(
        email: _email.text.trim().toLowerCase(),
        password: _password.text,
      );

      if (response.user == null || response.session == null) {
        throw Exception('Unable to sign in.');
      }

      // AuthGate alone verifies the profile and displays the role's screen.
      // Do not pop a route or sign out while that verification is in progress.
    } on AuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: const Text(
            'Unable to sign in. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }
    setState(() => _resetting = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If this account exists, a password reset email will be sent.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to request a reset. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF617168)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF5F7F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8EEEA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryGreen, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarketplaceEntrance(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7EE),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.storefront_rounded,
                                  color: primaryGreen,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Community Marketplace',
                                    style: TextStyle(
                                      color: Color(0xFF105C2B),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Center(
                              child: Image.asset(
                                'assets/community_market_welcome.png',
                                height:
                                    MediaQuery.viewInsetsOf(context).bottom > 0
                                    ? 90
                                    : 190,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Welcome back!',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.7,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Discover local finds. Meet the people behind them.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF617168),
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 34),

                    const Text(
                      'Email address',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),

                    MarketplaceEntrance(
                      delay: 100,
                      child: TextFormField(
                        controller: _email,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoration(
                          'you@example.com',
                          Icons.mail_outline,
                        ),
                        validator: (value) {
                          if (value == null ||
                              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(value.trim())) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      'Password',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),

                    MarketplaceEntrance(
                      delay: 180,
                      child: TextFormField(
                        controller: _password,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        obscureText: !_showPassword,
                        decoration: _decoration(
                          'Enter your password',
                          Icons.lock_outline,
                          suffix: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _showPassword = !_showPassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Password is required'
                            : null,
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading || _resetting
                            ? null
                            : _forgotPassword,
                        child: Text(
                          _resetting
                              ? 'Sending reset email…'
                              : 'Forgot password?',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_rounded),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    TextButton(
                      onPressed: _isLoading ? null : widget.onRegister,
                      child: const Text(
                        "Don't have an account? Create Account",
                        style: TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Temporary landing screen while we build the marketplace.
class MarketplaceWelcomeScreen extends StatelessWidget {
  final String firstName;

  const MarketplaceWelcomeScreen({super.key, required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Marketplace'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.signOut();

                // AuthGate listens for signOut and displays
                // the sign-in screen automatically.
              } catch (error) {
                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Unable to sign out. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 68, color: Color(0xFF16803C)),
            const SizedBox(height: 18),
            Text(
              'Welcome, $firstName!',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('You are successfully logged in.'),
          ],
        ),
      ),
    );
  }
}
