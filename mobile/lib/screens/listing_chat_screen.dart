import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

class ListingChatScreen extends StatefulWidget {
  const ListingChatScreen({
    super.key,
    required this.listingId,
    required this.listingTitle,
    this.peerId,
    this.peerName,
    this.initialMessage,
  });

  final int listingId;
  final String listingTitle;
  /// Id собеседника. Для продавца обязателен (id покупателя).
  final int? peerId;
  final String? peerName;
  final String? initialMessage;

  @override
  State<ListingChatScreen> createState() => _ListingChatScreenState();
}

class _ListingChatScreenState extends State<ListingChatScreen> {
  List<dynamic> messages = [];
  bool loading = true;
  bool sending = false;
  String? error;
  final input = TextEditingController();
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      input.text = widget.initialMessage!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы написать автору');
    if (!loggedIn || !mounted) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await context.read<AppState>().loadListingMessages(
            widget.listingId,
            peerId: widget.peerId,
          );
      if (mounted) {
        setState(() {
          messages = rows;
          loading = false;
        });
        _scrollToBottom();
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
      final msg = await context.read<AppState>().sendListingMessage(
            widget.listingId,
            body,
            peerId: widget.peerId,
          );
      if (mounted) {
        setState(() {
          messages = [...messages, msg];
          input.clear();
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String _fmtTime(String? iso) {
    return formatApiDateTime(iso, sep: ' ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = widget.peerName?.isNotEmpty == true
        ? '${widget.peerName} · ${widget.listingTitle}'
        : widget.listingTitle;
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
                                'Это личный чат. Сообщения видите только вы и собеседник.',
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (!mine && msg['sender_name'] != null)
                                        Text(
                                          '${msg['sender_name']}',
                                          style: GoogleFonts.manrope(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      Text('${msg['body']}', style: const TextStyle(height: 1.35)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _fmtTime(msg['created_at']?.toString()),
                                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
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
                          hintText: 'Сообщение…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : _send,
                      icon: sending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                            )
                          : const Icon(Icons.send),
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
