import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../call_service.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

class RideChatScreen extends StatefulWidget {
  const RideChatScreen({
    super.key,
    required this.rideId,
    required this.title,
    this.peerId,
    this.peerName,
  });

  final int rideId;
  final String title;
  final int? peerId;
  final String? peerName;

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  List<dynamic> messages = [];
  bool loading = true;
  bool sending = false;
  String? error;
  final input = TextEditingController();
  final scroll = ScrollController();
  Timer? _poll;
  int _seenInbox = 0;

  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_onLive);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_onLive);
    _poll?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  Future<void> _load() async {
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы написать');
    if (!loggedIn || !mounted) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await context.read<AppState>().loadRideMessages(widget.rideId, peerId: widget.peerId);
      if (mounted) {
        setState(() {
          messages = rows;
          loading = false;
        });
        _scrollToBottom();
        _startPoll();
        context.read<AppState>().refreshUnreadChats();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = AppState.userFriendlyError(e);
          loading = false;
        });
      }
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshSilent());
  }

  bool _sameThread(Map<String, dynamic> ev) {
    final rid = _asInt(ev['ride_id']);
    if (rid != widget.rideId) return false;
    final passengerId = _asInt(ev['passenger_id']);
    final myId = CallService.instance.myUserId;
    if (widget.peerId != null && passengerId != null) {
      return passengerId == widget.peerId || passengerId == myId;
    }
    return true;
  }

  void _onLive() {
    final svc = CallService.instance;
    if (svc.inboxSeq <= _seenInbox) return;
    _seenInbox = svc.inboxSeq;
    final ev = svc.inboxEvent;
    if (ev == null || !mounted || !_sameThread(ev)) return;
    final type = ev['type']?.toString();
    if (type == 'ride_chat') {
      final raw = ev['message'];
      if (raw is Map) _upsert(Map<String, dynamic>.from(raw));
    } else if (type == 'ride_chat_read') {
      setState(() {
        messages = [
          for (final m in messages)
            if (m is Map && m['is_mine'] == true) {...Map<String, dynamic>.from(m), 'is_read': true} else m,
        ];
      });
    }
  }

  void _upsert(Map<String, dynamic> msg) {
    final id = _asInt(msg['id']);
    final next = List<dynamic>.from(messages);
    final idx = next.indexWhere((m) => m is Map && _asInt(m['id']) == id);
    if (idx >= 0) {
      next[idx] = msg;
    } else {
      next.add(msg);
    }
    setState(() => messages = next);
    _scrollToBottom();
    context.read<AppState>().refreshUnreadChats();
  }

  Future<void> _refreshSilent() async {
    if (!mounted || loading) return;
    try {
      final rows = await context.read<AppState>().loadRideMessages(widget.rideId, peerId: widget.peerId);
      if (!mounted) return;
      setState(() => messages = rows);
      await context.read<AppState>().refreshUnreadChats();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final msg = await context.read<AppState>().sendRideMessage(
            widget.rideId,
            body,
            peerId: widget.peerId,
          );
      if (mounted) {
        _upsert(Map<String, dynamic>.from(msg));
        input.clear();
      }
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = widget.peerName?.isNotEmpty == true ? '${widget.peerName} · ${widget.title}' : widget.title;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Сообщения', style: TextStyle(fontSize: 16)),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null && messages.isEmpty
                    ? errorState(context: context, message: error!, onRetry: _load)
                    : messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Напишите, когда удобно выехать и где встретиться. Это личный чат.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scroll,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: messages.length,
                            itemBuilder: (_, i) {
                              final msg = messages[i] as Map<String, dynamic>;
                              final mine = msg['is_mine'] == true;
                              final read = msg['is_read'] == true;
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                  decoration: BoxDecoration(
                                    color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(mine ? 16 : 4),
                                      bottomRight: Radius.circular(mine ? 4 : 16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('${msg['body']}', style: const TextStyle(height: 1.35)),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            formatApiDateTime(msg['created_at']?.toString(), sep: ' '),
                                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                          ),
                                          if (mine) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              read ? Icons.done_all : Icons.done,
                                              size: 14,
                                              color: read ? scheme.primary : scheme.onSurfaceVariant,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          Material(
            elevation: 4,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Сообщение',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
