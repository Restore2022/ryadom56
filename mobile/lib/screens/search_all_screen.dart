import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../listing_row.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';
import '../ride_card.dart';
import 'directory_detail_screen.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';
import 'news_list_screen.dart';
import 'ride_detail_screen.dart';

class SearchAllScreen extends StatefulWidget {
  const SearchAllScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchAllScreen> createState() => _SearchAllScreenState();
}

class _SearchAllScreenState extends State<SearchAllScreen> {
  late final TextEditingController search;
  Timer? _debounce;
  bool loading = false;
  String? error;
  String lastQuery = '';
  List<dynamic> listings = [];
  List<dynamic> places = [];
  List<dynamic> news = [];
  List<dynamic> rides = [];

  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(widget.initialQuery));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (value.trim().length >= 2) _run(value);
    });
  }

  Future<void> _run(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        listings = [];
        places = [];
        news = [];
        rides = [];
        error = null;
        lastQuery = '';
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
      lastQuery = q;
    });
    try {
      final state = context.read<AppState>();
      final data = await state.searchAll(
        q,
        settlementId: state.filterSettlementId ?? state.preferredSettlementId,
      );
      if (!mounted) return;
      setState(() {
        listings = (data['listings'] as List?) ?? [];
        places = (data['places'] as List?) ?? [];
        news = (data['news'] as List?) ?? [];
        rides = (data['rides'] as List?) ?? [];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = AppState.userFriendlyError(e);
        loading = false;
      });
    }
  }

  bool get _empty => listings.isEmpty && places.isEmpty && news.isEmpty && rides.isEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: search,
              autofocus: widget.initialQuery.isEmpty,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                setState(() {});
                _onChanged(v);
              },
              onSubmitted: _run,
              decoration: InputDecoration(
                hintText: 'велосипед, попутка, аптека',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          search.clear();
                          _run('');
                          setState(() {});
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: loading && _empty
                ? const Center(child: CircularProgressIndicator())
                : error != null && _empty
                    ? errorState(context: context, message: error!, onRetry: () => _run(search.text))
                    : lastQuery.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                'Одно поле: объявления, попутки, места и новости. Напишите, что ищете.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                              ),
                            ),
                          )
                        : _empty
                            ? emptyState(
                                context: context,
                                title: 'Ничего не нашлось',
                                subtitle: 'Попробуйте другое слово — «аптека», «работа», «велосипед»',
                                icon: Icons.search_off,
                              )
                            : ListView(
                                padding: context.scrollPad(top: 4, bottom: 20),
                                children: [
                                  if (listings.isNotEmpty) ...[
                                    _sectionTitle('Объявления', listings.length),
                                    const SizedBox(height: 8),
                                    for (final raw in listings)
                                      if (raw is Map)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: ListingRow(
                                            item: Map<String, dynamic>.from(raw),
                                            onTap: () {
                                              final id = raw['id'] as int?;
                                              if (id == null) return;
                                              Navigator.push(
                                                context,
                                                fastRoute(ListingDetailScreen(listingId: id, preview: Map<String, dynamic>.from(raw))),
                                              );
                                            },
                                          ),
                                        ),
                                  ],
                                  if (rides.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _sectionTitle('Попутки', rides.length),
                                    const SizedBox(height: 8),
                                    for (final raw in rides)
                                      if (raw is Map)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: RideCard(
                                            item: Map<String, dynamic>.from(raw),
                                            onTap: () {
                                              final id = raw['id'] as int?;
                                              if (id == null) return;
                                              Navigator.push(
                                                context,
                                                fastRoute(RideDetailScreen(rideId: id, preview: Map<String, dynamic>.from(raw))),
                                              );
                                            },
                                          ),
                                        ),
                                  ],
                                  if (places.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _sectionTitle('Места', places.length),
                                    const SizedBox(height: 8),
                                    for (final raw in places)
                                      if (raw is Map)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: _PlaceHit(
                                            item: Map<String, dynamic>.from(raw),
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                fastRoute(DirectoryDetailScreen(item: Map<String, dynamic>.from(raw))),
                                              );
                                            },
                                          ),
                                        ),
                                  ],
                                  if (news.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _sectionTitle('Новости', news.length),
                                    const SizedBox(height: 8),
                                    for (final raw in news)
                                      if (raw is Map)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: _NewsHit(
                                            item: Map<String, dynamic>.from(raw),
                                            onTap: () => openNewsDetail(context, Map<String, dynamic>.from(raw)),
                                          ),
                                        ),
                                  ],
                                ],
                              ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count) {
    return Text(
      '$title · $count',
      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
    );
  }
}

class _PlaceHit extends StatelessWidget {
  const _PlaceHit({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat = categoryLabels[item['category']] ?? '${item['category'] ?? ''}';
    final village = '${item['settlement_name'] ?? ''}'.trim();
    final address = '${item['address'] ?? ''}'.trim();
    final sub = [if (village.isNotEmpty) village, if (address.isNotEmpty) address].join(' · ');
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.place_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cat, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                    Text(
                      '${item['title'] ?? 'Место'}',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    if (sub.isNotEmpty)
                      Text(sub, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13), maxLines: 2),
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

class _NewsHit extends StatelessWidget {
  const _NewsHit({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = (item['body']?.toString() ?? '').trim();
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['title'] ?? 'Новость'}',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
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
      ),
    );
  }
}
