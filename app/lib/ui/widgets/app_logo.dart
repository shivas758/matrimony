import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// The Wedbook Agent logo tile (SPEC §9.18 A): two interlocked gold rings
/// holding the ♂ and ♀ signs over the gold wordmark "Wedbook / Agent", on a
/// rounded royal-blue tile. Rendered by `tool/gen_logo.mjs` from
/// `assets/logo/wedbook_agent_source.jpg` into this asset and every Android
/// launcher / splash size.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.shadow = true});

  final double size;
  final bool shadow;

  /// Corner radius of the tile in the PNG, as a fraction of its side
  /// (`CORNER` in tool/gen_logo.mjs).
  static const cornerFraction = 0.2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: shadow
          ? BoxDecoration(
              // Same corner radius as the tile in the PNG, so the shadow hugs it.
              borderRadius: BorderRadius.circular(size * cornerFraction),
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
        semanticLabel: '${S.brandName} ${S.appTagline}',
      ),
    );
  }
}

/// The gold rings alone (no tile, no wordmark) — for blue surfaces such as
/// the login header and the splash, where a second tile would look boxed in.
/// The artwork is wide: [width] sets its width, the height follows (5 : 3).
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.width = 160});

  final double width;

  /// Width : height of `assets/logo/logo_mark.png` (720 × 432).
  static const aspectRatio = 720 / 432;

  double get height => width / aspectRatio;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/logo/logo_mark.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      );
}

/// "Wedbook" in the brand serif with a small "AGENT" line under it — the
/// logo's own two lines, set in type so they stay sharp at any size.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.onDark = false, this.size = 34, this.showTagline = true});

  final bool onDark;
  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final nameColor = onDark ? AppColors.goldLight : AppColors.navy;
    final tagColor = onDark ? Colors.white.withValues(alpha: 0.82) : AppColors.goldDark;
    return Semantics(
      label: showTagline ? '${S.brandName} ${S.appTagline}' : S.brandName,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.brandName,
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
            SizedBox(height: size * 0.16),
            // The letter spacing leaves a gap after the last letter; the left
            // padding of the same width keeps the line optically centred.
            Padding(
              padding: EdgeInsets.only(left: size * 0.16),
              child: Text(
                S.appTagline.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: size * 0.16,
                  color: tagColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
