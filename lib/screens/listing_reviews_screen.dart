import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ListingReviewsScreen extends StatefulWidget {
  final String listingId;
  final String listingTitle;
  final String sellerId;

  const ListingReviewsScreen({
    super.key,
    required this.listingId,
    required this.listingTitle,
    required this.sellerId,
  });

  @override
  State<ListingReviewsScreen> createState() => _ListingReviewsScreenState();
}

class _ListingReviewsScreenState extends State<ListingReviewsScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  List<Map<String, dynamic>> _reviews = [];
  int _rating = 5;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;
  bool get _isSeller => _userId != null && widget.sellerId == _userId;

  Map<String, dynamic>? get _myReview {
    for (final review in _reviews) {
      if (review['reviewer_id'] == _userId) return review;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Supabase.instance.client
          .from('listing_reviews')
          .select('id, listing_id, reviewer_id, rating, comment, created_at')
          .eq('listing_id', widget.listingId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      final items = List<Map<String, dynamic>>.from(results);
      Map<String, dynamic>? mine;
      for (final item in items) {
        if (item['reviewer_id'] == _userId) {
          mine = item;
          break;
        }
      }
      setState(() {
        _reviews = items;
        _rating = (mine?['rating'] as num?)?.toInt() ?? 5;
        _comment.text = (mine?['comment'] ?? '').toString();
      });
    } catch (error) {
      debugPrint('Review loading error: $error');
      if (mounted) {
        setState(() => _error = 'Could not load reviews. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveReview() async {
    if (_saving || _loading || _isSeller || _userId == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final existing = _myReview;
      if (existing == null) {
        await supabase.from('listing_reviews').insert({
          'listing_id': widget.listingId,
          'reviewer_id': _userId!,
          'rating': _rating,
          'comment': _comment.text.trim(),
        });
      } else {
        await supabase
            .from('listing_reviews')
            .update({'rating': _rating, 'comment': _comment.text.trim()})
            .eq('id', existing['id'])
            .eq('reviewer_id', _userId!);
      }
      if (!mounted) return;
      await _loadReviews();
      _showMessage(existing == null ? 'Review published!' : 'Review updated!');
    } on PostgrestException catch (error) {
      debugPrint('Review save error: ${error.message}');
      _showMessage('Could not save your review. Please check your account.');
    } catch (error) {
      debugPrint('Review save error: $error');
      _showMessage('Unable to save review. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteReview() async {
    final existing = _myReview;
    if (_saving || existing == null || _userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your review?'),
        content: const Text('You can write another review later if you want.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('listing_reviews')
          .delete()
          .eq('id', existing['id'])
          .eq('reviewer_id', _userId!);
      if (!mounted) return;
      await _loadReviews();
      _showMessage('Your review was deleted.');
    } catch (error) {
      debugPrint('Review deletion error: $error');
      _showMessage('Unable to delete review. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stars(int count, {double size = 19}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < count ? Icons.star_rounded : Icons.star_border_rounded,
          color: const Color(0xFFF59E0B),
          size: size,
        );
      }),
    );
  }

  String _dateLabel(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _summary() {
    final count = _reviews.length;
    final total = _reviews.fold<int>(
      0,
      (sum, review) => sum + ((review['rating'] as num?)?.toInt() ?? 0),
    );
    final average = count == 0 ? 0.0 : total / count;
    final fullStars = average.round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Text(
            count == 0 ? '—' : average.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stars(fullStars, size: 22),
                const SizedBox(height: 4),
                Text(
                  count == 1 ? '1 review' : '$count reviews',
                  style: const TextStyle(color: Color(0xFF617168)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewForm() {
    if (_isSeller) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 15),
        child: Text(
          'This is your listing. You can read reviews but not rate yourself.',
          style: TextStyle(color: Color(0xFF617168)),
        ),
      );
    }
    if (_userId == null) {
      return const Text('Please sign in to write a review.');
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _myReview == null ? 'Write a review' : 'Edit your review',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rate your experience honestly. One review per account per listing.',
            style: TextStyle(fontSize: 13, color: Color(0xFF617168)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 0,
            children: List.generate(5, (index) {
              return IconButton(
                tooltip: '${index + 1} star${index == 0 ? '' : 's'}',
                onPressed: _saving
                    ? null
                    : () => setState(() => _rating = index + 1),
                icon: Icon(
                  index < _rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 34,
                  color: const Color(0xFFF59E0B),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _comment,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Your feedback',
              hintText:
                  'Describe your experience with this product or service...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            validator: (text) {
              final length = (text ?? '').trim().length;
              if (length < 10) return 'Write at least 10 characters.';
              if (length > 1000) {
                return 'Keep your review under 1000 characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rate_review_outlined),
              label: Text(_myReview == null ? 'Publish Review' : 'Save Review'),
            ),
          ),
          if (_myReview != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _saving ? null : _deleteReview,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete my review'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    final mine = review['reviewer_id'] == _userId;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mine ? 'You' : 'Community member',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _dateLabel(review['created_at']),
                style: const TextStyle(color: Color(0xFF617168), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _stars(rating),
          const SizedBox(height: 10),
          Text(
            (review['comment'] ?? '').toString(),
            style: const TextStyle(height: 1.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F8),
        title: const Text('Reviews & Ratings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loadReviews,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReviews,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 650),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.listingTitle,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 17),
                          _summary(),
                          const SizedBox(height: 24),
                          _reviewForm(),
                          const SizedBox(height: 26),
                          const Text(
                            'Community feedback',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_reviews.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No reviews yet. Be the first to share your experience.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF617168)),
                              ),
                            )
                          else
                            ..._reviews.map(_reviewCard),
                          const SizedBox(height: 30),
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
