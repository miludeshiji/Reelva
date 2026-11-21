import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Reelva brand logo with rounded corners.
class ReelvaLogo extends StatelessWidget {
  const ReelvaLogo({
    super.key,
    this.size = 40.0,
    this.excludeFromSemantics = false,
  });

  /// The dimension (width and height) of the logo in logical pixels.
  final double size;

  /// Whether to exclude this logo from the semantics tree to avoid duplication.
  final bool excludeFromSemantics;

  static const String assetPath = 'assets/Reelva.svg';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticsLabel: excludeFromSemantics ? null : 'Reelva',
        excludeFromSemantics: excludeFromSemantics,
      ),
    );
  }
}
