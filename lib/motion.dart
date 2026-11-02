import 'package:flutter/material.dart';

// Material 3 motion: short (150–200 ms) for small feedback, medium (250–300 ms)
// for things entering the screen; emphasized-decelerate easing for entrances.

/// [d], or zero when the OS asks for reduced motion.
Duration motion(BuildContext context, Duration d) => MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;

/// Image.frameBuilder that fades network images in instead of popping in.
Widget fadeInFrame(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
  if (wasSynchronouslyLoaded) return child; // already cached: no fade
  return AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: motion(context, Durations.short4), curve: Easing.standard, child: child);
}

/// Fades and rises [child] in once, after [delay]. Used to stagger the first
/// appearance of a screen's content.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Durations.medium2);
  late final _a = CurvedAnimation(parent: _c, curve: Easing.emphasizedDecelerate);
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = 1;
    } else if (!_scheduled) {
      _scheduled = true;
      Future.delayed(widget.delay, () => mounted ? _c.forward() : null);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_a),
      child: widget.child,
    ),
  );
}
