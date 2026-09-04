import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../responsive.dart';
import '../ride_card.dart';
import '../scroll_to_top.dart';
import '../settlement_picker.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';
import 'create_ride_screen.dart';
import 'home_shell.dart';
import 'ride_detail_screen.dart';

class RidesPane extends StatefulWidget {
  const RidesPane({super.key, required this.settlementId});

  final int? settlementId;

  @override
  State<RidesPane> createState() => _RidesPaneState();
}

class _RidesPaneState extends State<RidesPane> {
  final scroll = ScrollController();
  List<dynamic> items = [];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = false;
  int total = 0;
  String? error;
  String kindFilter = 'all';
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant RidesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settlementId != widget.settlementId) {
      _load();
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  bool get _mine => kindFilter == 'mine';
  bool get _need => kindFilter == 'need';
  bool get _drive => kindFilter == 'drive';

  String get _emptyTitle {
    if (_mine) return 'У вас пока нет попуток';
    if (_need) return 'Пока никто не ищет';
    if (_drive) return 'Пока никто не едет';
    return 'Пока нет попуток';
  }

  String get _emptySubtitle {
    if (_mine) return 'Нажмите плюс внизу справа';
    if (_need) return 'Если нужна попутка — нажмите плюс внизу справа.';
    if (_drive) return 'Если едете — нажмите плюс внизу справа. Соседу может быть по пути.';
    return 'Нажмите плюс внизу справа, если едете или ищете.';
  }

  Future<void> _load({bool append = false}) async {
    if (widget.settlementId == null && !_mine) {
      setState(() {
        items = [];
        loading = false;
        error = null;
        hasMore = false;
      });
      return;
    }
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
      if (_mine) {
        final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы видеть свои попутки');
        if (!ok || !mounted) {
          setState(() {
            loading = false;
            loadingMore = false;
            kindFilter = 'all';
          });
          return;
        }
      }
      final page = await context.read<AppState>().loadRides(
            settlementId: _mine ? null : widget.settlementId,
            kind: kindFilter == 'drive' || kindFilter == 'need' ? kindFilter : null,
            mine: _mine,
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

  Future<void> _openCreate() async {
    final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы поставить попутку');
    if (!ok || !mounted) return;
    final created = await Navigator.push<bool>(
      context,
      fastRoute(
        CreateRideScreen(
          initialKind: 'drive',
          fromSettlementId: widget.settlementId,
        ),
      ),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padH = context.isLandscape ? 12.0 : 16.0;
    const fabClearance = 72.0;

    return Stack(
      children: [
        Column(
          children: [
            ryadomChipRow(
              padding: EdgeInsets.fromLTRB(padH, 0, padH, 4),
              children: [
                for (final entry in const [
                  ('all', 'Все'),
                  ('drive', 'Едут'),
                  ('need', 'Ищут'),
                  ('mine', 'Мои'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RyadomFilterChip(
                      label: entry.$2,
                      selected: kindFilter == entry.$1,
                      onSelected: (_) {
                        setState(() => kindFilter = entry.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
            if (total > 0)
              Padding(
                padding: EdgeInsets.fromLTRB(padH, 0, padH, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$total ${_mine ? 'ваших' : 'попуток'}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            Expanded(
              child: widget.settlementId == null && !_mine
                  ? emptyState(
                      context: context,
                      title: kPlacePickPlease,
                      subtitle: 'Попутки — для выбранного посёлка, села или города',
                      icon: Icons.directions_car_outlined,
                    )
                  : stackWithScrollToTop(
                      controller: scroll,
                      heroTag: 'scroll-top-rides',
                      bottom: fabClearance,
                      child: RefreshIndicator(
                        onRefresh: () => _load(),
                        child: loading && items.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : error != null && items.isEmpty
                                ? ListView(
                                    controller: scroll,
                                    children: [
                                      adaptiveFillMessage(
                                        context: context,
                                        child: errorState(context: context, message: error!, onRetry: () => _load()),
                                      ),
                                    ],
                                  )
                                : items.isEmpty
                                    ? ListView(
                                        controller: scroll,
                                        children: [
                                          adaptiveFillMessage(
                                            context: context,
                                            child: emptyState(
                                              context: context,
                                              title: _emptyTitle,
                                              subtitle: _emptySubtitle,
                                              icon: Icons.directions_car_outlined,
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
                                          padding: EdgeInsets.fromLTRB(16, 4, 16, context.listBottomPad + fabClearance),
                                          itemCount: items.length + (hasMore ? 1 : 0),
                                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                                          itemBuilder: (_, i) {
                                            if (i >= items.length) {
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                child: Center(
                                                  child: loadingMore
                                                      ? const SizedBox(
                                                          width: 22,
                                                          height: 22,
                                                          child: CircularProgressIndicator(strokeWidth: 2),
                                                        )
                                                      : TextButton(
                                                          onPressed: () => _load(append: true),
                                                          child: const Text('Ещё попутки'),
                                                        ),
                                                ),
                                              );
                                            }
                                            final item = Map<String, dynamic>.from(items[i] as Map);
                                            return RideCard(
                                              item: item,
                                              onTap: () async {
                                                await Navigator.push(
                                                  context,
                                                  fastRoute(RideDetailScreen(rideId: item['id'] as int, preview: item)),
                                                );
                                                if (mounted) _load();
                                              },
                                            );
                                          },
                                        ),
                                      ),
                      ),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'rides-add',
            tooltip: 'Добавить попутку',
            onPressed: _openCreate,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
