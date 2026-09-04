import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../responsive.dart';
import '../ride_text.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'ride_chat_screen.dart';

class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({super.key, required this.rideId, this.preview});

  final int rideId;
  final Map<String, dynamic>? preview;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  Map<String, dynamic>? item;
  String? error;
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    item = widget.preview;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppState>().getRide(widget.rideId);
      if (mounted) {
        setState(() {
          item = data;
          loading = false;
          error = null;
        });
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

  Future<void> _write() async {
    final data = item;
    if (data == null) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы написать');
    if (!loggedIn || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideChatScreen(
          rideId: widget.rideId,
          title: '${data['title'] ?? ''}',
          peerName: data['author_name']?.toString(),
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _call(String? phone) async {
    final cleaned = (phone ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы позвонить');
    if (!loggedIn || !mounted) return;
    await launchUrl(Uri(scheme: 'tel', path: cleaned));
  }

  Future<void> _close() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: const Text('Мест больше нет'), onTap: () => Navigator.pop(ctx, 'full')),
              ListTile(title: const Text('Поездка не состоится'), onTap: () => Navigator.pop(ctx, 'cancelled')),
              ListTile(title: const Text('Уже уехали'), onTap: () => Navigator.pop(ctx, 'gone')),
            ],
          ),
        );
      },
    );
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    try {
      final updated = await context.read<AppState>().closeRide(widget.rideId, reason: reason);
      if (mounted) setState(() => item = updated);
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _report() async {
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы пожаловаться');
    if (!loggedIn || !mounted) return;
    String reason = 'spam';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Жалоба на попутку'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Причина', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'spam', child: Text('Спам')),
                      DropdownMenuItem(value: 'fraud', child: Text('Мошенничество')),
                      DropdownMenuItem(value: 'other', child: Text('Другое')),
                    ],
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
      await context.read<AppState>().reportRide(
            widget.rideId,
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
    final scheme = Theme.of(context).colorScheme;
    final data = item;
    if (loading && data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Попутка')),
        body: errorState(context: context, message: error ?? 'Не найдено', onRetry: _load),
      );
    }
    final kind = data['kind']?.toString() ?? 'drive';
    final seats = (data['seats'] as num?)?.toInt() ?? 1;
    final isMine = data['is_mine'] == true;
    final status = data['status']?.toString() ?? 'open';
    final open = status == 'open';
    final phone = data['contact_phone']?.toString();
    final phoneHidden = data['phone_hidden'] == true;
    final isGuest = context.watch<AppState>().user == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Попутка'),
        actions: [
          if (!isMine)
            IconButton(
              tooltip: 'Пожаловаться',
              onPressed: _report,
              icon: const Icon(Icons.flag_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: context.scrollPad(top: 16, bottom: 24),
        children: [
          Text(
            '${data['title'] ?? ''}',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 22, height: 1.25),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, rideKindLabel(kind)),
              _chip(context, formatRideWhen(data['depart_at']?.toString())),
              _chip(context, rideSeatsLabel(kind, seats)),
            ],
          ),
          if (!open) ...[
            const SizedBox(height: 12),
            Text(
              rideCloseLabel(data['close_reason']?.toString()),
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
          ],
          if ((data['note'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text('${data['note']}', style: const TextStyle(height: 1.4, fontSize: 16)),
          ],
          const SizedBox(height: 16),
          Text(
            'Автор: ${data['author_name'] ?? '—'}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (isGuest) ...[
            const SizedBox(height: 16),
            const GuestCtaBanner(
              compact: true,
              title: 'Войдите, чтобы написать',
              subtitle: 'Попутка видна всем. Чат и телефон — после входа, без комиссии.',
            ),
          ],
          if (!isMine && open) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _write,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Написать'),
            ),
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _call(phone),
                icon: const Icon(Icons.phone_outlined),
                label: const Text('Позвонить'),
              ),
            ] else if (phoneHidden && !isGuest) ...[
              const SizedBox(height: 8),
              Text(
                'Номер откроется, когда автор ответит в чате.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ],
          ],
          if (isMine && open) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: busy ? null : _close,
              child: const Text('Снять попутку'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}
