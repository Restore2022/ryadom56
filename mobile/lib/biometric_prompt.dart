import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'biometric_service.dart';
import 'pin_storage.dart';
import 'state/app_state.dart';

Future<void> offerBiometricsIfAvailable(BuildContext context) async {
  final available = await BiometricService.isAvailable();
  if (!available || !context.mounted) return;
  if (await PinStorage.biometricsEnabled()) return;
  final by = await BiometricService.label();
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Быстрый вход'),
      content: Text('Входить по $by? PIN останется запасным способом, если биометрия не сработает.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Только PIN')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Включить')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final passed = await BiometricService.authenticate(reason: 'Подтвердите, чтобы включить вход по $by');
  if (!passed || !context.mounted) return;
  await context.read<AppState>().setBiometricsEnabled(true);
}

Future<bool> confirmAccountPassword(BuildContext context, {String title = 'Пароль аккаунта'}) async {
  final controller = TextEditingController();
  var obscure = true;
  String? error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Введите пароль от аккаунта, чтобы продолжить.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    errorText: error,
                    suffixIcon: IconButton(
                      onPressed: () => setLocal(() => obscure = !obscure),
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Продолжить')),
            ],
          );
        },
      );
    },
  );
  final password = controller.text;
  controller.dispose();
  if (confirmed != true || password.isEmpty) return false;
  if (!context.mounted) return false;
  try {
    await context.read<AppState>().verifyAccountPassword(password);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppState.userFriendlyError(e))),
      );
    }
    return false;
  }
}
