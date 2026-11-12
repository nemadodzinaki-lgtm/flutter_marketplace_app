import '../widgets/marketplace_components.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _ListingPhoto {
  final Uint8List bytes;
  final String extension;

  const _ListingPhoto({required this.bytes, required this.extension});

  String get contentType => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);
  static const int maxPhotos = 5;
  static const int maxPhotoBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _suburb = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();
  final _picker = ImagePicker();
  final List<_ListingPhoto> _photos = [];

  List<Map<String, dynamic>> _categories = [];
  bool _loadingCategories = true;
  bool _pickingPhotos = false;
  bool _publishing = false;
  String? _categoryError;
  String _progress = 'Publish Listing';

  int? _categoryId;
  String _listingType = 'product';
  String _priceType = 'fixed';
  String _condition = 'new';

  @override
  void initState() {
    super.initState();
    _loadCategories();
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });
    try {
      final result = await Supabase.instance.client
          .from('categories')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(result);
      });
    } catch (error) {
      debugPrint('Category loading error: $error');
      if (!mounted) return;
      setState(() => _categoryError = 'Could not load categories.');
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _pickPhotos() async {
    if (_pickingPhotos || _publishing) return;
    if (_photos.length >= maxPhotos) {
      _showMessage('You can select a maximum of 5 photos.');
      return;
    }

    setState(() => _pickingPhotos = true);
    try {
      final selected = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
      );
      final newPhotos = <_ListingPhoto>[];
      var skipped = 0;

      for (final file in selected) {
        if (_photos.length + newPhotos.length >= maxPhotos) {
          skipped++;
          continue;
        }
        final extension = file.name.split('.').last.toLowerCase();
        if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension) ||
            await file.length() > maxPhotoBytes) {
          skipped++;
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > maxPhotoBytes) {
          skipped++;
          continue;
        }
        newPhotos.add(_ListingPhoto(bytes: bytes, extension: extension));
      }

      if (!mounted) return;
      setState(() => _photos.addAll(newPhotos));
      if (skipped > 0) {
        _showMessage(
          '$skipped photo(s) skipped. Choose JPG, PNG or WebP files '
          'under 5 MB, with a maximum of 5 photos.',
        );
      }
    } catch (error) {
      debugPrint('Photo selection error: $error');
      _showMessage('Unable to select photos. Please try again.');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  String? _optionalText(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _publishListing() async {
    if (_publishing || _pickingPhotos) return;
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      _showMessage('Please choose a category.');
      return;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Please sign in to publish a listing.');
      return;
    }

    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (price == null ||
        !price.isFinite ||
        price < 0 ||
        price > 9999999999.99) {
      _showMessage('Enter a valid price in rand.');
      return;
    }

    setState(() {
      _publishing = true;
      _progress = 'Creating listing...';
    });

    try {
      // Create the listing exactly once, before uploading photos.
      final created = await supabase
          .from('listings')
          .insert({
            'seller_id': user.id,
            'category_id': _categoryId,
            'listing_type': _listingType,
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'price': price,
            'price_type': _priceType,
            'condition': _listingType == 'product' ? _condition : null,
            'quantity':
                _listingType == 'product' && _quantity.text.trim().isNotEmpty
                ? int.parse(_quantity.text.trim())
                : null,
            'suburb': _optionalText(_suburb),
            'city': _city.text.trim(),
            'province': _province.text.trim(),
            'status': 'active',
          })
          .select('id')
          .single();

      final listingId = created['id'] as String;
      var failedPhotos = 0;

      for (var i = 0; i < _photos.length; i++) {
        if (!mounted) return;
        setState(() {
          _progress = 'Uploading photo ${i + 1} of ${_photos.length}...';
        });

        final photo = _photos[i];
        final storagePath =
            '${user.id}/$listingId/${DateTime.now().microsecondsSinceEpoch}_$i.${photo.extension}';

        try {
          await supabase.storage
              .from('listing-images')
              .uploadBinary(
                storagePath,
                photo.bytes,
                fileOptions: FileOptions(
                  contentType: photo.contentType,
                  upsert: false,
                ),
              );

          final imageUrl = supabase.storage
              .from('listing-images')
              .getPublicUrl(storagePath);

          await supabase.from('listing_images').insert({
            'listing_id': listingId,
            'image_url': imageUrl,
            'storage_path': storagePath,
            'is_primary': i == 0,
            'display_order': i,
          });
        } catch (error) {
          failedPhotos++;
          debugPrint('Photo ${i + 1} upload/save failed: $error');
        }
      }

      if (!mounted) return;
      if (failedPhotos > 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Listing Published'),
            content: Text(
              'Your listing was saved, but $failedPhotos photo(s) '
              'could not be uploaded. Please check the listing on '
              'your homepage. Do not publish again to retry photos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      debugPrint('Create listing database error: ${error.message}');
      _showMessage('Unable to publish your advertisement. Please try again.');
    } catch (error) {
      debugPrint('Create listing error: $error');
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
          _progress = 'Publish Listing';
        });
      }
    }
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8E4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: green, width: 1.5),
      ),
    );
  }

  Widget _sectionTitle(String text) => MarketplaceSectionHeader(
    text,
    icon: text.toLowerCase().contains('locat')
        ? Icons.location_on_outlined
        : text.toLowerCase().contains('pric')
        ? Icons.payments_outlined
        : text.toLowerCase().contains('photo')
        ? Icons.photo_library_outlined
        : Icons.edit_note_rounded,
  );

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool isRequired = true,
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
            keyboardType: keyboardType,
            maxLines: maxLines,
            inputFormatters: formatters,
            decoration: _decoration(hint),
            validator:
                validator ??
                (value) {
                  if (isRequired && (value == null || value.trim().isEmpty)) {
                    return '$label is required';
                  }
                  return null;
                },
          ),
        ],
      ),
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Listing Photos'),
        const Text(
          'Choose up to 5 photos (JPG, PNG or WebP, max 5 MB each). '
          'The first photo will be the cover image.',
          style: TextStyle(color: Color(0xFF617168), fontSize: 13),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _photos[i].bytes,
                      width: 105,
                      height: 105,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton.filled(
                      tooltip: 'Remove photo',
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: _publishing
                          ? null
                          : () {
                              setState(() => _photos.removeAt(i));
                            },
                    ),
                  ),
                ],
              ),
            if (_photos.length < maxPhotos)
              SizedBox(
                height: 105,
                width: 140,
                child: OutlinedButton.icon(
                  onPressed: _publishing || _pickingPhotos ? null : _pickPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_pickingPhotos ? 'Opening...' : 'Add Photos'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${_photos.length} of $maxPhotos photos selected',
          style: const TextStyle(color: Color(0xFF617168), fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProduct = _listingType == 'product';

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Create Listing'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F9F8),
      ),
      body: Center(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'What are you listing?',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Share products and services with your local community.',
                    style: TextStyle(color: Color(0xFF617168)),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'product',
                        label: Text('Product'),
                        icon: Icon(Icons.shopping_bag_outlined),
                      ),
                      ButtonSegment(
                        value: 'service',
                        label: Text('Service'),
                        icon: Icon(Icons.handyman_outlined),
                      ),
                    ],
                    selected: {_listingType},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _listingType = selection.first;
                        _priceType = 'fixed';
                      });
                    },
                  ),
                  _sectionTitle('Basic Information'),
                  if (_loadingCategories)
                    const LinearProgressIndicator()
                  else if (_categoryError != null)
                    Row(
                      children: [
                        Expanded(child: Text(_categoryError!)),
                        TextButton(
                          onPressed: _loadCategories,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _categoryId,
                      isExpanded: true,
                      decoration: _decoration('Select category'),
                      items: _categories.map((category) {
                        return DropdownMenuItem<int>(
                          value: (category['id'] as num).toInt(),
                          child: Text(category['name'].toString()),
                        );
                      }).toList(),
                      onChanged: _publishing
                          ? null
                          : (value) {
                              setState(() => _categoryId = value);
                            },
                      validator: (value) =>
                          value == null ? 'Please select a category' : null,
                    ),
                  const SizedBox(height: 18),
                  _field(
                    label: 'Listing Title',
                    hint: 'e.g. Fresh spinach or hair braiding',
                    controller: _title,
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Enter at least 3 characters'
                        : null,
                  ),
                  _field(
                    label: 'Description',
                    hint: 'Describe your product or service...',
                    controller: _description,
                    maxLines: 4,
                    validator: (value) => (value ?? '').trim().length < 10
                        ? 'Enter at least 10 characters'
                        : null,
                  ),
                  _sectionTitle('Pricing'),
                  _field(
                    label: 'Price (R)',
                    hint: 'e.g. 150.00',
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final price = double.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      if (price == null ||
                          !price.isFinite ||
                          price < 0 ||
                          price > 9999999999.99) {
                        return 'Enter a valid price in rand';
                      }
                      return null;
                    },
                  ),
                  const Text(
                    'Pricing Type',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(_listingType),
                    initialValue: _priceType,
                    decoration: _decoration('Select pricing type'),
                    items: [
                      const DropdownMenuItem(
                        value: 'fixed',
                        child: Text('Fixed Price'),
                      ),
                      if (!isProduct) ...[
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
                    onChanged: (value) {
                      if (value != null) setState(() => _priceType = value);
                    },
                  ),
                  if (isProduct) ...[
                    _sectionTitle('Product Details'),
                    const Text(
                      'Condition',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _condition,
                      decoration: _decoration('Select condition'),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('New')),
                        DropdownMenuItem(
                          value: 'like_new',
                          child: Text('Like New'),
                        ),
                        DropdownMenuItem(value: 'good', child: Text('Good')),
                        DropdownMenuItem(value: 'fair', child: Text('Fair')),
                        DropdownMenuItem(value: 'used', child: Text('Used')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _condition = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    _field(
                      label: 'Quantity available (optional)',
                      hint: 'e.g. 5',
                      controller: _quantity,
                      isRequired: false,
                      keyboardType: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) return null;
                        final quantity = int.tryParse(value!.trim());
                        if (quantity == null || quantity < 1) {
                          return 'Enter a quantity of at least 1';
                        }
                        return null;
                      },
                    ),
                  ],
                  _sectionTitle('Listing Location'),
                  const Text(
                    'Enter a general location, not your home address.',
                    style: TextStyle(color: Color(0xFF617168), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    label: 'Suburb (optional)',
                    hint: 'e.g. Southernwood',
                    controller: _suburb,
                    isRequired: false,
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
                  _photoSection(),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed:
                          _publishing ||
                              _pickingPhotos ||
                              _loadingCategories ||
                              _categoryError != null ||
                              _categories.isEmpty
                          ? null
                          : _publishListing,
                      icon: _publishing
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(_progress),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
