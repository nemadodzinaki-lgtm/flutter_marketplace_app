import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reports either a listing or the seller behind that listing.
/// The reported seller ID is verified against listings by Supabase RLS.
class ReportListingScreen extends StatefulWidget {
  final String listingId;
  final String listingTitle;
  final String sellerId;

  const ReportListingScreen({
    super.key,
    required this.listingId,
    required this.listingTitle,
    required this.sellerId,
  });

  @override
  State<ReportListingScreen> createState() => _ReportListingScreenState();
}

class _ReportListingScreenState extends State<ReportListingScreen> {
  static const _green = Color(0xFF16803C);
  static const _background = Color(0xFFF7F9F8);

  final _formKey = GlobalKey<FormState>();
  final _detailsController = TextEditingController();
  String _reportType = 'listing';
  String? _reason;
  bool _saving = false;

  static const Map<String, String> _reasons = {
    'scam': 'Scam or misleading information',
    'inappropriate': 'Inappropriate content',
    'spam': 'Spam or repeated advertising',
    'harassment': 'Harassment or abusive behaviour',
    'prohibited': 'Prohibited or unsafe goods/services',
    'other': 'Other concern',
  };

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      _showMessage('Please sign in to submit a report.');
      return;
    }
    if (user.id == widget.sellerId) {
      _showMessage('You cannot report your own advertisement.');
      return;
    }

    setState(() => _saving = true);

    try {
      await supabase.from('marketplace_reports').insert({
        'reporter_id': user.id,
        'listing_id': widget.listingId,
        'reported_user_id': widget.sellerId,
        'report_type': _reportType,
        'reason': _reason,
        'details': _detailsController.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      if (error.code == '23505') {
        _showMessage('You already have an open report for this item.');
      } else if (error.code == '42501') {
        _showMessage('You do not have permission to submit this report.');
      } else {
        debugPrint('Report submission error: ${error.message}');
        _showMessage('Could not send your report. Please try again.');
      }
    } catch (error) {
      debugPrint('Report submission error: $error');
      if (mounted) _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _green, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Submit a Report'),
        backgroundColor: const Color(0xFFF7F9F8),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.flag_outlined, size: 50, color: _green),
                    const SizedBox(height: 14),
                    const Text(
                      'Help keep our community safe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Reports are private and available for future admin review.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF617168)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.listingTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'What are you reporting?',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: _reportType,
                      onChanged: (value) {
                        if (!_saving && value != null) {
                          setState(() => _reportType = value);
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            value: 'listing',
                            enabled: !_saving,
                            title: const Text('This advertisement'),
                            subtitle: const Text(
                              'Misleading or inappropriate listing',
                            ),
                          ),
                          RadioListTile<String>(
                            value: 'seller',
                            enabled: !_saving,
                            title: const Text('The seller'),
                            subtitle: const Text(
                              'Suspicious or abusive seller behaviour',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: _reason,
                      isExpanded: true,
                      decoration: _decoration('Select a reason'),
                      items: _reasons.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() => _reason = value);
                            },
                      validator: (value) =>
                          value == null ? 'Please select a reason' : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _detailsController,
                      enabled: !_saving,
                      maxLines: 5,
                      maxLength: 1000,
                      decoration: _decoration('Explain what happened')
                          .copyWith(labelText: 'Details'),
                      validator: (value) {
                        final length = (value ?? '').trim().length;
                        if (length < 15) {
                          return 'Please provide at least 15 characters';
                        }
                        if (length > 1000) {
                          return 'Keep details within 1000 characters';
                        }
                        return null;
                      },
                    ),
                    const Text(
                      'Avoid including identity numbers, home addresses, '
                      'passwords or other private information.',
                      style: TextStyle(color: Color(0xFF617168), fontSize: 12),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(_saving ? 'Sending...' : 'Submit Report'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Submitting a report does not automatically remove '
                      'the advertisement or suspend the seller.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF617168)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
