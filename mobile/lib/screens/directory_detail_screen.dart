import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import 'home_shell.dart';

class DirectoryDetailScreen extends StatelessWidget {
  const DirectoryDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = item['phone']?.toString();
    final website = item['website']?.toString();
    final address = item['address']?.toString();
    final hasMap = (item['lat'] is num && item['lon'] is num) || (address != null && address.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Контакт')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.muted = false});
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
