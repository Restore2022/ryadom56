import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../state/app_state.dart';
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
  bool phoneRevealed = false;

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

  Future<void> _message(String? phone, {required bool whatsapp}) async {
    final cleaned = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (cleaned.length < 10) {
      if (mounted) showAppSnack(context, 'Номер телефона не указан', error: true);
      return;
    }
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы написать автору');
    if (!loggedIn || !mounted) return;
    var digits = cleaned;
    if (digits.startsWith('8') && digits.length == 11) digits = '7${digits.substring(1)}';
    final uri = whatsapp
        ? Uri.parse('https://wa.me/$digits')
        : Uri(scheme: 'sms', path: '+$digits');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppSnack(context, 'Не удалось открыть приложение', error: true);
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

  Future<void> _report() async {
    if (reportBusy) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы пожаловаться');
    if (!loggedIn || !context.mounted) return;
    String reason = 'spam';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Пожаловаться'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Причина', border: OutlineInputBorder()),
                    items: reportReasons.entries
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
      await context.read<AppState>().reportListing(
            widget.listingId,
            reason: reason,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
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
    final canClose = isOwner && (data!['status'] == 'approved' || data['status'] == 'pending');
    final favorited = data != null && state.isFavorited(widget.listingId, item: data);

    Future<void> openChat() async {
      final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы написать автору');
      if (!loggedIn || !mounted) return;
      final template = 'Здравствуйте! Интересует объявление «${data!['title']}».';
      final authorName = data['author_name']?.toString();
      await Navigator.push(
        context,
        fastRoute(
          ListingChatScreen(
            listingId: widget.listingId,
            listingTitle: data['title'] as String,
            // покупатель: тред = он сам; продавец отвечает из вкладки «Чаты» с peerId
            peerName: authorName,
            initialMessage: template,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Объявление'),
        actions: [
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
              onPressed: reportBusy ? null : _report,
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
                            data['title'] as String,
                            style: GoogleFonts.unbounded(fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
                          ),
                          if (data['price'] != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              '${_fmtPrice(data['price'])} ₽',
                              style: GoogleFonts.manrope(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Text(
                            data['description'] as String,
                            style: GoogleFonts.manrope(fontSize: 16, height: 1.55),
                          ),
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
                          if (canSeePhone && hasPhone && (isOwner || isStaff || phoneRevealed))
                            _InfoRow(icon: Icons.phone_outlined, label: 'Телефон', value: contactPhone!),
                          _InfoRow(
                            icon: Icons.schedule_outlined,
                            label: 'Опубликовано',
                            value: _fmtDate(data['created_at']?.toString()),
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
                        ],
                      ),
                    ),
                    if (showChatPrimary) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: openChat,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Написать в приложении'),
                      ),
                    ],
                    if (canSeePhone && hasPhone && !isOwner) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (!phoneRevealed && !phoneHidden) {
                            final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы увидеть телефон');
                            if (!loggedIn || !mounted) return;
                            setState(() => phoneRevealed = true);
                          } else if (phoneHidden && !phoneRevealed) {
                            if (mounted) {
                              showAppSnack(context, 'Автор скрыл номер — напишите в чат', error: true);
                            }
                            return;
                          }
                          await _call(contactPhone);
                        },
                        icon: const Icon(Icons.phone_outlined),
                        label: Text(phoneRevealed && !phoneHidden ? 'Позвонить' : 'Показать телефон'),
                      ),
                      if (phoneRevealed && !phoneHidden) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _message(contactPhone, whatsapp: false),
                                icon: const Icon(Icons.sms_outlined),
                                label: const Text('SMS'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _message(contactPhone, whatsapp: true),
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text('WhatsApp'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    if ((isOwner || isStaff) && hasPhone) ...[
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
                        onPressed: reportBusy ? null : _report,
                        icon: const Icon(Icons.flag_outlined),
                        label: Text(reportBusy ? 'Отправка…' : 'Пожаловаться'),
                      ),
                    ],
                    if (isOwner) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Редактировать'),
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

  String _fmtPrice(dynamic price) {
    if (price is num) {
      if (price == price.roundToDouble()) return price.toInt().toString();
      return price.toStringAsFixed(2);
    }
    return '$price';
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
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
