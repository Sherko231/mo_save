import 'package:flutter/material.dart';

/// Keep long RTL finance screens in place at their scroll boundaries.
/// Android's Material overscroll stretching can briefly expose an empty
/// canvas during a hard downward drag, especially around expensive widgets.
class MoSaveScrollBehavior extends MaterialScrollBehavior {
  const MoSaveScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
