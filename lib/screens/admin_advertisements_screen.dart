import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 31C: Administrator-only advertisement moderation.
/// Permissions are enforced by the checked Supabase RPCs, not by this widget.
class AdminAdvertisementsScreen extends StatefulWidget {
  const AdminAdvertisementsScreen({super.key});

  @override
  State<AdminAdvertisementsScreen> createState() =>
      _AdminAdvertisementsScreenState();
}

class _AdminAdvertisementsScreenState extends State<AdminAdvertisementsScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);
  static const int pageSize = 20;

  final _client = Supabase.instance.client;
  final _search = TextEditingController();

  List<Map<String, dynamic>> _advertisements = [];
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  String _activeSearch = '';
  String? _error;
  String? _changingListingId;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadAdvertisements();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAdvertisements({bool append = false}) async {
    if (_loading || _loadingMore) return;

    final offset = append ? _advertisements.length : 0;
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
        'admin_list_marketplace_advertisements',
        params: {
          'p_search': _activeSearch,
          'p_status': _statusFilter,
          'p_type': _typeFilter,
          'p_limit': pageSize,
          'p_offset': offset,
        },
      );

      final data = Map<String, dynamic>.from(response as Map);
      final rows = (data['advertisements'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final total = (data['total'] as num?)?.toInt() ?? 0;
      if (!mounted) return;

      setState(() {
        _advertisements = append ? [..._advertisements, ...rows] : rows;
        _total = total;
      });
    } on PostgrestException catch (error) {
      debugPrint('Marketplace operation failed: ${error.code}');
      if (!mounted) return;
      setState(
        () => _error = 'Unable to load this information. Please try again.',
      );
    } catch (error) {
      debugPrint('Admin advertisements fetch error: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load advertisements. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _applySearch() {
    final query = _search.text.trim();
    if (query.length > 80) {
      _message('Search must be 80 characters or fewer.');
      return;
    }
    _activeSearch = query;
    FocusScope.of(context).unfocus();
    _loadAdvertisements();
  }

  String _label(String raw) {
    switch (raw) {
      case 'unavailable':
        return 'Unavailable';
      case 'removed':
        return 'Removed by admin';
      case 'sold':
        return 'Sold';
      case 'active':
        return 'Active';
      case 'product':
        return 'Product';
      case 'service':
        return 'Service';
      default:
        return raw.isEmpty
            ? 'Unknown'
            : '${raw[0].toUpperCase()}${raw.substring(1)}';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return green;
      case 'sold':
        return const Color(0xFF475569);
      case 'unavailable':
        return const Color(0xFFB45309);
      case 'removed':
        return const Color(0xFFB91C1C);
      default:
        return Colors.blueGrey;
    }
  }

  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatPrice(Map<String, dynamic> listing) {
    final raw = listing['price'];
    final amount = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;
    final suffix = switch (listing['price_type']) {
      'per_hour' => ' / hour',
      'per_day' => ' / day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };
    return 'R ${amount.toStringAsFixed(2)}$suffix';
  }

  String _date(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (parsed == null) return 'Unknown date';
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year}';
  }

  String _sellerName(Map<String, dynamic> ad) {
    final parts = [ad['seller_first_name'], ad['seller_surname']]
        .where((p) => p != null && p.toString().trim().isNotEmpty)
        .map((p) => p.toString().trim())
        .toList();
    return parts.isEmpty ? 'Seller' : parts.join(' ');
  }

  String _location(Map<String, dynamic> ad) {
    final parts = [ad['suburb'], ad['city'], ad['province']]
        .where((p) => p != null && p.toString().trim().isNotEmpty)
        .map((p) => p.toString().trim())
        .toList();
    return parts.isEmpty ? 'Area not provided' : parts.join(', ');
  }

  Future<void> _moderate(Map<String, dynamic> ad, String nextStatus) async {
    if (_changingListingId != null) return;
    final id = ad['id']?.toString();
    if (id == null || id.isEmpty) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ModerationReasonDialog(
        title: nextStatus == 'removed'
            ? 'Remove advertisement?'
            : 'Restore advertisement?',
        listingTitle: ad['title']?.toString() ?? 'This advertisement',
        removing: nextStatus == 'removed',
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _changingListingId = id);
    try {
      await _client.rpc(
        'admin_moderate_marketplace_advertisement',
        params: {
          'p_listing_id': id,
          'p_new_status': nextStatus,
          'p_reason': reason,
        },
      );
      if (!mounted) return;
      _message(
        nextStatus == 'removed'
            ? 'Advertisement removed from public browsing.'
            : 'Advertisement restored as active.',
      );
      await _loadAdvertisements();
    } on PostgrestException catch (error) {
      debugPrint('Marketplace operation failed: ${error.code}');
      _message('Unable to update advertisement. Please try again.');
    } catch (error) {
      debugPrint('Advertisement moderation error: $error');
      _message('Unable to update advertisement. Please try again.');
    } finally {
      if (mounted) setState(() => _changingListingId = null);
    }
  }

  void _showDetails(Map<String, dynamic> ad) {
    final last = ad['last_moderation'];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                ad['title']?.toString() ?? 'Advertisement',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusPill(ad['status']?.toString() ?? ''),
                  Chip(
                    label: Text(_label(ad['listing_type']?.toString() ?? '')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _formatPrice(ad),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: green,
                ),
              ),
              const SizedBox(height: 12),
              Text('Seller: ${_sellerName(ad)}'),
              Text(
                'Seller account: ${_label(ad['seller_account_status']?.toString() ?? '')}',
              ),
              Text('Category: ${ad['category_name'] ?? 'Not specified'}'),
              Text('Area: ${_location(ad)}'),
              Text('Posted: ${_date(ad['created_at'])}'),
              const SizedBox(height: 20),
              const Text(
                'Advertisement description',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 8),
              SelectableText(ad['description']?.toString() ?? 'No description'),
              if (last is Map) ...[
                const SizedBox(height: 20),
                const Divider(),
                const Text(
                  'Latest moderation decision',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const SizedBox(height: 7),
                Text('Action: ${_label(last['new_status']?.toString() ?? '')}'),
                Text('Date: ${_date(last['created_at'])}'),
                Text(last['reason']?.toString() ?? ''),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adCard(Map<String, dynamic> ad) {
    final status = ad['status']?.toString() ?? '';
    final id = ad['id']?.toString() ?? '';
    final removing = status != 'removed';
    final busy = _changingListingId != null;
    final cover = ad['cover_url']?.toString() ?? '';
    final openReports = (ad['open_reports'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFFE3EAE6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 102,
                    height: 106,
                    child: cover.isEmpty
                        ? _imagePlaceholder()
                        : Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _imagePlaceholder(),
                          ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad['title']?.toString() ?? 'Untitled advertisement',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _formatPrice(ad),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: green,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _sellerName(ad),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF617168),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _statusPill(status),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  ad['category_name']?.toString() ?? 'Uncategorized',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _location(ad),
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
                if (openReports > 0)
                  Text(
                    '$openReports open report${openReports == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _showDetails(ad),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Review details'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _moderate(ad, removing ? 'removed' : 'active'),
                  icon: Icon(
                    removing ? Icons.block_outlined : Icons.restore_outlined,
                    size: 18,
                  ),
                  label: Text(removing ? 'Remove ad' : 'Restore ad'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: removing ? const Color(0xFFB91C1C) : green,
                  ),
                ),
                if (busy && _changingListingId == id)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
    color: const Color(0xFFEAF3EE),
    alignment: Alignment.center,
    child: const Icon(Icons.image_outlined, size: 36, color: green),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Advertisement Management'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh advertisements',
            onPressed: _loading ? null : () => _loadAdvertisements(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadAdvertisements(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                const MarketplaceSectionHeader(
                  'Manage community advertisements',
                  icon: Icons.campaign_outlined,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Review all products and services. Removed ads disappear from public search but stay available for admin review.',
                  style: TextStyle(color: Color(0xFF617168)),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _applySearch(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: 'Search title, seller or city',
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: _applySearch,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _statusFilter,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All statuses'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(value: 'sold', child: Text('Sold')),
                          DropdownMenuItem(
                            value: 'unavailable',
                            child: Text('Unavailable'),
                          ),
                          DropdownMenuItem(
                            value: 'removed',
                            child: Text('Removed'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _statusFilter = value);
                          _loadAdvertisements();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _typeFilter,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Products & services'),
                          ),
                          DropdownMenuItem(
                            value: 'product',
                            child: Text('Products'),
                          ),
                          DropdownMenuItem(
                            value: 'service',
                            child: Text('Services'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _typeFilter = value);
                          _loadAdvertisements();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$_total advertisement(s)',
                  style: const TextStyle(
                    color: Color(0xFF617168),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(
                      child: CircularProgressIndicator(color: green),
                    ),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _loadAdvertisements(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else if (_advertisements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(
                      child: Text('No advertisements match these filters.'),
                    ),
                  )
                else ...[
                  ..._advertisements.map(_adCard),
                  if (_advertisements.length < _total)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: OutlinedButton.icon(
                          onPressed: _loadingMore || _loading
                              ? null
                              : () => _loadAdvertisements(append: true),
                          icon: _loadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more),
                          label: Text(
                            _loadingMore ? 'Loading...' : 'Load more',
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModerationReasonDialog extends StatefulWidget {
  final String title;
  final String listingTitle;
  final bool removing;

  const _ModerationReasonDialog({
    required this.title,
    required this.listingTitle,
    required this.removing,
  });

  @override
  State<_ModerationReasonDialog> createState() =>
      _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<_ModerationReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.listingTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                widget.removing
                    ? 'This hides the advertisement from public browsing. The seller cannot reactivate an admin-removed listing.'
                    : 'This restores the advertisement to Active and makes it visible to the public again.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _reason,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason for this decision',
                  hintText: 'Enter at least 10 characters',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final trimmed = (value ?? '').trim();
                  if (trimmed.length < 10 || trimmed.length > 500) {
                    return 'Reason must be 10–500 characters';
                  }
                  return null;
                },
              ),
            ],
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
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _reason.text.trim());
          },
          style: FilledButton.styleFrom(
            backgroundColor: widget.removing
                ? const Color(0xFFB91C1C)
                : const Color(0xFF16803C),
          ),
          child: Text(
            widget.removing ? 'Remove advertisement' : 'Restore advertisement',
          ),
        ),
      ],
    );
  }
}
