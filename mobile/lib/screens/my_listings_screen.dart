import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

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
    final state = context.watch<AppState>();
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
                                    padding: const EdgeInsets.all(16),
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (context, i) {
                                      final item = list[i] as Map<String, dynamic>;
                                      final images = (item['images'] as List?) ?? [];
                                      final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
                                      final status = '${item['status']}';
                                      final canClose = status == 'approved' || status == 'pending';
                                      final canRepublish =
                                          status == 'archived' || status == 'rejected' || status == 'draft';
                                      final canExtend = status == 'approved' ||
                                          (status == 'archived' && item['close_reason'] == 'expired');
                                      final canDelete =
                                          status == 'draft' || status == 'rejected' || status == 'archived';
                                      return Material(
                                        color: Theme.of(context).cardTheme.color,
                                        borderRadius: BorderRadius.circular(16),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(16),
                                          onTap: () async {
                                            await Navigator.push(
                                              context,
                                              fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
                                            );
                                            await _load();
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: thumb == null
                                                      ? Container(
                                                          width: 72,
                                                          height: 72,
                                                          color: scheme.surfaceContainerHighest,
                                                          child: const Icon(Icons.image_outlined),
                                                        )
                                                      : Image.network(
                                                          state.mediaUrl(thumb),
                                                          width: 72,
                                                          height: 72,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => Container(
                                                            width: 72,
                                                            height: 72,
                                                            color: scheme.surfaceContainerHighest,
                                                            child: const Icon(Icons.broken_image_outlined),
                                                          ),
                                                        ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item['title'] as String,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        statusLabels[status] ?? status,
                                                        style: TextStyle(
                                                          color: status == 'rejected'
                                                              ? scheme.error
                                                              : status == 'approved'
                                                                  ? scheme.primary
                                                                  : scheme.onSurfaceVariant,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                      if (status == 'pending') ...[
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          'Ожидает проверки модератором',
                                                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                                        ),
                                                      ],
                                                      if (status == 'rejected' && item['moderation_note'] != null) ...[
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          'Причина: ${item['moderation_note']}',
                                                          style: TextStyle(color: scheme.error, fontSize: 12, height: 1.3),
                                                        ),
                                                      ],
                                                      if (item['expires_at'] != null &&
                                                          (status == 'approved' || item['close_reason'] == 'expired')) ...[
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          _expiryLine(item),
                                                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                                        ),
                                                      ],
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 4,
                                                        children: [
                                                          TextButton(onPressed: () => _edit(item), child: const Text('Изменить')),
                                                          if (canRepublish)
                                                            TextButton(
                                                              onPressed: () => _republish(item),
                                                              child: Text(status == 'draft' ? 'Отправить' : 'Снова'),
                                                            ),
                                                          if (canExtend)
                                                            TextButton(onPressed: () => _extend(item), child: const Text('Продлить')),
                                                          if (canClose)
                                                            TextButton(onPressed: () => _close(item), child: const Text('Снять')),
                                                          if (canDelete)
                                                            TextButton(
                                                              onPressed: () => _delete(item),
                                                              child: Text('Удалить', style: TextStyle(color: scheme.error)),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
