import 'package:supabase_flutter/supabase_flutter.dart';

/// Only approved public-facing participant information is returned.
/// Supabase checks the currently signed-in user is a chat participant.
class ChatPeopleService {
  ChatPeopleService._();

  static Future<Map<String, Map<String, dynamic>>> forInbox() async {
    if (Supabase.instance.client.auth.currentUser == null) return {};
    final raw = await Supabase.instance.client.rpc(
      'step34_chat_participants',
      params: {'p_conversation_id': null},
    );
    final people = <String, Map<String, dynamic>>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final id = row['conversation_id']?.toString() ?? '';
        if (id.isNotEmpty) people[id] = row;
      }
    }
    return people;
  }

  static Future<Map<String, dynamic>?> forChat(String conversationId) async {
    if (Supabase.instance.client.auth.currentUser == null) return null;
    final raw = await Supabase.instance.client.rpc(
      'step34_chat_participants',
      params: {'p_conversation_id': conversationId},
    );
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }
}
