import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../listing_row.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

class ViewHistoryScreen extends StatelessWidget {
  const ViewHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.viewHistory;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История просмотров'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Очистить историю?'),
                    content: const Text('Список недавно просмотренных объявлений будет удалён.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очистить')),
                    ],
                  ),
                );
                if (ok == true) await state.clearViewHistory();
              },
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
              padding: context.scrollPad(top: 12, bottom: 20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = items[i];
                final date = formatApiDate(item['viewed_at']?.toString(), empty: '');
                return ListingRow(
                  item: item,
                  footer: date.isEmpty ? null : 'Смотрели $date',
                  onTap: () => Navigator.push(
                    context,
                    fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
                  ),
                );
              },
            ),
    );
  }
}
