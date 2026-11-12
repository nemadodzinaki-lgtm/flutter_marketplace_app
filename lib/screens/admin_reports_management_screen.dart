import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 31A: management of reports only.
/// The database RPC checks the caller's administrator role independently.
class AdminReportsManagementScreen extends StatefulWidget {
  const AdminReportsManagementScreen({super.key});

  @override
  State<AdminReportsManagementScreen> createState() =>
      _AdminReportsManagementScreenState();
}

class _AdminReportsManagementScreenState
    extends State<AdminReportsManagementScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _reports = [];
  String _filter = 'pending';
  bool _loading = true;
  String? _busyReport;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) throw StateError('Please sign in as administrator.');

      // A UI check for understandable errors; RLS and the RPC enforce security.
      final profile = await _client
          .from('profiles')
          .select('role, account_status')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role'] != 'admin' ||
          profile?['account_status'] != 'active') {
        throw StateError('Only active administrators can manage reports.');
      }

      final rows = await _client
          .from('marketplace_reports')
          .select('''
        id, report_type, reason, details, status, created_at,
        admin_note, reviewed_at,
        listings!marketplace_reports_listing_id_fkey(title)
      ''')
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() => _reports = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('Load reports failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Unable to load reports. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  String _listingTitle(Map<String, dynamic> report) {
    final listing = report['listings'];
    if (listing is Map && listing['title'] != null) {
      return listing['title'].toString();
    }
    return 'Advertisement';
  }

  Future<void> _changeStatus(
    Map<String, dynamic> report,
    String newStatus,
  ) async {
    if (_busyReport != null) return;
    final id = report['id']?.toString();
    if (id == null) return;

    String? note;
    if (newStatus == 'resolved' || newStatus == 'dismissed') {
      final controller = TextEditingController();
      try {
        note = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              newStatus == 'resolved' ? 'Resolve Report' : 'Dismiss Report',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record the reason for this decision. '
                  'It will be stored privately for administrators.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Decision note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.length < 10) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Write at least 10 characters.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, value);
                },
                child: Text(newStatus == 'resolved' ? 'Resolve' : 'Dismiss'),
              ),
            ],
          ),
        );
      } finally {
        // Dispose after the dialog route finishes its transition.
        // Using a brief microtask is sufficient after the pop result.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.dispose(),
        );
      }
      if (note == null || !mounted) return;
    } else {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Start reviewing this report?'),
          content: const Text(
            'This marks the report as Reviewing. No listing or account will be changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start Review'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _busyReport = id);
    try {
      await _client.rpc(
        'admin_review_marketplace_report',
        params: {
          'p_report_id': id,
          'p_new_status': newStatus,
          'p_admin_note': note,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report marked ${_label(newStatus)}.')),
      );
      await _loadReports();
    } on PostgrestException catch (e) {
      debugPrint('Marketplace operation failed: ${e.code}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update report. Please try again.')),
      );
    } catch (e) {
      debugPrint('Report moderation error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update the report.')),
      );
    } finally {
      if (mounted) setState(() => _busyReport = null);
    }
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final status = report['status']?.toString() ?? 'pending';
    final pending = status == 'pending';
    final open = pending || status == 'reviewing';
    final reportId = report['id']?.toString();
    final busy = _busyReport != null;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
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
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(_label(status))),
                Chip(
                  label: Text(
                    _label(report['report_type']?.toString() ?? 'listing'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _listingTitle(report),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 7),
            Text('Reason: ${_label(report['reason']?.toString() ?? 'other')}'),
            const SizedBox(height: 10),
            Text(
              report['details']?.toString() ?? '',
              style: const TextStyle(height: 1.45),
            ),
            if (report['admin_note'] != null) ...[
              const Divider(height: 25),
              Text(
                'Admin decision: ${report['admin_note']}',
                style: const TextStyle(color: Color(0xFF475569)),
              ),
            ],
            if (open) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pending)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _changeStatus(report, 'reviewing'),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Start Review'),
                    ),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _changeStatus(report, 'resolved'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Resolve'),
                    style: FilledButton.styleFrom(backgroundColor: green),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _changeStatus(report, 'dismissed'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Dismiss'),
                  ),
                ],
              ),
              if (_busyReport == reportId)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _reports
        .where((report) => _filter == 'all' || report['status'] == _filter)
        .toList();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Manage Reports'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _loading ? null : _loadReports,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadReports,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      const MarketplaceSectionHeader(
                        'Community Reports',
                        icon: Icons.fact_check_outlined,
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Review concerns about advertisements and sellers. '
                        'Closing a report does not automatically punish anyone.',
                        style: TextStyle(color: Color(0xFF617168)),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final entry in const [
                            ['pending', 'Pending'],
                            ['reviewing', 'Reviewing'],
                            ['resolved', 'Resolved'],
                            ['dismissed', 'Dismissed'],
                            ['all', 'All'],
                          ])
                            ChoiceChip(
                              label: Text(entry[1]),
                              selected: _filter == entry[0],
                              onSelected: (_) =>
                                  setState(() => _filter = entry[0]),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(25),
                          child: Center(
                            child: Text('No reports in this view.'),
                          ),
                        )
                      else
                        ...filtered.map(_reportCard),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
