import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin_dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/marketplace_shell.dart';
import '../screens/register_screen.dart';

class _SessionDestination {
  const _SessionDestination({required this.firstName, required this.role});
  final String firstName;
  final String role;
}

/// Owns authentication screens and routes verified database profiles by role.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSubscription;
  _SessionDestination? _destination;
  Object? _error;
  bool _loading = true;
  bool _showRegistration = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadDestination(_supabase.auth.currentSession?.user);
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      switch (data.event) {
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userUpdated:
        case AuthChangeEvent.tokenRefreshed:
          _loadDestination(data.session?.user);
          break;
        default:
          break;
      }
    });
  }

  Future<void> _loadDestination(User? user) async {
    final request = ++_request;
    setState(() {
      _showRegistration = false;
      _destination = null;
      _error = null;
      _loading = user != null;
    });
    if (user == null) return;

    try {
      // Only the database profile can grant administrator access.
      final profile = await _supabase
          .from('profiles')
          .select('first_name, role, account_status')
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) {
        throw StateError('Profile not found. Contact support.');
      }
      if (profile['account_status'] != 'active') {
        throw StateError(
          'Your account is not active. Please contact the administrator.',
        );
      }
      final role = profile['role']?.toString() ?? '';
      if (role != 'admin' && role != 'user') {
        throw StateError('Unknown account role. Contact support.');
      }

      // Ignore replies from an earlier session or a superseded retry.
      if (!mounted || request != _request) return;
      setState(() {
        _destination = _SessionDestination(
          firstName: profile['first_name']?.toString() ?? 'User',
          role: role,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _retry() => _loadDestination(_supabase.auth.currentSession?.user);

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  _error is StateError
                      ? (_error as StateError).message.toString()
                      : 'Unable to verify your account. Please try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _retry,
                  child: const Text('Try Again'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await _supabase.auth.signOut();
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Unable to sign out. Please try again.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final destination = _destination;
    if (destination == null) {
      // Keep both forms under the live gate, with no auth routes to pop.
      return _showRegistration
          ? RegisterScreen(
              onSignIn: () => setState(() => _showRegistration = false),
            )
          : LoginScreen(
              onRegister: () => setState(() => _showRegistration = true),
            );
    }
    if (destination.role == 'admin') {
      return const AdminDashboardScreen();
    }
    return MarketplaceShell(firstName: destination.firstName);
  }
}
