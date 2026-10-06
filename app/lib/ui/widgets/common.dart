import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_client.dart';
import '../strings.dart';
import '../theme.dart';

/// Full-screen empty/error state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(color: AppColors.goldPale, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, size: 38, color: AppColors.goldDark),
            ),
            const SizedBox(height: 18),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: S.somethingWrong,
        message: message,
        actionLabel: onRetry == null ? null : S.retry,
        onAction: onRetry,
      );
}

/// A profile photo from an authenticated route. The bearer token is passed as
/// a header because /api/photos/:id is not public.
class AuthedPhoto extends StatelessWidget {
  const AuthedPhoto({
    super.key,
    required this.url,
    required this.api,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholderInitials,
  });

  final String? url;
  final ApiClient api;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? placeholderInitials;

  @override
  Widget build(BuildContext context) {
    final token = api.tokenSync;
    if (url == null || token == null) return _placeholder(context);
    return CachedNetworkImage(
      imageUrl: url!,
      // /api/photos/:id is authenticated — the token travels as a header.
      httpHeaders: {'Authorization': 'Bearer $token'},
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => _placeholder(context, showSpinner: true),
      errorWidget: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context, {bool showSpinner = false}) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B4F82), Color(0xFF0F2F52)],
        ),
      ),
      alignment: Alignment.center,
      child: showSpinner
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : (placeholderInitials != null && placeholderInitials!.isNotEmpty
              ? Text(
                  placeholderInitials!,
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    fontVariations: [FontVariation('wght', 600)],
                    color: AppColors.goldLight,
                  ),
                )
              : const Icon(Icons.person_rounded, size: 44, color: AppColors.goldLight)),
    );
  }
}

/// Small coloured status pill.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon, this.solid = false});

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid pills sit on photos; tinted ones on white surfaces.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color.withValues(alpha: 0.92) : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Label/value row used across detail screens.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase heading with the gold accent bar.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.navy,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// White rounded panel with a hairline border — the building block of the
/// detail and More screens.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor ?? AppColors.rule),
        ),
        child: child,
      );
}

/// Icon + label + value tile for the "at a glance" grid on the detail screen.
class FactTile extends StatelessWidget {
  const FactTile({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.rule),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.goldPale, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: AppColors.goldDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// IST-friendly date formatting (SPEC §3.4 — store UTC, display IST).
String formatDate(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d.toLocal());

String formatDateTime(DateTime? d) =>
    d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: error ? scheme.onErrorContainer : Colors.white)),
      backgroundColor: error ? scheme.errorContainer : null,
      duration: Duration(seconds: error ? 4 : 2),
    ));
}
