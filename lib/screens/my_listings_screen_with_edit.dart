import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'edit_listing_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  List<Map<String, dynamic>> _listings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Please sign in to view your listings.');
      }

      final rows = await supabase
          .from('listings')
          .select('''
            id,
            title,
            price,
            price_type,
            listing_type,
            status,
            suburb,
            city,
            created_at,
            listing_images(image_url, is_primary, display_order)
          ''')
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _listings = List<Map<String, dynamic>>.from(rows);
      });
    } catch (error) {
      debugPrint('My Listings error: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load your listings. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _price(Map<String, dynamic> listing) {
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

  String? _coverImage(Map<String, dynamic> listing) {
    final raw = listing['listing_images'];
    if (raw is! List || raw.isEmpty) return null;

    final images = raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['image_url'] ?? '').toString().trim().isNotEmpty)
        .toList();

    if (images.isEmpty) return null;

    images.sort((a, b) {
      final aPrimary = a['is_primary'] == true ? 0 : 1;
      final bPrimary = b['is_primary'] == true ? 0 : 1;
      if (aPrimary != bPrimary) return aPrimary.compareTo(bPrimary);
      final aOrder = (a['display_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['display_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });

    return images.first['image_url'].toString();
  }

  String _location(Map<String, dynamic> listing) {
    final parts = [listing['suburb'], listing['city']]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString())
        .toList();
    return parts.isEmpty ? 'Location not provided' : parts.join(', ');
  }

  String _statusLabel(String status) {
    return switch (status) {
      'active' => 'Active',
      'sold' => 'Sold',
      'unavailable' => 'Unavailable',
      'removed' => 'Removed',
      _ => status,
    };
  }

  Color _statusColor(String status) {
    return switch (status) {
      'active' => green,
      'sold' => const Color(0xFF2563EB),
      'unavailable' => const Color(0xFF92400E),
      _ => const Color(0xFF6B7280),
    };
  }

  Widget _image(Map<String, dynamic> listing) {
    final url = _coverImage(listing);

    if (url == null) {
      return Container(
        color: const Color(0xFFE5F4E9),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, size: 40, color: green),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: const Color(0xFFE5F4E9),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: green),
      ),
    );
  }

  Widget _listingCard(Map<String, dynamic> listing) {
    final status = (listing['status'] ?? 'unknown').toString();
    final isActive = status == 'active';
    final color = _statusColor(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        onTap: isActive
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ListingDetailsScreen(
                      listingId: listing['id'].toString(),
                    ),
                  ),
                );
                if (mounted) await _loadListings();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 100,
                  height: 108,
                  child: _image(listing),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing['title']?.toString() ?? 'Untitled',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _price(listing),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: green,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            listing['listing_type'] == 'service'
                                ? 'Service'
                                : 'Product',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _location(listing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF617168),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                IconButton(
                  tooltip: 'Edit listing',
                  icon: const Icon(Icons.edit_outlined, color: green),
                  onPressed: () async {
                    final saved = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditListingScreen(
                          listingId: listing['id'].toString(),
                        ),
                      ),
                    );
                    if (!mounted) return;
                    if (saved == true) {
                      await _loadListings();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Listing updated successfully!'),
                          backgroundColor: green,
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F8),
        title: const Text('My Listings'),
        actions: [
          IconButton(
            tooltip: 'Refresh my listings',
            onPressed: _loading ? null : _loadListings,
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
                  const Icon(Icons.wifi_off, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadListings,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadListings,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 850),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text(
                        'Your advertisements',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${_listings.length} listing(s) posted by you',
                        style: const TextStyle(color: Color(0xFF617168)),
                      ),
                      const SizedBox(height: 24),
                      if (_listings.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 55,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 60,
                                color: green,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'You have no listings yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Use Post Listing on the homepage '
                                'to advertise your first product or service.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ..._listings.map(_listingCard),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
