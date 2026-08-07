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
              'Гостям доступен просмотр ленты и справочника. Для звонков, избранного и объявлений нужен аккаунт.',
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
