import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'near_me_screen.dart';

/// Browses public active listings by the seller-provided general area.
/// Does not request GPS coordinates or calculate actual distances.
class BrowseByAreaScreen extends StatefulWidget {
  const BrowseByAreaScreen({super.key});

  @override
  State<BrowseByAreaScreen> createState() => _BrowseByAreaScreenState();
}

class _BrowseByAreaScreenState extends State<BrowseByAreaScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  final _city = TextEditingController();
  final _suburb = TextEditingController();

  late Future<List<Map<String, dynamic>>> _categoriesFuture;
  List<Map<String, dynamic>> _listings = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String _listingType = 'all';
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _loadCategories();
    _search();
  }

  @override
  void dispose() {
    _city.dispose();
    _suburb.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadCategories() async {
    final rows = await Supabase.instance.client
        .from('categories')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _search() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final city = _city.text.trim();
      final suburb = _suburb.text.trim();
      final supabase = Supabase.instance.client;

      // Filtering is performed by Supabase, not on a small homepage cache.
      var query = supabase
          .from('listings')
          .select('''
        id, title, price, price_type, listing_type, suburb, city, province,
        listing_images(image_url, is_primary, display_order)
      ''')
          .eq('status', 'active');

      if (city.isNotEmpty) {
        query = query.ilike('city', '%$city%');
      }
      if (suburb.isNotEmpty) {
        query = query.ilike('suburb', '%$suburb%');
      }
      if (_listingType != 'all') {
        query = query.eq('listing_type', _listingType);
      }
      if (_categoryId != null) {
        query = query.eq('category_id', _categoryId!);
      }

      final rows = await query.order('created_at', ascending: false).limit(80);

      if (!mounted) return;
      setState(() {
        _listings = List<Map<String, dynamic>>.from(rows);
        _searched = true;
      });
    } catch (error) {
      debugPrint('Browse by area error: $error');
      if (!mounted) return;
      setState(() {
        _error =
            'Could not load listings. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearFilters() {
    _city.clear();
    _suburb.clear();
    setState(() {
      _listingType = 'all';
      _categoryId = null;
    });
    _search();
  }

  String? _coverImage(Map<String, dynamic> listing) {
    final raw = listing['listing_images'];
    if (raw is! List || raw.isEmpty) return null;

    final images = raw.whereType<Map>().toList();
    if (images.isEmpty) return null;

    images.sort((a, b) {
      final aPrimary = a['is_primary'] == true ? 0 : 1;
      final bPrimary = b['is_primary'] == true ? 0 : 1;
      if (aPrimary != bPrimary) return aPrimary.compareTo(bPrimary);
      final aOrder = (a['display_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['display_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });

    final url = images.first['image_url']?.toString();
    return url == null || url.isEmpty ? null : url;
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

  String _area(Map<String, dynamic> listing) {
    final places = [listing['suburb'], listing['city'], listing['province']]
        .where((item) => item != null && item.toString().trim().isNotEmpty)
        .map((item) => item.toString())
        .toList();
    return places.isEmpty ? 'Area not specified' : places.join(', ');
  }

  Widget _listingCard(Map<String, dynamic> listing) {
    final url = _coverImage(listing);

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8E4)),
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ListingDetailsScreen(listingId: listing['id'].toString()),
            ),
          );
          if (mounted) _search();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              height: 145,
              child: url == null
                  ? _placeholder()
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing['listing_type'] == 'service'
                        ? 'SERVICE'
                        : 'PRODUCT',
                    style: const TextStyle(
                      color: green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    listing['title']?.toString() ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _price(listing),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: green,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 15,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          _area(listing),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF617168),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFE5F4E9),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 52, color: green),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: green),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8E4)),
      ),
    );
  }

  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Find products and services in your area',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Search the general area sellers entered on their listings. '
          'This does not use your GPS location.',
          style: TextStyle(color: Color(0xFF617168), height: 1.45),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _city,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: _inputDecoration(
            'City (e.g. East London)',
            Icons.location_city_outlined,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _suburb,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: _inputDecoration(
            'Suburb (optional)',
            Icons.place_outlined,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 5,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _listingType == 'all',
              onSelected: (_) => setState(() => _listingType = 'all'),
            ),
            ChoiceChip(
              label: const Text('Products'),
              selected: _listingType == 'product',
              onSelected: (_) => setState(() => _listingType = 'product'),
            ),
            ChoiceChip(
              label: const Text('Services'),
              selected: _listingType == 'service',
              onSelected: (_) => setState(() => _listingType = 'service'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _categoriesFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Row(
                children: [
                  const Expanded(child: Text('Categories unavailable.')),
                  TextButton(
                    onPressed: () => setState(() {
                      _categoriesFuture = _loadCategories();
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();

            final categories = snapshot.data!;
            return DropdownButtonFormField<int>(
              key: ValueKey(_categoryId),
              initialValue: _categoryId,
              isExpanded: true,
              decoration: _inputDecoration('Category', Icons.category_outlined),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('All categories'),
                ),
                ...categories.map(
                  (category) => DropdownMenuItem<int>(
                    value: (category['id'] as num).toInt(),
                    child: Text(category['name'].toString()),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: const Icon(Icons.search),
                label: const Text('Search listings'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _loading ? null : _clearFilters,
              child: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Browse by Area'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Near Me (GPS)',
            icon: const Icon(Icons.my_location_outlined, color: green),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NearMeScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _filters(),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Listings',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_searched && !_loading && _error == null)
                          Text(
                            '${_listings.length} shown',
                            style: const TextStyle(color: Color(0xFF617168)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _search,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    else if (_listings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Column(
                          children: [
                            Icon(
                              Icons.travel_explore_outlined,
                              size: 54,
                              color: green,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No listings found for these filters.',
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Try another city, suburb or category.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF617168)),
                            ),
                          ],
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final columns = width >= 920
                              ? 3
                              : width >= 570
                              ? 2
                              : 1;
                          return GridView.builder(
                            itemCount: _listings.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  mainAxisExtent: 278,
                                ),
                            itemBuilder: (context, index) =>
                                _listingCard(_listings[index]),
                          );
                        },
                      ),
                    const SizedBox(height: 35),
                    const Text(
                      'Searches show up to 80 of the newest matching listings. '
                      'Distances and maps will be added later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF617168), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
