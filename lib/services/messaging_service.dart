import 'package:supabase_flutter/supabase_flutter.dart';

/// Starts or reopens a conversation about one active listing.
/// Never trusts a seller ID typed by a user: the database verifies ownership.
class MessagingService {
  static Future<String> openConversation({
    required String listingId,
    required String sellerId,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('Please sign in before contacting a seller.');
    }
    if (user.id == sellerId) {
      throw StateError('You cannot message yourself about your listing.');
    }

    Future<String?> existingConversation() async {
      final row = await client
          .from('conversations')
          .select('id')
          .eq('listing_id', listingId)
          .eq('buyer_id', user.id)
          .eq('seller_id', sellerId)
          .maybeSingle();
      return row?['id'] as String?;
    }

    final existing = await existingConversation();
    if (existing != null) return existing;

    try {
      final created = await client.from('conversations').insert({
        'listing_id': listingId,
        'buyer_id': user.id,
        'seller_id': sellerId,
      }).select('id').single();
      return created['id'] as String;
    } on PostgrestException catch (error) {
      // A double tap or concurrent create may hit the unique constraint.
      if (error.code == '23505') {
        final existing = await existingConversation();
        if (existing != null) return existing;
      }
      rethrow;
    }
  }
}
