import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Edit the basic information of an ACTIVE listing owned by the current user.
/// Existing photos are kept as-is. Photo management will be a separate step.
class EditListingScreen extends StatefulWidget {
  final String listingId;

  const EditListingScreen({super.key, required this.listingId});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  static const green = Color(0xFF16803C);
  static const background = Color(0xFFF7F9F8);

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  final _suburb = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  String _listingType = 'product';
  String _priceType = 'fixed';
  String _condition = 'new';

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadListing();
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _price,
      _quantity,
      _suburb,
      _city,
      _province,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadListing() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loadError = 'Please sign in to edit your listing.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final listing = await supabase
          .from('listings')
          .select('''
            id, seller_id, status, title, description, category_id,
            listing_type, price, price_type, condition, quantity,
            suburb, city, province
          ''')
          .eq('id', widget.listingId)
          .eq('seller_id', user.id)
          .maybeSingle();

      if (listing == null) {
        throw StateError('Listing not found or you are not its seller.');
      }
      if (listing['status'] != 'active') {
        throw StateError('Only active listings can be edited right now.');
      }

      final categories = await supabase
          .from('categories')
          .select('id, name')
          .eq('is_active', true)
          .order('name');

      if (!mounted) return;

      final categoryRows = List<Map<String, dynamic>>.from(categories);
      final currentCategory = (listing['category_id'] as num).toInt();

      setState(() {
        _categories = categoryRows;
        _categoryId =
            categoryRows.any(
              (row) => (row['id'] as num).toInt() == currentCategory,
            )
            ? currentCategory
            : null;
        _listingType = listing['listing_type'] == 'service'
            ? 'service'
            : 'product';
        _priceType = (listing['price_type'] ?? 'fixed').toString();
        _condition = (listing['condition'] ?? 'new').toString();
        _title.text = (listing['title'] ?? '').toString();
        _description.text = (listing['description'] ?? '').toString();
        final rawPrice = listing['price'];
        final amount = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice.toString()) ?? 0;
        _price.text = amount.toStringAsFixed(2);
        _quantity.text = listing['quantity']?.toString() ?? '';
        _suburb.text = (listing['suburb'] ?? '').toString();
        _city.text = (listing['city'] ?? '').toString();
        _province.text = (listing['province'] ?? '').toString();
        _loading = false;
      });
    } catch (error) {
      debugPrint('Edit listing load error: $error');
      if (!mounted) return;
      setState(() {
        _loadError = error is StateError
            ? error.message.toString()
            : 'Unable to load this listing. Please try again.';
        _loading = false;
      });
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE2E8E4)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE2E8E4)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: green, width: 1.5),
    ),
  );

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            decoration: _decoration(hint),
            validator:
                validator ??
                (value) => (value == null || value.trim().isEmpty)
                    ? '$label is required'
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => MarketplaceSectionHeader(
    title,
    icon: title.toLowerCase().contains('locat')
        ? Icons.location_on_outlined
        : title.toLowerCase().contains('pric')
        ? Icons.payments_outlined
        : Icons.edit_note_rounded,
  );

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _categoryId == null) return;

    setState(() => _saving = true);
    try {
      final price = double.parse(_price.text.trim().replaceAll(',', '.'));
      final updates = <String, dynamic>{
        'category_id': _categoryId,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'price': price,
        'price_type': _priceType,
        'condition': _listingType == 'product' ? _condition : null,
        'quantity':
            _listingType == 'product' && _quantity.text.trim().isNotEmpty
            ? int.parse(_quantity.text.trim())
            : null,
        'suburb': _optional(_suburb),
        'city': _city.text.trim(),
        'province': _province.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Only update the current seller's active listing. This does not
      // modify seller_id, status, photos, or listing_type.
      final saved = await Supabase.instance.client
          .from('listings')
          .update(updates)
          .eq('id', widget.listingId)
          .eq('seller_id', user.id)
          .eq('status', 'active')
          .select('id')
          .maybeSingle();

      if (saved == null) {
        throw StateError(
          'No listing was updated. Check that it is still active.',
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      debugPrint('Edit listing Supabase error: ${error.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to save changes. Please try again.'),
        ),
      );
    } catch (error) {
      debugPrint('Edit listing error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save changes. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Edit Listing'),
        backgroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadListing,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 650),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Update your advertisement',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Edit the details below. Existing photos will stay unchanged.',
                          style: TextStyle(color: Color(0xFF617168)),
                        ),
                        const SizedBox(height: 10),
                        _section('Basic Information'),
                        _field(
                          label: 'Listing title',
                          hint: 'Listing title',
                          controller: _title,
                          validator: (value) => (value?.trim().length ?? 0) < 3
                              ? 'Enter at least 3 characters'
                              : null,
                        ),
                        const Text(
                          'Category',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _categoryId,
                          isExpanded: true,
                          decoration: _decoration('Choose a category'),
                          items: _categories
                              .map(
                                (category) => DropdownMenuItem<int>(
                                  value: (category['id'] as num).toInt(),
                                  child: Text(category['name'].toString()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _categoryId = value),
                          validator: (value) =>
                              value == null ? 'Choose a category' : null,
                        ),
                        const SizedBox(height: 18),
                        _field(
                          label: 'Description',
                          hint: 'Describe the listing',
                          controller: _description,
                          maxLines: 4,
                          validator: (value) => (value?.trim().length ?? 0) < 10
                              ? 'Enter at least 10 characters'
                              : null,
                        ),
                        _section('Pricing'),
                        _field(
                          label: 'Price (R)',
                          hint: 'e.g. 150.00',
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            final n = double.tryParse(
                              (value ?? '').trim().replaceAll(',', '.'),
                            );
                            if (n == null ||
                                !n.isFinite ||
                                n < 0 ||
                                n > 9999999999.99) {
                              return 'Enter a valid price in rand';
                            }
                            return null;
                          },
                        ),
                        const Text(
                          'Price type',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _priceType,
                          decoration: _decoration('Price type'),
                          items: [
                            const DropdownMenuItem(
                              value: 'fixed',
                              child: Text('Fixed Price'),
                            ),
                            if (_listingType == 'service') ...[
                              const DropdownMenuItem(
                                value: 'per_hour',
                                child: Text('Per Hour'),
                              ),
                              const DropdownMenuItem(
                                value: 'per_day',
                                child: Text('Per Day'),
                              ),
                            ],
                            const DropdownMenuItem(
                              value: 'negotiable',
                              child: Text('Negotiable'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _priceType = value ?? 'fixed'),
                        ),
                        if (_listingType == 'product') ...[
                          _section('Product details'),
                          const Text(
                            'Condition',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _condition,
                            decoration: _decoration('Condition'),
                            items: const [
                              DropdownMenuItem(
                                value: 'new',
                                child: Text('New'),
                              ),
                              DropdownMenuItem(
                                value: 'like_new',
                                child: Text('Like New'),
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
                                setState(() => _condition = value ?? 'new'),
                          ),
                          const SizedBox(height: 18),
                          _field(
                            label: 'Quantity (optional)',
                            hint: 'e.g. 5',
                            controller: _quantity,
                            keyboardType: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final n = int.tryParse(value.trim());
                              return n == null || n < 0
                                  ? 'Enter a valid quantity'
                                  : null;
                            },
                          ),
                        ],
                        _section('General location'),
                        _field(
                          label: 'Suburb (optional)',
                          hint: 'e.g. Belgravia',
                          controller: _suburb,
                          validator: (_) => null,
                        ),
                        _field(
                          label: 'City',
                          hint: 'e.g. East London',
                          controller: _city,
                        ),
                        _field(
                          label: 'Province',
                          hint: 'e.g. Eastern Cape',
                          controller: _province,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving...' : 'Save Changes'),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
