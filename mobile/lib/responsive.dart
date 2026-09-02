import 'dart:math' as math;

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

  /// Системная панель снизу: три кнопки Android или полоска жестов.
  /// Берётся с устройства, меняется при повороте. При открытой клавиатуре 0 —
  /// Scaffold уже поднял экран.
  double get systemBottomInset {
    final mq = MediaQuery.of(this);
    if (mq.viewInsets.bottom > 40) return 0;
    return math.max(mq.padding.bottom, mq.viewPadding.bottom);
  }

  /// Отступ списка на полном экране (без нижней панели приложения).
  /// Слева/справа — вырез и кнопки в альбоме.
  EdgeInsets scrollPad({
    double left = 16,
    double top = 8,
    double right = 16,
    double bottom = 20,
  }) {
    final p = MediaQuery.paddingOf(this);
    return EdgeInsets.fromLTRB(
      left + p.left,
      top,
      right + p.right,
      bottom + systemBottomInset,
    );
  }

  /// Запас под последней карточкой во вкладках.
  /// Портрет: NavigationBar сам сидит над системными кнопками.
  /// Альбом / планшет: боковое меню, снизу нужен системный зазор.
  double get listBottomPad {
    const extra = 20.0;
    if (useNavigationRail) return extra + systemBottomInset;
    return extra;
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
