import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../biometric_prompt.dart';
import '../biometric_service.dart';
import '../state/app_state.dart';
import 'pin_setup_screen.dart';

/// Вход по отпечатку / лицу, PIN — запасной способ.
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
  bool _bioEnabled = false;
  bool _bioAvailable = false;
  bool _showPinPad = true;
  String _bioButton = 'Войти по отпечатку или лицу';
  IconData _bioIcon = Icons.fingerprint;
  late final AnimationController _shake;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareBiometrics());
  }

  @override
  void dispose() {
    _shake.dispose();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _prepareBiometrics() async {
    final state = context.read<AppState>();
    await state.refreshBiometricsState();
    if (!mounted) return;
    final available = state.biometricsAvailable;
    final enabled = state.biometricsEnabled;
    setState(() {
      _bioAvailable = available;
      _bioEnabled = enabled;
      _showPinPad = !enabled;
    });
    if (available) {
      _bioButton = await BiometricService.buttonLabel();
      _bioIcon = await BiometricService.icon();
      if (mounted) setState(() {});
    }
    if (_bioEnabled && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (mounted) await _unlockWithBiometrics();
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<AppState>().unlockWithBiometrics();
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      if (!widget.asGate) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        return;
      }
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      _showPinPad = true;
    });
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

  Future<void> _forgotPin() async {
    if (_busy) return;
    final ok = await confirmAccountPassword(context, title: 'Сброс PIN');
    if (!ok || !mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(mode: PinSetupMode.reset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    final scale = Tween(begin: 0.94, end: 1.0).animate(fade);
    final subtitle = _bioEnabled && !_showPinPad
        ? 'Войдите по отпечатку или лицу.\nPIN — запасной способ.'
        : _bioEnabled
            ? 'Введите PIN, если биометрия не сработала'
            : 'Введите PIN для доступа';

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
                    subtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(fontSize: 17, height: 1.3, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(flex: 2),
                  if (_bioEnabled && !_showPinPad) ...[
                    const Spacer(flex: 1),
                    Material(
                      color: scheme.primary.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _busy ? null : _unlockWithBiometrics,
                        child: SizedBox(
                          width: 132,
                          height: 132,
                          child: Icon(_bioIcon, size: 64, color: scheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _unlockWithBiometrics,
                      child: Text(_bioButton),
                    ),
                    const Spacer(flex: 3),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _showPinPad = true;
                                _error = null;
                              }),
                      child: const Text('Ввести PIN'),
                    ),
                  ] else ...[
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
                    _UnlockPad(
                      onDigit: _onDigit,
                      onBackspace: _onBackspace,
                      onBiometric: _bioEnabled ? _unlockWithBiometrics : null,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 8),
                    if (_bioEnabled)
                      TextButton(
                        onPressed: _busy ? null : _unlockWithBiometrics,
                        child: Text(_bioButton),
                      ),
                    if (_bioAvailable && !_bioEnabled)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await offerBiometricsIfAvailable(context);
                                if (!mounted) return;
                                await _prepareBiometrics();
                              },
                        child: const Text('Включить отпечаток или лицо'),
                      ),
                  ],
                  TextButton(
                    onPressed: _busy ? null : _usePassword,
                    child: const Text('Войти по паролю'),
                  ),
                  if (_showPinPad)
                    TextButton(
                      onPressed: _busy ? null : _forgotPin,
                      child: const Text('Забыли PIN?'),
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

class _UnlockPad extends StatelessWidget {
  const _UnlockPad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _SharedPinPad(
      onDigit: onDigit,
      onBackspace: onBackspace,
      onBiometric: onBiometric,
      enabled: enabled,
    );
  }
}

class _SharedPinPad extends StatelessWidget {
  const _SharedPinPad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['bio', '0', '⌫'],
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((label) {
              if (label == 'bio') {
                if (onBiometric == null) return const SizedBox(width: 76, height: 76);
                return _KeyBtn(
                  enabled: enabled,
                  onTap: onBiometric!,
                  child: Icon(Icons.fingerprint, color: scheme.primary, size: 32),
                );
              }
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
