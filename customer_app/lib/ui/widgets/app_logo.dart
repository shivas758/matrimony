import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// The Wedbook Matrimony logo (SPEC §9.18 A): the rounded wine tile with the
/// two interlocked gold rings and the gold wordmark "Wedbook / Matrimony" —
/// or, below [compactBelow] px where the wordmark can no longer be read, the
/// tile with the rings alone. Rendered by `tool/gen_logo.mjs` from
/// `assets/logo/wedbook_matrimony_source.jpg` into these assets and every
/// Android launcher / splash size.
///
/// The tile is dark: on the cream pages it stands by itself; on the wine
/// headers pass [onDark] so a thin gold rim keeps it from melting into them.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.shadow = true, this.onDark = false});

  final double size;
  final bool shadow;

  /// Shown on a wine background: draws a thin gold rim around the tile.
  final bool onDark;

  static const double compactBelow = 64;

  /// The tile's corner radius as a fraction of its side (as in gen_logo.mjs).
  static const double cornerRatio = 0.2;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * cornerRatio);
    final image = Image.asset(
      size < compactBelow ? 'assets/logo/logo_mark.png' : 'assets/logo/logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
    if (!shadow && !onDark) return SizedBox(width: size, height: size, child: image);
    return Container(
      width: size,
      height: size,
      // The rim is painted over the tile's edge, so the logo keeps its size.
      foregroundDecoration: onDark
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.85),
                width: (size * 0.012).clamp(1.0, 2.5),
              ),
            )
          : null,
      decoration: shadow
          ? BoxDecoration(
              // Follows the tile's rounded corners.
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: (onDark ? Colors.black : AppColors.wineDeep).withValues(alpha: onDark ? 0.35 : 0.28),
                  blurRadius: size * 0.28,
                  offset: Offset(0, size * 0.09),
                ),
              ],
            )
          : null,
      child: image,
    );
  }
}

/// "Wedbook" in the logo's serif, with "Matrimony" underneath — the wordmark
/// next to the small logo in the app bar.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.onDark = false, this.size = 34, this.showTagline = true});

  final bool onDark;
  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final nameColor = onDark ? AppColors.gold : AppColors.wine;
    final tagColor = onDark ? Colors.white.withValues(alpha: 0.78) : AppColors.goldDark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          S.brandShort,
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontSize: size,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
            color: nameColor,
            height: 1.1,
            letterSpacing: size * 0.01,
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: size * 0.06),
          Text(
            S.appTagline,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontSize: size * 0.5,
              fontWeight: FontWeight.w500,
              fontVariations: const [FontVariation('wght', 500)],
              letterSpacing: size * 0.02,
              color: tagColor,
            ),
          ),
        ],
      ],
    );
  }
}
