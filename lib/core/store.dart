import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Settings and caches, stored as JSON files in the app support directory.
class Store {
  final Directory dir;
  Store._(this.dir);

  // Settings
  List<String> folders = [];

  /// Folders where only confidently recognised movies/TV are shown (set by
  /// auto-discovery for folders that also hold home videos, tutorials, etc.).
  Set<String> strictFolders = {};
  String tmdbKey = '';
  bool setupDone = false;

  // Cache: parsed-name key -> identified title (null = looked up, nothing found).
  final Map<String, MediaInfo?> matches = {};

  /// Keys the user matched by hand; never re-identified automatically.
  final Set<String> pinned = {};

  /// Match score per parsed-name key (0 = searched, nothing found).
  final Map<String, double> scores = {};

  /// The user's own ratings (1–10) keyed by MediaInfo.id.
  final Map<String, int> myRatings = {};

  static Future<Store> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return at(dir);
  }

  /// Opens a store in a specific directory (used by tests).
  static Future<Store> at(Directory dir) async {
    final s = Store._(dir);
    await s._load();
    return s;
  }

  File get _settingsFile => File(p.join(dir.path, 'settings.json'));
  File get _libraryFile => File(p.join(dir.path, 'library.json'));

  Future<void> _load() async {
    try {
      final j = jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>;
      folders = ((j['folders'] as List?) ?? []).cast<String>();
      strictFolders = ((j['strictFolders'] as List?) ?? []).cast<String>().toSet();
      tmdbKey = j['tmdbKey'] as String? ?? '';
      setupDone = j['setupDone'] as bool? ?? false;
    } catch (_) {}
    try {
      final j = jsonDecode(await _libraryFile.readAsString()) as Map<String, dynamic>;
      (j['matches'] as Map? ?? {}).forEach((k, v) {
        matches[k as String] = v == null ? null : MediaInfo.fromJson((v as Map).cast());
      });
      pinned.addAll(((j['pinned'] as List?) ?? []).cast<String>());
      (j['scores'] as Map? ?? {}).forEach((k, v) => scores[k as String] = (v as num).toDouble());
      (j['myRatings'] as Map? ?? {}).forEach((k, v) => myRatings[k as String] = v as int);
    } catch (_) {}
  }

  Future<void> saveSettings() => _write(_settingsFile, {
        'folders': folders,
        'strictFolders': strictFolders.toList(),
        'tmdbKey': tmdbKey,
        'setupDone': setupDone,
      });

  Future<void> saveLibrary() => _write(_libraryFile, {
        'matches': {for (final e in matches.entries) e.key: e.value?.toJson()},
        'pinned': pinned.toList(),
        'scores': scores,
        'myRatings': myRatings,
      });

  /// Write to a temp file then rename, so a crash never leaves a half-written file.
  Future<void> _write(File f, Object data) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
    await tmp.rename(f.path);
  }
}
