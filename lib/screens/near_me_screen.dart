import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/location_helper.dart';
import 'listing_details_screen.dart';

class NearMeScreen extends StatefulWidget {
  const NearMeScreen({super.key});

  @override
  State<NearMeScreen> createState() => _NearMeScreenState();
}

class _NearMeScreenState extends State<NearMeScreen> {
  static const green = Color(0xFF16803C);
  static const background = Color(0xFFF7F9F8);

  double _radiusKm = 10;
  String _type = 'all';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _listings = [];

  Future<void> _search() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Permission and GPS are requested only after tapping Find Near Me.
      final position = await MarketplaceLocation.currentPosition();
      if (!MarketplaceLocation.validCoordinates(
        position.latitude,
        position.longitude,
      )) {
        throw StateError('The device returned an invalid location.');
      }

      final data = await Supabase.instance.client.rpc(
        'find_nearby_marketplace_listings',
        params: {
          'p_lat': position.latitude,
          'p_lon': position.longitude,
          'p_radius_km': _radiusKm,
          'p_listing_type': _type == 'all' ? null : _type,
        },
      );

      if (!mounted) return;
      setState(() {
        _listings = List<Map<String, dynamic>>.from(data as List);
        _searched = true;
      });
    } catch (error) {
      debugPrint('Nearby search error: $error');
      if (!mounted) return;
      setState(() {
        _error = error is StateError ? error.message.toString() : 'Unable to search nearby listings. Check location permissions and try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _price(Map<String, dynamic> listing) {
    final raw = listing['price'];
    final price = raw is num
        ? raw.toDouble()
        : double.tryParse(raw.toString()) ?? 0;
    final suffix = switch (listing['price_type']) {
      'per_hour' => ' / hour',
      'per_day' => ' / day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };
    return 'R ${price.toStringAsFixed(2)}$suffix';
  }

  String _area(Map<String, dynamic> listing) {
    final parts = [listing['suburb'], listing['city'], listing['province']]
        .where((s) => s != null && s.toString().trim().isNotEmpty)
        .map((s) => s.toString())
        .toList();
    return parts.isEmpty ? 'Area not provided' : parts.join(', ');
  }

  Widget _listingCard(Map<String, dynamic> listing) {
    final imageUrl = listing['image_url']?.toString();
    final distance = listing['distance_km']?.toString() ?? '?';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ListingDetailsScreen(
              listingId: listing['listing_id'].toString(),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: imageUrl == null || imageUrl.isEmpty
                      ? const ColoredBox(
                          color: Color(0xFFE5F4E9),
                          child: Icon(
                            Icons.image_outlined,
                            color: green,
                            size: 38,
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFE5F4E9),
                            child: Icon(
                              Icons.image_not_supported_outlined,
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
                      listing['title']?.toString() ?? 'Untitled',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _price(listing),
                      style: const TextStyle(
                        color: green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _area(listing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF617168),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Approximately $distance km away',
                      style: const TextStyle(color: green, fontSize: 12),
                    ),
                  ],
                ),
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
        title: const Text('Near Me'),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.near_me_outlined, color: green, size: 52),
                  const SizedBox(height: 10),
                  const Text(
                    'Find products and services near you',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Location is requested only when you search. Your exact GPS position '
                    'is used to calculate distances but is not saved to your profile. '
                    'Results include only listings whose sellers opted into approximate-location search.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF617168), height: 1.5),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'Search radius',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    children: [5.0, 10.0, 20.0, 50.0].map((r) {
                      return ChoiceChip(
                        label: Text('${r.toInt()} km'),
                        selected: _radiusKm == r,
                        onSelected: _loading
                            ? null
                            : (_) => setState(() => _radiusKm = r),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Listing type',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    children:
                        [
                          ('all', 'All'),
                          ('product', 'Products'),
                          ('service', 'Services'),
                        ].map((option) {
                          return ChoiceChip(
                            label: Text(option.$2),
                            selected: _type == option.$1,
                            onSelected: _loading
                                ? null
                                : (_) => setState(() => _type = option.$1),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      style: FilledButton.styleFrom(backgroundColor: green),
                      icon: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        _loading ? 'Finding listings...' : 'Find Near Me',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    )
                  else if (_searched && _listings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(25),
                      child: Text(
                        'No nearby listings with an approximate location yet. '
                        'A seller must first open My Listings and choose "Set Nearby Area" '
                        'for an active listing. You can still use Browse by Area.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_listings.isNotEmpty) ...[
                    Text(
                      '${_listings.length} nearby listing(s)',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._listings.map(_listingCard),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
