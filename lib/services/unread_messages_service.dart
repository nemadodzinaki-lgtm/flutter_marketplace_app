import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared actions for unread message counts and read receipts.
/// The database checks participant identity and access permissions.
class UnreadMessagesService {
  UnreadMessagesService._();

  /// Notifies visible message widgets that their counts should be refreshed.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void notifyChanged() {
    changes.value += 1;
  }

  /// Returns unread incoming message counts keyed by conversation UUID.
  static Future<Map<String, int>> fetchCounts() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return {};

    final rows = await client.rpc('step21_unread_counts');
    final counts = <String, int>{};

    if (rows is List) {
      for (final item in rows) {
        if (item is! Map) continue;
        final id = item['conversation_id']?.toString();
        final rawCount = item['unread_count'];
        if (id == null || id.isEmpty) continue;
        final count = rawCount is num
            ? rawCount.toInt()
            : int.tryParse(rawCount?.toString() ?? '') ?? 0;
        if (count > 0) counts[id] = count;
      }
    }
    return counts;
  }

  static Future<void> markConversationRead(String conversationId) async {
    await Supabase.instance.client.rpc(
      'step21_mark_conversation_read',
      params: {'target_conversation': conversationId},
    );
    notifyChanged();
  }
}
