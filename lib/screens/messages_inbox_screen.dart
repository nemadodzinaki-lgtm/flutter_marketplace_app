import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/unread_messages_service.dart';
import '../services/chat_people_service.dart';
import '../widgets/chat_person_avatar.dart';
import 'chat_screen.dart';

class MessagesInboxScreen extends StatefulWidget {
  const MessagesInboxScreen({super.key});

  @override
  State<MessagesInboxScreen> createState() => _MessagesInboxScreenState();
}

class _InboxData {
  final List<Map<String, dynamic>> conversations;
  final Map<String, int> unreadByConversation;
  final Map<String, Map<String, dynamic>> participants;

  const _InboxData(
    this.conversations,
    this.unreadByConversation,
    this.participants,
  );
}

class _MessagesInboxScreenState extends State<MessagesInboxScreen>
    with WidgetsBindingObserver {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  late Future<_InboxData> _inbox;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inbox = _loadInbox();
    UnreadMessagesService.changes.addListener(_onUnreadChanged);

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId != null) {
      _channel = client
          .channel('inbox-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (_) => _reload(),
          )
          .subscribe();
    }
  }

  void _onUnreadChanged() {
    _reload();
  }

  Future<_InboxData> _loadInbox() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return const _InboxData([], {}, {});

    final result = await client
        .from('conversations')
        .select(
          'id, listing_id, buyer_id, seller_id, created_at, listings(title)',
        )
        .or('buyer_id.eq.${user.id},seller_id.eq.${user.id}')
        .order('created_at', ascending: false)
        .limit(100);

    final counts = await UnreadMessagesService.fetchCounts();
    final participants = await ChatPeopleService.forInbox();
    final conversations = List<Map<String, dynamic>>.from(result);
    // Most recently active chats come first, not necessarily newest created.
    DateTime sortTime(Map<String, dynamic> c) {
      final id = c['id']?.toString() ?? '';
      final lastAt = participants[id]?['last_message_at']?.toString();
      return DateTime.tryParse(lastAt ?? '') ??
          DateTime.tryParse(c['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    conversations.sort((a, b) => sortTime(b).compareTo(sortTime(a)));
    return _InboxData(conversations, counts, participants);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final pending = _loadInbox();
    setState(() {
      _inbox = pending;
    });
    try {
      await pending;
    } catch (_) {
      // FutureBuilder shows an error with a Retry action.
    }
  }

  Future<void> _openChat(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id)),
    );
    if (!mounted) return;
    await _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UnreadMessagesService.changes.removeListener(_onUnreadChanged);
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F8),
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Refresh inbox',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_InboxData>(
        future: _inbox,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: green));
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_outlined, size: 44),
                  const SizedBox(height: 12),
                  const Text('Could not load conversations.'),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final conversations = data.conversations;
          if (conversations.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Icon(Icons.forum_outlined, size: 65, color: green),
                  SizedBox(height: 18),
                  Text(
                    'No conversations yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Open a product or service and tap Contact Seller to start chatting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF617168)),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final convo = conversations[index];
                final id = convo['id'].toString();
                final unread = data.unreadByConversation[id] ?? 0;
                final isBuyer = convo['buyer_id'] == myId;
                final otherRole = isBuyer ? 'Seller' : 'Buyer';
                final person = data.participants[id];
                final personName =
                    (person?['display_name'] ?? 'Community member').toString();
                final photo = person?['profile_image_url']?.toString();
                final preview = person?['last_message']?.toString() ?? '';
                final lastFromMe = person?['last_sender_id'] == myId;
                final isImagePreview = preview.startsWith(
                  '[[community_market_image]]:',
                );
                final previewLabel = isImagePreview ? '📷 Photo' : preview;
                final previewText = preview.isEmpty
                    ? 'No messages yet'
                    : lastFromMe
                    ? 'You: $previewLabel'
                    : previewLabel;
                final listing = convo['listings'];
                final listingTitle = listing is Map
                    ? (listing['title'] ?? 'Listing').toString()
                    : 'Listing';

                return Card(
                  elevation: 0,
                  color: unread > 0 ? const Color(0xFFEAF7EE) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE5EDE8)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: ChatPersonAvatar(imageUrl: photo, size: 48),
                    title: Text(
                      personName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: unread > 0
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '$otherRole · $listingTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF617168),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0 ? green : const Color(0xFF617168),
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unread > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: green,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    onTap: () => _openChat(id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
