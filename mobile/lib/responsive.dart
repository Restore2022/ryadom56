import 'package:flutter/material.dart';

/// Адаптация под телефоны (портрет/альбом) и планшеты.
class RyadomBreakpoints {
  static const double tabletShortest = 600;
  static const double contentMax = 720;
}

extension RyadomResponsive on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);

  bool get isLandscape => MediaQuery.orientationOf(this) == Orientation.landscape;

  bool get isTablet => screenSize.shortestSide >= RyadomBreakpoints.tabletShortest;

  /// Боковое меню вместо нижней панели — планшет и любой альбом (больше места по вертикали).
  bool get useNavigationRail => isTablet || isLandscape;

  EdgeInsets get pagePadding {
    final h = isLandscape ? 12.0 : 16.0;
    final v = isLandscape ? 6.0 : 12.0;
    return EdgeInsets.fromLTRB(h, v, h, v);
  }

  /// Запас под последней карточкой. Scaffold уже поднимает body над NavigationBar —
  /// большой отступ (100+) давал пустоту; оставляем только «воздух».
  double get listBottomPad {
    final safe = MediaQuery.paddingOf(this).bottom;
    if (useNavigationRail) return 20 + safe * 0.25;
    return 20 + safe * 0.25;
  }

  /// Ограничение ширины контента на больших экранах.
  Widget constrainContent(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, RyadomBreakpoints.contentMax)
            : RyadomBreakpoints.contentMax;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: w, child: child),
        );
      },
    );
  }
}

/// Пустое / ошибочное состояние с высотой от доступного пространства.
Widget adaptiveFillMessage({
  required BuildContext context,
  required Widget child,
  double minHeight = 180,
}) {
  final h = MediaQuery.sizeOf(context).height;
  final target = (h * 0.45).clamp(minHeight, 360.0);
  return SizedBox(height: target, child: child);
}
