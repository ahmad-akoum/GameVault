import 'package:flutter/material.dart';

/// Keep controls in their familiar row when there is room; stack them when
/// their local panel is narrow, including inside dialogs.
class AdaptiveRow extends StatelessWidget {
  const AdaptiveRow({
    super.key,
    required this.children,
    this.breakpoint = 600,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });
  final List<Widget> children;
  final double breakpoint;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= breakpoint) {
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          mainAxisAlignment: mainAxisAlignment,
          children: children,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            if (child is! Spacer && !(child is SizedBox && child.child == null))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: child is Flexible ? child.child : child,
              ),
        ],
      );
    },
  );
}

/// At narrow widths the page's controls and results share one vertical scroll,
/// so a tall filter panel cannot consume the whole results viewport.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      }
      return ListView(
        children: [
          for (final child in children) child is Expanded ? child.child : child,
        ],
      );
    },
  );
}
