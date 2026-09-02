import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'listing_templates.dart';
import 'state/app_state.dart';

class ListingRow extends StatelessWidget {
  const ListingRow({
    super.key,
    required this.item,
    required this.onTap,
    this.badge,
    this.badgeColor,
    this.footer,
    this.trailing,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;
  final String? footer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final images = (item['images'] as List?) ?? [];
    final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
    final cat = '${item['category'] ?? ''}';
    final price = listingPriceLabel(item);
    final village = '${item['settlement_name'] ?? ''}'.trim();

    final wanted = cat == 'wanted';
    final free = cat == 'free';
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: wanted
                  ? scheme.secondary.withValues(alpha: 0.5)
                  : free
                      ? scheme.tertiary.withValues(alpha: 0.5)
                      : scheme.outlineVariant.withValues(alpha: 0.45),
              width: wanted || free ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumb == null
                    ? Container(
                        width: 76,
                        height: 76,
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                      )
                    : Image.network(
                        state.mediaUrl(thumb),
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 76,
                          height: 76,
                          color: scheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          listingCategoryLabels[cat] ?? cat,
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? scheme.primary).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                color: badgeColor ?? scheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        if (price.isNotEmpty)
                          Text(price, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item['title'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    if (village.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(village, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                    if (footer != null && footer!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(footer!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.3)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing! else const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
