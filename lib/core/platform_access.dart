import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Access to macOS sandbox features (security-scoped bookmarks etc.).
/// On other platforms these are no-ops with sensible fallbacks.
class PlatformAccess {
  static const _channel = MethodChannel('moviecat/macos');

  static bool? _sandboxed;
  static String? _home;

  /// True when running inside the macOS App Sandbox (the App Store build).
  static bool get sandboxed => _sandboxed ?? false;

  /// Lets tests and screenshot tooling render the App Store (sandboxed) UI.
  @visibleForTesting
  static set sandboxedForTesting(bool value) => _sandboxed = value;

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

  /// What the platform calls the place deleted files go.
  static String get trashName => Platform.isWindows ? 'Recycle Bin' : 'Trash';

  /// Moves a file to the Trash (Recycle Bin on Windows). Throws on failure.
  static Future<void> trash(String path) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod('trash', path);
      return;
    }
    final ProcessResult r;
    if (Platform.isWindows) {
      // The path goes in through the environment, so it never needs quoting.
      r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"Add-Type -AssemblyName Microsoft.VisualBasic; "
            r"[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("
            r"$env:MOVIECAT_TRASH, 'OnlyErrorDialogs', 'SendToRecycleBin')",
      ], environment: {'MOVIECAT_TRASH': path});
    } else {
      r = await Process.run('gio', ['trash', '--', path]);
    }
    if (r.exitCode != 0) {
      throw FileSystemException('${r.stderr}'.trim(), path);
    }
  }

  /// Shows a file in Finder (macOS only).
  static Future<void> reveal(String path) => _channel.invokeMethod('reveal', path);
}
