import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/unread_messages_service.dart';
import '../services/chat_people_service.dart';
import '../widgets/chat_person_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color green = Color(0xFF16803C);
  static const Color background = Color(0xFFF7F9F8);

  final _input = TextEditingController();
  final _picker = ImagePicker();
  late Future<Map<String, dynamic>?> _conversation;
  late Future<Map<String, dynamic>?> _participant;
  late Stream<List<Map<String, dynamic>>> _messages;
  bool _sending = false;
  bool _markingRead = false;
  bool _markAgain = false;
  bool _markScheduled = false;
  static const _imageMessagePrefix = '[[community_market_image]]:';

  @override
  void initState() {
    super.initState();
    _conversation = _loadConversation();
    _participant = ChatPeopleService.forChat(widget.conversationId);
    _messages = _messageStream();
  }

  Future<Map<String, dynamic>?> _loadConversation() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    final conversation = await client
        .from('conversations')
        .select('id, buyer_id, seller_id, listings(title)')
        .eq('id', widget.conversationId)
        .maybeSingle();

    if (conversation == null ||
        (conversation['buyer_id'] != user.id &&
            conversation['seller_id'] != user.id)) {
      return null;
    }
    return conversation;
  }

  Stream<List<Map<String, dynamic>>> _messageStream() {
    return Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: true);
  }

  // Messages remain unread in the inbox until this conversation is opened.
  // When this chat is visible, mark only incoming messages as read.
  void _scheduleReadIfNeeded(List<Map<String, dynamic>> messages) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;

    final hasUnreadIncoming = messages.any(
      (message) => message['sender_id'] != myId && message['is_read'] == false,
    );
    if (!hasUnreadIncoming) return;

    if (_markingRead) {
      _markAgain = true;
      return;
    }
    if (_markScheduled) return;

    _markScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markScheduled = false;
      if (mounted) _markRead();
    });
  }

  Future<void> _markRead() async {
    if (_markingRead) {
      _markAgain = true;
      return;
    }
    _markingRead = true;
    try {
      await UnreadMessagesService.markConversationRead(widget.conversationId);
    } catch (error) {
      // A read-receipt error should never block the conversation.
      debugPrint('Could not mark messages read: $error');
    } finally {
      _markingRead = false;
      if (_markAgain && mounted) {
        _markAgain = false;
        _markRead();
      }
    }
  }

  void _retry() {
    setState(() {
      _conversation = _loadConversation();
      _participant = ChatPeopleService.forChat(widget.conversationId);
      _messages = _messageStream();
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    if (text.length > 2000) {
      _message('Keep messages under 2000 characters.');
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _message('Please sign in again.');
      return;
    }

    setState(() => _sending = true);
    try {
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'message_text': text,
      });
      if (!mounted) return;
      if (_input.text.trim() == text) _input.clear();
    } catch (error) {
      debugPrint('Send message failed: $error');
      if (!mounted) return;
      _message('Could not send message. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _message('Please sign in again.');
      return;
    }
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      // The Supabase listing-images bucket is configured with a 5 MB limit.
      if (bytes.length > 5 * 1024 * 1024) {
        _message('Choose an image smaller than 5 MB.');
        return;
      }
      final extension = image.name.contains('.')
          ? image.name.split('.').last.toLowerCase()
          : 'jpg';
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      setState(() => _sending = true);
      final path =
          '${user.id}/messages/${widget.conversationId}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      final storage = Supabase.instance.client.storage.from('listing-images');
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false),
      );
      final imageUrl = storage.getPublicUrl(path);
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'message_text': '$_imageMessagePrefix$imageUrl',
      });
    } catch (error) {
      debugPrint('Send image failed: $error');
      if (mounted) {
        final details = error.toString();
        final likelyPolicyIssue = details.contains('row-level security') ||
            details.contains('Unauthorized') ||
            details.contains('403');
        _message(
          likelyPolicyIssue
              ? 'Upload blocked by Supabase Storage policies. Check the listing-images policies.'
              : 'Could not send image: $details',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _clock(String? raw) {
    if (raw == null) return '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _bubble(Map<String, dynamic> message) {
    final own =
        message['sender_id'] == Supabase.instance.client.auth.currentUser?.id;
    final text = (message['message_text'] ?? '').toString();
    final imageUrl = text.startsWith(_imageMessagePrefix)
        ? text.substring(_imageMessagePrefix.length)
        : null;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: own ? green : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(own ? 20 : 5),
              bottomRight: Radius.circular(own ? 5 : 20),
            ),
            border: own ? null : Border.all(color: const Color(0xFFE4EAE6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    width: 230,
                    height: 190,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const SizedBox(
                            width: 230,
                            height: 190,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                    errorBuilder: (context, error, stack) => const SizedBox(
                      width: 230,
                      height: 100,
                      child: Center(child: Text('Image unavailable')),
                    ),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: TextStyle(
                      height: 1.4,
                      color: own ? Colors.white : const Color(0xFF1B2B20),
                    ),
                  ),
                ),
              const SizedBox(height: 5),
              Text(
                _clock(message['created_at']?.toString()),
                style: TextStyle(
                  fontSize: 11,
                  color: own ? Colors.white70 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thread() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load messages.'),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: green));
        }
        final messages = snapshot.data!;
        _scheduleReadIfNeeded(messages);
        if (messages.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No messages yet. Say hello to start the conversation!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF617168)),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _bubble(messages[messages.length - index - 1]),
        );
      },
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Send a picture',
              onPressed: _sending ? null : _sendImage,
              icon: const Icon(Icons.image_outlined, color: green),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a message...',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF5F7F6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            IconButton.filled(
              tooltip: 'Send message',
              style: IconButton.styleFrom(backgroundColor: green),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _conversation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: green)),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Messages')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not open this conversation.'),
                  TextButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final conversation = snapshot.data;
        if (conversation == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Messages')),
            body: const Center(child: Text('Conversation not available.')),
          );
        }
        final me = Supabase.instance.client.auth.currentUser?.id;
        final otherRole = conversation['buyer_id'] == me ? 'Seller' : 'Buyer';
        final listing = conversation['listings'];
        final title = listing is Map
            ? (listing['title'] ?? 'Listing').toString()
            : 'Listing';

        return Scaffold(
          backgroundColor: background,
          appBar: AppBar(
            backgroundColor: const Color(0xFFF7F9F8),
            titleSpacing: 0,
            title: FutureBuilder<Map<String, dynamic>?>(
              future: _participant,
              builder: (context, who) {
                final person = who.data;
                final displayName = who.hasError
                    ? 'Name unavailable'
                    : (person?['display_name'] ?? otherRole).toString();
                final image = person?['profile_image_url']?.toString();
                return Row(
                  children: [
                    ChatPersonAvatar(imageUrl: image, size: 39),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$otherRole · $title',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF617168),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          body: Column(
            children: [
              Expanded(child: _thread()),
              _composer(),
            ],
          ),
        );
      },
    );
  }
}
