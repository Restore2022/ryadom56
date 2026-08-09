import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../event_actions.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';
import '../update_service.dart';
import 'about_screen.dart';
import 'create_listing_screen.dart';
import 'directory_detail_screen.dart';
import 'district_hub_screen.dart';
import 'directory_favorites_screen.dart';
import 'edit_profile_screen.dart';
import 'event_detail_screen.dart';
import 'favorites_screen.dart';
import 'legal_doc_screen.dart';
import 'listing_detail_screen.dart';
import 'my_listings_screen.dart';
import 'my_reports_screen.dart';
import 'news_list_screen.dart';
import 'notifications_screen.dart';
import 'transport_detail_screen.dart';
import 'view_history_screen.dart';

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

const badgeLabels = {
  'verified': 'Проверенный',
  'trusted': 'Надёжный',
  'caution': 'Осторожно',
  'new': 'Новичок',
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
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13, color: fg, height: 1.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

/// Горизонтальный ряд чипов без обрезки по высоте (раньше SizedBox(height: 40) резал ленту).
Widget ryadomChipRow({
  required EdgeInsetsGeometry padding,
  required List<Widget> children,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: children),
    ),
  );
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      _lastUnread = state.unreadNotifications;
      _pollNotifications();
      final msg = state.sessionMessage;
      if (msg != null && mounted) {
        state.clearSessionMessage();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      if (mounted) await checkAndShowEventReminders(context);
      if (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) await checkForAppUpdate(context);
      }
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
    final titles = ['Объявления', 'Афиша', 'Транспорт', 'Справочник', 'Профиль'];
    final pages = [
      const _ListingsTab(),
      const _EventsTab(),
      const _TransportTab(),
      const _DirectoryTab(),
      _ProfileTab(user: state.user),
    ];
    final useRail = context.useNavigationRail;
    final landscape = context.isLandscape;

    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Лента'),
      const NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Афиша'),
      const NavigationDestination(
        icon: Icon(Icons.directions_bus_outlined),
        selectedIcon: Icon(Icons.directions_bus),
        label: 'Транспорт',
      ),
      const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Места'),
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
    ];

    final railDestinations = [
      const NavigationRailDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: Text('Лента')),
      const NavigationRailDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: Text('Афиша')),
      const NavigationRailDestination(
        icon: Icon(Icons.directions_bus_outlined),
        selectedIcon: Icon(Icons.directions_bus),
        label: Text('Транспорт'),
      ),
      const NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: Text('Места')),
      NavigationRailDestination(
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
        label: const Text('Профиль'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[index]),
        toolbarHeight: landscape && !context.isTablet ? 48 : kToolbarHeight,
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
      body: Row(
        children: [
          if (useRail)
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              labelType: NavigationRailLabelType.all,
              destinations: railDestinations,
            ),
          if (useRail) const VerticalDivider(width: 1),
          Expanded(child: context.constrainContent(pages[index])),
        ],
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              height: landscape ? 64 : null,
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: destinations,
            ),
      floatingActionButton: index == 0
          ? (landscape
              ? FloatingActionButton(
                  onPressed: () => _openCreate(context),
                  tooltip: 'Подать',
                  child: const Icon(Icons.add),
                )
              : FloatingActionButton.extended(
                  onPressed: () => _openCreate(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Подать'),
                ))
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
  List<Map<String, dynamic>> activeAlerts = [];
  final Set<int> dismissedAlertIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final q = context.read<AppState>().filterQuery;
      if (q.isNotEmpty) search.text = q;
      _loadAlert();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _loadAlert() async {
    try {
      final alerts = await context.read<AppState>().loadActiveAlerts(limit: 5);
      if (mounted) setState(() => activeAlerts = alerts);
    } catch (_) {
      if (mounted) setState(() => activeAlerts = []);
    }
  }

  Color _alertBg(BuildContext context, String? kind) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (kind) {
      case 'danger':
        return scheme.errorContainer;
      case 'warn':
        return isDark ? const Color(0xFF4A3B14) : const Color(0xFFFFF3CD);
      default:
        return scheme.primaryContainer;
    }
  }

  Color _alertFg(BuildContext context, String? kind) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (kind) {
      case 'danger':
        return scheme.onErrorContainer;
      case 'warn':
        return isDark ? const Color(0xFFFFE08A) : const Color(0xFF6B4E00);
      default:
        return scheme.onPrimaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.listings;
    final scheme = Theme.of(context).colorScheme;
    final padH = context.isLandscape ? 12.0 : 16.0;
    final bottomPad = context.listBottomPad;
    final visibleAlerts =
        activeAlerts.where((a) => !dismissedAlertIds.contains(a['id'] as int?)).toList();
    // В альбоме не забиваем экран пачкой баннеров
    final alertsToShow = context.isLandscape ? visibleAlerts.take(1).toList() : visibleAlerts;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([state.loadListings(), _loadAlert()]);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
            state.loadMoreListings();
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (state.hasConnectionIssue)
              SliverToBoxAdapter(
                child: Material(
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padH, 8, padH, 8),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off, color: scheme.onErrorContainer, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppState.offlineMessage,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => state.refreshPublic(),
                          child: const Text('Ещё раз'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ...alertsToShow.map(
              (alert) => SliverToBoxAdapter(
                child: Material(
                  color: _alertBg(context, alert['kind']?.toString()),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padH, context.isLandscape ? 6 : 10, 8, context.isLandscape ? 6 : 10),
                    child: Row(
                      children: [
                        Icon(
                          alert['kind'] == 'danger'
                              ? Icons.warning_amber_rounded
                              : alert['kind'] == 'warn'
                                  ? Icons.info_outline
                                  : Icons.campaign_outlined,
                          color: _alertFg(context, alert['kind']?.toString()),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${alert['message']}',
                            maxLines: context.isLandscape ? 2 : 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _alertFg(context, alert['kind']?.toString()),
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final id = alert['id'];
                            if (id is int) setState(() => dismissedAlertIds.add(id));
                          },
                          icon: Icon(Icons.close, color: _alertFg(context, alert['kind']?.toString())),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padH, 8, padH, 6),
                child: TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) => state.applyListingFilters(query: v),
                  decoration: InputDecoration(
                    isDense: context.isLandscape,
                    hintText: 'Поиск по объявлениям',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.tune),
                      onPressed: () => _openFilters(context, state),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: ryadomChipRow(
                padding: EdgeInsets.symmetric(horizontal: padH),
                children: [
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
                        onSelected: (_) => state.applyListingFilters(
                          category: state.filterCategory == c ? '' : c,
                          clearCategory: state.filterCategory == c,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padH, 8, padH, 4),
                child: Row(
                  children: [
                    Text(
                      state.listingsTotal > 0
                          ? '${state.listingsTotal} объявл.'
                          : '${items.length} объявл.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
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
            ),
            if (state.listingsLoading && items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (state.listingsOffline && items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: adaptiveFillMessage(
                  context: context,
                  child: errorState(
                    context: context,
                    message: state.error ?? AppState.offlineMessage,
                    onRetry: () => state.loadListings(),
                  ),
                ),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: adaptiveFillMessage(
                  context: context,
                  child: emptyState(
                    context: context,
                    title: 'Пока нет объявлений',
                    subtitle: 'Измените фильтры или подайте своё объявление',
                    icon: Icons.storefront_outlined,
                    actionLabel: 'Обновить',
                    onAction: () => state.loadListings(),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padH, 4, padH, bottomPad),
                sliver: SliverList.separated(
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
          ],
        ),
      ),
    );
  }

  Future<void> _openFilters(BuildContext context, AppState state) async {
    String? category = state.filterCategory;
    int? settlementId = state.filterSettlementId;
    String sort = state.sort;
    bool hasPhotos = state.filterHasPhotos;
    final priceMinCtrl = TextEditingController(
      text: state.filterPriceMin != null ? state.filterPriceMin!.toStringAsFixed(state.filterPriceMin! % 1 == 0 ? 0 : 2) : '',
    );
    final priceMaxCtrl = TextEditingController(
      text: state.filterPriceMax != null ? state.filterPriceMax!.toStringAsFixed(state.filterPriceMax! % 1 == 0 ? 0 : 2) : '',
    );

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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceMinCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Цена от, ₽'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: priceMaxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Цена до, ₽'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Только с фото'),
                    value: hasPhotos,
                    onChanged: (v) => setModal(() => hasPhotos = v),
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
                      double? parsePrice(String raw) {
                        final t = raw.trim().replaceAll(',', '.');
                        if (t.isEmpty) return null;
                        return double.tryParse(t);
                      }

                      Navigator.pop(ctx);
                      await state.setListingFilters(
                        category: category,
                        settlementId: settlementId,
                        sortBy: sort,
                        query: search.text.trim(),
                        hasPhotos: hasPhotos,
                        priceMin: parsePrice(priceMinCtrl.text),
                        priceMax: parsePrice(priceMaxCtrl.text),
                      );
                    },
                    child: const Text('Применить'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      search.clear();
                      priceMinCtrl.clear();
                      priceMaxCtrl.clear();
                      await state.setListingFilters(
                        category: null,
                        settlementId: null,
                        query: '',
                        sortBy: 'newest',
                        hasPhotos: false,
                        priceMin: null,
                        priceMax: null,
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
    priceMinCtrl.dispose();
    priceMaxCtrl.dispose();
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

class _EventsTab extends StatefulWidget {
  const _EventsTab();

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  List<dynamic> items = [];
  bool loading = true;
  String? error;
  /// null = all published ordered by API default upcoming-first mix; true upcoming; false past
  bool? upcomingOnly = true;
  int? settlementId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AppState>().user;
      final sid = user?['settlement_id'] as int?;
      if (sid != null) settlementId = sid;
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppState>().loadEvents(
            upcoming: upcomingOnly,
            settlementId: settlementId,
          );
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

  String _fmtWhen(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'
        ' · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settlements = context.watch<AppState>().settlements;
    final padH = context.isLandscape ? 12.0 : 16.0;
    return Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, context.isLandscape ? 6 : 12, padH, 8),
                  child: DropdownButtonFormField<int?>(
                    value: settlementId != null && settlements.any((s) => s['id'] == settlementId)
                        ? settlementId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: context.isLandscape,
                      labelText: 'Населённый пункт',
                      prefixIcon: const Icon(Icons.place_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Весь район')),
                      ...settlements.map(
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
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, 0, padH, 8),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'upcoming', label: Text('Скоро')),
                      ButtonSegment(value: 'past', label: Text('Было')),
                      ButtonSegment(value: 'all', label: Text('Все')),
                    ],
                    selected: {
                      if (upcomingOnly == true) 'upcoming' else if (upcomingOnly == false) 'past' else 'all',
                    },
                    onSelectionChanged: (s) {
                      final v = s.first;
                      setState(() {
                        upcomingOnly = v == 'upcoming'
                            ? true
                            : v == 'past'
                                ? false
                                : null;
                      });
                      _load();
                    },
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
                          adaptiveFillMessage(
                            context: context,
                            child: errorState(context: context, message: error!, onRetry: _load),
                          ),
                        ],
                      )
                    : items.isEmpty
                        ? ListView(
                            children: [
                              adaptiveFillMessage(
                                context: context,
                                child: emptyState(
                                  context: context,
                                  title: upcomingOnly == false ? 'Прошедших событий нет' : 'Пока нет событий',
                                  subtitle: 'Афиша района появится здесь',
                                  icon: Icons.event_outlined,
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
                              return Material(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => Navigator.push(
                                    context,
                                    fastRoute(EventDetailScreen(item: item)),
                                  ),
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
                                          _fmtWhen(item['starts_at']?.toString()),
                                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${item['title']}',
                                          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${item['place_text']}${item['settlement_name'] != null ? ' · ${item['settlement_name']}' : ''}',
                                          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
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
}

class _TransportTab extends StatefulWidget {
  const _TransportTab();

  @override
  State<_TransportTab> createState() => _TransportTabState();
}

class _TransportTabState extends State<_TransportTab> {
  final search = TextEditingController();
  List<dynamic> items = [];
  bool loading = false;
  String? error;
  int? settlementId;
  String dayFilter = 'today';
  bool favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      final user = state.user;
      final sid = user?['settlement_id'] as int? ?? state.preferredSettlementId;
      if (sid != null) {
        setState(() => settlementId = sid);
        _load();
      }
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (settlementId == null) {
      setState(() {
        items = [];
        loading = false;
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppState>().loadTransport(
            settlementId: settlementId,
            q: search.text.trim().isEmpty ? null : search.text,
            day: dayFilter,
            favoritesOnly: favoritesOnly,
          );
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

  Future<void> _toggleFavoritesFilter() async {
    if (!favoritesOnly) {
      final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы видеть избранные маршруты');
      if (!ok || !mounted) return;
    }
    setState(() => favoritesOnly = !favoritesOnly);
    await _load();
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id is! int) return;
    final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы сохранить маршрут в избранное');
    if (!ok || !mounted) return;
    final state = context.read<AppState>();
    final was = state.isTransportFavorited(id, item: item);
    try {
      final updated = await state.toggleTransportFavorite(id, currentlyFavorited: was);
      if (!mounted) return;
      setState(() {
        final idx = items.indexWhere((e) => e is Map && e['id'] == id);
        if (idx >= 0) items[idx] = updated;
        if (favoritesOnly && updated['is_favorited'] != true) {
          items.removeWhere((e) => e is Map && e['id'] == id);
        }
      });
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final settlements = state.settlements;
    final padH = context.isLandscape ? 12.0 : 16.0;

    return Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.lastTransportFromCache)
                  Material(
                    color: scheme.secondaryContainer,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padH, 8, padH, 8),
                      child: Row(
                        children: [
                          Icon(Icons.offline_bolt, size: 18, color: scheme.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Показано сохранённое расписание — нет связи с сервером',
                              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, context.isLandscape ? 6 : 12, padH, 8),
                  child: DropdownButtonFormField<int>(
                    value: settlementId != null && settlements.any((s) => s['id'] == settlementId)
                        ? settlementId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: context.isLandscape,
                      labelText: 'Населённый пункт',
                      hintText: 'Выберите населённый пункт',
                      prefixIcon: const Icon(Icons.place_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    items: settlements
                        .map(
                          (s) => DropdownMenuItem<int>(
                            value: s['id'] as int,
                            child: Text(s['display_name'] as String, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => settlementId = v);
                      _load();
                    },
                  ),
                ),
                if (settlementId != null) ...[
                  ryadomChipRow(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, 8),
                    children: [
                      for (final entry in const [
                        ('today', 'Сегодня'),
                        ('weekdays', 'Будни'),
                        ('weekends', 'Выходные'),
                        ('all', 'Все'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: RyadomFilterChip(
                            label: entry.$2,
                            selected: dayFilter == entry.$1,
                            onSelected: (_) {
                              setState(() => dayFilter = entry.$1);
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, 8),
                    child: TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        isDense: context.isLandscape,
                        hintText: 'направление, остановка…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  search.clear();
                                  _load();
                                },
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, 6),
                    child: Row(
                      children: [
                        Text(
                          '${items.length} маршрутов',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        RyadomFilterChip(
                          label: 'Избранное',
                          selected: favoritesOnly,
                          onSelected: (_) => _toggleFavoritesFilter(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: settlementId == null
              ? emptyState(
                  context: context,
                  title: 'Выберите населённый пункт',
                  subtitle: 'Маршруты показываются только для выбранного села или города',
                  icon: Icons.directions_bus_outlined,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: loading && items.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : error != null && items.isEmpty
                          ? ListView(
                              children: [
                                adaptiveFillMessage(
                                  context: context,
                                  child: errorState(context: context, message: error!, onRetry: _load),
                                ),
                              ],
                            )
                          : items.isEmpty
                              ? ListView(
                                  children: [
                                    adaptiveFillMessage(
                                      context: context,
                                      child: emptyState(
                                        context: context,
                                        title: favoritesOnly ? 'Нет избранных маршрутов' : 'Маршрутов нет',
                                        subtitle: favoritesOnly
                                            ? 'Добавьте маршруты звёздочкой в списке'
                                            : 'Для этого населённого пункта расписаний пока нет',
                                        icon: Icons.directions_bus_outlined,
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
                                    final item = Map<String, dynamic>.from(items[i] as Map);
                                    final number = item['route_number']?.toString();
                                    final id = item['id'];
                                    final favorited =
                                        id is int && state.isTransportFavorited(id, item: item);
                                    return Material(
                                      color: Theme.of(context).cardTheme.color,
                                      borderRadius: BorderRadius.circular(18),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () async {
                                          await Navigator.push(
                                            context,
                                            fastRoute(TransportDetailScreen(item: item)),
                                          );
                                          if (mounted) _load();
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
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (number != null && number.isNotEmpty)
                                                      Text(
                                                        number,
                                                        style: TextStyle(
                                                          color: scheme.primary,
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    Text(
                                                      '${item['title']}',
                                                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17),
                                                    ),
                                                    if (item['description'] != null) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        '${item['description']}',
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: favorited ? 'Убрать из избранного' : 'В избранное',
                                                visualDensity: VisualDensity.compact,
                                                onPressed: () => _toggleFavorite(item),
                                                icon: Icon(
                                                  favorited ? Icons.star : Icons.star_border,
                                                  color: favorited ? scheme.primary : scheme.onSurfaceVariant,
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

  Future<void> _openMaps(String? mapsUrl, Map<String, dynamic> item) async {
    if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
      var url = mapsUrl.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final lat = item['lat'];
    final lon = item['lon'];
    final address = item['address']?.toString();
    Uri uri;
    if (lat is num && lon is num) {
      uri = Uri.parse('geo:$lat,$lon?q=$lat,$lon(${Uri.encodeComponent(item['title'] as String)})');
    } else if (address != null && address.isNotEmpty) {
      uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
    } else {
      return;
    }
    if (!await launchUrl(uri)) {
      final q = address ?? '${item['title']}';
      await launchUrl(
        Uri.parse('https://yandex.ru/maps/?text=${Uri.encodeComponent(q)}'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.directory;
    final scheme = Theme.of(context).colorScheme;
    final padH = context.isLandscape ? 12.0 : 16.0;

    return Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, context.isLandscape ? 6 : 12, padH, 8),
                  child: TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      state.setDirectoryFilters(
                        category: state.directoryCategory,
                        settlementId: state.directorySettlementId,
                        query: v,
                      );
                    },
                    decoration: InputDecoration(
                      isDense: context.isLandscape,
                      hintText: 'Школа, больница, магазин…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.tune),
                        onPressed: () => _openFilters(context, state),
                      ),
                    ),
                  ),
                ),
                ryadomChipRow(
                  padding: EdgeInsets.symmetric(horizontal: padH),
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
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, 8, padH, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${items.length} записей',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => state.loadDirectory(),
            child: state.directoryLoading && items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.directoryOffline && items.isEmpty
                    ? ListView(
                        children: [
                          adaptiveFillMessage(
                            context: context,
                            child: errorState(
                              context: context,
                              message: state.error ?? AppState.offlineMessage,
                              onRetry: () => state.loadDirectory(),
                            ),
                          ),
                        ],
                      )
                    : items.isEmpty
                        ? ListView(
                            children: [
                              adaptiveFillMessage(
                                context: context,
                                child: emptyState(
                                  context: context,
                                  title: 'Справочник пуст',
                                  subtitle: 'Попробуйте другой населённый пункт или категорию',
                                  icon: Icons.map_outlined,
                                  actionLabel: 'Обновить',
                                  onAction: () => state.loadDirectory(),
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
                              final phone = item['phone']?.toString();
                              final dirFav = item['is_favorited'] == true;
                              final openNow = item['is_open_now'] == true;
                              final closedNow = item['is_open_now'] == false;
                              final mapsUrl = item['maps_url']?.toString();
                              final hasMap = (mapsUrl != null && mapsUrl.isNotEmpty) ||
                                  (item['lat'] is num && item['lon'] is num) ||
                                  (item['address'] != null && '${item['address']}'.isNotEmpty);
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
                                                style: TextStyle(
                                                  color: scheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            if (openNow)
                                              Container(
                                                margin: const EdgeInsets.only(right: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: scheme.primaryContainer,
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  'Открыто',
                                                  style: TextStyle(
                                                    color: scheme.onPrimaryContainer,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              )
                                            else if (closedNow)
                                              Container(
                                                margin: const EdgeInsets.only(right: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: scheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  'Закрыто',
                                                  style: TextStyle(
                                                    color: scheme.onSurfaceVariant,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            IconButton(
                                              visualDensity: VisualDensity.compact,
                                              tooltip: dirFav ? 'Убрать из избранного' : 'В избранное',
                                              onPressed: () async {
                                                final ok = await ensureLoggedIn(
                                                  context,
                                                  message: 'Войдите, чтобы сохранить организацию',
                                                );
                                                if (!ok || !context.mounted) return;
                                                try {
                                                  await state.toggleDirectoryFavorite(
                                                    item['id'] as int,
                                                    currentlyFavorited: dirFav,
                                                  );
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
                                          style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25),
                                          softWrap: true,
                                        ),
                                        if (item['address'] != null) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Icon(Icons.place_outlined, size: 16, color: scheme.onSurfaceVariant),
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  '${item['address']}',
                                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.3),
                                                  softWrap: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (item['settlement_name'] != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            '${item['settlement_name']}',
                                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                                            softWrap: true,
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            if (phone != null && phone.isNotEmpty)
                                              IconButton.filledTonal(
                                                tooltip: 'Позвонить',
                                                onPressed: () => _call(phone),
                                                icon: const Icon(Icons.phone, size: 20),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            if (hasMap) ...[
                                              if (phone != null && phone.isNotEmpty) const SizedBox(width: 4),
                                              IconButton.outlined(
                                                tooltip: 'Карта',
                                                onPressed: () => _openMaps(mapsUrl, item),
                                                icon: const Icon(Icons.map_outlined, size: 20),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ],
                                            const Spacer(),
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
    final pad = context.isLandscape ? 12.0 : 16.0;
    if (user == null) {
      return ListView(
        padding: EdgeInsets.all(pad),
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
            leading: const Icon(Icons.location_city_outlined),
            title: const Text('Район'),
            subtitle: const Text('Срочное, новости и события'),
            trailing: const Icon(Icons.chevron_right),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => Navigator.push(context, fastRoute(const DistrictHubScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.newspaper_outlined),
            title: const Text('Новости района'),
            trailing: const Icon(Icons.chevron_right),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => Navigator.push(
              context,
              fastRoute(NewsListScreen(settlementId: state.filterSettlementId)),
            ),
          ),
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
      padding: EdgeInsets.all(pad),
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
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Жалобы на мои объявления'),
          subtitle: const Text('Статус и ответ модератора'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const MyReportsScreen())),
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
          leading: const Icon(Icons.location_city_outlined),
          title: const Text('Район'),
          subtitle: const Text('Срочное, новости и события'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(context, fastRoute(const DistrictHubScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.newspaper_outlined),
          title: const Text('Новости района'),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.push(
            context,
            fastRoute(NewsListScreen(settlementId: state.filterSettlementId)),
          ),
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
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Выйти из аккаунта?'),
                content: const Text('Вы сможете войти снова в любой момент.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
                ],
              ),
            );
            if (ok == true) await state.logout();
          },
          child: const Text('Выйти'),
        ),
      ],
    );
  }
}
