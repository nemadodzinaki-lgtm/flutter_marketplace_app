import '../widgets/marketplace_components.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageListingPhotosScreen extends StatefulWidget {
  final String listingId;

  const ManageListingPhotosScreen({super.key, required this.listingId});

  @override
  State<ManageListingPhotosScreen> createState() =>
      _ManageListingPhotosScreenState();
}

class _SelectedPhoto {
  final Uint8List bytes;
  final String extension;

  const _SelectedPhoto({required this.bytes, required this.extension});

  String get contentType => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class _ManageListingPhotosScreenState extends State<ManageListingPhotosScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);
  static const int maxPhotos = 5;
  static const int maxBytes = 5 * 1024 * 1024;

  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _photos = [];
  final List<_SelectedPhoto> _pending = [];
  String _title = 'Manage Photos';
  String _status = 'active';
  bool _loading = true;
  bool _busy = false;
  bool _picking = false;
  String? _error;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  bool get _editable => _status == 'active';
  int get _remainingSlots => maxPhotos - _photos.length - _pending.length;

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : green,
      ),
    );
  }

  Future<void> _loadPhotos() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Please sign in again.');

      // Only load a listing that belongs to the signed-in user.
      final listing = await _supabase
          .from('listings')
          .select('id, title, status')
          .eq('id', widget.listingId)
          .eq('seller_id', user.id)
          .maybeSingle();

      if (listing == null) {
        throw StateError('Listing not found or not owned by you.');
      }

      final rows = await _supabase
          .from('listing_images')
          .select('id, image_url, storage_path, is_primary, display_order')
          .eq('listing_id', widget.listingId)
          .order('display_order');

      final images = List<Map<String, dynamic>>.from(rows);
      images.sort((a, b) {
        final aCover = a['is_primary'] == true ? 0 : 1;
        final bCover = b['is_primary'] == true ? 0 : 1;
        if (aCover != bCover) return aCover.compareTo(bCover);
        final aOrder = (a['display_order'] as num?)?.toInt() ?? 0;
        final bOrder = (b['display_order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      });

      if (!mounted) return;
      setState(() {
        _title = listing['title']?.toString() ?? 'Manage Photos';
        _status = listing['status']?.toString() ?? 'removed';
        _photos = images;
      });
    } catch (error) {
      debugPrint('Load listing photos: $error');
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : 'Unable to load listing photos. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhotos() async {
    if (_busy || _picking || !_editable || _remainingSlots <= 0) return;
    setState(() => _picking = true);

    try {
      final selected = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (selected.isEmpty) return;

      final accepted = <_SelectedPhoto>[];
      var rejected = 0;

      for (final file in selected) {
        if (accepted.length >= _remainingSlots) {
          rejected++;
          continue;
        }

        final extension = file.name.split('.').last.toLowerCase();
        if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension) ||
            await file.length() > maxBytes) {
          rejected++;
          continue;
        }

        final bytes = await file.readAsBytes();
        if (bytes.length > maxBytes) {
          rejected++;
          continue;
        }

        accepted.add(_SelectedPhoto(bytes: bytes, extension: extension));
      }

      if (!mounted) return;
      setState(() => _pending.addAll(accepted));
      if (rejected > 0) {
        _notice(
          '$rejected photo(s) skipped. Maximum $maxPhotos photos, '
          'JPG/PNG/WebP, up to 5 MB each.',
          error: true,
        );
      }
    } catch (error) {
      debugPrint('Choose listing photos: $error');
      _notice('Could not select photos.', error: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _uploadPending() async {
    if (_busy || _pending.isEmpty || !_editable) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _notice('Please sign in again.', error: true);
      return;
    }

    setState(() {
      _busy = true;
      _progress = 'Uploading photos...';
    });

    var uploadedCount = 0;
    String? failure;
    final batch = List<_SelectedPhoto>.of(_pending);

    try {
      for (var i = 0; i < batch.length; i++) {
        if (!mounted) break;
        setState(() => _progress = 'Uploading ${i + 1} of ${batch.length}...');

        final photo = batch[i];
        final path =
            '${user.id}/${widget.listingId}/${DateTime.now().microsecondsSinceEpoch}_$i.${photo.extension}';
        var stored = false;

        try {
          await _supabase.storage
              .from('listing-images')
              .uploadBinary(
                path,
                photo.bytes,
                fileOptions: FileOptions(
                  contentType: photo.contentType,
                  upsert: false,
                ),
              );
          stored = true;

          final url = _supabase.storage
              .from('listing-images')
              .getPublicUrl(path);

          await _supabase.from('listing_images').insert({
            'listing_id': widget.listingId,
            'image_url': url,
            'storage_path': path,
            'is_primary': _photos.isEmpty && uploadedCount == 0,
            'display_order': _photos.length + uploadedCount,
          });
          uploadedCount++;
        } catch (error) {
          // Avoid leaving a new orphan file if its database insert fails.
          if (stored) {
            try {
              await _supabase.storage.from('listing-images').remove([path]);
            } catch (cleanupError) {
              debugPrint('Upload cleanup failed: $cleanupError');
            }
          }
          failure = error.toString();
          debugPrint('Photo upload failed: $error');
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _pending.removeRange(0, uploadedCount);
          _busy = false;
          _progress = null;
        });
        await _loadPhotos();
      }
    }

    if (!mounted) return;
    if (failure != null) {
      _notice(
        '$uploadedCount photo(s) saved; upload stopped. '
        'Your remaining photos are still selected. Please try again.',
        error: true,
      );
    } else if (uploadedCount > 0) {
      _notice('$uploadedCount photo(s) uploaded successfully!');
    }
  }

  Future<void> _setCover(Map<String, dynamic> photo) async {
    if (_busy || !_editable || photo['is_primary'] == true) return;
    setState(() => _busy = true);

    try {
      // Unmark the previous cover, then mark the selected photo.
      // The app can fall back to display_order if a request fails between calls.
      await _supabase
          .from('listing_images')
          .update({'is_primary': false})
          .eq('listing_id', widget.listingId)
          .eq('is_primary', true);

      await _supabase
          .from('listing_images')
          .update({'is_primary': true})
          .eq('listing_id', widget.listingId)
          .eq('id', photo['id'])
          .select('id')
          .single();

      await _loadPhotos();
      _notice('Cover photo updated.');
    } catch (error) {
      debugPrint('Change cover photo: $error');
      _notice(
        'Could not change the cover photo. Refresh and retry.',
        error: true,
      );
      await _loadPhotos();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    if (_busy || !_editable) return;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'This removes the photograph from the listing and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _notice('Please sign in again.', error: true);
      return;
    }

    final path = photo['storage_path']?.toString() ?? '';
    if (!path.startsWith('${user.id}/${widget.listingId}/')) {
      _notice('Unexpected photo path. Please contact support.', error: true);
      return;
    }

    setState(() => _busy = true);
    var deletedFromDatabase = false;
    var storageCleaned = true;

    try {
      // Remove the database reference first to avoid displaying a broken image.
      await _supabase
          .from('listing_images')
          .delete()
          .eq('id', photo['id'])
          .eq('listing_id', widget.listingId)
          .select('id')
          .single();
      deletedFromDatabase = true;

      if (photo['is_primary'] == true) {
        final remaining = _photos.where((p) => p['id'] != photo['id']).toList();
        if (remaining.isNotEmpty) {
          try {
            await _supabase
                .from('listing_images')
                .update({'is_primary': true})
                .eq('id', remaining.first['id'])
                .eq('listing_id', widget.listingId);
          } catch (error) {
            debugPrint('Replacement cover update failed: $error');
          }
        }
      }

      try {
        await _supabase.storage.from('listing-images').remove([path]);
      } catch (error) {
        storageCleaned = false;
        debugPrint('Storage photo deletion failed: $error');
      }

      await _loadPhotos();
      _notice(
        storageCleaned
            ? 'Photo removed successfully.'
            : 'Photo removed from the listing, but Storage cleanup failed.',
      );
    } catch (error) {
      debugPrint('Delete listing photo: $error');
      _notice(
        deletedFromDatabase ? 'Photo removed, but cleanup was incomplete.' : 'Unable to remove photo. Check your Storage and database policies.',
        error: true,
      );
      await _loadPhotos();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _photoCard(Map<String, dynamic> photo) {
    final isCover = photo['is_primary'] == true;
    final url = photo['image_url']?.toString() ?? '';

    return SizedBox(
      width: 230,
      child: Card(
        color: Colors.white,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8E4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 160,
              child: url.isEmpty
                  ? const Icon(Icons.image_not_supported_outlined, size: 48)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isCover)
                    const Text(
                      'COVER PHOTO',
                      style: TextStyle(
                        color: green,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    const Text('Listing photo'),
                  const SizedBox(height: 8),
                  if (_editable)
                    Wrap(
                      spacing: 6,
                      children: [
                        if (!isCover)
                          TextButton.icon(
                            onPressed: _busy ? null : () => _setCover(photo),
                            icon: const Icon(Icons.star_border, size: 17),
                            label: const Text('Set cover'),
                          ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _deletePhoto(photo),
                          icon: const Icon(Icons.delete_outline, size: 17),
                          label: const Text('Remove'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Manage Photos'),
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh photos',
            onPressed: _loading || _busy ? null : _loadPhotos,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadPhotos,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const MarketplaceSectionHeader(
                        'Your photo gallery',
                        subtitle: 'Show your advertisement at its best.',
                        icon: Icons.photo_library_outlined,
                      ),
                      Text(
                        '${_photos.length} / $maxPhotos saved photos',
                        style: const TextStyle(color: Color(0xFF617168)),
                      ),
                      const SizedBox(height: 18),
                      if (!_editable)
                        const Text(
                          'Photo editing is available for Active listings only. Mark a Sold or Unavailable listing as Active first. Administrator-removed listings cannot be reactivated.',
                          style: TextStyle(color: Colors.red),
                        )
                      else ...[
                        const Text(
                          'Add up to 5 photos. Each image can be up to 5 MB '
                          '(JPG, PNG or WebP). The cover photo appears on the homepage.',
                          style: TextStyle(color: Color(0xFF617168)),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _busy || _picking || _remainingSlots <= 0
                              ? null
                              : _pickPhotos,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Choose Photos'),
                        ),
                        if (_pending.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Selected photos (not uploaded yet)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (var i = 0; i < _pending.length; i++)
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        _pending[i].bytes,
                                        width: 108,
                                        height: 108,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: IconButton.filled(
                                        tooltip: 'Remove selected photo',
                                        icon: const Icon(Icons.close, size: 16),
                                        onPressed: _busy
                                            ? null
                                            : () => setState(
                                                () => _pending.removeAt(i),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: green,
                            ),
                            onPressed: _busy ? null : _uploadPending,
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: Text(
                              _busy
                                  ? 'Uploading...'
                                  : 'Upload ${_pending.length} Photo(s)',
                            ),
                          ),
                        ],
                      ],
                      if (_progress != null) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(color: green),
                        const SizedBox(height: 8),
                        Text(_progress!),
                      ],
                      const SizedBox(height: 25),
                      const Text(
                        'Current Photos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_photos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No photos added yet.'),
                        )
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _photos.map(_photoCard).toList(),
                        ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
