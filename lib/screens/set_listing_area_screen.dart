import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/location_helper.dart';

/// Seller opts in to storing an APPROXIMATE area for one listing.
/// We never store the raw device position in Supabase.
class SetListingAreaScreen extends StatefulWidget {
  final String listingId;
  const SetListingAreaScreen({super.key, required this.listingId});

  @override
  State<SetListingAreaScreen> createState() => _SetListingAreaScreenState();
}

class _SetListingAreaScreenState extends State<SetListingAreaScreen> {
  static const green = Color(0xFF16803C);
  bool _working = false;
  bool _consent = false;
  bool _hasArea = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please sign in first.';
        _loaded = true;
      });
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('listings')
          .select('latitude, longitude, status')
          .eq('id', widget.listingId)
          .eq('seller_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (data == null || data['status'] != 'active') {
        setState(() {
          _error = 'Only your active listings can be location-tagged.';
          _loaded = true;
        });
        return;
      }
      setState(() {
        _hasArea = data['latitude'] != null && data['longitude'] != null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not check this listing.';
        _loaded = true;
      });
    }
  }

  Future<void> _saveArea() async {
    if (!_consent || _working) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _working = true);
    try {
      final position = await MarketplaceLocation.currentPosition();
      if (!MarketplaceLocation.validCoordinates(
        position.latitude,
        position.longitude,
      )) {
        throw StateError('Your device returned an invalid location.');
      }
      // Round before sending to Supabase; precise position isn't saved.
      final latitude = MarketplaceLocation.approximateCoordinate(
        position.latitude,
      );
      final longitude = MarketplaceLocation.approximateCoordinate(
        position.longitude,
      );
      final changed = await Supabase.instance.client
          .from('listings')
          .update({'latitude': latitude, 'longitude': longitude})
          .eq('id', widget.listingId)
          .eq('seller_id', user.id)
          .eq('status', 'active')
          .select('id')
          .maybeSingle();
      if (changed == null) {
        throw StateError(
          'Listing could not be updated. Refresh and try again.',
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : 'Could not tag the area. Check GPS permission and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _removeArea() async {
    if (_working) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _working = true);
    try {
      final changed = await Supabase.instance.client
          .from('listings')
          .update({'latitude': null, 'longitude': null})
          .eq('id', widget.listingId)
          .eq('seller_id', user.id)
          .eq('status', 'active')
          .select('id')
          .maybeSingle();
      if (changed == null) {
        throw StateError('Listing not available for editing.');
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove the area. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text('Approximate Listing Area'),
        backgroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Text(_error!, textAlign: TextAlign.center)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: green,
                        size: 58,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Help nearby buyers find your listing',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Optional: while you are at your shop, service area or a safe public meeting spot, '
                        'use this device to attach an approximate location to your listing. '
                        'Do not use this feature at your home if you want your home area private.',
                        style: TextStyle(height: 1.5, color: Color(0xFF475569)),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F5EC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Only an approximately 2 km grid location is saved, not your exact GPS position. '
                          'Nearby distances will be approximate, and other users may infer your general area. '
                          'Your device location is requested only when you tap Save Area.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (_hasArea)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'This listing already has a nearby-search area.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'I understand this shares an approximate area with buyers.',
                        ),
                        value: _consent,
                        onChanged: _working
                            ? null
                            : (value) =>
                                  setState(() => _consent = value ?? false),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _working || !_consent ? null : _saveArea,
                        style: FilledButton.styleFrom(
                          backgroundColor: green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _working
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(
                          _working
                              ? 'Please wait...'
                              : 'Use This Device’s Approximate Area',
                        ),
                      ),
                      if (_hasArea) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _working ? null : _removeArea,
                          icon: const Icon(Icons.location_off_outlined),
                          label: const Text('Remove Area from Listing'),
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
