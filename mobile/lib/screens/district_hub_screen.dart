import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../scroll_to_top.dart';
import '../state/app_state.dart';
import 'event_detail_screen.dart';
import 'home_shell.dart';
import 'news_list_screen.dart';

class DistrictHubScreen extends StatefulWidget {
  const DistrictHubScreen({super.key});

  @override
  State<DistrictHubScreen> createState() => _DistrictHubScreenState();
}

class _DistrictHubScreenState extends State<DistrictHubScreen> {
  final scroll = ScrollController();
  List<Map<String, dynamic>> alerts = [];
  List<dynamic> news = [];
  List<dynamic> events = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final state = context.read<AppState>();
    final settlementId = state.preferredSettlementId ?? state.filterSettlementId;
    try {
      final results = await Future.wait([
        state.loadActiveAlerts(limit: 5),
        state.loadNews(settlementId: settlementId),
        state.loadEvents(upcoming: true, settlementId: settlementId),
      ]);
      if (mounted) {
        setState(() {
          alerts = List<Map<String, dynamic>>.from(results[0] as List);
          news = (results[1] as List<dynamic>).take(3).toList();
          events = (results[2] as List<dynamic>).take(5).toList();
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

  String _fmtWhen(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}'
        ' · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Район')),
      body: stackWithScrollToTop(
        controller: scroll,
        heroTag: 'scroll-top-district',
        child: RefreshIndicator(
          onRefresh: _load,
          child: loading && alerts.isEmpty && news.isEmpty && events.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: Icon(Icons.wifi_off, color: scheme.onErrorContainer),
                          title: Text(error!, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
                          trailing: TextButton(onPressed: _load, child: const Text('Ещё раз')),
                        ),
                      ),
                    ),
                  Text('Важное', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 10),
                  if (alerts.isEmpty)
                    Text('Нет активных оповещений', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    ...alerts.map(
                      (a) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _alertBg(context, a['kind']?.toString()),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              a['kind'] == 'danger'
                                  ? Icons.warning_amber_rounded
                                  : a['kind'] == 'warn'
                                      ? Icons.info_outline
                                      : Icons.campaign_outlined,
                              color: _alertFg(context, a['kind']?.toString()),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${a['message']}',
                                style: TextStyle(
                                  color: _alertFg(context, a['kind']?.toString()),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Новости', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            fastRoute(NewsListScreen(settlementId: state.preferredSettlementId ?? state.filterSettlementId)),
                          );
                        },
                        child: const Text('Все'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (news.isEmpty)
                    Text('Новостей пока нет', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    ...news.map((n) {
                      final item = n as Map<String, dynamic>;
                      return _HubCard(
                        title: '${item['title']}',
                        subtitle: item['settlement_name']?.toString(),
                        onTap: () {
                          Navigator.push(
                            context,
                            fastRoute(NewsListScreen(settlementId: state.preferredSettlementId ?? state.filterSettlementId)),
                          );
                        },
                      );
                    }),
                  const SizedBox(height: 20),
                  Text('Скоро в афише', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 8),
                  if (events.isEmpty)
                    Text('Ближайших событий нет', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    ...events.map((e) {
                      final item = e as Map<String, dynamic>;
                      return _HubCard(
                        title: '${item['title']}',
                        subtitle: '${_fmtWhen(item['starts_at']?.toString())} · ${item['place_text'] ?? ''}',
                        onTap: () => Navigator.push(context, fastRoute(EventDetailScreen(item: item))),
                      );
                    }),
                ],
              ),
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.title, this.subtitle, required this.onTap});
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
