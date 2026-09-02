import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../settlement_picker.dart';
import '../state/app_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  int? settlementId;
  late final AnimationController blobs;

  @override
  void initState() {
    super.initState();
    blobs = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    blobs.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await context.read<AppState>().completeOnboarding(settlementId: settlementId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final landscape = context.isLandscape;
    return Scaffold(
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface,
                  scheme.primary.withValues(alpha: 0.08),
                  scheme.surface,
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          AnimatedBuilder(
            animation: blobs,
            builder: (context, _) {
              final t = blobs.value * 2 * math.pi;
              return Stack(
                children: [
                  Positioned(
                    left: -40 + 12 * math.sin(t),
                    top: 80 + 18 * math.cos(t * 0.7),
                    child: _Blob(color: scheme.primary.withValues(alpha: 0.10), size: 180),
                  ),
                  Positioned(
                    right: -30 + 10 * math.cos(t),
                    bottom: 120 + 16 * math.sin(t * 0.8),
                    child: _Blob(color: scheme.primary.withValues(alpha: 0.08), size: 150),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, landscape ? 12 : 24, 24, landscape ? 12 : 20),
              child: Column(
                children: [
                  Text(
                    'Рядом56',
                    style: GoogleFonts.unbounded(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.place_outlined, size: 56, color: scheme.primary),
                            const SizedBox(height: 20),
                            Text(
                              'Ваше село',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.unbounded(fontSize: 26, fontWeight: FontWeight.w600, height: 1.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Покажем объявления ближе к вам. Потом можно сменить в шапке ленты.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45, fontSize: 15.5),
                            ),
                            const SizedBox(height: 24),
                            SettlementPicker(
                              value: settlementId != null && state.settlements.any((s) => s['id'] == settlementId)
                                  ? settlementId
                                  : null,
                              settlements: state.settlements,
                              allowAll: true,
                              allLabel: 'Вся область',
                              onChanged: (v) => setState(() => settlementId = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _finish,
                      child: const Text('Смотреть ленту'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
