import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';

/// Returns true if the user is logged in after optional login/register prompt.
Future<bool> ensureLoggedIn(
  BuildContext context, {
  String message = 'Войдите, чтобы продолжить',
}) async {
  final state = context.read<AppState>();
  if (state.user != null) return true;

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Гостям доступны лента, афиша, транспорт, справочник и новости. Для избранного, подачи объявлений, жалоб и звонков нужен аккаунт.',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'login'),
              child: const Text('Войти'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'register'),
              child: const Text('Создать аккаунт'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Позже'),
            ),
          ],
        ),
      );
    },
  );
  if (!context.mounted || action == null) return false;
  if (action == 'login') {
    await Navigator.pushNamed(context, '/login');
  } else if (action == 'register') {
    await Navigator.pushNamed(context, '/register');
  }
  if (!context.mounted) return false;
  return context.read<AppState>().user != null;
}

class GuestCtaBanner extends StatelessWidget {
  const GuestCtaBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  child: const Text('Войти'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pushNamed(context, '/register'),
                  child: const Text('Создать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
