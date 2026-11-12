import '../widgets/marketplace_components.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// View and update the signed-in user's own public-facing profile details.
/// Private identity fields, role and account status are deliberately excluded.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _phone = TextEditingController();
  final _suburb = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _signingOut = false;
  String? _error;
  String? _profileImageUrl;

  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _pendingPhoto;
  String? _pendingExtension;
  String? _pendingContentType;
  bool _pickingPhoto = false;
  bool _uploadingPhoto = false;
  bool _removingPhoto = false;

  static const String photoBucket = 'profile-images';
  static const int maxPhotoBytes = 2 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _surname.dispose();
    _phone.dispose();
    _suburb.dispose();
    _city.dispose();
    _province.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to view your profile.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select(
            'first_name, surname, phone, suburb, city, province, profile_image_url',
          )
          .eq('id', user.id)
          .single();

      if (!mounted) return;
      setState(() {
        _firstName.text = (profile['first_name'] ?? '').toString();
        _surname.text = (profile['surname'] ?? '').toString();
        _phone.text = (profile['phone'] ?? '').toString();
        _suburb.text = (profile['suburb'] ?? '').toString();
        _city.text = (profile['city'] ?? '').toString();
        _province.text = (profile['province'] ?? '').toString();
        _profileImageUrl = profile['profile_image_url']?.toString();
      });
    } catch (error) {
      debugPrint('Load profile error: $error');
      if (!mounted) return;
      setState(() => _error = 'Unable to load your profile. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _saveProfile() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showMessage('Your session has expired. Please sign in again.');
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await Supabase.instance.client
          .from('profiles')
          .update({
            'first_name': _firstName.text.trim(),
            'surname': _surname.text.trim(),
            'phone': _optional(_phone),
            'suburb': _optional(_suburb),
            'city': _optional(_city),
            'province': _optional(_province),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id)
          .select('id')
          .maybeSingle();

      if (!mounted) return;
      if (updated == null) {
        _showMessage(
          'Profile was not updated. Check your account permissions.',
        );
      } else {
        _showMessage('Profile updated successfully!');
      }
    } on PostgrestException catch (error) {
      debugPrint('Marketplace operation failed: ${error.code}');
      if (mounted) {
        _showMessage('Could not save your profile. Please try again.');
      }
    } catch (error) {
      debugPrint('Save profile error: $error');
      if (mounted) _showMessage('Unable to save changes. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      // AuthGate is the first route and handles the signed-out screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      debugPrint('Sign out error: $error');
      if (mounted) _showMessage('Could not sign out. Please try again.');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF617168), size: 21),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
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

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          TextFormField(
            controller: controller,
            enabled: !_saving,
            keyboardType: keyboardType,
            decoration: _decoration(hint, icon),
            validator: validator,
          ),
        ],
      ),
    );
  }

  // Use a file's actual signature rather than trusting its filename.
  (String, String)? _photoType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return ('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return ('webp', 'image/webp');
    }
    return null;
  }

  Future<void> _choosePhoto() async {
    if (_pickingPhoto || _uploadingPhoto || _removingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1000,
      );
      if (picked == null) return;
      if (await picked.length() > maxPhotoBytes) {
        _showMessage('Choose a photo smaller than 2 MB.');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
        _showMessage('Choose a photo smaller than 2 MB.');
        return;
      }
      final type = _photoType(bytes);
      if (type == null) {
        _showMessage('Please choose a JPG, PNG or WebP image.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _pendingPhoto = bytes;
        _pendingExtension = type.$1;
        _pendingContentType = type.$2;
      });
    } catch (error) {
      debugPrint('Choose profile photo error: $error');
      if (mounted) _showMessage('Unable to select photo. Please try again.');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  // Only remove images which this screen uploaded to the current user's folder.
  String? _ownedPhotoPath(String? photoUrl, String uid) {
    if (photoUrl == null || photoUrl.trim().isEmpty) return null;
    final parsed = Uri.tryParse(photoUrl);
    if (parsed == null) return null;
    final expected = Uri.parse(
      Supabase.instance.client.storage
          .from(photoBucket)
          .getPublicUrl('$uid/example.jpg'),
    );
    if (parsed.scheme != expected.scheme || parsed.host != expected.host) {
      return null;
    }
    final segments = parsed.pathSegments;
    if (segments.length != 7 ||
        segments[0] != 'storage' ||
        segments[1] != 'v1' ||
        segments[2] != 'object' ||
        segments[3] != 'public' ||
        segments[4] != photoBucket ||
        segments[5] != uid ||
        !RegExp(r'^avatar_[0-9]+\.(jpg|png|webp)$').hasMatch(segments[6])) {
      return null;
    }
    return '$uid/${segments[6]}';
  }

  Future<void> _uploadProfilePhoto() async {
    final bytes = _pendingPhoto;
    final ext = _pendingExtension;
    final mime = _pendingContentType;
    if (_uploadingPhoto ||
        _removingPhoto ||
        bytes == null ||
        ext == null ||
        mime == null) {
      return;
    }

    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      _showMessage('Please sign in again to upload a photo.');
      return;
    }
    setState(() => _uploadingPhoto = true);
    String? uploadedPath;
    var saved = false;
    try {
      final oldUrl = _profileImageUrl;
      uploadedPath =
          '$uid/avatar_${DateTime.now().microsecondsSinceEpoch}.$ext';
      await supabase.storage
          .from(photoBucket)
          .uploadBinary(
            uploadedPath,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final newUrl = supabase.storage
          .from(photoBucket)
          .getPublicUrl(uploadedPath);
      final updated = await supabase
          .from('profiles')
          .update({
            'profile_image_url': newUrl,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw StateError('Your profile photo could not be saved.');
      }
      saved = true;
      if (mounted) {
        setState(() {
          _profileImageUrl = newUrl;
          _pendingPhoto = null;
          _pendingExtension = null;
          _pendingContentType = null;
        });
        _showMessage('Profile picture updated successfully!');
      }
      final oldPath = _ownedPhotoPath(oldUrl, uid);
      if (oldPath != null) {
        try {
          await supabase.storage.from(photoBucket).remove([oldPath]);
        } catch (error) {
          debugPrint('Unable to clean up old profile photo: $error');
        }
      }
    } catch (error) {
      debugPrint('Upload profile photo error: $error');
      if (!saved && uploadedPath != null) {
        try {
          await supabase.storage.from(photoBucket).remove([uploadedPath]);
        } catch (cleanupError) {
          debugPrint('Unable to clean up failed upload: $cleanupError');
        }
      }
      if (mounted) _showMessage('Photo upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    if (_uploadingPhoto || _removingPhoto) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || _profileImageUrl == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('Your initials will be shown instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingPhoto = true);
    try {
      final supabase = Supabase.instance.client;
      final oldUrl = _profileImageUrl;
      final updated = await supabase
          .from('profiles')
          .update({
            'profile_image_url': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw StateError('Unable to update the profile.');
      }
      if (mounted) {
        setState(() => _profileImageUrl = null);
        _showMessage('Profile picture removed.');
      }
      final oldPath = _ownedPhotoPath(oldUrl, uid);
      if (oldPath != null) {
        try {
          await supabase.storage.from(photoBucket).remove([oldPath]);
        } catch (error) {
          debugPrint('Unable to delete previous image: $error');
        }
      }
    } catch (error) {
      debugPrint('Remove profile photo error: $error');
      if (mounted) _showMessage('Could not remove photo. Please retry.');
    } finally {
      if (mounted) setState(() => _removingPhoto = false);
    }
  }

  Widget _photoControls() {
    final busy = _pickingPhoto || _uploadingPhoto || _removingPhoto;
    final hasStoredPhoto = _profileImageUrl?.trim().isNotEmpty ?? false;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            _avatar(),
            Material(
              color: green,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Choose profile picture',
                onPressed: busy ? null : _choosePhoto,
                icon: const Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : _choosePhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(hasStoredPhoto ? 'Change Photo' : 'Choose Photo'),
        ),
        if (_pendingPhoto != null) ...[
          const SizedBox(height: 9),
          const Text(
            'Photo preview — not uploaded yet',
            style: TextStyle(color: Color(0xFF617168), fontSize: 12),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : _uploadProfilePhoto,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_uploadingPhoto ? 'Uploading...' : 'Upload Photo'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _pendingPhoto = null;
                        _pendingExtension = null;
                        _pendingContentType = null;
                      }),
                child: const Text('Cancel selection'),
              ),
            ],
          ),
        ],
        if (hasStoredPhoto && _pendingPhoto == null) ...[
          const SizedBox(height: 5),
          TextButton.icon(
            onPressed: busy ? null : _removeProfilePhoto,
            icon: const Icon(Icons.delete_outline),
            label: Text(_removingPhoto ? 'Removing...' : 'Remove Photo'),
          ),
        ],
        if (busy) ...[
          const SizedBox(height: 10),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }

  Widget _avatar() {
    final initials = [
      if (_firstName.text.trim().isNotEmpty) _firstName.text.trim()[0],
      if (_surname.text.trim().isNotEmpty) _surname.text.trim()[0],
    ].join().toUpperCase();

    Widget fallback() => Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: green,
        ),
      ),
    );

    final imageUrl = _profileImageUrl;
    final preview = _pendingPhoto;
    return CircleAvatar(
      radius: 41,
      backgroundColor: const Color(0xFFE5F4E9),
      child: ClipOval(
        child: SizedBox(
          width: 82,
          height: 82,
          child: preview != null
              ? Image.memory(preview, fit: BoxFit.cover)
              : imageUrl == null || imageUrl.trim().isEmpty
              ? fallback()
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback(),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('My Profile'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F9F8),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: _loading || _saving ? null : _loadProfile,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 55),
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _loadProfile,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Center(child: _photoControls()),
                        const SizedBox(height: 14),
                        Text(
                          '${_firstName.text.trim()} ${_surname.text.trim()}'
                              .trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          email,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF617168)),
                        ),
                        const SizedBox(height: 26),
                        const MarketplaceSectionHeader(
                          'Personal Information',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 17),
                        _field(
                          label: 'First name',
                          hint: 'Your first name',
                          controller: _firstName,
                          icon: Icons.person_outline,
                          validator: (value) => (value ?? '').trim().length < 2
                              ? 'Enter at least 2 characters'
                              : null,
                        ),
                        _field(
                          label: 'Surname',
                          hint: 'Your surname',
                          controller: _surname,
                          icon: Icons.person_outline,
                          validator: (value) => (value ?? '').trim().length < 2
                              ? 'Enter at least 2 characters'
                              : null,
                        ),
                        _field(
                          label: 'Phone number (optional)',
                          hint: 'e.g. 0821234567',
                          controller: _phone,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            final phone = (value ?? '').trim();
                            if (phone.isNotEmpty &&
                                !RegExp(r'^\+?[0-9 ]{7,18}$').hasMatch(phone)) {
                              return 'Enter a valid phone number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 5),
                        const MarketplaceSectionHeader(
                          'General location',
                          icon: Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Use your general area, not your full home address.',
                          style: TextStyle(
                            color: Color(0xFF617168),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _field(
                          label: 'Suburb (optional)',
                          hint: 'Your suburb',
                          controller: _suburb,
                          icon: Icons.location_on_outlined,
                        ),
                        _field(
                          label: 'City (optional)',
                          hint: 'Your city',
                          controller: _city,
                          icon: Icons.location_city_outlined,
                        ),
                        _field(
                          label: 'Province (optional)',
                          hint: 'Your province',
                          controller: _province,
                          icon: Icons.map_outlined,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _saveProfile,
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
                        const SizedBox(height: 30),
                        const Text(
                          'Account Settings',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          margin: EdgeInsets.zero,
                          color: Colors.white,
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(
                                  Icons.lock_outline,
                                  color: green,
                                ),
                                title: const Text('Change Password'),
                                subtitle: const Text(
                                  'Update your account password',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) =>
                                        const _ChangePasswordDialog(),
                                  );
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(
                                  Icons.logout_rounded,
                                  color: Colors.red,
                                ),
                                title: const Text('Sign Out'),
                                subtitle: const Text('Log out of this device'),
                                trailing: _signingOut
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: _signingOut ? null : _signOut,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your email is managed by Supabase Authentication. '
                          'Your ID number and account permissions are not editable here. '
                          'Profile photos are public: avoid private or sensitive images.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF617168),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _working = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_working || !_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      debugPrint('Change password error: $error');
      if (mounted) {
        setState(() {
          _error = 'Password update failed. Please sign in again and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _password,
                enabled: !_working,
                obscureText: _hidePassword,
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) => (value ?? '').length < 8
                    ? 'Use at least 8 characters'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPassword,
                enabled: !_working,
                obscureText: _hideConfirmation,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _hideConfirmation = !_hideConfirmation),
                    icon: Icon(
                      _hideConfirmation
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) =>
                    value != _password.text ? 'Passwords do not match' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working ? null : _changePassword,
          child: Text(_working ? 'Updating...' : 'Update Password'),
        ),
      ],
    );
  }
}
