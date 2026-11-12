import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed jobseeker entry screen. The marketplace uses the same
/// profiles table and auth session as the rest of the app.
class JobseekerDashboard extends StatelessWidget {
  const JobseekerDashboard({super.key});

  Future<Map<String, dynamic>?> _loadProfile() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;
    return client
        .from('profiles')
        .select('first_name, role, account_status')
        .eq('id', user.id)
        .maybeSingle();
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobseeker dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _loadProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load your profile.'));
          }
          final name = snapshot.data?['first_name']?.toString().trim();
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.work_outline_rounded, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome${name == null || name.isEmpty ? '' : ', $name'}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your account is connected through Supabase. '
                    'Marketplace features are available from the main app.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
