import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ride_text.dart';
import 'time_format.dart';

class RideCard extends StatelessWidget {
  const RideCard({super.key, required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final kind = item['kind']?.toString() ?? 'drive';
    final seats = (item['seats'] as num?)?.toInt() ?? 1;
    final when = formatRideWhen(item['depart_at']?.toString());
    final note = item['note']?.toString();
    final mine = item['is_mine'] == true;
    final status = item['status']?.toString() ?? 'open';
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: dark ? const Color(0xFF4A6354) : const Color(0xFFD5E0D0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      rideKindLabel(kind),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 6),
                    Text('ваша', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                  if (status != 'open') ...[
                    const SizedBox(width: 6),
                    Text(
                      status == 'hidden' ? 'скрыта' : 'снята',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${item['title'] ?? '${item['from_name']} → ${item['to_name']}'}',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                [if (when.isNotEmpty) when, rideSeatsLabel(kind, seats)].join(' · '),
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
