import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 31B: admin-only user management.
/// The Supabase RPCs enforce administrator permissions independently of this UI.
class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  State<AdminUserManagementScreen> createState() =>
      _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);
  static const int pageSize = 25;

  final _client = Supabase.instance.client;
  final _search = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  String _statusFilter = 'all';
  String _activeSearch = '';
  String? _error;
  String? _changingId;
  bool _loading = false;
  bool _loadingMore = false;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool append = false}) async {
    if (_loading || _loadingMore) return;
    final offset = append ? _users.length : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });

    try {
      final response = await _client.rpc(
        'admin_list_marketplace_users',
        params: {
          'p_search': _activeSearch,
          'p_status': _statusFilter,
          'p_limit': pageSize,
          'p_offset': offset,
        },
      );

      final data = Map<String, dynamic>.from(response as Map);
      final rows = (data['users'] as List<dynamic>? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final count = (data['total'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      setState(() {
        _users = append ? [..._users, ...rows] : rows;
        _total = count;
      });
    } on PostgrestException catch (error) {
      debugPrint('Marketplace operation failed: ${error.code}');
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load this information. Please try again.';
      });
    } catch (error) {
      debugPrint('User management load failed: $error');
      if (!mounted) return;
      setState(() => _error = 'Could not load accounts. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _applySearch() {
    final next = _search.text.trim();
    if (next.length > 80) {
      _message('Search must be 80 characters or fewer.');
      return;
    }
    _activeSearch = next;
    _loadUsers();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _label(String raw) =>
      raw.isEmpty ? 'Unknown' : '${raw[0].toUpperCase()}${raw.substring(1)}';

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return green;
      case 'suspended':
        return const Color(0xFFB45309);
      case 'banned':
        return const Color(0xFFB91C1C);
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> user, String target) async {
    if (_changingId != null) return;
    final userId = user['id']?.toString();
    if (userId == null) return;

    final name = [user['first_name'], user['surname']]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .map((part) => part.toString())
        .join(' ');

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _StatusReasonDialog(
        targetStatus: target,
        userName: name.isEmpty ? 'this user' : name,
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _changingId = userId);
    try {
      await _client.rpc(
        'admin_set_marketplace_user_status',
        params: {
          'p_user_id': userId,
          'p_new_status': target,
          'p_reason': reason,
        },
      );

      if (!mounted) return;
      _message('Account marked ${_label(target)}.');
      // Don't show a previous status; retrieve the authoritative result.
      await _loadUsers();
    } on PostgrestException catch (error) {
      debugPrint('Marketplace operation failed: ${error.code}');
      _message('Unable to update account. Please try again.');
    } catch (error) {
      debugPrint('User status update failed: $error');
      _message('Unable to update this account.');
    } finally {
      if (mounted) setState(() => _changingId = null);
    }
  }

  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final role = user['role']?.toString() ?? 'user';
    final status = user['account_status']?.toString() ?? 'unknown';
    final id = user['id']?.toString() ?? '';
    final isSelf = id == _client.auth.currentUser?.id;
    final canManage = role == 'user' && !isSelf;
    final busy = _changingId != null;
    final name = [user['first_name'], user['surname']]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString())
        .join(' ');
    final email = user['email']?.toString() ?? 'No email available';
    final city = user['city']?.toString();
    final lastAction = user['last_action'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE3EBE6)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE5F4E9),
                  foregroundColor: green,
                  child: Icon(
                    role == 'admin'
                        ? Icons.admin_panel_settings_outlined
                        : Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Unnamed account' : name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF617168),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusPill(status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'Role: ${_label(role)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF617168),
                  ),
                ),
                if (city != null && city.trim().isNotEmpty)
                  Text(
                    'City: $city',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF617168),
                    ),
                  ),
              ],
            ),
            if (lastAction is Map) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest decision: ${_label(lastAction['new_status']?.toString() ?? '')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      lastAction['reason']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            if (canManage) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'active') ...[
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _changeStatus(user, 'suspended'),
                      icon: const Icon(Icons.pause_circle_outline, size: 18),
                      label: const Text('Suspend'),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => _changeStatus(user, 'banned'),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Ban'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                    ),
                  ] else if (status == 'suspended') ...[
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => _changeStatus(user, 'active'),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Reactivate'),
                      style: FilledButton.styleFrom(backgroundColor: green),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => _changeStatus(user, 'banned'),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Ban'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                    ),
                  ] else if (status == 'banned')
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _changeStatus(user, 'active'),
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Restore Access'),
                    ),
                ],
              ),
            ] else if (role == 'admin') ...[
              const SizedBox(height: 10),
              const Text(
                'Administrator accounts cannot be modified here.',
                style: TextStyle(color: Color(0xFF617168), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh accounts',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _loadUsers(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: () => _loadUsers(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const MarketplaceSectionHeader(
                  'Manage community accounts',
                  icon: Icons.manage_accounts_outlined,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Search accounts, review their status, and record a reason for moderation actions.',
                  style: TextStyle(color: Color(0xFF617168)),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _applySearch(),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: const Icon(Icons.search_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: _applySearch,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(_statusFilter),
                  initialValue: _statusFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Account status',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All accounts')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                    DropdownMenuItem(value: 'banned', child: Text('Banned')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _statusFilter = value);
                    _loadUsers();
                  },
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(45),
                    child: Center(
                      child: CircularProgressIndicator(color: green),
                    ),
                  )
                else if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _loadUsers(),
                    child: const Text('Try Again'),
                  ),
                ] else ...[
                  Text(
                    'Showing ${_users.length} of $_total accounts',
                    style: const TextStyle(color: Color(0xFF617168)),
                  ),
                  const SizedBox(height: 12),
                  if (_users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Text('No accounts match your search.'),
                      ),
                    )
                  else
                    ..._users.map(_userCard),
                  if (_users.length < _total)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _loadingMore
                            ? null
                            : () => _loadUsers(append: true),
                        icon: _loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more),
                        label: const Text('Load More'),
                      ),
                    ),
                ],
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Requests an explicit written reason before the admin can change a status.
class _StatusReasonDialog extends StatefulWidget {
  final String targetStatus;
  final String userName;

  const _StatusReasonDialog({
    required this.targetStatus,
    required this.userName,
  });

  @override
  State<_StatusReasonDialog> createState() => _StatusReasonDialogState();
}

class _StatusReasonDialogState extends State<_StatusReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRestriction = widget.targetStatus != 'active';
    return AlertDialog(
      title: Text('Confirm ${widget.targetStatus}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update ${widget.userName} to ${widget.targetStatus}?'),
                const SizedBox(height: 10),
                Text(
                  isRestriction
                      ? 'Their marketplace access will be restricted. This will not delete their advertisements or messages.'
                      : 'This will restore access to their existing marketplace account.',
                  style: const TextStyle(
                    color: Color(0xFF617168),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _reason,
                  maxLength: 500,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason for this decision',
                    hintText: 'Explain the evidence or reason for this change',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final length = (value ?? '').trim().length;
                    if (length < 10 || length > 500) {
                      return 'Enter a reason of 10 to 500 characters.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _reason.text.trim());
            }
          },
          child: Text(
            widget.targetStatus == 'active' ? 'Restore Access' : 'Confirm',
          ),
        ),
      ],
    );
  }
}
