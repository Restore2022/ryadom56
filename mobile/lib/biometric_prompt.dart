import 'package:flutter/material.dart';

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
  await context.readAppState().setBiometricsEnabled(true);
}

extension _ReadApp on BuildContext {
  AppState readAppState() {
    // imported via provider in callers; keep this file free of provider import cycle
    return AppState.of(this);
  }
}
