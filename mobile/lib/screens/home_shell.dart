import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import 'create_listing_screen.dart';
import 'directory_detail_screen.dart';
import 'listing_detail_screen.dart';
import 'my_listings_screen.dart';

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
              onPressed: () => Navigator.push(context, fastRoute(const CreateListingScreen())),
            ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Лента'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Справочник'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Профиль'),
        ],
      ),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, fastRoute(const CreateListingScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Подать'),
            )
          : null,
    );
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
              Text('${items.length} объявл.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final item = items[i] as Map<String, dynamic>;
                          return _ListingCard(item: item);
                        },
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
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) {
                  final images = (item['images'] as List?) ?? [];
                  final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
                  final state = context.read<AppState>();
                  return ClipRRect(
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
                  );
                },
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
                            categoryLabels[item['category']] ?? '${item['category']}',
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
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
                                    Text(
                                      categoryLabels[item['category']] ?? '${item['category']}',
                                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
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
    if (user == null) return const SizedBox.shrink();
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
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
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Мои объявления'),
          subtitle: const Text('Статус, снять с публикации'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const MyListingsScreen())),
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
            if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
          },
          child: const Text('Выйти'),
        ),
      ],
    );
  }
}
