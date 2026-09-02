import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../auth_prompt.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

class AuthorListingsScreen extends StatefulWidget {
  const AuthorListingsScreen({
    super.key,
    required this.authorId,
    required this.authorName,
  });

  final int authorId;
  final String authorName;

  @override
  State<AuthorListingsScreen> createState() => _AuthorListingsScreenState();
}

class _AuthorListingsScreenState extends State<AuthorListingsScreen> {
  List<dynamic> items = [];
  Map<String, dynamic>? profile;
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
      final state = context.read<AppState>();
      final results = await Future.wait([
        state.loadAuthorListings(widget.authorId),
        state.getPublicProfile(widget.authorId),
      ]);
      if (mounted) {
        setState(() {
          items = results[0] as List<dynamic>;
          profile = results[1] as Map<String, dynamic>;
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

  String _fmtMemberSince(String? iso) => formatApiMonthYear(iso);

  Future<void> _reportUser() async {
    final me = context.read<AppState>().user;
    if (me != null && me['id'] == widget.authorId) {
      showAppSnack(context, 'Нельзя пожаловаться на себя');
      return;
    }
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы пожаловаться');
    if (!loggedIn || !mounted) return;
    String reason = 'spam';
    final note = TextEditingController();
    const reasons = {
      'spam': 'Спам',
      'fraud': 'Мошенничество',
      'prohibited': 'Запрещённый контент',
      'abuse': 'Оскорбления / угрозы',
      'other': 'Другое',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Жалоба на человека'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Причина', border: OutlineInputBorder()),
                    items: reasons.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setLocal(() => reason = v ?? 'spam'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий (необязательно)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отправить')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().reportUser(
            widget.authorId,
            reason: reason,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
      if (mounted) showAppSnack(context, 'Жалоба отправлена');
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final p = profile;
    final reportsAgainst = (p?['reports_against'] as num?)?.toInt() ?? 0;
    final badge = p?['badge']?.toString();
    final rating = p?['rating_score'];
    final listingsCount = (p?['listings_count'] as num?)?.toInt() ?? items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.authorName),
        actions: [
          IconButton(
            tooltip: 'Пожаловаться на человека',
            onPressed: _reportUser,
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && items.isEmpty && p == null
              ? Center(child: Text(error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: context.scrollPad(top: 16, bottom: 16),
                    children: [
                      if (p != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: scheme.primaryContainer,
                                    backgroundImage: (p['avatar_url'] != null && '${p['avatar_url']}'.isNotEmpty)
                                        ? NetworkImage(state.mediaUrl(p['avatar_url']?.toString()))
                                        : null,
                                    child: (p['avatar_url'] == null || '${p['avatar_url']}'.isEmpty)
                                        ? Text(
                                            (widget.authorName.isNotEmpty ? widget.authorName.substring(0, 1) : '?').toUpperCase(),
                                            style: GoogleFonts.unbounded(fontWeight: FontWeight.w700),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['full_name'] as String? ?? widget.authorName,
                                          style: GoogleFonts.unbounded(fontSize: 20, fontWeight: FontWeight.w600),
                                        ),
                                        if (p['settlement_name'] != null) ...[
                                          const SizedBox(height: 4),
                                          Text('${p['settlement_name']}', style: TextStyle(color: scheme.onSurfaceVariant)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (badge != null && badge.isNotEmpty)
                                    _ProfileChip(
                                      badgeLabels[badge] ?? badge,
                                      color: badge == 'caution' ? scheme.errorContainer : scheme.primaryContainer,
                                      fg: badge == 'caution' ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                                    ),
                                  if (rating != null)
                                    _ProfileChip('★ ${(rating as num).toStringAsFixed(1)}'),
                                  _ProfileChip('$listingsCount объявл.'),
                                  if (p['member_since'] != null)
                                    _ProfileChip(_fmtMemberSince(p['member_since']?.toString()), muted: true),
                                ],
                              ),
                              if (reportsAgainst >= 2) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.errorContainer.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'На объявления автора поступало несколько жалоб. Будьте внимательны при сделке.',
                                          style: TextStyle(color: scheme.onErrorContainer, height: 1.35, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text('Объявления', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 10),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Нет опубликованных объявлений', style: TextStyle(color: scheme.onSurfaceVariant))),
                        )
                      else
                        ...items.map((raw) {
                          final item = raw as Map<String, dynamic>;
                          final images = (item['images'] as List?) ?? [];
                          final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Theme.of(context).cardTheme.color,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.push(
                                  context,
                                  fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: thumb == null
                                            ? Container(
                                                width: 64,
                                                height: 64,
                                                color: scheme.surfaceContainerHighest,
                                                child: const Icon(Icons.image_outlined),
                                              )
                                            : Image.network(
                                                state.mediaUrl(thumb),
                                                width: 64,
                                                height: 64,
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['title'] as String, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                                            const SizedBox(height: 4),
                                            Text(
                                              categoryLabels[item['category']] ?? '${item['category']}',
                                              style: TextStyle(color: scheme.primary, fontSize: 12),
                                            ),
                                            if (item['price'] != null)
                                              Text('${item['price']} ₽', style: const TextStyle(fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip(this.text, {this.color, this.fg, this.muted = false});
  final String text;
  final Color? color;
  final Color? fg;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
