import 'package:flutter/material.dart';

/// Кнопка «наверх» для длинных списков.
class ScrollToTopFab extends StatefulWidget {
  const ScrollToTopFab({
    super.key,
    required this.controller,
    this.showAfter = 280,
    this.heroTag,
  });

  final ScrollController controller;
  final double showAfter;
  final Object? heroTag;

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(covariant ScrollToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _onScroll();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final next = widget.controller.offset >= widget.showAfter;
    if (next != _visible && mounted) setState(() => _visible = next);
  }

  Future<void> _goTop() async {
    if (!widget.controller.hasClients) return;
    await widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedScale(
        scale: _visible ? 1 : 0.85,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: FloatingActionButton.small(
            heroTag: widget.heroTag ?? 'scroll-to-top',
            tooltip: 'Наверх',
            onPressed: _goTop,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            elevation: 3,
            child: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
          ),
        ),
      ),
    );
  }
}

/// Список + кнопка «наверх» поверх него.
Widget stackWithScrollToTop({
  required ScrollController controller,
  required Widget child,
  Object? heroTag,
  double bottom = 18,
  double right = 16,
  double showAfter = 280,
}) {
  return Stack(
    children: [
      child,
      Positioned(
        right: right,
        bottom: bottom,
        child: ScrollToTopFab(
          controller: controller,
          heroTag: heroTag,
          showAfter: showAfter,
        ),
      ),
    ],
  );
}
