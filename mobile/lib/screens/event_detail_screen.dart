import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../event_actions.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Map<String, dynamic> item;
  bool reminding = false;

  @override
  void initState() {
    super.initState();
    item = Map<String, dynamic>.from(widget.item);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = item['id'];
      if (id is int) context.read<AppState>().trackEventView(id);
    });
  }

  Future<void> _openMaps() async {
    final lat = item['lat'];
    final lon = item['lon'];
    final address = item['address']?.toString();
    final place = item['place_text']?.toString() ?? item['title']?.toString() ?? '';
    Uri uri;
    if (lat is num && lon is num) {
      uri = Uri.parse('geo:$lat,$lon?q=$lat,$lon(${Uri.encodeComponent(place)})');
    } else if (address != null && address.isNotEmpty) {
      uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
    } else if (place.isNotEmpty) {
      uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(place)}');
    } else {
      return;
    }
    if (!await launchUrl(uri)) {
      final q = address ?? place;
      await launchUrl(
        Uri.parse('https://yandex.ru/maps/?text=${Uri.encodeComponent(q)}'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> _share() async {
    try {
      await shareEvent(item);
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  Future<void> _calendar() async {
    try {
      await addEventToCalendar(item);
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    }
  }

  Future<void> _remind() async {
    setState(() => reminding = true);
    try {
      final dateLabel = await remindEventTomorrow(item);
      if (mounted) {
        showAppSnack(context, 'Напоминание сохранено: за день до события ($dateLabel)');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => reminding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final address = item['address']?.toString();
    final place = item['place_text']?.toString() ?? '';
    final cover = item['cover_url']?.toString();
    final hasMap = (item['lat'] is num && item['lon'] is num) ||
        (address != null && address.isNotEmpty) ||
        place.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Событие'),
        actions: [
          IconButton(
            tooltip: 'Поделиться',
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: context.scrollPad(top: 8, bottom: 20),
        children: [
          if (cover != null && cover.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  state.mediaUrl(cover),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: scheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            '${item['title']}',
            style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 12),
          Text(
            formatEventWhen(item['starts_at']?.toString(), item['ends_at']?.toString()),
            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item['settlement_name'] != null)
                _chip(context, '${item['settlement_name']}', Icons.place_outlined),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Поделиться'),
              ),
              OutlinedButton.icon(
                onPressed: _calendar,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('В календарь'),
              ),
              OutlinedButton.icon(
                onPressed: reminding ? null : _remind,
                icon: reminding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.alarm_add_outlined, size: 18),
                label: const Text('Напомнить'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Место', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(place, style: const TextStyle(fontSize: 16, height: 1.35)),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(address, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 20),
          Text('Описание', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('${item['description']}', style: const TextStyle(height: 1.45, fontSize: 15)),
          if (hasMap) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openMaps,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Открыть на карте'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}
