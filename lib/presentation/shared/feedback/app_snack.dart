import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../widgets/neu/neu.dart';

/// The app-wide snackbar system — one grammar for every transient message.
///
/// Severity is carried by a 3 px left accent bar + leading icon on a white
/// neu card with ink text; the background never screams. Copy rules live in
/// `documentation/UX_POLISH_PLAN.md` §A: raw exception strings never reach
/// the UI — call sites map errors to human copy and log the raw string.
enum AppSnackType {
  /// Saves and confirmations. Teal, 2 s.
  success,

  /// Neutral FYIs. Blue, 3 s.
  info,

  /// Offline / unreachable / degraded — a condition, not a fault.
  /// Amber, 3.5 s.
  warning,

  /// Real failures (rejected, refused, broken). Red, 4 s.
  error;

  Color get color => switch (this) {
        success => AppColors.primary,
        info => AppColors.rampBlue,
        warning => AppColors.warning,
        error => AppColors.critical,
      };

  IconData get icon => switch (this) {
        success => Icons.check_circle_outline,
        info => Icons.info_outline,
        warning => Icons.cloud_off_rounded,
        error => Icons.error_outline,
      };

  Duration get duration => switch (this) {
        success => const Duration(seconds: 2),
        info => const Duration(seconds: 3),
        warning => const Duration(milliseconds: 3500),
        error => const Duration(seconds: 4),
      };
}

/// Shows an [appSnackBar], replacing any snack currently visible so
/// rapid-fire actions don't queue a backlog of stale messages.
void showAppSnack(
  BuildContext context, {
  required AppSnackType type,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(
      type: type,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    ));
}

/// The styled [SnackBar] itself — exposed separately for call sites that
/// captured a [ScaffoldMessengerState] before an async gap (dialog flows).
SnackBar appSnackBar({
  required AppSnackType type,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return SnackBar(
    // The Material chrome is fully disabled; the card below is the snack.
    elevation: 0,
    backgroundColor: Colors.transparent,
    padding: EdgeInsets.zero,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: type.duration,
    content: _AppSnackCard(
      type: type,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

class _AppSnackCard extends StatelessWidget {
  const _AppSnackCard({
    required this.type,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final AppSnackType type;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: neuRaisedShadows(distance: 4, blur: 12),
        border: Border(left: BorderSide(color: type.color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(type.icon, size: 19, color: type.color),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.ink,
              ),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                onAction?.call();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
