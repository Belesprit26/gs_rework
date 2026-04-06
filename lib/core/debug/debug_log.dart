import 'package:flutter/foundation.dart';

/// Master switch for debug logging.
///
/// Set to `false` to silence all [debugLog] calls without removing
/// them from the codebase. Defaults to [kDebugMode] so logs appear
/// only in debug builds.
const bool kEnableDebugLogging = kDebugMode;

/// Centralised debug logger.
///
/// Prints `[$tag] $message` when [kEnableDebugLogging] is true.
/// Every debug log in the app routes through this single function,
/// making it trivial to:
/// - Silence all output (flip the constant above)
/// - Filter by tag
/// - Redirect to a file/Crashlytics in the future
void debugLog(String tag, String message) {
  if (kEnableDebugLogging) {
    debugPrint('[$tag] $message');
  }
}
