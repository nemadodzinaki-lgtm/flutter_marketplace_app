import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _idNumber = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isLoading = false;

  static const Color primaryGreen = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _surname,
      _email,
      _phone,
      _idNumber,
      _password,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF617168), size: 20),
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

  Widget _input({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF26352D),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscure,
          validator:
              validator ??
              (value) {
                if (value == null || value.trim().isEmpty) {
                  return '$label is required';
                }
                return null;
              },
          decoration: _inputDecoration(hint: hint, icon: icon, suffix: suffix),
        ),
      ],
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim().toLowerCase(),
        password: _password.text,
        data: {
          'first_name': _firstName.text.trim(),
          'surname': _surname.text.trim(),
          'phone': _phone.text.trim(),
          'id_number': _idNumber.text.trim(),
        },
      );

      if (!mounted) return;

      if (response.user == null) {
        throw Exception('Registration could not be completed.');
      }

      final needsConfirmation = response.session == null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: primaryGreen,
          content: Text(
            needsConfirmation
                ? 'Please check your email to confirm your account.'
                : 'Your account has been created successfully!',
          ),
        ),
      );

      if (needsConfirmation) {
        widget.onSignIn();
      }
      // If sign-up created a session, AuthGate verifies and opens the account.
    } on AuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Registration failed. Please try again.'),
        ),
      );
      debugPrint('Registration error: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5F4E9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: primaryGreen,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Community Marketplace',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Your neighbourhood, connected.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 38),

                    const Text(
                      'Create your account',
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.7,
                        color: Color(0xFF17251D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Join your community. Buy, sell and discover local services.',
                      style: TextStyle(
                        color: Color(0xFF617168),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 30),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 350;

                        final first = _input(
                          label: 'First name',
                          hint: 'First name',
                          icon: Icons.person_outline,
                          controller: _firstName,
                        );

                        final last = _input(
                          label: 'Surname',
                          hint: 'Surname',
                          icon: Icons.person_outline,
                          controller: _surname,
                        );

                        if (compact) {
                          return Column(
                            children: [first, const SizedBox(height: 18), last],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: first),
                            const SizedBox(width: 12),
                            Expanded(child: last),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 18),

                    _input(
                      label: 'Email address',
                      hint: 'you@example.com',
                      icon: Icons.mail_outline,
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null ||
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(value.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    _input(
                      label: 'Phone number',
                      hint: 'e.g. 0821234567',
                      icon: Icons.phone_outlined,
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                    ),

                    const SizedBox(height: 18),

                    _input(
                      label: 'SA ID number',
                      hint: 'Enter 13-digit ID number',
                      icon: Icons.badge_outlined,
                      controller: _idNumber,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(13),
                      ],
                      validator: (value) {
                        if (value == null ||
                            !RegExp(r'^\d{13}$').hasMatch(value)) {
                          return 'Enter a 13-digit SA ID number';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    _input(
                      label: 'Password',
                      hint: 'At least 8 characters',
                      icon: Icons.lock_outline,
                      controller: _password,
                      obscure: !_showPassword,
                      validator: (value) {
                        if (value == null || value.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                      suffix: IconButton(
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

                    const SizedBox(height: 18),

                    _input(
                      label: 'Confirm password',
                      hint: 'Repeat your password',
                      icon: Icons.lock_outline,
                      controller: _confirmPassword,
                      obscure: !_showConfirmPassword,
                      validator: (value) {
                        if (value != _password.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                      suffix: IconButton(
                        icon: Icon(
                          _showConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _showConfirmPassword = !_showConfirmPassword;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: primaryGreen,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your personal information will be protected.',
                            style: TextStyle(
                              color: Color(0xFF617168),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),

                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_rounded),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : widget.onSignIn,
                        child: const Text(
                          'Already have an account? Sign in',
                          style: TextStyle(
                            fontSize: 13,
                            color: primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
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
