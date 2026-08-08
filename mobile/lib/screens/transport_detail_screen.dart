import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TransportDetailScreen extends StatelessWidget {
  const TransportDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

  String _fmtUpdated(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final number = item['route_number']?.toString();
    final notes = item['notes']?.toString();
    final description = item['description']?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (number != null && number.isNotEmpty)
            Text(
              number,
              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          Text(
            '${item['title']}',
            style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          ),
          if (item['settlement_name'] != null) ...[
            const SizedBox(height: 8),
            Text('${item['settlement_name']}', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Text(
            'Обновлено: ${_fmtUpdated(item['updated_at']?.toString())}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(description, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 20),
          Text('Расписание', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${item['schedule_text']}',
              style: const TextStyle(height: 1.45, fontSize: 15),
            ),
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Важно', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(notes, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
