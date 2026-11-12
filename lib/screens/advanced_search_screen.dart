import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'near_me_screen.dart';

/// Explore marketplace advertisements with server-side filters and pagination.
/// Step 33 uses the SECURITY INVOKER marketplace_advanced_search RPC.
class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  static const _green = Color(0xFF16803C);
  static const _background = Color(0xFFF7F9F8);
  static const _pageSize = 20;

  final _keyword = TextEditingController();
  final _city = TextEditingController();
  final _suburb = TextEditingController();
  final _province = TextEditingController();
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _results = [];
  bool _loadingCategories = false;
  bool _busy = false;
  bool _hasMore = false;
  bool _filtersExpanded = false;
  int _categoryId = 0;
  int _page = 0;
  int _requestToken = 0;
  String _listingType = 'all';
  String _condition = 'any';
  String _sort = 'newest';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _search(reset: true);
  }

  @override
  void dispose() {
    _requestToken++;
    for (final controller in [
      _keyword,
      _city,
      _suburb,
      _province,
      _minimum,
      _maximum,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final data = await Supabase.instance.client
          .from('categories')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() => _categories = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Step 33 category loading error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load categories. Try refreshing.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  double? _money(String input) {
    final value = input.trim().replaceAll(',', '.');
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  String? _validatePrices() {
    final minText = _minimum.text.trim();
    final maxText = _maximum.text.trim();
    final min = _money(minText);
    final max = _money(maxText);
    if ((minText.isNotEmpty && min == null) ||
        (maxText.isNotEmpty && max == null)) {
      return 'Enter valid amounts, such as 100 or 150.50.';
    }
    if ((min != null && min < 0) || (max != null && max < 0)) {
      return 'Prices cannot be negative.';
    }
    if (min != null && max != null && min > max) {
      return 'Minimum price cannot exceed maximum price.';
    }
    return null;
  }

  Future<void> _search({required bool reset}) async {
    if (!reset && (_busy || !_hasMore)) return;
    final priceError = _validatePrices();
    if (priceError != null) {
      setState(() => _error = priceError);
      return;
    }

    // A new search invalidates older requests so stale results don't win.
    final request = ++_requestToken;
    final requestedPage = reset ? 0 : _page;
    final keyword = _keyword.text.trim();
    final city = _city.text.trim();
    final suburb = _suburb.text.trim();
    final province = _province.text.trim();
    final type = _listingType;
    final condition = _condition;
    final sort = _sort;
    final category = _categoryId;
    final minPrice = _money(_minimum.text);
    final maxPrice = _money(_maximum.text);

    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _page = 0;
        _hasMore = false;
      }
    });

    try {
      final raw = await Supabase.instance.client.rpc(
        'marketplace_advanced_search',
        params: {
          'p_keyword': keyword.isEmpty ? null : keyword,
          'p_listing_type': type == 'all' ? null : type,
          'p_category_id': category == 0 ? null : category,
          'p_min_price': minPrice,
          'p_max_price': maxPrice,
          'p_condition': condition == 'any' ? null : condition,
          'p_city': city.isEmpty ? null : city,
          'p_suburb': suburb.isEmpty ? null : suburb,
          'p_province': province.isEmpty ? null : province,
          'p_sort': sort,
          'p_page': requestedPage,
          'p_page_size': _pageSize,
        },
      );
      final rows = (raw as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted || request != _requestToken) return;
      setState(() {
        if (reset) {
          _results = rows;
        } else {
          _results = [..._results, ...rows];
        }
        _hasMore = rows.length == _pageSize;
        _page = requestedPage + 1;
      });
    } catch (e) {
      debugPrint('Step 33 advanced search error: $e');
      if (!mounted || request != _requestToken) return;
      setState(
        () => _error =
            'Search is unavailable. Check your connection and try again.',
      );
    } finally {
      if (mounted && request == _requestToken) {
        setState(() => _busy = false);
      }
    }
  }

  void _clearFilters() {
    for (final controller in [
      _keyword,
      _city,
      _suburb,
      _province,
      _minimum,
      _maximum,
    ]) {
      controller.clear();
    }
    setState(() {
      _listingType = 'all';
      _condition = 'any';
      _categoryId = 0;
      _sort = 'newest';
      _error = null;
    });
    _search(reset: true);
  }

  String _formatPrice(Map<String, dynamic> row) {
    final raw = row['price'];
    if (raw == null) return 'Price on request';
    final amount = raw is num
        ? raw.toDouble()
        : double.tryParse(raw.toString());
    if (amount == null) return 'Price on request';
    final suffix = switch (row['price_type']) {
      'per_hour' => ' / hour',
      'per_day' => ' / day',
      'negotiable' => ' · Negotiable',
      _ => '',
    };
    return 'R ${amount.toStringAsFixed(2)}$suffix';
  }

  String _location(Map<String, dynamic> row) {
    final parts = [row['suburb'], row['city'], row['province']]
        .map((value) => (value ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Location not specified' : parts.join(', ');
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(reset: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _filters() {
    final moneyFormatter = FilteringTextInputFormatter.allow(
      RegExp(r'[0-9.,]'),
    );
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE3EAE5)),
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text(
              'Advanced filters',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Type, category, price, condition and area'),
            leading: const Icon(Icons.tune, color: _green),
            trailing: Icon(
              _filtersExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
            onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
          ),
          if (_filtersExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 200,
                        child: _dropdown<String>(
                          label: 'Advertisement type',
                          value: _listingType,
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('Products and services'),
                            ),
                            DropdownMenuItem(
                              value: 'product',
                              child: Text('Products only'),
                            ),
                            DropdownMenuItem(
                              value: 'service',
                              child: Text('Services only'),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _listingType = value ?? 'all';
                            if (_listingType == 'service') _condition = 'any';
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 225,
                        child: _dropdown<int>(
                          label: _loadingCategories
                              ? 'Loading categories...'
                              : 'Category',
                          value: _categoryId,
                          items: [
                            const DropdownMenuItem(
                              value: 0,
                              child: Text('All categories'),
                            ),
                            ..._categories.map(
                              (category) => DropdownMenuItem<int>(
                                value: (category['id'] as num).toInt(),
                                child: Text(
                                  category['name'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _categoryId = value ?? 0),
                        ),
                      ),
                      if (_listingType != 'service')
                        SizedBox(
                          width: 195,
                          child: _dropdown<String>(
                            label: 'Product condition',
                            value: _condition,
                            items: const [
                              DropdownMenuItem(
                                value: 'any',
                                child: Text('Any condition'),
                              ),
                              DropdownMenuItem(
                                value: 'new',
                                child: Text('New'),
                              ),
                              DropdownMenuItem(
                                value: 'like_new',
                                child: Text('Like new'),
                              ),
                              DropdownMenuItem(
                                value: 'good',
                                child: Text('Good'),
                              ),
                              DropdownMenuItem(
                                value: 'fair',
                                child: Text('Fair'),
                              ),
                              DropdownMenuItem(
                                value: 'used',
                                child: Text('Used'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _condition = value ?? 'any'),
                          ),
                        ),
                      SizedBox(
                        width: 165,
                        child: _field(
                          _minimum,
                          'Minimum price (R)',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [moneyFormatter],
                        ),
                      ),
                      SizedBox(
                        width: 165,
                        child: _field(
                          _maximum,
                          'Maximum price (R)',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [moneyFormatter],
                        ),
                      ),
                      SizedBox(width: 200, child: _field(_city, 'City')),
                      SizedBox(width: 200, child: _field(_suburb, 'Suburb')),
                      SizedBox(
                        width: 200,
                        child: _field(_province, 'Province'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Clear all'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                          ),
                          onPressed: () => _search(reset: true),
                          icon: const Icon(Icons.search),
                          label: const Text('Apply filters'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _listingCard(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    return MarketplaceListingCard(
      title: (row['title'] ?? 'Untitled advertisement').toString(),
      price: _formatPrice(row),
      location: _location(row),
      imageUrl: row['cover_image_url']?.toString(),
      isService: row['listing_type'] == 'service',
      onTap: id.isEmpty
          ? null
          : () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ListingDetailsScreen(listingId: id),
                ),
              );
              if (mounted) _search(reset: true);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Explore Advertisements'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh search',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadCategories();
              _search(reset: true);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _search(reset: true),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 850
                ? 4
                : constraints.maxWidth >= 650
                ? 3
                : constraints.maxWidth >= 400
                ? 2
                : 1;
            return ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                TextField(
                  controller: _keyword,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(reset: true),
                  decoration: InputDecoration(
                    hintText: 'Search products, services or descriptions',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.arrow_forward, color: _green),
                      onPressed: () => _search(reset: true),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE3EAE5)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _filters(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.near_me_outlined),
                        label: const Text('Find near me'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NearMeScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dropdown<String>(
                        label: 'Sort results',
                        value: _sort,
                        items: const [
                          DropdownMenuItem(
                            value: 'newest',
                            child: Text('Newest first'),
                          ),
                          DropdownMenuItem(
                            value: 'oldest',
                            child: Text('Oldest first'),
                          ),
                          DropdownMenuItem(
                            value: 'price_low',
                            child: Text('Price: low to high'),
                          ),
                          DropdownMenuItem(
                            value: 'price_high',
                            child: Text('Price: high to low'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _sort = value ?? 'newest');
                          _search(reset: true);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '${_results.length} advertisements loaded',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_busy && _results.isEmpty) ...[
                  const SizedBox(height: 30),
                  const Center(child: CircularProgressIndicator(color: _green)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          TextButton(
                            onPressed: () => _search(reset: true),
                            child: const Text('Retry search'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (!_busy && _error == null && _results.isEmpty) ...[
                  const SizedBox(height: 38),
                  const Icon(
                    Icons.search_off,
                    size: 48,
                    color: Color(0xFF81978A),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'No matching advertisements. Try fewer filters.',
                    ),
                  ),
                ],
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _results.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent:
                          340 +
                          (MediaQuery.textScalerOf(context).scale(16) - 16) * 6,
                    ),
                    itemBuilder: (context, index) =>
                        _listingCard(_results[index]),
                  ),
                ],
                if (_busy && _results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator(color: _green)),
                ],
                if (_hasMore && !_busy) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more advertisements'),
                      onPressed: () => _search(reset: false),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
              ],
            );
          },
        ),
      ),
    );
  }
}
