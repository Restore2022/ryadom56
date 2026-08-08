import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

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

  String _fmt(String? iso, {bool withTime = true}) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    if (!withTime) return d;
    return '$d, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final address = item['address']?.toString();
    final place = item['place_text']?.toString() ?? '';
    final hasMap = (item['lat'] is num && item['lon'] is num) ||
        (address != null && address.isNotEmpty) ||
        place.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Событие')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${item['title']}',
            style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, _fmt(item['starts_at']?.toString()), Icons.event),
              if (item['settlement_name'] != null)
                _chip(context, '${item['settlement_name']}', Icons.place_outlined),
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
          if (item['ends_at'] != null) ...[
            const SizedBox(height: 16),
            Text('Окончание', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_fmt(item['ends_at']?.toString())),
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
