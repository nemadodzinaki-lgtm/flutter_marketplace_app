import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'advanced_search_screen.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  bool _loading = true;
  String? _error;
  String? _removingId;
  List<Map<String, dynamic>> _listings = [];

  @override
  void initState() {
    super.initState();
    _loadFavourites();
  }

  Future<void> _loadFavourites() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw StateError('Please sign in first.');

      final savedRows = await supabase
          .from('favorites')
          .select('listing_id')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(100);
      final ids = savedRows
          .map((row) => row['listing_id']?.toString())
          .whereType<String>()
          .toList();

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() => _listings = []);
        return;
      }

      final rows = await supabase
          .from('listings')
          .select('''
            id, title, price, price_type, listing_type, suburb, city,
            listing_images(image_url, is_primary, display_order)
          ''')
          .inFilter('id', ids)
          .eq('status', 'active');

      final lookup = <String, Map<String, dynamic>>{
        for (final row in rows) row['id'].toString(): row,
      };

      if (!mounted) return;
      setState(() {
        _listings = [
          for (final id in ids)
            if (lookup[id] != null) lookup[id]!,
        ];
      });
    } catch (error) {
      debugPrint('Favourites load error: $error');
      if (!mounted) return;
      setState(() => _error = 'Unable to load Favourites. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavourite(String listingId) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null || _removingId != null) return;

    setState(() => _removingId = listingId);
    try {
      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', user.id)
          .eq('listing_id', listingId);
      if (!mounted) return;
      setState(() {
        _listings.removeWhere((item) => item['id'].toString() == listingId);
      });
    } catch (error) {
      debugPrint('Favourites remove error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove favourite.')),
      );
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  String? _imageUrl(Map<String, dynamic> listing) {
    final images = listing['listing_images'];
    if (images is! List || images.isEmpty) return null;
    final valid = images.whereType<Map>().toList();
    if (valid.isEmpty) return null;
    valid.sort((a, b) {
      final aPrimary = a['is_primary'] == true ? 0 : 1;
      final bPrimary = b['is_primary'] == true ? 0 : 1;
      if (aPrimary != bPrimary) return aPrimary.compareTo(bPrimary);
      final aOrder = (a['display_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['display_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });
    final url = valid.first['image_url']?.toString();
    return url == null || url.isEmpty ? null : url;
  }

  String _price(Map<String, dynamic> listing) {
    final raw = listing['price'];
    final amount = raw is num
        ? raw.toDouble()
        : double.tryParse(raw.toString()) ?? 0;
    final suffix = switch (listing['price_type']) {
      'per_hour' => '/hour',
      'per_day' => '/day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };
    return 'R ${amount.toStringAsFixed(2)}$suffix';
  }

  Widget _card(Map<String, dynamic> listing) {
    final id = listing['id'].toString();
    final imageUrl = _imageUrl(listing);
    final area = [
      listing['suburb'],
      listing['city'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(', ');

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8EEEA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ListingDetailsScreen(listingId: id),
            ),
          );
          if (!mounted) return;
          await _loadFavourites();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: imageUrl == null
                      ? Container(
                          color: const Color(0xFFE8F2EC),
                          child: const Icon(Icons.image_outlined, color: green),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFE8F2EC),
                            child: const Icon(
                              Icons.image_outlined,
                              color: green,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing['title']?.toString() ?? 'Untitled listing',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _price(listing),
                      style: const TextStyle(
                        color: green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (area.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from Favourites',
                onPressed: _removingId == null
                    ? () => _removeFavourite(id)
                    : null,
                icon: _removingId == id
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_rounded, color: green),
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
        title: const Text('My Favourites'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh Favourites',
            onPressed: _loadFavourites,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFavourites,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: green))
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 130),
                  Center(child: Text(_error!)),
                  const SizedBox(height: 12),
                  Center(
                    child: ElevatedButton(
                      onPressed: _loadFavourites,
                      child: const Text('Try Again'),
                    ),
                  ),
                ],
              )
            : _listings.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  MarketplaceEmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'Keep your favourites close',
                    message:
                        'Save the finds you love and come back to them here.',
                    actionLabel: 'Explore advertisements',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdvancedSearchScreen(),
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _listings.length,
                itemBuilder: (context, index) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 850),
                    child: _card(_listings[index]),
                  ),
                ),
              ),
      ),
    );
  }
}
