import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'advanced_search_screen.dart';

import 'favourites_screen.dart';
import 'messages_inbox_screen.dart';
import '../widgets/unread_messages_badge.dart';
import 'my_profile_screen.dart';

class MarketplaceHomeScreen extends StatefulWidget {
  final String firstName;

  const MarketplaceHomeScreen({super.key, required this.firstName});

  @override
  State<MarketplaceHomeScreen> createState() => _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends State<MarketplaceHomeScreen> {
  static const primaryGreen = Color(0xFF16803C);
  static const background = Color(0xFFF7F9F8);

  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _listings = [];

  final Set<String> _savedIds = {};
  final Set<String> _savingIds = {};
  bool _savedLoaded = false;
  bool _loading = true;
  String? _error;
  int? _selectedCategory;
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    _loadMarketplace();
    _loadSaved();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMarketplace() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;

      final categories = await supabase
          .from('categories')
          .select('id, name, icon_name')
          .eq('is_active', true)
          .order('name');

      final listings = await supabase
          .from('listings')
          .select('''
            id,
            title,
            price,
            price_type,
            listing_type,
            category_id,
            suburb,
            city,
            listing_images(
              image_url,
              is_primary,
              display_order
            )
          ''')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;

      setState(() {
        _categories = List<Map<String, dynamic>>.from(categories);
        _listings = List<Map<String, dynamic>>.from(listings);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load marketplace data.';
      });
      debugPrint('Marketplace error: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadSaved() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final rows = await client
          .from('favorites')
          .select('listing_id')
          .eq('user_id', user.id);
      if (!mounted) return;
      setState(() {
        _savedIds
          ..clear()
          ..addAll(rows.map((row) => row['listing_id'].toString()));
        _savedLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savedLoaded = false);
    }
  }

  Future<void> _toggleSaved(String id) async {
    if (!_savedLoaded || _savingIds.contains(id)) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final wasSaved = _savedIds.contains(id);
    setState(() => _savingIds.add(id));
    try {
      if (wasSaved) {
        await client
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('listing_id', id);
      } else {
        await client
            .from('favorites')
            .upsert(
              {'user_id': user.id, 'listing_id': id},
              onConflict: 'user_id,listing_id',
              ignoreDuplicates: true,
            );
      }
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedIds.remove(id);
        } else {
          _savedIds.add(id);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update favourites. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingIds.remove(id));
    }
  }

  List<Map<String, dynamic>> get _filteredListings {
    final query = _searchController.text.trim().toLowerCase();

    return _listings.where((listing) {
      final title = (listing['title'] ?? '').toString().toLowerCase();
      final city = (listing['city'] ?? '').toString().toLowerCase();
      final suburb = (listing['suburb'] ?? '').toString().toLowerCase();

      final matchesSearch =
          query.isEmpty ||
          title.contains(query) ||
          city.contains(query) ||
          suburb.contains(query);

      final matchesCategory =
          _selectedCategory == null ||
          listing['category_id'] == _selectedCategory;

      final matchesType =
          _selectedType == 'all' || listing['listing_type'] == _selectedType;

      return matchesSearch && matchesCategory && matchesType;
    }).toList();
  }

  String? _getImageUrl(Map<String, dynamic> listing) {
    final images = listing['listing_images'];

    if (images is! List || images.isEmpty) return null;

    for (final image in images) {
      if (image is Map && image['is_primary'] == true) {
        return image['image_url']?.toString();
      }
    }

    return images.first['image_url']?.toString();
  }

  String _formatPrice(Map<String, dynamic> listing) {
    final value = listing['price'];

    final price = value is num
        ? value.toDouble()
        : double.tryParse(value.toString()) ?? 0;

    final suffix = switch (listing['price_type']) {
      'per_hour' => '/hour',
      'per_day' => '/day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };

    return 'R ${price.toStringAsFixed(2)}$suffix';
  }

  String _formatLocation(Map<String, dynamic> listing) {
    final suburb = (listing['suburb'] ?? '').toString();
    final city = (listing['city'] ?? '').toString();

    final parts = [
      suburb,
      city,
    ].where((part) => part.trim().isNotEmpty).toList();

    return parts.isEmpty ? 'Location not provided' : parts.join(', ');
  }

  Widget _listingCard(Map<String, dynamic> listing) {
    return MarketplaceListingCard(
      title: (listing['title'] ?? 'Untitled').toString(),
      price: _formatPrice(listing),
      location: _formatLocation(listing),
      isService: listing['listing_type'] == 'service',
      imageUrl: _getImageUrl(listing),
      trailing: IconButton.filledTonal(
        tooltip: !_savedLoaded
            ? 'Reload saved listings'
            : _savedIds.contains(listing['id'].toString())
            ? 'Remove from Favourites'
            : 'Save to Favourites',
        style: IconButton.styleFrom(backgroundColor: Colors.white),
        onPressed: _savingIds.contains(listing['id'].toString())
            ? null
            : !_savedLoaded
            ? _loadSaved
            : () => _toggleSaved(listing['id'].toString()),
        icon: Icon(
          _savedIds.contains(listing['id'].toString())
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: primaryGreen,
        ),
      ),
    );
  }

  Widget _categoryFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All Categories'),
              selected: _selectedCategory == null,
              onSelected: (_) {
                setState(() => _selectedCategory = null);
              },
            ),
          ),
          ..._categories.map((category) {
            final id = category['id'] as int;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: const Icon(Icons.category_outlined, size: 18),
                label: Text(category['name'].toString()),
                selected: _selectedCategory == id,
                onSelected: (_) {
                  setState(() => _selectedCategory = id);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _typeFilters() {
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      children: [
        _typeChip('All', 'all'),
        const SizedBox(width: 8),
        _typeChip('Products', 'product'),
        const SizedBox(width: 8),
        _typeChip('Services', 'service'),
      ],
    );
  }

  Widget _typeChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedType == value,
      onSelected: (_) {
        setState(() => _selectedType = value);
      },
    );
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      // AuthGate will display the registration screen.
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredListings;

    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F8),
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, color: primaryGreen),
            SizedBox(width: 9),
            Flexible(
              child: Text(
                'Community Marketplace',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Messages',
            icon: const UnreadMessagesBadge(),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MessagesInboxScreen()),
            ),
          ),

          PopupMenuButton<String>(
            tooltip: 'Your account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) async {
              if (value == 'refresh') {
                _loadMarketplace();
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => value == 'profile'
                      ? const MyProfileScreen()
                      : const FavouritesScreen(),
                ),
              );
              if (mounted) await _loadSaved();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('My Profile')),
              PopupMenuItem(value: 'favourites', child: Text('My Favourites')),
              PopupMenuItem(value: 'refresh', child: Text('Refresh listings')),
            ],
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMarketplace,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),

                      MarketplaceEntrance(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF105C2B),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${widget.firstName}',
                                style: const TextStyle(
                                  color: Color(0xFFD8EDDF),
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Good finds.\nCloser to home.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Discover products, services and people in your community.',
                                style: TextStyle(
                                  color: Color(0xFFD8EDDF),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _searchController,
                        readOnly: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdvancedSearchScreen(),
                          ),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search products, services or locations',
                          suffixIcon: const Icon(Icons.tune_rounded),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: primaryGreen,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(17),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),

                      const Text(
                        'Explore Categories',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _categoryFilters(),

                      const SizedBox(height: 28),

                      const Text(
                        'Recently added',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _typeFilters(),

                      const SizedBox(height: 20),

                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(50),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        Center(
                          child: Column(
                            children: [
                              Text(_error!),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadMarketplace,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        )
                      else if (filtered.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 55,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.inventory_2_outlined,
                                size: 58,
                                color: primaryGreen,
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No listings found yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Listings will appear here as '
                                'products and services are added.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;

                            final columns = width >= 1000
                                ? 4
                                : width >= 650
                                ? 3
                                : width >= 380
                                ? 2
                                : 1;

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
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
                              itemBuilder: (context, index) {
                                final listing = filtered[index];

                                return InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ListingDetailsScreen(
                                          listingId: listing['id'].toString(),
                                        ),
                                      ),
                                    );
                                    if (mounted) await _loadSaved();
                                  },
                                  child: _listingCard(listing),
                                );
                              },
                            );
                          },
                        ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
