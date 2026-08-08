import 'package:flutter/material.dart';

import 'api.dart';
import 'state/app_state.dart';

String friendlyError(Object e, {String? context}) {
  if (e is ApiException) {
    if (context == 'login' && (e.statusCode == 401 || e.message.toLowerCase().contains('неверн'))) {
      return 'Неверный email или пароль';
    }
    if (context == 'register' && e.statusCode == 400) {
      return e.message;
    }
    return e.message;
  }
  return AppState.userFriendlyError(e);
}

bool isValidEmail(String value) {
  final v = value.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
}

Widget emptyState({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData icon = Icons.inbox_outlined,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    ),
  );
}

Widget errorState({
  required BuildContext context,
  required String message,
  VoidCallback? onRetry,
}) {
  return emptyState(
    context: context,
    title: message,
    icon: Icons.wifi_off_outlined,
    actionLabel: onRetry != null ? 'Повторить' : null,
    onAction: onRetry,
  );
}

void showAppSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
