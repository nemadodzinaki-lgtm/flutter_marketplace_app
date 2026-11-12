import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/messaging_service.dart';
import 'chat_screen.dart';
import 'listing_details_screen.dart';

/// Public seller information deliberately excludes identity numbers,
/// email addresses, phone numbers, account status and GPS coordinates.
class PublicSellerProfileScreen extends StatefulWidget {
  final String sellerId;

  const PublicSellerProfileScreen({super.key, required this.sellerId});

  @override
  State<PublicSellerProfileScreen> createState() =>
      _PublicSellerProfileScreenState();
}

class _PublicSellerData {
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> listings;

  const _PublicSellerData({required this.profile, required this.listings});
}

class _PublicSellerProfileScreenState extends State<PublicSellerProfileScreen> {
  static const _green = Color(0xFF16803C);
  static const _background = Color(0xFFF7F9F8);

  late Future<_PublicSellerData?> _dataFuture;
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadSeller();
  }

  Future<_PublicSellerData?> _loadSeller() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    // Use a secure RPC: do NOT select another user's full profiles row.
    final raw = await client.rpc(
      'marketplace_public_seller_profile',
      params: {'p_seller_id': widget.sellerId},
    );

    if (raw is! List || raw.isEmpty || raw.first is! Map) {
      return null; // Seller not available or not permitted to view.
    }
    final profile = Map<String, dynamic>.from(raw.first as Map);

    // Existing listings and listing_images RLS still apply.
    final result = await client
        .from('listings')
        .select('''
          id, title, price, price_type, listing_type, city, suburb,
          listing_images(image_url, is_primary, display_order)
        ''')
        .eq('seller_id', widget.sellerId)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(50);

    return _PublicSellerData(
      profile: profile,
      listings: List<Map<String, dynamic>>.from(result),
    );
  }

  Future<void> _refresh() async {
    final future = _loadSeller();
    setState(() => _dataFuture = future);
    await future;
  }

  String _area(Map<String, dynamic> profile) {
    final parts = [profile['city'], profile['province']]
        .map((value) => (value ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Area not specified' : parts.join(', ');
  }

  String? _coverImage(Map<String, dynamic> listing) {
    final raw = listing['listing_images'];
    if (raw is! List || raw.isEmpty) return null;
    final images = raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => (row['image_url'] ?? '').toString().isNotEmpty)
        .toList();
    if (images.isEmpty) return null;

    images.sort((a, b) {
      final primaryA = a['is_primary'] == true ? 0 : 1;
      final primaryB = b['is_primary'] == true ? 0 : 1;
      if (primaryA != primaryB) return primaryA.compareTo(primaryB);
      final orderA = (a['display_order'] as num?)?.toInt() ?? 0;
      final orderB = (b['display_order'] as num?)?.toInt() ?? 0;
      return orderA.compareTo(orderB);
    });
    return images.first['image_url']?.toString();
  }

  String _price(Map<String, dynamic> listing) {
    final raw = listing['price'];
    final price = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;
    final suffix = switch (listing['price_type']) {
      'per_hour' => '/hour',
      'per_day' => '/day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };
    return 'R ${price.toStringAsFixed(2)}$suffix';
  }

  Widget _avatar(Map<String, dynamic> profile) {
    final url = (profile['profile_image_url'] ?? '').toString();
    return ClipOval(
      child: SizedBox(
        width: 82,
        height: 82,
        child: url.isEmpty
            ? Container(
                color: const Color(0xFFE6F4EB),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 38,
                  color: _green,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFE6F4EB),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 38,
                    color: _green,
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _contactSeller(_PublicSellerData data) async {
    if (_openingChat || data.listings.isEmpty) return;
    if (Supabase.instance.client.auth.currentUser?.id == widget.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is your own seller profile.')),
      );
      return;
    }

    // Messaging is linked to a listing in the existing database.
    final listingId = data.listings.first['id']?.toString();
    if (listingId == null || listingId.isEmpty) return;

    setState(() => _openingChat = true);
    try {
      final conversationId = await MessagingService.openConversation(
        listingId: listingId,
        sellerId: widget.sellerId,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(conversationId: conversationId),
        ),
      );
    } catch (error) {
      debugPrint('Seller contact error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open chat. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Widget _listingCard(Map<String, dynamic> listing) {
    final id = (listing['id'] ?? '').toString();
    return MarketplaceListingCard(
      title: (listing['title'] ?? 'Advertisement').toString(),
      price: _price(listing),
      imageUrl: _coverImage(listing),
      location: [
        listing['suburb'],
        listing['city'],
      ].where((v) => v != null && v.toString().isNotEmpty).join(', '),
      isService: listing['listing_type'] == 'service',
      onTap: id.isEmpty
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ListingDetailsScreen(listingId: id),
              ),
            ),
    );
  }

  Widget _sellerContent(_PublicSellerData data) {
    final profile = data.profile;
    final count =
        (profile['active_listing_count'] as num?)?.toInt() ??
        data.listings.length;
    final joinedRaw = profile['member_since']?.toString();
    final joined = joinedRaw == null ? null : DateTime.tryParse(joinedRaw);
    final isOwn =
        Supabase.instance.client.auth.currentUser?.id == widget.sellerId;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 950),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Color(0xFFE2EBE5)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          _avatar(profile),
                          const SizedBox(height: 12),
                          Text(
                            (profile['display_name'] ?? 'Community Seller')
                                .toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _area(profile),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF617168)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$count active advertisement${count == 1 ? '' : 's'}'
                            '${joined == null ? '' : ' · Joined ${joined.year}'}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF617168)),
                          ),
                          if (!isOwn && data.listings.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openingChat
                                    ? null
                                    : () => _contactSeller(data),
                                icon: _openingChat
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                      ),
                                label: Text(
                                  _openingChat
                                      ? 'Opening chat...'
                                      : 'Contact Seller',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'Chat is linked to one of this seller’s advertisements.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF617168),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Advertisements',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (data.listings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('No active advertisements.')),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final columns = width >= 850
                            ? 3
                            : width >= 540
                            ? 2
                            : 1;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: data.listings.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent:
                                    330 +
                                    (MediaQuery.textScalerOf(context)
                                                .scale(16) -
                                            16) *
                                        6,
                              ),
                          itemBuilder: (context, index) =>
                              _listingCard(data.listings[index]),
                        );
                      },
                    ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F8),
        title: const Text('Seller Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_PublicSellerData?>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  const Text('Unable to load the seller profile.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _refresh(),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This seller profile is not currently available.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _sellerContent(data);
        },
      ),
    );
  }
}
