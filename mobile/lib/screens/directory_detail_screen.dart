import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import 'home_shell.dart';

const directoryReportReasons = {
  'wrong_phone': 'Неверный телефон',
  'wrong_address': 'Неверный адрес',
  'closed': 'Закрыто / не работает',
  'other': 'Другое',
};

class DirectoryDetailScreen extends StatefulWidget {
  const DirectoryDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  State<DirectoryDetailScreen> createState() => _DirectoryDetailScreenState();
}

class _DirectoryDetailScreenState extends State<DirectoryDetailScreen> {
  bool reportBusy = false;

  Map<String, dynamic> get item => widget.item;

  @override
  void initState() {
    super.initState();
    final id = item['id'];
    if (id is int) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AppState>().trackDirectoryView(id);
      });
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[\s\-()]'), ''));
    await launchUrl(uri);
  }

  Future<void> _openWeb(String url) async {
    var value = url.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  }

  Future<void> _openMaps() async {
    final mapsUrl = item['maps_url']?.toString();
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

  Future<void> _report() async {
    if (reportBusy) return;
    final id = item['id'];
    if (id is! int) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы сообщить о неверных контактах');
    if (!loggedIn || !mounted) return;
    String reason = 'wrong_phone';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Неверные контакты'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Что не так', border: OutlineInputBorder()),
                    items: directoryReportReasons.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setLocal(() => reason = v ?? 'wrong_phone'),
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
      await context.read<AppState>().reportDirectory(
            id,
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
      note.dispose();
      if (mounted) setState(() => reportBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = item['phone']?.toString();
    final website = item['website']?.toString();
    final address = item['address']?.toString();
    final hasMap = (item['maps_url']?.toString().isNotEmpty == true) ||
        (item['lat'] is num && item['lon'] is num) ||
        (address != null && address.isNotEmpty);
    final openNow = item['is_open_now'] == true;
    final closedNow = item['is_open_now'] == false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Контакт'),
        actions: [
          IconButton(
            tooltip: 'Неверные контакты',
            onPressed: reportBusy ? null : _report,
            icon: const Icon(Icons.flag_outlined),
          ),
          Consumer<AppState>(
            builder: (context, state, _) {
              final id = item['id'] as int?;
              final fav = id != null && (state.directoryFavoriteIds.contains(id) || item['is_favorited'] == true);
              return IconButton(
                tooltip: fav ? 'Убрать из избранного' : 'В избранное',
                onPressed: id == null
                    ? null
                    : () async {
                        final ok = await ensureLoggedIn(context, message: 'Войдите, чтобы сохранить организацию');
                        if (!ok || !context.mounted) return;
                        try {
                          await state.toggleDirectoryFavorite(id, currentlyFavorited: fav);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppState.userFriendlyError(e))));
                          }
                        }
                      },
                icon: Icon(fav ? Icons.bookmark : Icons.bookmark_border),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: context.scrollPad(top: 8, bottom: 20),
        children: [
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
                    _Pill(categoryLabels[item['category']] ?? '${item['category']}'),
                    if (item['settlement_name'] != null) _Pill('${item['settlement_name']}', muted: true),
                    if (openNow) _Pill('Открыто', highlight: true),
                    if (closedNow) _Pill('Закрыто', muted: true),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  item['title'] as String,
                  style: GoogleFonts.unbounded(fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
                ),
                if (item['description'] != null && '${item['description']}'.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('${item['description']}', style: GoogleFonts.manrope(fontSize: 16, height: 1.5)),
                ],
                const SizedBox(height: 18),
                const Divider(),
                if (address != null && address.isNotEmpty)
                  _Row(icon: Icons.place_outlined, label: 'Адрес', value: address),
                if (item['hours'] != null && '${item['hours']}'.isNotEmpty)
                  _Row(icon: Icons.schedule_outlined, label: 'Часы работы', value: '${item['hours']}'),
                if (phone != null && phone.isNotEmpty) _Row(icon: Icons.phone_outlined, label: 'Телефон', value: phone),
                if (website != null && website.isNotEmpty)
                  _Row(icon: Icons.language_outlined, label: 'Сайт', value: website),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (phone != null && phone.isNotEmpty)
            FilledButton.icon(
              onPressed: () => _call(phone),
              icon: const Icon(Icons.phone),
              label: const Text('Позвонить'),
            ),
          if (hasMap) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openMaps,
              icon: const Icon(Icons.map_outlined),
              label: const Text('На карте'),
            ),
          ],
          if (website != null && website.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openWeb(website),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Открыть сайт'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: reportBusy ? null : _report,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Сообщить о неверных контактах'),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.muted = false, this.highlight = false});
  final String text;
  final bool muted;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer
            : muted
                ? scheme.surfaceContainerHighest
                : scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: highlight
              ? scheme.onPrimaryContainer
              : muted
                  ? scheme.onSurfaceVariant
                  : scheme.primary,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
