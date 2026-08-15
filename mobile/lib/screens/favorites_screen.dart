import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<dynamic> items = [];
  bool loading = true;
  String? error;
  int? _loadedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (state.user == null) {
      setState(() {
        items = [];
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
      final data = await context.read<AppState>().loadFavorites();
      if (mounted) {
        setState(() {
          items = data;
          loading = false;
          _loadedUserId = context.read<AppState>().user?['id'] as int?;
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    final uid = state.user?['id'] as int?;
    if (uid != null && uid != _loadedUserId && !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: state.user == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const GuestCtaBanner(
                  title: 'Избранное — после входа',
                  subtitle:
                      'Ленту смотреть можно. Чтобы сохранить объявление и вернуться к нему позже — нужен аккаунт.',
                ),
                const SizedBox(height: 16),
                emptyState(
                  context: context,
                  title: 'Пока ничего не сохранено',
                  subtitle: 'Войдите и нажмите ♡ на карточке',
                  icon: Icons.favorite_border,
                ),
              ],
            )
          : loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : items.isEmpty
                  ? emptyState(
                      context: context,
                      title: 'Избранное пусто',
                      subtitle: 'Нажмите ♡ на объявлении, чтобы сохранить его здесь',
                      icon: Icons.favorite_border,
                    )
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
                          final id = item['id'] as int;
                          return Material(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  fastRoute(ListingDetailScreen(listingId: id, preview: item)),
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
                                            categoryLabels[item['category']] ?? '${item['category']}',
                                            style: TextStyle(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item['title'] as String,
                                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                                          ),
                                          if (item['settlement_name'] != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '${item['settlement_name']}',
                                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Убрать из избранного',
                                      onPressed: () async {
                                        try {
                                          await state.toggleFavorite(id, currentlyFavorited: true);
                                          await _load();
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(AppState.userFriendlyError(e))),
                                            );
                                          }
                                        }
                                      },
                                      icon: Icon(Icons.favorite, color: scheme.error),
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
