import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../state/app_state.dart';
import 'about_screen.dart';
import 'create_listing_screen.dart';
import 'directory_detail_screen.dart';
import 'edit_profile_screen.dart';
import 'favorites_screen.dart';
import 'legal_doc_screen.dart';
import 'listing_detail_screen.dart';
import 'my_listings_screen.dart';
import 'notifications_screen.dart';
import 'view_history_screen.dart';
import 'directory_favorites_screen.dart';

Route<T> fastRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
  );
}

const categoryLabels = {
  'goods': 'Товары',
  'services': 'Услуги',
  'jobs': 'Работа',
  'rent': 'Аренда',
  'free': 'Отдам',
  'lost_found': 'Потеряшки',
  'school': 'Школа',
  'hospital': 'Больница',
  'shop': 'Магазин',
  'pharmacy': 'Аптека',
  'admin': 'Администрация',
  'bank': 'Банк',
  'post': 'Почта',
  'transport': 'Транспорт',
  'culture': 'Культура',
  'sport': 'Спорт',
  'other': 'Другое',
};

const sortLabels = {
  'newest': 'Сначала новые',
  'oldest': 'Сначала старые',
  'price_asc': 'Цена ↑',
  'price_desc': 'Цена ↓',
};

class RyadomFilterChip extends StatelessWidget {
  const RyadomFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? (isDark ? const Color(0xFF2F6B45) : const Color(0xFF1B6B3A))
        : (isDark ? const Color(0xFF243328) : Colors.white);
    final fg = selected
        ? (isDark ? const Color(0xFFE8FFF0) : Colors.white)
        : (isDark ? const Color(0xFFD7E6D9) : const Color(0xFF1C2B1F));
    final border = selected
        ? Colors.transparent
        : (isDark ? const Color(0xFF3A4F3E) : const Color(0xFFB7C9B8));

    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onSelected,
      selectedColor: bg,
      backgroundColor: bg,
      checkmarkColor: fg,
      side: BorderSide(color: border),
      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13, color: fg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  int _lastUnread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      _lastUnread = state.unreadNotifications;
      _pollNotifications();
    });
  }

  Future<void> _pollNotifications() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 40));
      if (!mounted) return;
      final state = context.read<AppState>();
      if (state.user == null) continue;
      final before = state.unreadNotifications;
      await state.refreshUnreadNotifications();
      final after = state.unreadNotifications;
      if (!mounted) return;
      if (after > before && after > _lastUnread) {
        _lastUnread = after;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Новое уведомление · непрочитанных: $after'),
            action: SnackBarAction(
              label: 'Открыть',
              onPressed: () {
                Navigator.push(context, fastRoute(const NotificationsScreen()));
              },
            ),
          ),
        );
      } else {
        _lastUnread = after;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      const _ListingsTab(),
      const _DirectoryTab(),
      _ProfileTab(user: state.user),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(index == 0 ? 'Объявления' : index == 1 ? 'Справочник' : 'Профиль'),
        actions: [
          IconButton(
            tooltip: state.darkMode ? 'Светлая тема' : 'Тёмная тема',
            onPressed: () => state.setDarkMode(!state.darkMode),
            icon: Icon(state.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
          if (index == 0)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _openCreate(context),
            ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Лента'),
          const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Справочник'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: state.user != null && state.unreadNotifications > 0,
              label: Text('${state.unreadNotifications > 99 ? 99 : state.unreadNotifications}'),
              child: const Icon(Icons.person_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: state.user != null && state.unreadNotifications > 0,
              label: Text('${state.unreadNotifications > 99 ? 99 : state.unreadNotifications}'),
              child: const Icon(Icons.person),
            ),
            label: 'Профиль',
          ),
        ],
      ),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openCreate(context),
              icon: const Icon(Icons.add),
              label: const Text('Подать'),
            )
          : null,
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы подать объявление');
    if (!ok || !context.mounted) return;
    await Navigator.push(context, fastRoute(const CreateListingScreen()));
  }
}

class _ListingsTab extends StatefulWidget {
  const _ListingsTab();

  @override
  State<_ListingsTab> createState() => _ListingsTabState();
}

class _ListingsTabState extends State<_ListingsTab> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.listings;

    return Column(
      children: [
        if (state.hasConnectionIssue)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppState.offlineMessage,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => state.loadListings(),
                    child: const Text('Ещё раз'),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => state.applyListingFilters(query: v),
            decoration: InputDecoration(
              hintText: 'Поиск по объявлениям',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.tune),
                onPressed: () => _openFilters(context, state),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RyadomFilterChip(
                  label: 'Все',
                  selected: state.filterCategory == null,
                  onSelected: (_) => state.applyListingFilters(clearCategory: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RyadomFilterChip(
                  label: 'С фото',
                  selected: state.filterHasPhotos,
                  onSelected: (_) => state.applyListingFilters(hasPhotos: !state.filterHasPhotos),
                ),
              ),
              ...['goods', 'services', 'jobs', 'rent', 'free', 'lost_found'].map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: RyadomFilterChip(
                    label: categoryLabels[c]!,
                    selected: state.filterCategory == c,
                    onSelected: (_) => state.applyListingFilters(category: state.filterCategory == c ? '' : c),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text(
                state.listingsTotal > 0
                    ? '${state.listingsTotal} объявл.'
                    : '${items.length} объявл.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: state.sort,
                  items: sortLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) state.applyListingFilters(sortBy: v);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => state.loadListings(),
            child: state.listingsLoading && items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Ничего не найдено')),
                        ],
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
                            state.loadMoreListings();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          itemCount: items.length + (state.listingsLoadingMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            if (i >= items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final item = items[i] as Map<String, dynamic>;
                            return _ListingCard(item: item);
                          },
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Future<void> _openFilters(BuildContext context, AppState state) async {
    String? category = state.filterCategory;
    int? settlementId = state.filterSettlementId;
    String sort = state.sort;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Фильтры', style: GoogleFonts.unbounded(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Все категории')),
                      ...['goods', 'services', 'jobs', 'rent', 'free', 'lost_found']
                          .map((c) => DropdownMenuItem(value: c, child: Text(categoryLabels[c]!))),
                    ],
                    onChanged: (v) => setModal(() => category = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: settlementId,
                    decoration: const InputDecoration(labelText: 'Населённый пункт'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Весь район')),
                      ...state.settlements.map(
                        (s) => DropdownMenuItem(value: s['id'] as int, child: Text(s['display_name'] as String)),
                      ),
                    ],
                    onChanged: (v) => setModal(() => settlementId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: sort,
                    decoration: const InputDecoration(labelText: 'Сортировка'),
                    items: sortLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setModal(() => sort = v ?? 'newest'),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await state.setListingFilters(
                        category: category,
                        settlementId: settlementId,
                        sortBy: sort,
                        query: search.text.trim(),
                      );
                    },
                    child: const Text('Применить'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      search.clear();
                      await state.setListingFilters(
                        category: null,
                        settlementId: null,
                        query: '',
                        sortBy: 'newest',
                      );
                    },
                    child: const Text('Сбросить'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final id = item['id'] as int;
    final isOwner = state.user != null && item['author_id'] == state.user!['id'];
    final favorited = state.isFavorited(id, item: item);
    final images = (item['images'] as List?) ?? [];
    final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;

    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          state.addViewHistory(item);
          Navigator.push(
            context,
            fastRoute(ListingDetailScreen(listingId: id, preview: item)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item['is_pinned'] == true
                  ? scheme.primary
                  : item['is_urgent'] == true
                      ? scheme.error.withValues(alpha: 0.55)
                      : item['category'] == 'free'
                          ? scheme.tertiary.withValues(alpha: 0.55)
                          : scheme.outlineVariant.withValues(alpha: 0.45),
              width: (item['is_pinned'] == true || item['is_urgent'] == true || item['category'] == 'free')
                  ? 1.6
                  : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumb == null
                    ? Container(
                        width: 76,
                        height: 76,
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                      )
                    : Image.network(
                        state.mediaUrl(thumb),
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 76,
                          height: 76,
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          categoryLabels[item['category']] ?? '${item['category']}',
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        if (item['is_pinned'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Важно', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11)),
                          ),
                        if (item['is_urgent'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Срочно', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w800, fontSize: 11)),
                          ),
                        if (item['category'] == 'free')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.tertiary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Бесплатно', style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w800, fontSize: 11)),
                          ),
                        if (item['price'] != null)
                          Text(
                            '${item['price']} ₽',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['title'] as String,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item['settlement_name'] ?? ''}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!isOwner)
                IconButton(
                  tooltip: favorited ? 'Убрать из избранного' : 'В избранное',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы сохранить в избранное');
                    if (!loggedIn || !context.mounted) return;
                    try {
                      await state.toggleFavorite(id, currentlyFavorited: favorited);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppState.userFriendlyError(e))),
                        );
                      }
                    }
                  },
                  icon: Icon(
                    favorited ? Icons.favorite : Icons.favorite_border,
                    color: favorited ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryTab extends StatefulWidget {
  const _DirectoryTab();

  @override
  State<_DirectoryTab> createState() => _DirectoryTabState();
}

class _DirectoryTabState extends State<_DirectoryTab> {
  final search = TextEditingController();

  static const dirCategories = [
    'school',
    'hospital',
    'shop',
    'pharmacy',
    'admin',
    'bank',
    'post',
    'transport',
    'culture',
    'sport',
    'other',
  ];

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[\s\-()]'), ''));
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.directory;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => state.setDirectoryFilters(
              category: state.directoryCategory,
              settlementId: state.directorySettlementId,
              query: v,
            ),
            decoration: InputDecoration(
              hintText: 'Школа, больница, магазин…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.tune),
                onPressed: () => _openFilters(context, state),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RyadomFilterChip(
                  label: 'Все',
                  selected: state.directoryCategory == null,
                  onSelected: (_) => state.setDirectoryFilters(
                    category: null,
                    settlementId: state.directorySettlementId,
                    query: search.text,
                  ),
                ),
              ),
              ...dirCategories.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: RyadomFilterChip(
                    label: categoryLabels[c] ?? c,
                    selected: state.directoryCategory == c,
                    onSelected: (_) => state.setDirectoryFilters(
                      category: state.directoryCategory == c ? null : c,
                      settlementId: state.directorySettlementId,
                      query: search.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${items.length} записей',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => state.loadDirectory(),
            child: state.directoryLoading && items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Ничего не найдено')),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final item = items[i] as Map<String, dynamic>;
                          final phone = item['phone']?.toString();
                          final dirFav = item['is_favorited'] == true;
                          return Material(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => DirectoryDetailScreen(item: item)),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            categoryLabels[item['category']] ?? '${item['category']}',
                                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          tooltip: dirFav ? 'Убрать из избранного' : 'В избранное',
                                          onPressed: () async {
                                            final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы сохранить организацию');
                                            if (!ok || !context.mounted) return;
                                            try {
                                              await state.toggleDirectoryFavorite(item['id'] as int, currentlyFavorited: dirFav);
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text(AppState.userFriendlyError(e))),
                                                );
                                              }
                                            }
                                          },
                                          icon: Icon(
                                            dirFav ? Icons.bookmark : Icons.bookmark_border,
                                            color: dirFav ? scheme.primary : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      item['title'] as String,
                                      style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800),
                                    ),
                                    if (item['address'] != null) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.place_outlined, size: 16, color: scheme.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              '${item['address']}',
                                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (item['settlement_name'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text('${item['settlement_name']}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                                    ],
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        if (phone != null && phone.isNotEmpty)
                                          FilledButton.tonalIcon(
                                            onPressed: () => _call(phone),
                                            icon: const Icon(Icons.phone, size: 18),
                                            label: const Text('Позвонить'),
                                          ),
                                        const Spacer(),
                                        Text('Подробнее', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                                        Icon(Icons.chevron_right, color: scheme.primary),
                                      ],
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
    );
  }

  Future<void> _openFilters(BuildContext context, AppState state) async {
    String? category = state.directoryCategory;
    int? settlementId = state.directorySettlementId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Фильтры справочника', style: GoogleFonts.unbounded(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Все категории')),
                      ...dirCategories.map((c) => DropdownMenuItem(value: c, child: Text(categoryLabels[c] ?? c))),
                    ],
                    onChanged: (v) => setModal(() => category = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: settlementId,
                    decoration: const InputDecoration(labelText: 'Населённый пункт'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Весь район')),
                      ...state.settlements.map(
                        (s) => DropdownMenuItem(value: s['id'] as int, child: Text(s['display_name'] as String)),
                      ),
                    ],
                    onChanged: (v) => setModal(() => settlementId = v),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await state.setDirectoryFilters(
                        category: category,
                        settlementId: settlementId,
                        query: search.text.trim(),
                      );
                    },
                    child: const Text('Применить'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      search.clear();
                      await state.setDirectoryFilters(category: null, settlementId: null, query: '');
                    },
                    child: const Text('Сбросить'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.user});
  final Map<String, dynamic>? user;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    if (user == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [scheme.primary.withValues(alpha: 0.9), scheme.primary.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Рядом56', style: GoogleFonts.unbounded(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 8),
                Text('Гостевой режим', style: GoogleFonts.unbounded(color: Colors.white, fontSize: 26)),
                const SizedBox(height: 6),
                const Text(
                  'Смотрите ленту и справочник. Чтобы звонить и подавать объявления — войдите.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            child: const Text('Войти'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, '/register'),
            child: const Text('Создать аккаунт'),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('О проекте'),
            trailing: const Icon(Icons.chevron_right),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => Navigator.push(context, fastRoute(const AboutScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Пользовательское соглашение'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, fastRoute(const LegalDocScreen(slug: 'terms', title: 'Пользовательское соглашение'))),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Политика конфиденциальности'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, fastRoute(const LegalDocScreen(slug: 'privacy', title: 'Политика конфиденциальности'))),
          ),
          ListTile(
            leading: const Icon(Icons.rule_outlined),
            title: const Text('Правила объявлений'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              fastRoute(const LegalDocScreen(slug: 'listing_rules', title: 'Правила размещения объявлений')),
            ),
          ),
          SwitchListTile(
            value: state.darkMode,
            onChanged: state.setDarkMode,
            title: const Text('Тёмная тема'),
            secondary: Icon(state.darkMode ? Icons.dark_mode : Icons.light_mode),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [scheme.primary.withValues(alpha: 0.9), scheme.primary.withValues(alpha: 0.55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Рядом56', style: GoogleFonts.unbounded(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 8),
              Text(user!['full_name'] as String, style: GoogleFonts.unbounded(color: Colors.white, fontSize: 26)),
              const SizedBox(height: 6),
              Text(user!['email'] as String, style: const TextStyle(color: Colors.white70)),
              if (user!['phone'] != null) Text(user!['phone'] as String, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: Badge(
            isLabelVisible: state.unreadNotifications > 0,
            label: Text('${state.unreadNotifications}'),
            child: const Icon(Icons.notifications_outlined),
          ),
          title: const Text('Уведомления'),
          subtitle: const Text('Одобрения, отклонения, жалобы'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const NotificationsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Мои объявления'),
          subtitle: const Text('Статус, изменить, снять'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const MyListingsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_outline),
          title: const Text('Избранное'),
          subtitle: const Text('Сохранённые объявления'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const FavoritesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.bookmark_outline),
          title: const Text('Избранные организации'),
          subtitle: const Text('Справочник'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const DirectoryFavoritesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('История просмотров'),
          subtitle: const Text('Недавно открытые объявления'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const ViewHistoryScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Редактировать профиль'),
          subtitle: const Text('Имя, телефон, пароль'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const EditProfileScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('О проекте'),
          subtitle: const Text('Рядом56, поддержка и документы'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const AboutScreen())),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: state.darkMode,
          onChanged: state.setDarkMode,
          title: const Text('Тёмная тема'),
          subtitle: const Text('Удобно вечером и ночью'),
          secondary: Icon(state.darkMode ? Icons.dark_mode : Icons.light_mode),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await state.logout();
          },
          child: const Text('Выйти'),
        ),
      ],
    );
  }
}
