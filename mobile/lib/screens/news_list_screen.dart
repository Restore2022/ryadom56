import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../scroll_to_top.dart';
import '../settlement_picker.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

List<String> newsPhotoUrls(Map<String, dynamic> item) {
  final photos = item['photos'];
  if (photos is List && photos.isNotEmpty) {
    final urls = <String>[];
    for (final p in photos) {
      if (p is Map && p['url'] != null) {
        final u = p['url'].toString();
        if (u.isNotEmpty) urls.add(u);
      }
    }
    if (urls.isNotEmpty) return urls;
  }
  final cover = item['cover_url']?.toString();
  if (cover != null && cover.isNotEmpty) return [cover];
  return [];
}

String? newsSourceLabel(Map<String, dynamic> item) {
  switch (item['source']?.toString()) {
    case 'vk':
      return 'Администрация Сакмарского района';
    case 'vk_oblast':
      return 'Новости Оренбургской области';
    default:
      return null;
  }
}

void openNewsDetail(BuildContext context, Map<String, dynamic> item) {
  final scheme = Theme.of(context).colorScheme;
  final state = context.read<AppState>();
  final published = formatApiDate(item['published_at']?.toString() ?? item['created_at']?.toString());
  final photos = newsPhotoUrls(item);
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
            padding: ctx.scrollPad(left: 20, top: 4, right: 20, bottom: 20),
            children: [
              if (photos.isNotEmpty) _NewsPhotoGallery(urls: photos, mediaUrl: state.mediaUrl),
              if (photos.isNotEmpty) const SizedBox(height: 14),
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
                  if (newsSourceLabel(item) != null)
                    Text(newsSourceLabel(item)!, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
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

class NewsListScreen extends StatefulWidget {
  const NewsListScreen({super.key, this.settlementId});

  final int? settlementId;

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  final scroll = ScrollController();
  List<dynamic> items = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  int total = 0;
  String? error;
  int? settlementId;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    settlementId = widget.settlementId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append) {
      if (!hasMore || loadingMore || loading) return;
      setState(() => loadingMore = true);
    } else {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final page = await context.read<AppState>().loadNews(
            settlementId: settlementId,
            offset: append ? items.length : 0,
            limit: _pageSize,
          );
      if (mounted) {
        setState(() {
          items = append ? [...items, ...page.items] : page.items;
          total = page.total;
          hasMore = items.length < total;
          loading = false;
          loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = AppState.userFriendlyError(e);
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  String _fmtDate(String? iso) => formatApiDate(iso);

  List<String> _photoUrls(Map<String, dynamic> item) => newsPhotoUrls(item);

  void _openDetail(Map<String, dynamic> item) => openNewsDetail(context, item);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Новости')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child:             SettlementPicker(
              value: settlementId != null && state.settlements.any((s) => s['id'] == settlementId) ? settlementId : null,
              settlements: state.settlements,
              allowAll: true,
              allLabel: 'Все новости',
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
            child: stackWithScrollToTop(
              controller: scroll,
              heroTag: 'scroll-top-news',
              child: RefreshIndicator(
                onRefresh: () => _load(),
                child: loading && items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : error != null && items.isEmpty
                        ? ListView(
                            controller: scroll,
                            children: [
                              SizedBox(
                                height: 280,
                                child: errorState(context: context, message: error!, onRetry: () => _load()),
                              ),
                            ],
                          )
                        : items.isEmpty
                            ? ListView(
                                controller: scroll,
                                children: [
                                  SizedBox(
                                    height: 280,
                                    child: emptyState(
                                      context: context,
                                      title: 'Пока нет новостей',
                                      subtitle: 'Новости появятся здесь',
                                      icon: Icons.newspaper_outlined,
                                      actionLabel: 'Обновить',
                                      onAction: () => _load(),
                                    ),
                                  ),
                                ],
                              )
                            : NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
                                    _load(append: true);
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                controller: scroll,
                                padding: context.scrollPad(top: 4, bottom: 20),
                                itemCount: items.length + (hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                if (i >= items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: loadingMore
                                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                          : TextButton(onPressed: () => _load(append: true), child: const Text('Ещё новости')),
                                    ),
                                  );
                                }
                                final item = items[i] as Map<String, dynamic>;
                                final date = _fmtDate(
                                  item['published_at']?.toString() ?? item['created_at']?.toString(),
                                );
                                final body = item['body']?.toString() ?? '';
                                final photos = _photoUrls(item);
                                final cover = photos.isNotEmpty ? photos.first : null;
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
                                              child: Stack(
                                                children: [
                                                  Image.network(
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
                                                  if (photos.length > 1)
                                                    Positioned(
                                                      right: 4,
                                                      bottom: 4,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black54,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          '${photos.length}',
                                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                                        ),
                                                      ),
                                                    ),
                                                ],
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
                                                ] else if (newsSourceLabel(item) != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    newsSourceLabel(item)!,
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
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsPhotoGallery extends StatefulWidget {
  const _NewsPhotoGallery({required this.urls, required this.mediaUrl});

  final List<String> urls;
  final String Function(String?) mediaUrl;

  @override
  State<_NewsPhotoGallery> createState() => _NewsPhotoGalleryState();
}

class _NewsPhotoGalleryState extends State<_NewsPhotoGallery> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PageView.builder(
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => index = i),
              itemBuilder: (_, i) {
                return Image.network(
                  widget.mediaUrl(widget.urls[i]),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.urls.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            '${index + 1} / ${widget.urls.length}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
