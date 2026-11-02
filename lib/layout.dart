import 'package:flutter/material.dart';

// Material 3 window size classes: compact < 600 ≤ medium < 1200 (here) ≤ expanded.

/// Wide windows get a side navigation rail instead of a bottom bar.
bool useRail(Size screen) => screen.width >= 600;

/// Height the bottom navigation bar takes (0 when the rail is used).
double bottomBarHeight(BuildContext context) {
  final mq = MediaQuery.of(context);
  if (useRail(mq.size)) return 0;
  return (NavigationBarTheme.of(context).height ?? 80) + mq.padding.bottom; // NavigationBar's own default
}

/// Card width in the sideways rows; bigger cards on bigger windows.
double cardWidthFor(Size screen) => screen.width < 600 ? 220 : (screen.width < 1200 ? 240 : 280);

/// Height of the text under a card's 16:9 tile, following the system text size.
double cardTextHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context);
  double line(double fontSize) => scale.scale(fontSize) * 1.5; // ≈ Roboto line height, rounded up
  return 8 + line(14) + 2 + line(12) + 2; // gap, name, gap, subtitle, slack
}

double cardHeightFor(BuildContext context, double width) => width * 9 / 16 + cardTextHeight(context);
