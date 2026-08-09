import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Красивый ввод PIN для разблокировки / быстрого входа.
class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key, this.asGate = true});

  /// true — корневой экран после запуска; false — с экрана логина.
  final bool asGate;

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> with TickerProviderStateMixin {
  String _pin = '';
  String? _error;
  bool _busy = false;
  late final AnimationController _shake;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  }

  @override
  void dispose() {
    _shake.dispose();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _onDigit(String d) async {
    if (_busy || _pin.length >= 5) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _pin += d;
    });
    if (_pin.length < 5) return;

    setState(() => _busy = true);
    final ok = await context.read<AppState>().unlockWithPin(_pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      if (widget.asGate) {
        // RootGate перерисуется сам (pinUnlocked).
        setState(() => _busy = false);
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
      return;
    }

    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _error = 'Неверный PIN';
      _pin = '';
      _busy = false;
    });
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() {
      _error = null;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  void _usePassword() {
    if (widget.asGate) {
      Navigator.pushNamed(context, '/login');
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    final scale = Tween(begin: 0.94, end: 1.0).animate(fade);

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Рядом56',
                    style: GoogleFonts.unbounded(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Введите PIN',
                    style: GoogleFonts.manrope(fontSize: 17, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(flex: 2),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      final t = Curves.elasticIn.transform(_shake.value);
                      final dx = (1 - t) * 12 * ((_shake.value * 8).floor().isEven ? 1 : -1);
                      return Transform.translate(offset: Offset(dx, 0), child: child);
                    },
                    child: _UnlockDots(filled: _pin.length, error: _error != null),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                  ],
                  const Spacer(flex: 3),
                  _UnlockPad(onDigit: _onDigit, onBackspace: _onBackspace, enabled: !_busy),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _usePassword,
                    child: const Text('Войти по паролю'),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockDots extends StatelessWidget {
  const _UnlockDots({required this.filled, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final on = i < filled;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: on ? 1.0 : 0.85),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? (error ? scheme.error : scheme.primary) : Colors.transparent,
              border: Border.all(
                color: error ? scheme.error : (on ? scheme.primary : scheme.outline),
                width: 2.2,
              ),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: (error ? scheme.error : scheme.primary).withValues(alpha: 0.28),
                        blurRadius: 10,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

// Reuse pad widgets from setup via private duplication kept minimal — import pad from setup file.
// setup file's pad is private; duplicate thin wrappers:

class _UnlockPad extends StatelessWidget {
  const _UnlockPad({required this.onDigit, required this.onBackspace, this.enabled = true});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Delegate to shared visual from PinSetupScreen file by embedding identical pad.
    return _SharedPinPad(onDigit: onDigit, onBackspace: onBackspace, enabled: enabled);
  }
}

/// Public-ish pad used by unlock (mirrors setup pad visuals).
class _SharedPinPad extends StatelessWidget {
  const _SharedPinPad({required this.onDigit, required this.onBackspace, this.enabled = true});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((label) {
              if (label.isEmpty) return const SizedBox(width: 76, height: 76);
              final isBack = label == '⌫';
              return _KeyBtn(
                enabled: enabled,
                onTap: () => isBack ? onBackspace() : onDigit(label),
                child: isBack
                    ? Icon(Icons.backspace_outlined, color: scheme.onSurface)
                    : Text(label, style: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w700)),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _KeyBtn extends StatefulWidget {
  const _KeyBtn({required this.child, required this.onTap, this.enabled = true});

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_KeyBtn> createState() => _KeyBtnState();
}

class _KeyBtnState extends State<_KeyBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: _pressed ? 0.18 : 0.08),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
