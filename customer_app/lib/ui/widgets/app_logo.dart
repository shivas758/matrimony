import 'package:flutter/material.dart';

import '../../config.dart';
import '../strings.dart';
import '../theme.dart';

/// The MILI logo on its rounded cream tile (SPEC §9.17): the gold rings, MILI
/// and MATRIMONY — or, below [compactBelow] px where MATRIMONY can no longer
/// be read, just the rings and MILI. Rendered by `tool/gen_logo.mjs` from
/// `assets/logo/mili_source.jpg` into these assets and every Android
/// launcher/splash size. The tile reads on both the cream pages and the wine
/// headers.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.shadow = true});

  final double size;
  final bool shadow;

  static const double compactBelow = 64;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.215);
    return Container(
      width: size,
      height: size,
      decoration: shadow
          ? BoxDecoration(
              // Follows the tile's rounded corners.
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: AppColors.wineDeep.withValues(alpha: 0.30),
                  blurRadius: size * 0.3,
                  offset: Offset(0, size * 0.1),
                ),
              ],
            )
          : null,
      child: Image.asset(
        size < compactBelow ? 'assets/logo/logo_mark.png' : 'assets/logo/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// "MILI" spaced out like the logo's lettering, with MATRIMONY underneath.
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
          AppConfig.appName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: size,
            fontWeight: FontWeight.w500,
            color: nameColor,
            height: 1.05,
            letterSpacing: size * 0.08,
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: size * 0.12),
          Text(
            S.appTagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: size * 0.3,
              fontWeight: FontWeight.w500,
              letterSpacing: size * 0.09,
              color: tagColor,
            ),
          ),
        ],
      ],
    );
  }
}
