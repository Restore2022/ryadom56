import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../call_service.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'listing_chat_screen.dart';
import 'ride_chat_screen.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  bool loading = true;
  String? error;
  int? _loadedUserId;
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
    super.dispose();
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || loading) return;
      final state = context.read<AppState>();
      if (state.user == null) return;
      try {
        await state.loadConversations();
      } catch (_) {}
    });
  }

  void _onLive() {
    final svc = CallService.instance;
    if (svc.inboxSeq <= _seenInbox) return;
    _seenInbox = svc.inboxSeq;
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.user == null) return;
    state.loadConversations();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (state.user == null) {
      _poll?.cancel();
      setState(() {
        loading = false;
        error = null;
        _loadedUserId = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await state.loadConversations();
      if (!mounted) return;
      setState(() {
        loading = false;
        _loadedUserId = state.user?['id'] as int?;
        error = null;
      });
      _startPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = AppState.userFriendlyError(e);
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final pad = context.isLandscape ? 12.0 : 16.0;

    final uid = state.user?['id'] as int?;
    if (uid != null && uid != _loadedUserId && !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    if (state.user == null) {
      return ListView(
        padding: EdgeInsets.all(pad),
        children: [
          adaptiveFillMessage(
            context: context,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GuestCtaBanner(
                  title: 'Чаты после входа',
                  subtitle:
                      'Ленту уже смотрите. Аккаунт нужен, чтобы написать автору и не потерять переписку. Без комиссии.',
                ),
                const SizedBox(height: 16),
                emptyState(
                  context: context,
                  title: 'Пока гость',
                  subtitle: 'Создайте аккаунт за минуту — имя, почта и место',
                  icon: Icons.chat_bubble_outline,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final items = state.conversations;
    return RefreshIndicator(
      onRefresh: _load,
      child: loading && items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator()),
              ],
            )
          : error != null && items.isEmpty
              ? ListView(
                  children: [
                    adaptiveFillMessage(
                      context: context,
                      child: errorState(context: context, message: error!, onRetry: _load),
                    ),
                  ],
                )
              : items.isEmpty
                  ? ListView(
                      children: [
                        adaptiveFillMessage(
                          context: context,
                          child: emptyState(
                            context: context,
                            title: 'Пока нет чатов',
                            subtitle: 'Напишите из карточки объявления или попутки — переписка появится здесь',
                            icon: Icons.forum_outlined,
                            actionLabel: 'Обновить',
                            onAction: _load,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, context.listBottomPad),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final item = items[i] as Map<String, dynamic>;
                        final unread = item['unread_count'] as int? ?? 0;
                        final peer = item['peer_name']?.toString();
                        final rideId = item['ride_id'] as int?;
                        final title = item['listing_title']?.toString() ?? item['title']?.toString() ?? (rideId != null ? 'Попутка' : 'Объявление');
                        final last = item['last_message']?.toString() ?? '';
                        final lastKind = item['last_kind']?.toString() ?? 'text';
                        final isSeller = item['is_seller'] == true || item['is_driver'] == true;
                        final peerId = item['peer_id'] as int?;
                        return Material(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              if (rideId != null) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RideChatScreen(
                                      rideId: rideId,
                                      title: title,
                                      peerId: peerId,
                                      peerName: peer,
                                    ),
                                  ),
                                );
                              } else {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ListingChatScreen(
                                      listingId: item['listing_id'] as int,
                                      listingTitle: title,
                                      peerId: peerId,
                                      peerName: peer,
                                    ),
                                  ),
                                );
                              }
                              if (mounted) _load();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: scheme.primaryContainer,
                                    child: Icon(
                                      rideId != null
                                          ? Icons.directions_car_outlined
                                          : (isSeller ? Icons.storefront : Icons.person_outline),
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                peer?.isNotEmpty == true ? peer! : (isSeller ? 'Покупатель' : 'Продавец'),
                                                style: GoogleFonts.manrope(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              formatApiChatList(item['last_message_at']?.toString()),
                                              style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          title,
                                          style: TextStyle(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (lastKind == 'call') ...[
                                              Icon(
                                                last.contains('Пропущен')
                                                    ? Icons.phone_missed
                                                    : Icons.call,
                                                size: 14,
                                                color: unread > 0 ? scheme.primary : scheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 4),
                                            ] else if (lastKind == 'photo') ...[
                                              Icon(
                                                Icons.photo_outlined,
                                                size: 14,
                                                color: unread > 0 ? scheme.primary : scheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            Expanded(
                                              child: Text(
                                                last,
                                                style: TextStyle(
                                                  color: scheme.onSurfaceVariant,
                                                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (unread > 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        unread > 99 ? '99+' : '$unread',
                                        style: TextStyle(
                                          color: scheme.onPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
