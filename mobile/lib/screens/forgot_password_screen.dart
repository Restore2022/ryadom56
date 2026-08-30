import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> with TickerProviderStateMixin {
  final email = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final codeFocus = FocusNode();

  int step = 0;
  bool busy = false;
  bool obscure = true;
  String? error;
  int resendIn = 0;
  Timer? _resendTimer;

  late final AnimationController blobs;
  late final AnimationController appear;
  late final AnimationController pulse;
  late final AnimationController send;

  @override
  void initState() {
    super.initState();
    email.text = widget.initialEmail?.trim() ?? '';
    blobs = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 640))..forward();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    send = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    email.dispose();
    code.dispose();
    password.dispose();
    confirm.dispose();
    codeFocus.dispose();
    blobs.dispose();
    appear.dispose();
    pulse.dispose();
    send.dispose();
    super.dispose();
  }

  void _go(int next) {
    setState(() {
      step = next;
      error = null;
    });
    appear
      ..reset()
      ..forward();
    if (next == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) codeFocus.requestFocus();
      });
    }
  }

  void _startResendClock() {
    _resendTimer?.cancel();
    setState(() => resendIn = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (resendIn <= 1) {
        t.cancel();
        setState(() => resendIn = 0);
      } else {
        setState(() => resendIn -= 1);
      }
    });
  }

  Future<void> _sendCode({bool again = false}) async {
    final mail = email.text.trim();
    if (!isValidEmail(mail)) {
      setState(() => error = 'Введите почту, как при регистрации');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await send.forward(from: 0);
      await context.read<AppState>().requestPasswordReset(mail);
      if (!mounted) return;
      _startResendClock();
      if (!again) {
        _go(1);
      } else {
        showAppSnack(context, 'Код отправили ещё раз. Проверьте почту');
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) {
        send.reset();
        setState(() => busy = false);
      }
    }
  }

  Future<void> _savePassword() async {
    final mail = email.text.trim();
    final rawCode = code.text.trim();
    final pass = password.text;
    if (rawCode.length != 6) {
      setState(() => error = 'Введите все 6 цифр из письма');
      return;
    }
    if (pass.length < 6) {
      setState(() => error = 'Пароль не короче 6 символов');
      return;
    }
    if (pass != confirm.text) {
      setState(() => error = 'Пароли не совпадают');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<AppState>().confirmPasswordReset(
            email: mail,
            code: rawCode,
            password: pass,
          );
      if (!mounted) return;
      _go(3);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _next() async {
    if (busy) return;
    if (step == 0) {
      await _sendCode();
      return;
    }
    if (step == 1) {
      if (code.text.trim().length != 6) {
        setState(() => error = 'Введите все 6 цифр из письма');
        return;
      }
      _go(2);
      return;
    }
    if (step == 2) {
      await _savePassword();
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  String get _title {
    switch (step) {
      case 0:
        return 'Забыли пароль?';
      case 1:
        return 'Код из письма';
      case 2:
        return 'Новый пароль';
      default:
        return 'Готово';
    }
  }

  String get _body {
    switch (step) {
      case 0:
        return 'Напишите почту, с которой входили. Пришлём короткий код — без него пароль не сменить.';
      case 1:
        return 'Открыли письмо от Рядом56? Введите шесть цифр. Код живёт 20 минут.';
      case 2:
        return 'Придумайте пароль не короче 6 символов и повторите его.';
      default:
        return 'Пароль обновлён. Войдите с новым — старый больше не подойдёт.';
    }
  }

  String get _button {
    if (busy) {
      if (step == 0) return 'Отправляем…';
      if (step == 2) return 'Сохраняем…';
      return 'Дальше…';
    }
    switch (step) {
      case 0:
        return 'Прислать код';
      case 1:
        return 'Дальше';
      case 2:
        return 'Сохранить пароль';
      default:
        return 'Войти';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = step >= 3;

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
                  scheme.primary.withValues(alpha: 0.10),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          _SoftBlobs(animation: blobs, color: scheme.primary),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Назад',
                        onPressed: busy
                            ? null
                            : () {
                                if (step == 0 || last) {
                                  Navigator.maybePop(context);
                                  return;
                                }
                                _go(step - 1);
                              },
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Spacer(),
                      if (!last)
                        TextButton(
                          onPressed: busy ? null : () => Navigator.maybePop(context),
                          child: const Text('Отмена'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Row(
                    children: List.generate(4, (i) {
                      final on = i == step;
                      final done = i < step;
                      return Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          height: 6,
                          margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: done || on
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      _HeroMark(
                        step: step,
                        appear: appear,
                        pulse: pulse,
                        send: send,
                      ),
                      const SizedBox(height: 22),
                      _FadeSlide(
                        controller: appear,
                        begin: 0.08,
                        child: Text(
                          _title,
                          style: GoogleFonts.unbounded(fontSize: 26, fontWeight: FontWeight.w700, height: 1.15),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _FadeSlide(
                        controller: appear,
                        begin: 0.16,
                        child: Text(
                          _body,
                          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 26),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.04, 0.06),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(step),
                          child: _stepBody(scheme),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Text(error!, style: TextStyle(color: scheme.error, height: 1.35)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : _next,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(_button, key: ValueKey(_button)),
                          ),
                        ),
                      ),
                      if (step == 1) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: busy || resendIn > 0 ? null : () => _sendCode(again: true),
                          child: Text(resendIn > 0 ? 'Ещё раз через $resendIn с' : 'Прислать код ещё раз'),
                        ),
                      ],
                      if (error != null &&
                          (error == AppState.offlineMessage ||
                              error == ApiClient.noInternetMessage ||
                              error == ApiClient.serverUnreachableMessage ||
                              error!.contains('связи') ||
                              error!.contains('интернет')))
                        OutlinedButton(
                          onPressed: busy ? null : _next,
                          child: const Text('Повторить'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(ColorScheme scheme) {
    if (step == 0) {
      return TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        enabled: !busy,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _next(),
        decoration: const InputDecoration(labelText: 'Почта'),
      );
    }
    if (step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email.text.trim(),
            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _CodeBoxes(
            controller: code,
            focusNode: codeFocus,
            enabled: !busy,
            onFilled: () => _go(2),
          ),
        ],
      );
    }
    if (step == 2) {
      return Column(
        children: [
          TextField(
            controller: password,
            obscureText: obscure,
            enabled: !busy,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Новый пароль',
              suffixIcon: IconButton(
                onPressed: busy ? null : () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirm,
            obscureText: obscure,
            enabled: !busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _next(),
            decoration: const InputDecoration(labelText: 'Повторите пароль'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _HeroMark extends StatelessWidget {
  const _HeroMark({
    required this.step,
    required this.appear,
    required this.pulse,
    required this.send,
  });

  final int step;
  final AnimationController appear;
  final AnimationController pulse;
  final AnimationController send;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (step) {
      0 => Icons.mark_email_unread_outlined,
      1 => Icons.pin_outlined,
      2 => Icons.lock_reset_outlined,
      _ => Icons.check_rounded,
    };

    return AnimatedBuilder(
      animation: Listenable.merge([appear, pulse, send]),
      builder: (context, _) {
        final fly = Curves.easeInOutCubic.transform(send.value);
        final pop = Curves.easeOutBack.transform(appear.value.clamp(0.0, 1.0));
        final breathe = 1 + 0.04 * math.sin(pulse.value * math.pi);
        return Transform.translate(
          offset: Offset(0, -18 * fly),
          child: Opacity(
            opacity: (1 - fly * 0.35).clamp(0.2, 1),
            child: Transform.scale(
              scale: (0.86 + 0.14 * pop) * (step == 3 ? 1 : breathe),
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.16),
                      scheme.primary.withValues(alpha: 0.36),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Icon(icon, key: ValueKey(icon), size: 48, color: scheme.primary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CodeBoxes extends StatefulWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onFilled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onFilled;

  @override
  State<_CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<_CodeBoxes> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.focusNode.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    widget.focusNode.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final raw = widget.controller.text;
    final digits = raw.padRight(6).substring(0, 6);

    return GestureDetector(
      onTap: widget.enabled ? () => widget.focusNode.requestFocus() : null,
      child: Stack(
        children: [
          SizedBox(
            height: 56,
            child: Opacity(
              opacity: 0.02,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                onChanged: (v) {
                  if (v.length == 6) widget.onFilled();
                },
              ),
            ),
          ),
          IgnorePointer(
            child: Row(
              children: List.generate(6, (i) {
                final ch = digits[i];
                final filled = RegExp(r'\d').hasMatch(ch);
                final active = raw.length == i && widget.focusNode.hasFocus;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 56,
                    margin: EdgeInsets.only(right: i == 5 ? 0 : 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).inputDecorationTheme.fillColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        width: active || filled ? 1.6 : 1,
                        color: active
                            ? scheme.primary
                            : filled
                                ? scheme.primary.withValues(alpha: 0.45)
                                : scheme.outlineVariant,
                      ),
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      style: GoogleFonts.unbounded(
                        fontSize: filled ? 22 : 18,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      child: Text(filled ? ch : '·'),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  const _FadeSlide({
    required this.controller,
    required this.child,
    this.begin = 0,
  });

  final AnimationController controller;
  final Widget child;
  final double begin;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

class _SoftBlobs extends StatelessWidget {
  const _SoftBlobs({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final a = animation.value * 2 * math.pi;
          Widget blob(double size, Color c) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            );
          }

          return Stack(
            children: [
              Positioned(
                top: -90 + 18 * math.sin(a),
                right: -70 + 14 * math.cos(a),
                child: blob(240, color.withValues(alpha: 0.16)),
              ),
              Positioned(
                bottom: 40 + 22 * math.cos(a * 0.8),
                left: -110 + 10 * math.sin(a * 0.9),
                child: blob(300, color.withValues(alpha: 0.10)),
              ),
            ],
          );
        },
      ),
    );
  }
}
