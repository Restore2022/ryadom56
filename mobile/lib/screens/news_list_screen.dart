import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui_helpers.dart';

class NewsListScreen extends StatefulWidget {
  const NewsListScreen({super.key, this.settlementId});

  final int? settlementId;

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  List<dynamic> items = [];
  bool loading = true;
  String? error;
  int? settlementId;

  @override
  void initState() {
    super.initState();
    settlementId = widget.settlementId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppState>().loadNews(settlementId: settlementId);
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

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  void _openDetail(Map<String, dynamic> item) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.read<AppState>();
    final published = _fmtDate(item['published_at']?.toString() ?? item['created_at']?.toString());
    final cover = item['cover_url']?.toString();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                if (cover != null && cover.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        state.mediaUrl(cover),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                  ),
                if (cover != null && cover.isNotEmpty) const SizedBox(height: 14),
                Text(
                  '${item['title']}',
                  style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (item['is_pinned'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('Закреплено', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11)),
                      ),
                    if (published.isNotEmpty)
                      Text(published, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                    if (item['settlement_name'] != null)
                      Text(
                        '· ${item['settlement_name']}',
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${item['body']}',
                  style: const TextStyle(height: 1.45, fontSize: 15),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Новости района')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<int?>(
              value: settlementId != null && state.settlements.any((s) => s['id'] == settlementId) ? settlementId : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Населённый пункт',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Весь район')),
                ...state.settlements.map(
                  (s) => DropdownMenuItem<int?>(
                    value: s['id'] as int,
                    child: Text(s['display_name'] as String, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => settlementId = v);
                _load();
              },
            ),
          ),
          if (context.watch<AppState>().lastNewsFromCache)
            Material(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.offline_bolt, size: 18, color: scheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Показаны сохранённые новости — нет связи с сервером',
                        style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: loading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : error != null && items.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: 280,
                              child: errorState(context: context, message: error!, onRetry: _load),
                            ),
                          ],
                        )
                      : items.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height: 280,
                                  child: emptyState(
                                    context: context,
                                    title: 'Пока нет новостей',
                                    subtitle: 'Новости района появятся здесь',
                                    icon: Icons.newspaper_outlined,
                                    actionLabel: 'Обновить',
                                    onAction: _load,
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final item = items[i] as Map<String, dynamic>;
                                final date = _fmtDate(
                                  item['published_at']?.toString() ?? item['created_at']?.toString(),
                                );
                                final body = item['body']?.toString() ?? '';
                                final cover = item['cover_url']?.toString();
                                return Material(
                                  color: Theme.of(context).cardTheme.color,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _openDetail(item),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: item['is_pinned'] == true
                                              ? scheme.primary.withValues(alpha: 0.55)
                                              : scheme.outlineVariant.withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (cover != null && cover.isNotEmpty) ...[
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                state.mediaUrl(cover),
                                                width: 72,
                                                height: 72,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  width: 72,
                                                  height: 72,
                                                  color: scheme.surfaceContainerHighest,
                                                  child: const Icon(Icons.image_outlined),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    if (date.isNotEmpty)
                                                      Text(
                                                        date,
                                                        style: TextStyle(
                                                          color: scheme.primary,
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (item['is_pinned'] == true)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: scheme.primary.withValues(alpha: 0.16),
                                                          borderRadius: BorderRadius.circular(999),
                                                        ),
                                                        child: Text(
                                                          'Закреплено',
                                                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '${item['title']}',
                                                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17),
                                                ),
                                                if (item['settlement_name'] != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${item['settlement_name']}',
                                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                                                  ),
                                                ],
                                                if (body.isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    body,
                                                    maxLines: 3,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
                                                  ),
                                                ],
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
}
