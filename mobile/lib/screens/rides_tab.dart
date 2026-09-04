import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../responsive.dart';
import '../ride_card.dart';
import '../scroll_to_top.dart';
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

  Future<void> _openCreate(String kind) async {
    final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы поставить попутку');
    if (!ok || !mounted) return;
    final created = await Navigator.push<bool>(
      context,
      fastRoute(
        CreateRideScreen(
          initialKind: kind,
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

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padH, 0, padH, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openCreate('drive'),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: const Text('Еду'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _openCreate('need'),
                  icon: const Icon(Icons.hail_outlined),
                  label: const Text('Ищу'),
                ),
              ),
            ],
          ),
        ),
        ryadomChipRow(
          padding: EdgeInsets.fromLTRB(padH, 0, padH, 8),
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
                  title: 'Выберите село',
                  subtitle: 'Попутки показываются для выбранного села или города',
                  icon: Icons.directions_car_outlined,
                )
              : stackWithScrollToTop(
                  controller: scroll,
                  heroTag: 'scroll-top-rides',
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
                                          title: _mine ? 'У вас пока нет попуток' : 'Пока никто не едет',
                                          subtitle: _mine
                                              ? 'Нажмите «Еду» или «Ищу» сверху'
                                              : 'Если едете в город — напишите. Соседу может быть по пути.',
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
                                      padding: EdgeInsets.fromLTRB(16, 4, 16, context.listBottomPad),
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
    );
  }
}
