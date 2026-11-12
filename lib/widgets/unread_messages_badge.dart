import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/unread_messages_service.dart';

/// Place inside the existing Messages IconButton: icon: const UnreadMessagesBadge()
/// Count means individual unread incoming messages, not conversation count.
class UnreadMessagesBadge extends StatefulWidget {
  const UnreadMessagesBadge({super.key});

  @override
  State<UnreadMessagesBadge> createState() => _UnreadMessagesBadgeState();
}

class _UnreadMessagesBadgeState extends State<UnreadMessagesBadge>
    with WidgetsBindingObserver {
  static const Color badgeRed = Color(0xFFE53935);

  RealtimeChannel? _channel;
  Timer? _fallbackTimer;
  int _unread = 0;
  int _latestRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UnreadMessagesService.changes.addListener(_onChanged);
    _refresh();

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId != null) {
      // Step 20 enables Realtime on public.messages. RLS still filters rows.
      _channel = client
          .channel('unread-badge-$userId-${identityHashCode(this)}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (_) => _refresh(),
          )
          .subscribe();
    }

    // Resynchronizes if a Realtime event was missed or the connection resumed.
    _fallbackTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refresh(),
    );
  }

  void _onChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_latestRequest;
    try {
      final counts = await UnreadMessagesService.fetchCounts();
      if (!mounted || request != _latestRequest) return;
      setState(() {
        _unread = counts.values.fold<int>(0, (sum, value) => sum + value);
      });
    } catch (error) {
      // Keep the previously known count on temporary connection errors.
      debugPrint('Unread badge refresh failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UnreadMessagesService.changes.removeListener(_onChanged);
    _fallbackTimer?.cancel();
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Messages, $_unread unread',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded),
          if (_unread > 0)
            Positioned(
              right: -11,
              top: -11,
              child: Container(
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeRed,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.3),
                ),
                child: Text(
                  _unread > 99 ? '99+' : '$_unread',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
