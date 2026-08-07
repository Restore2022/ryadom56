import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'create_listing_screen.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

const closeReasons = {
  'sold': 'Продали / отдали',
  'not_relevant': 'Неактуально',
  'busy': 'Пока занят / нет времени',
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
      final data = await context.read<AppState>().loadMyListings();
      if (mounted) {
        setState(() {
          items = data;
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

  Future<void> _edit(Map<String, dynamic> item) async {
    final ok = await Navigator.push<bool>(
      context,
      fastRoute(CreateListingScreen(listingId: item['id'] as int, initial: item)),
    );
    if (ok == true) await _load();
  }

  Future<void> _republish(Map<String, dynamic> item) async {
    try {
      await context.read<AppState>().republishListing(item['id'] as int);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отправлено на модерацию')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppState.userFriendlyError(e))),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Объявление снято')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppState.userFriendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Мои объявления')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : items.isEmpty
                  ? const Center(child: Text('Пока нет объявлений'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final item = items[i] as Map<String, dynamic>;
                          final images = (item['images'] as List?) ?? [];
                          final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
                          final status = '${item['status']}';
                          final canClose = status == 'approved' || status == 'pending';
                          final canRepublish = status == 'archived' || status == 'rejected' || status == 'draft';
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
                                          Text(item['title'] as String, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text(
                                            statusLabels[status] ?? status,
                                            style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                          if (status == 'rejected' && item['moderation_note'] != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Причина: ${item['moderation_note']}',
                                              style: TextStyle(color: scheme.error, fontSize: 12),
                                            ),
                                          ],
                                          if (item['close_reason'] != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              closeReasons['${item['close_reason']}'] ?? '${item['close_reason']}',
                                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 4,
                                            children: [
                                              TextButton(
                                                onPressed: () => _edit(item),
                                                child: const Text('Изменить'),
                                              ),
                                              if (canRepublish)
                                                TextButton(
                                                  onPressed: () => _republish(item),
                                                  child: Text(status == 'draft' ? 'Отправить' : 'Снова'),
                                                ),
                                              if (canClose)
                                                TextButton(
                                                  onPressed: () => _close(item),
                                                  child: const Text('Снять'),
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
    );
  }
}
