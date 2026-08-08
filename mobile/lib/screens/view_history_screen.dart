import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui_helpers.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

class ViewHistoryScreen extends StatelessWidget {
  const ViewHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.viewHistory;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История просмотров'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => state.clearViewHistory(),
              child: const Text('Очистить'),
            ),
        ],
      ),
      body: items.isEmpty
          ? emptyState(
              context: context,
              title: 'История пуста',
              subtitle: 'Откройте объявление в ленте — оно появится здесь',
              icon: Icons.history,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = items[i];
                final images = (item['images'] as List?) ?? [];
                final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
                return Material(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                      context,
                      fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: thumb == null
                                ? Container(
                                    width: 64,
                                    height: 64,
                                    color: scheme.surfaceContainerHighest,
                                    child: const Icon(Icons.image_outlined),
                                  )
                                : Image.network(state.mediaUrl(thumb), width: 64, height: 64, fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item['title']}', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                  categoryLabels['${item['category']}'] ?? '${item['category']}',
                                  style: TextStyle(color: scheme.primary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
