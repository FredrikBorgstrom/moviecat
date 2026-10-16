import 'dart:io';

import 'package:flutter/services.dart';

/// Access to macOS sandbox features (security-scoped bookmarks etc.).
/// On other platforms these are no-ops with sensible fallbacks.
class PlatformAccess {
  static const _channel = MethodChannel('moviecat/macos');

  static bool? _sandboxed;
  static String? _home;

  /// True when running inside the macOS App Sandbox (the App Store build).
  static bool get sandboxed => _sandboxed ?? false;

  /// The user's real home folder (inside the sandbox, \$HOME is the app container).
  static String get home =>
      _home ?? Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

  static Future<void> init() async {
    if (!Platform.isMacOS) return;
    try {
      _sandboxed = await _channel.invokeMethod<bool>('isSandboxed');
      _home = await _channel.invokeMethod<String>('realHome');
    } catch (_) {}
  }

  /// Creates a bookmark that lets the app reopen [path] after a restart.
  static Future<String?> bookmark(String path) async {
    if (!Platform.isMacOS) return null;
    try {
      return await _channel.invokeMethod<String>('bookmark', path);
    } catch (_) {
      return null;
    }
  }

  /// Regains access to a bookmarked folder. Returns its current path.
  static Future<({String path, bool stale})?> resolve(String bookmark) async {
    if (!Platform.isMacOS) return null;
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('resolve', bookmark);
      if (r == null) return null;
      return (path: r['path'] as String, stale: r['stale'] as bool? ?? false);
    } catch (_) {
      return null;
    }
  }

  /// Shows a file in Finder (macOS only).
  static Future<void> reveal(String path) => _channel.invokeMethod('reveal', path);
}
