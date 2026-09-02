import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../listing_row.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'create_listing_screen.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

const closeReasons = {
  'sold': 'Продали / отдали',
  'not_relevant': 'Неактуально',
  'busy': 'Пока занят / нет времени',
  'expired': 'Истёк срок',
  'other': 'Другое',
};

const statusLabels = {
  'draft': 'Черновик',
  'pending': 'На проверке',
  'approved': 'Опубликовано',
  'rejected': 'Отклонено',
  'archived': 'Снято',
};

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  List<dynamic> items = [];
  Map<String, dynamic>? stats;
  bool loading = true;
  String? error;
  String filter = 'all';

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
      final app = context.read<AppState>();
      final data = await app.loadMyListings();
      final st = await app.loadMyListingStats();
      if (mounted) {
        setState(() {
          items = data;
          stats = st;
          loading = false;
        });
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

  List<dynamic> get visible {
    if (filter == 'all') return items;
    return items.where((e) => e is Map && '${e['status']}' == filter).toList();
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final ok = await Navigator.push<bool>(
      context,
      fastRoute(CreateListingScreen(listingId: item['id'] as int, initial: item)),
    );
    if (ok == true) await _load();
  }

  Future<void> _extend(Map<String, dynamic> item) async {
    int days = 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Продлить'),
              content: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 30, label: Text('30 дней')),
                  ButtonSegment(value: 60, label: Text('60 дней')),
                ],
                selected: {days},
                onSelectionChanged: (v) => setLocal(() => days = v.first),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Продлить')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().extendListing(item['id'] as int, days: days);
      await _load();
      if (mounted) showAppSnack(context, 'Срок продлён');
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  Future<void> _republish(Map<String, dynamic> item) async {
    try {
      await context.read<AppState>().republishListing(item['id'] as int);
      await _load();
      if (mounted) showAppSnack(context, 'Отправлено на модерацию');
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить объявление?'),
        content: Text('«${item['title']}» будет удалено без возможности восстановления.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().deleteListing(item['id'] as int);
      await _load();
      if (mounted) showAppSnack(context, 'Объявление удалено');
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  Future<void> _close(Map<String, dynamic> item) async {
    String reason = 'sold';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Снять объявление'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Причина', border: OutlineInputBorder()),
                    items: closeReasons.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setLocal(() => reason = v ?? 'sold'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий (необязательно)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Снять')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().closeListing(
            item['id'] as int,
            reason: reason,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
      await _load();
      if (mounted) showAppSnack(context, 'Объявление снято');
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = (stats?['active'] as num?)?.toInt() ?? 0;
    final maxActive = (stats?['max_active'] as num?)?.toInt() ?? 5;
    final list = visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои объявления'),
        actions: [
          if (stats != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '$active/$maxActive активных',
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? errorState(context: context, message: error!, onRetry: _load)
              : Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        children: [
                          _chip('all', 'Все', items.length),
                          _chip('pending', 'На проверке', stats?['pending']),
                          _chip('approved', 'Опубликовано', stats?['approved']),
                          _chip('draft', 'Черновики', stats?['draft']),
                          _chip('rejected', 'Отклонённые', stats?['rejected']),
                          _chip('archived', 'Снятые', stats?['archived']),
                        ],
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? emptyState(
                              context: context,
                              title: 'Пока нет объявлений',
                              subtitle: 'Подайте первое — оно появится здесь со статусом проверки',
                              icon: Icons.post_add_outlined,
                              actionLabel: 'Подать объявление',
                              onAction: () async {
                                final ok = await Navigator.push<bool>(context, fastRoute(const CreateListingScreen()));
                                if (ok == true) await _load();
                              },
                            )
                          : list.isEmpty
                              ? emptyState(
                                  context: context,
                                  title: 'В этом статусе пусто',
                                  subtitle: 'Выберите другой фильтр сверху',
                                  icon: Icons.filter_alt_outlined,
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.separated(
                                    padding: context.scrollPad(top: 8, bottom: 20),
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (context, i) {
                                      final item = list[i] as Map<String, dynamic>;
                                      final status = '${item['status']}';
                                      final canClose = status == 'approved' || status == 'pending';
                                      final canRepublish =
                                          status == 'archived' || status == 'rejected' || status == 'draft';
                                      final canExtend = status == 'approved' ||
                                          (status == 'archived' && item['close_reason'] == 'expired');
                                      final canDelete =
                                          status == 'draft' || status == 'rejected' || status == 'archived';
                                      String? footer;
                                      if (status == 'pending') footer = 'Ждёт проверки';
                                      if (status == 'rejected' && item['moderation_note'] != null) {
                                        footer = '${item['moderation_note']}';
                                      }
                                      if (item['expires_at'] != null &&
                                          (status == 'approved' || item['close_reason'] == 'expired')) {
                                        footer = _expiryLine(item);
                                      }
                                      return ListingRow(
                                        item: item,
                                        badge: statusLabels[status],
                                        badgeColor: status == 'rejected'
                                            ? scheme.error
                                            : status == 'approved'
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                        footer: footer,
                                        onTap: () async {
                                          await Navigator.push(
                                            context,
                                            fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
                                          );
                                          await _load();
                                        },
                                        trailing: PopupMenuButton<String>(
                                          tooltip: 'Действия',
                                          onSelected: (v) {
                                            switch (v) {
                                              case 'edit':
                                                _edit(item);
                                              case 'republish':
                                                _republish(item);
                                              case 'extend':
                                                _extend(item);
                                              case 'close':
                                                _close(item);
                                              case 'delete':
                                                _delete(item);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                                            if (canRepublish)
                                              PopupMenuItem(
                                                value: 'republish',
                                                child: Text(status == 'draft' ? 'Отправить' : 'Снова опубликовать'),
                                              ),
                                            if (canExtend) const PopupMenuItem(value: 'extend', child: Text('Продлить')),
                                            if (canClose) const PopupMenuItem(value: 'close', child: Text('Снять')),
                                            if (canDelete)
                                              const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }

  String _expiryLine(Map item) {
    final iso = item['expires_at']?.toString();
    final dt = parseApiTime(iso);
    final date = formatApiDate(iso, empty: '—');
    if (dt == null) return 'Срок: $date';
    final days = dt.difference(DateTime.now()).inDays;
    if (item['close_reason'] == 'expired' || days < 0) return 'Срок истёк $date — нажмите Продлить';
    if (days == 0) return 'Снимается сегодня';
    return 'До $date · ещё $days дн.';
  }

  Widget _chip(String key, String label, dynamic count) {
    final n = count is num ? count.toInt() : (count is int ? count : null);
    final selected = filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(n == null ? label : '$label ($n)'),
        onSelected: (_) => setState(() => filter = key),
      ),
    );
  }
}
