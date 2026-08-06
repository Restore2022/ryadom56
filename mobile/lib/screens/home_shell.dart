import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';

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
      _DirectoryTab(items: state.directory),
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
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen())),
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
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen())),
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
                child: FilterChip(
                  label: const Text('Все'),
                  selected: state.filterCategory == null,
                  onSelected: (_) => state.applyListingFilters(clearCategory: true),
                ),
              ),
              ...['goods', 'services', 'jobs', 'rent', 'free', 'lost_found'].map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(categoryLabels[c]!),
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
            MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listingId: item['id'] as int, preview: item),
            ),
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
                style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25),
              ),
              const SizedBox(height: 8),
              Text(
                item['description'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${item['settlement_name'] ?? ''}',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Text('Открыть', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryTab extends StatelessWidget {
  const _DirectoryTab({required this.items});
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Справочник пока пуст'));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().loadDirectory(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final item = items[i] as Map<String, dynamic>;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${categoryLabels[item['category']] ?? item['category']}'
                '${item['settlement_name'] != null ? ' · ${item['settlement_name']}' : ''}'
                '${item['address'] != null ? '\n${item['address']}' : ''}'
                '${item['phone'] != null ? '\n${item['phone']}' : ''}',
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
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
