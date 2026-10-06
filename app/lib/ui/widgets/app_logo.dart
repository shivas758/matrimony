import 'package:flutter/material.dart';

import '../../config.dart';
import '../strings.dart';
import '../theme.dart';

/// The Mediator logo tile: the gold heart-and-handshake icon on a navy tile.
/// Rendered by `tool/gen_logo.mjs` from `assets/logo/mediator_source.jpg`
/// into this asset and every Android launcher/splash size.
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
              // Same corner radius as the tile in the PNG, so the shadow hugs it.
              borderRadius: BorderRadius.circular(size * 0.225),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navyDeep.withValues(alpha: 0.30),
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

/// The icon alone (no tile) — for placing on navy surfaces such as the login
/// header, where a second tile would look boxed in.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/logo/logo_mark.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      );
}

/// "Mediator" in the brand serif with the small "MATRIMONY PARTNERS" line.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.onDark = false, this.size = 34, this.showTagline = true});

  final bool onDark;
  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final nameColor = onDark ? AppColors.goldLight : AppColors.navy;
    final tagColor = onDark ? Colors.white.withValues(alpha: 0.78) : AppColors.gold;
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
          SizedBox(height: size * 0.18),
          Text(
            S.appTagline.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: size * 0.30,
              fontWeight: FontWeight.w600,
              letterSpacing: size * 0.09,
              color: tagColor,
            ),
          ),
        ],
      ],
    );
  }
}
