import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_reports_management_screen.dart';
import 'admin_user_management_screen.dart';
import 'admin_advertisements_screen.dart';

/// Place this widget inside Home's AppBar actions.
/// The shortcut is visible only to an active administrator.
class AdminDashboardShortcut extends StatefulWidget {
  const AdminDashboardShortcut({super.key});

  @override
  State<AdminDashboardShortcut> createState() => _AdminDashboardShortcutState();
}

class _AdminDashboardShortcutState extends State<AdminDashboardShortcut> {
  late final Future<bool> _isAdmin = _checkAdmin();

  Future<bool> _checkAdmin() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return false;

    try {
      final profile = await client
          .from('profiles')
          .select('role, account_status')
          .eq('id', user.id)
          .maybeSingle();

      return profile?['role'] == 'admin' &&
          profile?['account_status'] == 'active';
    } catch (error) {
      debugPrint('Admin shortcut access check failed: $error');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return IconButton(
          tooltip: 'Admin Dashboard',
          icon: const Icon(Icons.admin_panel_settings_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            );
          },
        );
      },
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _reports = [];
  String _reportFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Please sign in first.');

      // UI gate is not security: the RPC ALSO checks active admin status.
      final profile = await client
          .from('profiles')
          .select('role, account_status')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role'] != 'admin' ||
          profile?['account_status'] != 'active') {
        throw StateError('Access denied. Administrator account required.');
      }

      final result = await client.rpc('step30_admin_dashboard_stats');
      final reports = await client
          .from('marketplace_reports')
          .select('''
            id, listing_id, report_type, reason, details, status, created_at,
            listings!marketplace_reports_listing_id_fkey(title)
          ''')
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;
      setState(() {
        _stats = Map<String, dynamic>.from(result as Map);
        _reports = List<Map<String, dynamic>>.from(reports);
      });
    } catch (error) {
      debugPrint('Admin dashboard loading error: $error');
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message
            : 'Unable to load the dashboard. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(String field) {
    final value = _stats[field];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _managementCard(
    String title,
    String subtitle,
    IconData icon,
    Widget page,
  ) {
    return SizedBox(
      width: 300,
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Icon(icon, color: green, size: 28),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page),
            );
            if (mounted) _loadData();
          },
        ),
      ),
    );
  }

  Widget _metricCard(String label, String field, IconData icon) {
    return SizedBox(
      width: 215,
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE4EBE6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 25, color: green),
              const SizedBox(height: 16),
              Text(
                '${_count(field)}',
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(label, style: const TextStyle(color: Color(0xFF617168))),
            ],
          ),
        ),
      ),
    );
  }

  String _label(String value) {
    switch (value) {
      case 'seller':
        return 'Seller';
      case 'listing':
        return 'Advertisement';
      case 'scam':
        return 'Possible scam / misleading information';
      case 'inappropriate':
        return 'Inappropriate content';
      case 'spam':
        return 'Spam';
      case 'harassment':
        return 'Harassment or abuse';
      case 'prohibited':
        return 'Prohibited or unsafe goods/services';
      case 'reviewing':
        return 'Reviewing';
      case 'dismissed':
        return 'Dismissed';
      case 'resolved':
        return 'Resolved';
      case 'pending':
        return 'Pending';
      default:
        return value.isEmpty
            ? 'Other'
            : '${value[0].toUpperCase()}${value.substring(1)}';
    }
  }

  String _formatDate(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return 'Date unavailable';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final relation = report['listings'];
    String title = 'Listing';
    if (relation is Map && relation['title'] != null) {
      title = relation['title'].toString();
    }
    final status = (report['status'] ?? 'pending').toString();
    final pending = status == 'pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE4EBE6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _label((report['report_type'] ?? '').toString()),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: pending
                        ? const Color(0xFFFFF4D6)
                        : const Color(0xFFE9F2EC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _label(status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: pending ? const Color(0xFF8A5500) : green,
                    ),
                  ),
                ),
                Text(
                  _formatDate(report['created_at']),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Reason: ${_label((report['reason'] ?? 'other').toString())}',
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            const SizedBox(height: 10),
            Text(
              (report['details'] ?? '').toString(),
              style: const TextStyle(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      // The parent AuthGate will replace this screen with Registration.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _reports.where((report) {
      return _reportFilter == 'all' || report['status'] == _reportFilter;
    }).toList();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh dashboard',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadData,
          ),
          IconButton(
            tooltip: 'Sign out of Admin',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 56),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: green,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Management Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 23,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_count('pending_reports')} report(s) awaiting review',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const MarketplaceSectionHeader(
                        'Management',
                        subtitle: 'Keep your community safe and connected.',
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _managementCard(
                            'User Management',
                            'Accounts and access',
                            Icons.manage_accounts_outlined,
                            const AdminUserManagementScreen(),
                          ),
                          _managementCard(
                            'Advertisement Management',
                            'Review and moderate listings',
                            Icons.campaign_outlined,
                            const AdminAdvertisementsScreen(),
                          ),
                          _managementCard(
                            'Reports Management',
                            'Review community reports',
                            Icons.fact_check_outlined,
                            const AdminReportsManagementScreen(),
                          ),
                        ],
                      ),
                      const MarketplaceSectionHeader(
                        'Live overview',
                        subtitle: 'Current marketplace activity',
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _metricCard(
                            'Total accounts',
                            'total_users',
                            Icons.people_outline,
                          ),
                          _metricCard(
                            'Active accounts',
                            'active_users',
                            Icons.verified_user_outlined,
                          ),
                          _metricCard(
                            'Active advertisements',
                            'active_listings',
                            Icons.campaign_outlined,
                          ),
                          _metricCard(
                            'Active products',
                            'active_products',
                            Icons.shopping_bag_outlined,
                          ),
                          _metricCard(
                            'Active services',
                            'active_services',
                            Icons.handyman_outlined,
                          ),
                          _metricCard(
                            'Pending reports',
                            'pending_reports',
                            Icons.flag_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Submitted Reports',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DropdownButton<String>(
                            value: _reportFilter,
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('All'),
                              ),
                              DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pending'),
                              ),
                              DropdownMenuItem(
                                value: 'reviewing',
                                child: Text('Reviewing'),
                              ),
                              DropdownMenuItem(
                                value: 'resolved',
                                child: Text('Resolved'),
                              ),
                              DropdownMenuItem(
                                value: 'dismissed',
                                child: Text('Dismissed'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _reportFilter = value);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your latest 50 community reports. Open Reports Management to review and take action.',
                        style: TextStyle(color: Color(0xFF617168)),
                      ),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'No reports in this view.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ...filtered.map(_reportCard),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
