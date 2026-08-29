import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../state/app_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  static const _pageCount = 6;

  final page = PageController();
  int step = 0;
  int? settlementId;

  late final AnimationController blobs;
  late final AnimationController appear;

  @override
  void initState() {
    super.initState();
    blobs = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 720))..forward();
  }

  @override
  void dispose() {
    blobs.dispose();
    appear.dispose();
    page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await context.read<AppState>().completeOnboarding(settlementId: settlementId);
  }

  void _go(int index) {
    page.animateToPage(
      index.clamp(0, _pageCount - 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (step >= _pageCount - 1) {
      _finish();
      return;
    }
    _go(step + 1);
  }

  void _onPageChanged(int i) {
    setState(() => step = i);
    appear
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final landscape = context.isLandscape;
    final last = step >= _pageCount - 1;

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
          _FloatingBlobs(animation: blobs, color: scheme.primary),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: step > 0 ? 1 : 0,
                        child: TextButton(
                          onPressed: step > 0 ? () => _go(step - 1) : null,
                          child: const Text('Назад'),
                        ),
                      ),
                      const Spacer(),
                      if (!last)
                        TextButton(
                          onPressed: _finish,
                          child: const Text('Пропустить'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: page,
                    onPageChanged: _onPageChanged,
                    children: [
                      _TourSlide(
                        appear: appear,
                        icon: Icons.wb_sunny_outlined,
                        title: 'Рядом56',
                        body:
                            'Приложение Сакмарского района: объявления соседей, чаты, звонки, транспорт, места, афиша и новости — бесплатно, в одном месте.',
                      ),
                      _TourSlide(
                        appear: appear,
                        icon: Icons.campaign_outlined,
                        title: 'Лента объявлений',
                        body:
                            'На главной — то, что продают, отдают и ищут рядом. Плюс внизу экрана — подать своё. После проверки модератором объявление увидит весь район.',
                      ),
                      _TourSlide(
                        appear: appear,
                        icon: Icons.call_outlined,
                        title: 'Чаты и звонки',
                        body:
                            'Пишите автору объявления один на один. Голосовой звонок — из чата или карточки, через интернет, без записи разговора.',
                      ),
                      _TourSlide(
                        appear: appear,
                        icon: Icons.map_outlined,
                        title: 'Район под рукой',
                        body: 'Нижние вкладки и профиль — всё, чем пользуются каждый день.',
                        extra: _FeatureGrid(appear: appear),
                      ),
                      _VillageSlide(
                        appear: appear,
                        settlementId: settlementId,
                        onChanged: (v) => setState(() => settlementId = v),
                      ),
                      _TourSlide(
                        appear: appear,
                        icon: Icons.verified_user_outlined,
                        title: 'Можно начинать',
                        body:
                            'Ленту, афишу и транспорт смотрите сразу, без входа. Объявление — кнопка «Подать» на главной, после проверки модератором. Чтобы писать и звонить, войдите и поставьте PIN: чужие не откроют приложение с вашего телефона.',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, landscape ? 8 : 12, 24, landscape ? 12 : 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pageCount, (i) {
                          final on = i == step;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            width: on ? 22 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3.5),
                            decoration: BoxDecoration(
                              color: on ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }),
                      ),
                      SizedBox(height: landscape ? 12 : 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              last ? 'Начать' : 'Далее',
                              key: ValueKey(last),
                            ),
                          ),
                        ),
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
}

class _FloatingBlobs extends StatelessWidget {
  const _FloatingBlobs({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final a = animation.value * 2 * math.pi;
          return Stack(
            children: [
              Positioned(
                top: -90 + 18 * math.sin(a),
                right: -70 + 14 * math.cos(a),
                child: _blob(240, color.withValues(alpha: 0.16)),
              ),
              Positioned(
                bottom: 40 + 22 * math.cos(a * 0.8),
                left: -110 + 10 * math.sin(a * 0.9),
                child: _blob(300, color.withValues(alpha: 0.10)),
              ),
              Positioned(
                top: 210 + 12 * math.sin(a * 1.3),
                left: -40,
                child: _blob(120, color.withValues(alpha: 0.08)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _blob(double size, Color c) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = context.isLandscape ? 72.0 : 112.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.16),
            scheme.primary.withValues(alpha: 0.34),
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
      child: Icon(icon, size: size * 0.42, color: scheme.primary),
    );
  }
}

class _Appear extends StatelessWidget {
  const _Appear({
    required this.controller,
    required this.child,
    this.begin = 0,
    this.dy = 0.10,
  });

  final AnimationController controller;
  final Widget child;
  final double begin;
  final double dy;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(0, dy), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

class _TourSlide extends StatelessWidget {
  const _TourSlide({
    required this.appear,
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });

  final AnimationController appear;
  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final landscape = context.isLandscape;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1).animate(
                    CurvedAnimation(parent: appear, curve: Curves.easeOutBack),
                  ),
                  child: FadeTransition(
                    opacity: appear,
                    child: _IconBadge(icon: icon),
                  ),
                ),
                SizedBox(height: landscape ? 16 : 28),
                _Appear(
                  controller: appear,
                  begin: 0.12,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.unbounded(
                      fontSize: landscape ? 22 : 26,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                SizedBox(height: landscape ? 10 : 14),
                _Appear(
                  controller: appear,
                  begin: 0.22,
                  dy: 0.08,
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                      fontSize: landscape ? 14 : 15.5,
                    ),
                  ),
                ),
                if (extra != null) ...[
                  SizedBox(height: landscape ? 14 : 22),
                  extra!,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.appear});
  final AnimationController appear;

  static const _items = [
    (Icons.directions_bus_outlined, 'Транспорт', 'Рейсы по сёлам'),
    (Icons.storefront_outlined, 'Места', 'Справочник района'),
    (Icons.event_outlined, 'Афиша', 'Концерты и события'),
    (Icons.notifications_outlined, 'Новости', 'Срочное — в колокольчике'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Appear(
      controller: appear,
      begin: 0.32,
      dy: 0.06,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < _items.length; i++)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 140, maxWidth: 168),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
                ),
                child: Row(
                  children: [
                    Icon(_items[i].$1, color: scheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _items[i].$2,
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13.5),
                          ),
                          Text(
                            _items[i].$3,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.2),
                          ),
                        ],
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

class _VillageSlide extends StatelessWidget {
  const _VillageSlide({
    required this.appear,
    required this.settlementId,
    required this.onChanged,
  });

  final AnimationController appear;
  final int? settlementId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final landscape = context.isLandscape;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1).animate(
                    CurvedAnimation(parent: appear, curve: Curves.easeOutBack),
                  ),
                  child: FadeTransition(
                    opacity: appear,
                    child: const _IconBadge(icon: Icons.place_outlined),
                  ),
                ),
                SizedBox(height: landscape ? 16 : 28),
                _Appear(
                  controller: appear,
                  begin: 0.12,
                  child: Text(
                    'Ваше село',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.unbounded(
                      fontSize: landscape ? 22 : 26,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                SizedBox(height: landscape ? 10 : 14),
                _Appear(
                  controller: appear,
                  begin: 0.22,
                  child: Text(
                    'Покажем транспорт, афишу и новости ближе к вам. Потом можно сменить в профиле.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                      fontSize: landscape ? 14 : 15.5,
                    ),
                  ),
                ),
                SizedBox(height: landscape ? 16 : 24),
                _Appear(
                  controller: appear,
                  begin: 0.34,
                  dy: 0.05,
                  child: DropdownButtonFormField<int?>(
                    value: settlementId != null && state.settlements.any((s) => s['id'] == settlementId)
                        ? settlementId
                        : null,
                    isExpanded: true,
                    isDense: landscape,
                    decoration: const InputDecoration(
                      labelText: 'Населённый пункт',
                      prefixIcon: Icon(Icons.place_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Весь район')),
                      ...state.settlements.map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as int,
                          child: Text(
                            s['display_name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
