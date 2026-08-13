import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../pin_storage.dart';
import '../state/app_state.dart';

/// Обязательная настройка 5-значного PIN (защита входа в аккаунт на устройстве).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, this.allowSkip = false});

  final bool allowSkip;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> with SingleTickerProviderStateMixin {
  String _first = '';
  String _confirm = '';
  bool _confirming = false;
  String? _error;
  bool _busy = false;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  String get _current => _confirming ? _confirm : _first;

  Future<void> _onDigit(String d) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      if (_confirming) {
        if (_confirm.length < 5) _confirm += d;
      } else {
        if (_first.length < 5) _first += d;
      }
    });
    final value = _confirming ? _confirm : _first;
    if (value.length < 5) return;

    if (!_confirming) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() {
        _confirming = true;
        _confirm = '';
      });
      return;
    }

    if (_confirm != _first) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _error = 'Коды не совпали. Попробуйте ещё раз';
        _confirming = false;
        _first = '';
        _confirm = '';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      await PinStorage.setPin(_first);
      if (!mounted) return;
      final state = context.read<AppState>();
      final token = await state.api.token;
      await PinStorage.saveSessionToken(token);
      if (!mounted) return;
      state.hasPin = true;
      state.markPinUnlocked();
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось сохранить PIN';
          _busy = false;
        });
      }
    }
  }

  void _onBackspace() {
    if (_busy) return;
    setState(() {
      _error = null;
      if (_confirming) {
        if (_confirm.isNotEmpty) {
          _confirm = _confirm.substring(0, _confirm.length - 1);
        } else {
          _confirming = false;
        }
      } else if (_first.isNotEmpty) {
        _first = _first.substring(0, _first.length - 1);
      }
    });
  }

  Future<void> _skip() async {
    if (!widget.allowSkip || _busy) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _confirming ? 'Повторите PIN' : 'Придумайте PIN';
    final subtitle = _confirming
        ? 'Введите тот же код ещё раз'
        : '5 цифр — чтобы посторонние не открыли ваш аккаунт на этом телефоне';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Рядом56',
                  style: GoogleFonts.unbounded(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              const Spacer(flex: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
                ),
                child: Column(
                  key: ValueKey(_confirming),
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.unbounded(fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(fontSize: 16, height: 1.35, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = Curves.elasticIn.transform(_shake.value);
                  final dx = (1 - t) * 10 * ((_shake.value * 8).floor().isEven ? 1 : -1);
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: _PinDots(filled: _current.length, error: _error != null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
              ],
              const Spacer(flex: 3),
              _PinPad(onDigit: _onDigit, onBackspace: _onBackspace, enabled: !_busy),
              if (widget.allowSkip) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : _skip, child: const Text('Не сейчас')),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filled, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final on = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: on ? 16 : 14,
          height: on ? 16 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? (error ? scheme.error : scheme.primary) : Colors.transparent,
            border: Border.all(
              color: error ? scheme.error : (on ? scheme.primary : scheme.outline),
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onBackspace, this.enabled = true});

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
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((label) {
              if (label.isEmpty) return const SizedBox(width: 76, height: 76);
              final isBack = label == '⌫';
              return _PinKey(
                label: isBack ? null : label,
                icon: isBack ? Icons.backspace_outlined : null,
                enabled: enabled,
                onTap: () {
                  if (isBack) {
                    onBackspace();
                  } else {
                    onDigit(label);
                  }
                },
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _PinKey extends StatefulWidget {
  const _PinKey({this.label, this.icon, required this.onTap, this.enabled = true});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
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
            child: widget.icon != null
                ? Icon(widget.icon, color: scheme.onSurface)
                : Text(
                    widget.label ?? '',
                    style: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}
