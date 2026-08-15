import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'listing_detail_screen.dart';
import 'home_shell.dart';

const reportStatusLabels = {
  'open': 'На рассмотрении',
  'reviewed': 'Рассмотрено',
  'dismissed': 'Отклонено',
};

const reportReasonLabels = {
  'spam': 'Спам',
  'fraud': 'Мошенничество',
  'prohibited': 'Запрещённый товар',
  'other': 'Другое',
};

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<dynamic> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await context.read<AppState>().loadReportsAgainstMe();
      if (mounted) {
        setState(() {
          items = rows;
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

  String _fmtDate(String? iso) => formatApiDate(iso);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Жалобы на мои объявления')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : error != null && items.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: 280,
                        child: errorState(context: context, message: error!, onRetry: _load),
                      ),
                    ],
                  )
                : items.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: 280,
                            child: emptyState(
                              context: context,
                              title: 'Жалоб нет',
                              subtitle: 'Если на объявление пожалуются, вы увидите это здесь',
                              icon: Icons.flag_outlined,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final item = items[i] as Map<String, dynamic>;
                          final status = '${item['status']}';
                          return Material(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                final lid = item['listing_id'];
                                if (lid is int) {
                                  Navigator.push(
                                    context,
                                    fastRoute(ListingDetailScreen(listingId: lid)),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['listing_title'] ?? 'Объявление'}',
                                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _Chip(
                                          reportStatusLabels[status] ?? status,
                                          color: status == 'open' ? scheme.errorContainer : scheme.primaryContainer,
                                          fg: status == 'open' ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                                        ),
                                        _Chip(
                                          reportReasonLabels['${item['reason']}'] ?? '${item['reason']}',
                                          muted: true,
                                        ),
                                      ],
                                    ),
                                    if (item['note'] != null && '${item['note']}'.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text('${item['note']}', style: TextStyle(color: scheme.onSurfaceVariant)),
                                    ],
                                    if (item['moderator_reply'] != null && '${item['moderator_reply']}'.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Ответ модератора',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: scheme.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('${item['moderator_reply']}'),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      _fmtDate(item['created_at']?.toString()),
                                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.color, this.fg, this.muted = false});
  final String text;
  final Color? color;
  final Color? fg;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? (muted ? scheme.surfaceContainerHighest : scheme.primary.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg ?? (muted ? scheme.onSurfaceVariant : scheme.primary),
        ),
      ),
    );
  }
}
