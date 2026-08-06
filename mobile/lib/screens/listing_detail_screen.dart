import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import 'home_shell.dart';

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
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
          item ??= widget.preview;
        });
      }
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = item;

    return Scaffold(
      appBar: AppBar(title: const Text('Объявление')),
      body: data == null && loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? Center(child: Text(error ?? 'Не найдено'))
              : ListView(
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
                              _Tag(categoryLabels[data['category']] ?? '${data['category']}'),
                              if (data['settlement_name'] != null) _Tag('${data['settlement_name']}', muted: true),
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
                          _InfoRow(icon: Icons.person_outline, label: 'Автор', value: '${data['author_name'] ?? '—'}'),
                          if (data['contact_phone'] != null)
                            _InfoRow(icon: Icons.phone_outlined, label: 'Телефон', value: '${data['contact_phone']}'),
                          _InfoRow(
                            icon: Icons.schedule_outlined,
                            label: 'Опубликовано',
                            value: _fmtDate(data['created_at']?.toString()),
                          ),
                        ],
                      ),
                    ),
                    if (data['contact_phone'] != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _call(data['contact_phone'] as String),
                        icon: const Icon(Icons.phone),
                        label: const Text('Позвонить'),
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
