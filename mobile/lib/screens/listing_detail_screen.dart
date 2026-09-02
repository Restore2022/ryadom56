import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../call_screens.dart';
import '../listing_templates.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'author_listings_screen.dart';
import 'create_listing_screen.dart';
import 'home_shell.dart';
import 'listing_chat_screen.dart';
import 'my_listings_screen.dart';

const reportReasons = {
  'spam': 'Спам',
  'fraud': 'Мошенничество',
  'prohibited': 'Запрещённый товар',
  'abuse': 'Оскорбления / угрозы',
  'other': 'Другое',
};

const listingReportReasons = {
  'spam': 'Спам',
  'fraud': 'Мошенничество',
  'prohibited': 'Запрещённый товар',
  'other': 'Другое',
};

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId, this.preview});

  final int listingId;
  final Map<String, dynamic>? preview;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  Map<String, dynamic>? item;
  String? error;
  bool loading = true;
  int photoIndex = 0;
  bool favBusy = false;
  bool reportBusy = false;
  bool relevantBusy = false;

  @override
  void initState() {
    super.initState();
    item = widget.preview;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppState>().getListing(widget.listingId);
      if (mounted) {
        setState(() {
          item = data;
          loading = false;
          error = null;
        });
        context.read<AppState>().addViewHistory(data);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = AppState.userFriendlyError(e);
          loading = false;
          item ??= widget.preview;
        });
      }
    }
  }

  Future<void> _call(String? phone) async {
    final cleaned = (phone ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Номер телефона не указан')),
        );
      }
      return;
    }
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы позвонить автору');
    if (!loggedIn || !context.mounted) return;
    final uri = Uri(scheme: 'tel', path: cleaned);
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть звонок')),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    if (favBusy || item == null) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы сохранить в избранное');
    if (!loggedIn || !context.mounted) return;
    setState(() => favBusy = true);
    try {
      final updated = await context.read<AppState>().toggleFavorite(
            widget.listingId,
            currentlyFavorited: item!['is_favorited'] == true,
          );
      if (mounted) setState(() => item = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppState.userFriendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => favBusy = false);
    }
  }

  Future<void> _report({required bool againstUser}) async {
    if (reportBusy) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы пожаловаться');
    if (!loggedIn || !context.mounted) return;
    String reason = 'spam';
    final note = TextEditingController();
    final reasons = againstUser ? reportReasons : listingReportReasons;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(againstUser ? 'Жалоба на человека' : 'Жалоба на объявление'),
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
    setState(() => reportBusy = true);
    try {
      final app = context.read<AppState>();
      if (againstUser) {
        final authorId = item?['author_id'] as int?;
        if (authorId == null) return;
        await app.reportUser(
          authorId,
          reason: reason,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          listingId: widget.listingId,
        );
      } else {
        await app.reportListing(
          widget.listingId,
          reason: reason,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба отправлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppState.userFriendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => reportBusy = false);
    }
  }

  Future<void> _chooseReport() async {
    final which = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('На объявление'),
                subtitle: const Text('Спам, запрещённый товар, обман в карточке'),
                onTap: () => Navigator.pop(ctx, 'listing'),
              ),
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('На человека'),
                subtitle: const Text('Поведение, угрозы, повторный обман'),
                onTap: () => Navigator.pop(ctx, 'user'),
              ),
            ],
          ),
        );
      },
    );
    if (which == 'listing') await _report(againstUser: false);
    if (which == 'user') await _report(againstUser: true);
  }

  Future<void> _extend() async {
    int days = 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Продлить объявление'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Срок считается от сегодня или от текущей даты снятия — что позже.'),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 30, label: Text('30 дней')),
                      ButtonSegment(value: 60, label: Text('60 дней')),
                    ],
                    selected: {days},
                    onSelectionChanged: (v) => setLocal(() => days = v.first),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Продлить')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await context.read<AppState>().extendListing(widget.listingId, days: days);
      if (mounted) {
        setState(() => item = updated);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Срок продлён')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppState.userFriendlyError(e))));
      }
    }
  }

  Future<void> _share() async {
    final data = item;
    if (data == null) return;
    final id = data['id'] ?? widget.listingId;
    final title = data['title']?.toString() ?? 'Объявление';
    final village = data['settlement_name']?.toString() ?? '';
    final price = listingPriceLabel(data);
    final text = [
      title,
      if (price.isNotEmpty) price,
      if (village.isNotEmpty) village,
      'https://legac.ru/l/$id',
    ].join('\n');
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _confirmRelevant() async {
    if (relevantBusy) return;
    setState(() => relevantBusy = true);
    try {
      final updated = await context.read<AppState>().confirmListingRelevant(widget.listingId);
      if (mounted) {
        setState(() => item = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Оставили в ленте')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppState.userFriendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => relevantBusy = false);
    }
  }

  Future<void> _edit() async {
    if (item == null) return;
    final ok = await Navigator.push<bool>(
      context,
      fastRoute(CreateListingScreen(listingId: widget.listingId, initial: item)),
    );
    if (ok == true) await _load();
  }

  Future<void> _close() async {
    String reason = 'sold';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Снять объявление'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Причина', border: OutlineInputBorder()),
                    items: closeReasons.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setLocal(() => reason = v ?? 'sold'),
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
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Снять')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await context.read<AppState>().closeListing(
            widget.listingId,
            reason: reason,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
      if (mounted) {
        setState(() => item = updated);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Объявление снято')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppState.userFriendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final data = item;
    final images = ((data?['images'] as List?) ?? []).cast<dynamic>();
    final isOwner = data != null && state.user != null && data['author_id'] == state.user!['id'];
    final role = state.user?['role']?.toString();
    final isStaff = role == 'admin' || role == 'moderator' || role == 'editor';
    final phoneHidden = data?['phone_hidden'] == true;
    final contactPhone = data?['contact_phone']?.toString();
    final hasPhone = contactPhone != null && contactPhone.isNotEmpty;
    final canSeePhone = isOwner || isStaff || (!phoneHidden && hasPhone);
    final showChatPrimary = !isOwner;
    final canClose = isOwner && (data?['status'] == 'approved' || data?['status'] == 'pending');
    final canExtend = isOwner &&
        (data?['status'] == 'approved' || (data?['status'] == 'archived' && data?['close_reason'] == 'expired'));
    final isGuest = state.user == null;
    final favorited = data != null && state.isFavorited(widget.listingId, item: data);

    Future<void> openChat() async {
      final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы написать автору');
      if (!loggedIn || !mounted) return;
      final title = data!['title']?.toString() ?? 'объявление';
      final template = 'Здравствуйте! Интересует объявление «$title».';
      final authorName = data['author_name']?.toString();
      await Navigator.push(
        context,
        fastRoute(
          ListingChatScreen(
            listingId: widget.listingId,
            listingTitle: title,
            // покупатель: тред = он сам; продавец отвечает из вкладки «Чаты» с peerId
            peerName: authorName,
            initialMessage: template,
          ),
        ),
      );
      await _load();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Объявление'),
        actions: [
          if (data != null)
            IconButton(
              tooltip: 'Поделиться ссылкой',
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
            ),
          if (data != null && !isOwner)
            IconButton(
              tooltip: favorited ? 'Убрать из избранного' : 'В избранное',
              onPressed: favBusy ? null : _toggleFavorite,
              icon: Icon(favorited ? Icons.favorite : Icons.favorite_border, color: favorited ? scheme.error : null),
            ),
          if (isOwner)
            IconButton(
              tooltip: 'Изменить',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (!isOwner && data != null)
            IconButton(
              tooltip: 'Пожаловаться',
              onPressed: reportBusy ? null : _chooseReport,
              icon: const Icon(Icons.flag_outlined),
            ),
          if (canClose)
            TextButton(onPressed: _close, child: const Text('Снять')),
        ],
      ),
      body: data == null && loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? errorState(
                  context: context,
                  message: error ?? 'Объявление недоступно',
                  onRetry: _load,
                )
              : ListView(
                  padding: context.scrollPad(top: 8, bottom: 20),
                  children: [
                    if (images.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: PageView.builder(
                            itemCount: images.length,
                            onPageChanged: (i) => setState(() => photoIndex = i),
                            itemBuilder: (_, i) {
                              final url = state.mediaUrl((images[i] as Map)['url'] as String?);
                              return Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image_outlined, size: 48),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (images.length > 1) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            '${photoIndex + 1} / ${images.length}',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (isOwner && data['ask_if_relevant'] == true) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ещё актуально?',
                              style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Объявление висит уже две недели. Если продали — снимите, чтобы не висело зря.',
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: relevantBusy ? null : _confirmRelevant,
                                    child: Text(relevantBusy ? 'Секунду…' : 'Ещё актуально'),
                                  ),
                                ),
                                if (canClose) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _close,
                                      child: const Text('Снять'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Tag(categoryLabels[data['category']] ?? '${data['category']}'),
                              if (data['settlement_name'] != null) _Tag('${data['settlement_name']}', muted: true),
                              if (isOwner) _Tag(statusLabels['${data['status']}'] ?? '${data['status']}', muted: true),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            data['title']?.toString() ?? 'Объявление',
                            style: GoogleFonts.unbounded(fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
                          ),
                          if (listingPriceLabel(data).isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              listingPriceLabel(data),
                              style: GoogleFonts.manrope(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                          if ((data['description']?.toString() ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Text(
                              data['description'].toString(),
                              style: GoogleFonts.manrope(fontSize: 16, height: 1.55),
                            ),
                          ],
                          const SizedBox(height: 22),
                          const Divider(),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () {
                              final authorId = data['author_id'] as int?;
                              final name = '${data['author_name'] ?? 'Автор'}';
                              if (authorId == null) return;
                              Navigator.push(
                                context,
                                fastRoute(AuthorListingsScreen(authorId: authorId, authorName: name)),
                              );
                            },
                            child: _InfoRow(
                              icon: Icons.person_outline,
                              label: 'Автор',
                              value: '${data['author_name'] ?? '—'} · другие объявления',
                            ),
                          ),
                          if (canSeePhone && hasPhone)
                            InkWell(
                              onTap: () => _call(contactPhone),
                              child: _InfoRow(icon: Icons.phone_outlined, label: 'Телефон', value: contactPhone!),
                            ),
                          _InfoRow(
                            icon: Icons.schedule_outlined,
                            label: 'Опубликовано',
                            value: formatApiDate(data['created_at']?.toString(), empty: '—'),
                          ),
                          if (isOwner && data['status'] == 'rejected' && data['moderation_note'] != null)
                            _InfoRow(
                              icon: Icons.info_outline,
                              label: 'Причина отклонения',
                              value: '${data['moderation_note']}',
                            ),
                          if (data['close_reason'] != null)
                            _InfoRow(
                              icon: Icons.archive_outlined,
                              label: 'Причина снятия',
                              value: closeReasons['${data['close_reason']}'] ?? '${data['close_note'] ?? data['close_reason']}',
                            ),
                          if (data['expires_at'] != null && (isOwner || data['status'] == 'approved'))
                            _InfoRow(
                              icon: Icons.event_available_outlined,
                              label: 'Срок',
                              value: _expiryLabel(data),
                            ),
                        ],
                      ),
                    ),
                    if (isGuest) ...[
                      const SizedBox(height: 16),
                      const GuestCtaBanner(
                        compact: true,
                        title: 'Войдите, чтобы написать и сохранить',
                        subtitle: 'Гостям видна лента. Чат, избранное и телефон — после аккаунта, без комиссии.',
                      ),
                    ],
                    if (showChatPrimary) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: openChat,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Написать'),
                      ),
                      if (!isGuest) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы позвонить');
                            if (!loggedIn || !mounted) return;
                            await startAppCall(
                              context,
                              listingId: widget.listingId,
                              gsmPhone: (!phoneHidden && hasPhone) ? contactPhone : null,
                            );
                          },
                          icon: const Icon(Icons.phone_in_talk_outlined),
                          label: const Text('Позвонить'),
                        ),
                      ],
                    ],
                    if (phoneHidden && !isOwner && !isStaff && !isGuest) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Номер откроется, когда автор ответит в чате.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.35),
                      ),
                    ],
                    if (isOwner && hasPhone) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _call(contactPhone!),
                        icon: const Icon(Icons.phone),
                        label: const Text('Позвонить'),
                      ),
                    ],
                    if (!isOwner) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Поделиться ссылкой'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: reportBusy ? null : _chooseReport,
                        icon: const Icon(Icons.flag_outlined),
                        label: Text(reportBusy ? 'Отправка…' : 'Пожаловаться'),
                      ),
                    ],
                    if (isOwner) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Поделиться ссылкой'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Редактировать'),
                      ),
                    ],
                    if (canExtend) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _extend,
                        icon: const Icon(Icons.update),
                        label: const Text('Продлить'),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: scheme.error, fontSize: 12)),
                    ],
                  ],
                ),
    );
  }

  String _expiryLabel(Map data) {
    final iso = data['expires_at']?.toString();
    final dt = parseApiTime(iso);
    if (dt == null) return formatApiDate(iso, empty: '—');
    final days = dt.difference(DateTime.now()).inDays;
    final date = formatApiDate(iso, empty: '—');
    if (days < 0) return 'Истёк $date';
    if (days == 0) return 'Снимается сегодня ($date)';
    return 'До $date · ещё $days дн.';
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: muted ? scheme.surfaceContainerHighest : scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: muted ? scheme.onSurfaceVariant : scheme.primary,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
