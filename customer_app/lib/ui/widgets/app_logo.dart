import 'package:flutter/material.dart';

import '../../config.dart';
import '../strings.dart';
import '../theme.dart';

/// The Gandharva disc: the rose-gold couple and lotus heart on a round maroon
/// disc, on a transparent background. Rendered by `tool/gen_logo.mjs` from
/// `assets/logo/gandharva_source.jpg` into this asset and every Android
/// launcher/splash size.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.shadow = true});

  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: shadow
          ? BoxDecoration(
              // The disc is round, so the shadow is too.
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.maroonDeep.withValues(alpha: 0.32),
                  blurRadius: size * 0.3,
                  offset: Offset(0, size * 0.1),
                ),
              ],
            )
          : null,
      child: Image.asset(
        'assets/logo/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// "Gandharva" in the brand serif with the small tagline underneath.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.onDark = false, this.size = 34, this.showTagline = true});

  final bool onDark;
  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final nameColor = onDark ? AppColors.roseGold : AppColors.maroon;
    final tagColor = onDark ? Colors.white.withValues(alpha: 0.78) : AppColors.roseDark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppConfig.appName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontSize: size,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
            color: nameColor,
            height: 1.05,
            letterSpacing: -0.3,
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: size * 0.22),
          Text(
            S.appTagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w500,
              letterSpacing: size * 0.02,
              color: tagColor,
            ),
          ),
        ],
      ],
    );
  }
}
