import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppState>().loadNotifications();
      if (mounted) {
        setState(() {
          items = data;
          loading = false;
        });
      }
      await context.read<AppState>().refreshUnreadNotifications();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = AppState.userFriendlyError(e);
          loading = false;
        });
      }
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id'] as int?;
    if (id != null && item['is_read'] != true) {
      try {
        await context.read<AppState>().markNotificationRead(id);
      } catch (_) {}
    }
    final listingId = item['listing_id'] as int?;
    if (listingId != null && mounted) {
      try {
        await context.read<AppState>().getListing(listingId);
        if (!mounted) return;
        await Navigator.push(context, fastRoute(ListingDetailScreen(listingId: listingId)));
      } on ApiException catch (e) {
        if (mounted) showAppSnack(context, e.message, error: true);
      } catch (e) {
        if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                await context.read<AppState>().markAllNotificationsRead();
                await _load();
              },
              child: const Text('Прочитать все'),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? errorState(context: context, message: error!, onRetry: _load)
              : items.isEmpty
                  ? emptyState(
                      context: context,
                      title: 'Пока нет уведомлений',
                      subtitle: 'Здесь появятся ответы по объявлениям и жалобам',
                      icon: Icons.notifications_none,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final item = items[i] as Map<String, dynamic>;
                          final unread = item['is_read'] != true;
                          return Material(
                            color: unread
                                ? scheme.primaryContainer.withValues(alpha: 0.35)
                                : Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _open(item),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['title'] as String? ?? 'Уведомление',
                                            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                                          ),
                                      ],
                                    ),
                                    if (item['body'] != null) ...[
                                      const SizedBox(height: 6),
                                      Text('${item['body']}', style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
