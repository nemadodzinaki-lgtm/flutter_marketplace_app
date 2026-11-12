import '../widgets/chat_person_avatar.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/messaging_service.dart';
import 'chat_screen.dart';
import 'listing_reviews_screen.dart';
import 'report_listing_screen.dart';
import 'public_seller_profile_screen.dart';

class ListingDetailsScreen extends StatefulWidget {
  final String listingId;

  const ListingDetailsScreen({super.key, required this.listingId});

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  late Future<Map<String, dynamic>?> _listingFuture;
  Future<Map<String, dynamic>?>? _sellerFuture;
  int _currentImage = 0;
  bool _isFavourite = false;
  bool _favouriteLoading = true;
  bool _favouriteSaving = false;
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    _listingFuture = _loadListing();
    _loadFavourite();
  }

  Future<Map<String, dynamic>?> _loadListing() async {
    final listing = await Supabase.instance.client
        .from('listings')
        .select('''
          id, seller_id, title, description, price, price_type,
          listing_type, condition, quantity, suburb, city, province,
          status, listing_images(image_url, is_primary, display_order)
        ''')
        .eq('id', widget.listingId)
        .eq('status', 'active')
        .maybeSingle();
    final sellerId = listing?['seller_id']?.toString();
    if (sellerId != null && sellerId.isNotEmpty) {
      _sellerFuture = _loadPublicSeller(sellerId);
    }
    return listing;
  }

  Future<Map<String, dynamic>?> _loadPublicSeller(String id) async {
    try {
      final rows = await Supabase.instance.client.rpc(
        'marketplace_public_seller_profile',
        params: {'p_seller_id': id},
      );
      return rows is List && rows.isNotEmpty && rows.first is Map
          ? Map<String, dynamic>.from(rows.first as Map)
          : null;
    } catch (_) {
      return null; // Seller card failure never blocks the advertisement.
    }
  }

  Widget _sellerCard() => FutureBuilder<Map<String, dynamic>?>(
    future: _sellerFuture,
    builder: (context, snapshot) {
      final seller = snapshot.data;
      if (seller == null) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              ChatPersonAvatar(
                imageUrl: seller['profile_image_url']?.toString(),
                size: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MEET THE SELLER',
                      style: TextStyle(
                        fontSize: 11,
                        color: green,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (seller['display_name'] ?? 'Community member').toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [seller['city'], seller['province']]
                          .where((v) => v != null && v.toString().isNotEmpty)
                          .join(', '),
                      style: const TextStyle(color: Color(0xFF617168)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _loadFavourite() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _favouriteLoading = false);
      return;
    }

    try {
      final result = await supabase
          .from('favorites')
          .select('id')
          .eq('user_id', user.id)
          .eq('listing_id', widget.listingId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _isFavourite = result != null;
        _favouriteLoading = false;
      });
    } catch (error) {
      debugPrint('Favourite read error: $error');
      if (!mounted) return;
      setState(() => _favouriteLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to check saved listings.')),
      );
    }
  }

  Future<void> _toggleFavourite() async {
    if (_favouriteSaving || _favouriteLoading) return;
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please sign in first.')));
      return;
    }

    setState(() => _favouriteSaving = true);
    try {
      if (_isFavourite) {
        await supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('listing_id', widget.listingId);
      } else {
        await supabase
            .from('favorites')
            .upsert(
              {'user_id': user.id, 'listing_id': widget.listingId},
              onConflict: 'user_id,listing_id',
              ignoreDuplicates: true,
            );
      }
      if (!mounted) return;
      setState(() => _isFavourite = !_isFavourite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavourite ? 'Added to Favourites.' : 'Removed from Favourites.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      debugPrint('Favourite save error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update Favourites. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _favouriteSaving = false);
    }
  }

  Future<void> _contactSeller(Map<String, dynamic> listing) async {
    if (_openingChat) return;
    final sellerId = (listing['seller_id'] ?? '').toString();
    if (sellerId.isEmpty) return;

    setState(() => _openingChat = true);
    try {
      final id = await MessagingService.openConversation(
        listingId: widget.listingId,
        sellerId: sellerId,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id)),
      );
    } catch (error) {
      debugPrint('Contact seller failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open chat. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _reportListing(Map<String, dynamic> listing) async {
    final sellerId = (listing['seller_id'] ?? '').toString();
    if (sellerId.isEmpty) return;

    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportListingScreen(
          listingId: widget.listingId,
          listingTitle: (listing['title'] ?? 'Advertisement').toString(),
          sellerId: sellerId,
        ),
      ),
    );

    if (!mounted || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report submitted. Thank you for helping keep the community safe.',
        ),
        backgroundColor: green,
      ),
    );
  }

  void _retry() {
    setState(() {
      _currentImage = 0;
      _listingFuture = _loadListing();
      _favouriteLoading = true;
    });
    _loadFavourite();
  }

  List<Map<String, dynamic>> _images(Map<String, dynamic> listing) {
    final raw = listing['listing_images'];
    if (raw is! List) return [];

    final images = raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['image_url'] ?? '').toString().isNotEmpty)
        .toList();
    images.sort((a, b) {
      final aPrimary = a['is_primary'] == true ? 0 : 1;
      final bPrimary = b['is_primary'] == true ? 0 : 1;
      if (aPrimary != bPrimary) return aPrimary.compareTo(bPrimary);
      final aOrder = (a['display_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['display_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return images;
  }

  String _price(Map<String, dynamic> listing) {
    final raw = listing['price'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw.toString()) ?? 0;
    final suffix = switch (listing['price_type']) {
      'per_hour' => ' / hour',
      'per_day' => ' / day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };
    return 'R ${value.toStringAsFixed(2)}$suffix';
  }

  String _location(Map<String, dynamic> listing) {
    final parts = [listing['suburb'], listing['city'], listing['province']]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .map((part) => part.toString())
        .toList();
    return parts.isEmpty ? 'Location not provided' : parts.join(', ');
  }

  String _condition(String value) {
    return value
        .split('_')
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFE8F2EC),
    alignment: Alignment.center,
    child: const Icon(Icons.image_outlined, size: 76, color: green),
  );

  Widget _gallery(Map<String, dynamic> listing) {
    final images = _images(listing);
    if (images.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 280 : 400,
          width: double.infinity,
          child: _placeholder(),
        ),
      );
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).width < 600 ? 280 : 400,
            width: double.infinity,
            child: PageView.builder(
              itemCount: images.length,
              onPageChanged: (index) => setState(() => _currentImage = index),
              itemBuilder: (context, index) => Image.network(
                images[index]['image_url'].toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(),
              ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(images.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 7,
                width: index == _currentImage ? 22 : 7,
                decoration: BoxDecoration(
                  color: index == _currentImage ? green : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF617168))),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _details(Map<String, dynamic> listing) {
    final isService = listing['listing_type'] == 'service';
    final ownListing =
        listing['seller_id'] == Supabase.instance.client.auth.currentUser?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gallery(listing),
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE5F4E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isService ? 'SERVICE' : 'PRODUCT',
                style: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            if (!ownListing)
              OutlinedButton.icon(
                onPressed: _favouriteLoading || _favouriteSaving
                    ? null
                    : _toggleFavourite,
                icon: _favouriteSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isFavourite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                label: Text(_isFavourite ? 'Saved' : 'Save'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          listing['title']?.toString() ?? 'Untitled listing',
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          _price(listing),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: green,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: Colors.grey,
              size: 19,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _location(listing),
                style: const TextStyle(color: Color(0xFF617168)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!ownListing)
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _openingChat ? null : () => _contactSeller(listing),
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _openingChat
                  ? const SizedBox(
                      height: 19,
                      width: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(_openingChat ? 'Opening chat...' : 'Contact Seller'),
            ),
          ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 18),
        const Text(
          'Description',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          listing['description']?.toString() ?? 'No description provided.',
          style: const TextStyle(fontSize: 15, height: 1.6),
        ),
        const SizedBox(height: 25),
        const Divider(),
        const SizedBox(height: 18),
        const Text(
          'Listing Information',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _infoRow('Type', isService ? 'Service' : 'Product'),
        if (!isService && listing['condition'] != null)
          _infoRow('Condition', _condition(listing['condition'].toString())),
        if (!isService && listing['quantity'] != null)
          _infoRow('Available quantity', listing['quantity'].toString()),
        _infoRow('Status', 'Available'),
        const SizedBox(height: 20),
        _sellerCard(),

        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('View Seller Profile'),
            onPressed: () {
              final sellerId = (listing['seller_id'] ?? '').toString();

              if (sellerId.isEmpty) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicSellerProfileScreen(sellerId: sellerId),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListingReviewsScreen(
                    listingId: widget.listingId,
                    listingTitle: (listing['title'] ?? 'Listing').toString(),
                    sellerId: (listing['seller_id'] ?? '').toString(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.star_outline_rounded),
            label: const Text('Reviews & Ratings'),
            style: OutlinedButton.styleFrom(
              foregroundColor: green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!ownListing) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _reportListing(listing),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report Listing or Seller'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
        if (ownListing)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'This is your listing. Buyers can contact you through Messages.',
              style: TextStyle(color: Color(0xFF617168)),
            ),
          ),
        const SizedBox(height: 30),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Listing Details'),
        backgroundColor: const Color(0xFFF7F9F8),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _listingFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: green));
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 50),
                  const SizedBox(height: 12),
                  const Text('Unable to load listing details.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }
          final listing = snapshot.data;
          if (listing == null) {
            return const Center(
              child: Text('This listing is no longer available.'),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _details(listing),
              ),
            ),
          );
        },
      ),
    );
  }
}
