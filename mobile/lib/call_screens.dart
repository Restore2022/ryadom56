import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'call_service.dart';

class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  State<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends State<CallOverlayHost> {
  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_onCall);
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_onCall);
    super.dispose();
  }

  void _onCall() {
    if (!mounted) return;
    setState(() {});
    final svc = CallService.instance;
    if (svc.offerGsm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeGsmFallback(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = CallService.instance;
    final show = svc.phase != CallPhase.idle;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (show)
          const Positioned.fill(
            child: CallSessionScreen(),
          ),
      ],
    );
  }
}

class CallSessionScreen extends StatefulWidget {
  const CallSessionScreen({super.key});

  @override
  State<CallSessionScreen> createState() => _CallSessionScreenState();
}

class _CallSessionScreenState extends State<CallSessionScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (CallService.instance.phase == CallPhase.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CallService.instance,
      builder: (context, _) {
        final svc = CallService.instance;
        final call = svc.call;
        final incoming = svc.phase == CallPhase.incoming;
        final ended = svc.phase == CallPhase.ended;
        final name = incoming ? (call?.callerName ?? 'Звонок') : (call?.calleeName ?? 'Звонок');
        final title = call?.listingTitle ?? '';
        return Material(
          color: const Color(0xFF0E1A12),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: Column(
                children: [
                  Text(
                    incoming
                        ? 'Входящий звонок'
                        : ended
                            ? 'Звонок завершён'
                            : svc.phase == CallPhase.active
                                ? 'Разговор'
                                : 'Звоним…',
                    style: GoogleFonts.manrope(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF1F6B3A),
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: GoogleFonts.unbounded(fontSize: 36, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.unbounded(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(color: Colors.white60, fontSize: 15),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _subtitle(svc),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(color: Colors.white54, fontSize: 14),
                  ),
                  if (svc.lastError != null) ...[
                    const SizedBox(height: 10),
                    Text(svc.lastError!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFB4A8))),
                  ],
                  const Spacer(),
                  if (!ended && incoming)
                    Row(
                      children: [
                        Expanded(
                          child: _RoundAction(
                            color: const Color(0xFFB3261E),
                            icon: Icons.call_end,
                            label: 'Сбросить',
                            onTap: svc.decline,
                          ),
                        ),
                        const SizedBox(width: 28),
                        Expanded(
                          child: _RoundAction(
                            color: const Color(0xFF2E7D4F),
                            icon: Icons.call,
                            label: 'Ответить',
                            onTap: svc.accept,
                          ),
                        ),
                      ],
                    )
                  else if (!ended) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundAction(
                          color: svc.muted ? Colors.white24 : const Color(0xFF1C2B22),
                          icon: svc.muted ? Icons.mic_off : Icons.mic,
                          label: svc.muted ? 'Микрофон выкл' : 'Микрофон',
                          onTap: svc.toggleMute,
                        ),
                        _RoundAction(
                          color: svc.speaker ? const Color(0xFF1F6B3A) : const Color(0xFF1C2B22),
                          icon: svc.speaker ? Icons.volume_up : Icons.hearing,
                          label: svc.speaker ? 'Динамик' : 'К уху',
                          onTap: svc.toggleSpeaker,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _RoundAction(
                      color: const Color(0xFFB3261E),
                      icon: Icons.call_end,
                      label: 'Завершить',
                      onTap: () => svc.hangup(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _subtitle(CallService svc) {
    switch (svc.phase) {
      case CallPhase.outgoing:
        return 'Ожидание ответа';
      case CallPhase.incoming:
        return 'Звонок в приложении';
      case CallPhase.connecting:
        return 'Соединяем…';
      case CallPhase.active:
        final start = svc.connectedAt ?? DateTime.now();
        final sec = DateTime.now().difference(start).inSeconds.clamp(0, 24 * 3600);
        final m = (sec ~/ 60).toString().padLeft(2, '0');
        final s = (sec % 60).toString().padLeft(2, '0');
        return '$m:$s';
      case CallPhase.ended:
        return svc.endedBanner ?? 'Звонок завершён';
      case CallPhase.idle:
        return '';
    }
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.manrope(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

Future<void> startAppCall(
  BuildContext context, {
  required int listingId,
  int? calleeId,
  String? gsmPhone,
}) async {
  final svc = CallService.instance;
  final ok = await svc.startCall(listingId: listingId, calleeId: calleeId);
  if (!context.mounted) return;
  if (!ok && svc.lastError != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(svc.lastError!)));
    if (svc.lastError!.contains('занят') || svc.lastError!.contains('много')) return;
    await maybeGsmFallback(context, phone: gsmPhone, force: true);
  }
}

Future<void> maybeGsmFallback(BuildContext context, {String? phone, bool force = false}) async {
  final svc = CallService.instance;
  final number = phone ?? svc.call?.gsmPhone;
  if (number == null || number.isEmpty) return;
  if (!force && !svc.offerGsm) return;
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Позвонить на телефон?'),
      content: const Text(
        'В приложении сейчас не получилось. Можно набрать обычный номер — как запасной вариант.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Набрать')),
      ],
    ),
  );
  svc.offerGsm = false;
  if (go == true) {
    final cleaned = number.replaceAll(RegExp(r'[\s\-()]'), '');
    await launchUrl(Uri(scheme: 'tel', path: cleaned));
  }
}
