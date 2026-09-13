import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// A section heading with an explanatory tooltip.
///
/// The ⓘ icon is the *visible* hint that help is available — a tooltip nobody knows to
/// look for is not an affordance. It opens on hover for pointer users and on tap for
/// touch users, and carries a semantics label for screen readers.
class InfoHeading extends StatelessWidget {
  const InfoHeading({
    super.key,
    required this.title,
    required this.help,
    this.style,
  });

  final String title;
  final String help;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: style ?? const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 6),
        InfoHint(help: help, label: title),
      ],
    );
  }
}

/// The ⓘ affordance on its own, for placing next to a control rather than a heading.
class InfoHint extends StatelessWidget {
  const InfoHint({super.key, required this.help, required this.label});

  final String help;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: help,
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: const Duration(milliseconds: 200),
      showDuration: const Duration(seconds: 20),
      preferBelow: true,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      textStyle: const TextStyle(color: Colors.white, height: 1.35),
      child: Icon(
        Icons.info_outline,
        size: 16,
        color: Palette.mutedInk,
        semanticLabel: 'About $label: $help',
      ),
    );
  }
}
