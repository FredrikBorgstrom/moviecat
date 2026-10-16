import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'filename_parser.dart';
import 'matcher.dart';
import 'media_filter.dart';
import 'models.dart';
import 'providers/keyless.dart';
import 'providers/tmdb.dart';
import 'store.dart';

enum ItemStatus { pending, matched, unmatched, error }

class MediaFile {
  final String path;
  final int size;
  final ParsedName parsed;

  /// Comes from a strict folder: only shown if confidently recognised.
  final bool strict;
  const MediaFile(this.path, this.size, this.parsed, {this.strict = false});
}

/// One card in the library: a movie or show, with every file that belongs to it.
class LibraryItem {
  /// Parsed-name keys that resolved to this title (e.g. "Heat 1995" and "Heat (1995)").
  final List<String> keys;
  final ParsedName parsed;
  final List<MediaFile> files;
  final MediaInfo? info;
  final ItemStatus status;
  final String? error;

  const LibraryItem({
    required this.keys,
    required this.parsed,
    required this.files,
    required this.status,
    this.info,
    this.error,
  });

  String get displayTitle => info?.title ?? parsed.title;
  int? get displayYear => info?.year ?? parsed.year;
  MediaKind get kind => info?.kind ?? parsed.kind;
}

class _Group {
  final String key;
  final ParsedName parsed;
  final List<MediaFile> files = [];
  MediaInfo? info;
  double score = 0;
  ItemStatus status = ItemStatus.pending;
  String? error;
  _Group(this.key, this.parsed);
}

class Library extends ChangeNotifier {
  final Store store;
  Library(this.store);

  final Map<String, _Group> _groups = {};
  int _generation = 0;
  List<LibraryItem>? _items;

  bool scanning = false;
  int progressDone = 0;
  int progressTotal = 0;
  String? scanMessage;

  MetadataProvider get provider =>
      store.tmdbKey.isNotEmpty ? TmdbProvider(store.tmdbKey) : KeylessProvider();

  int? myRating(String id) => store.myRatings[id];

  /// All titles, with groups that matched the same title merged together.
  List<LibraryItem> get items => _items ??= _buildItems();

  List<LibraryItem> _buildItems() {
    final byId = <String, List<_Group>>{};
    final out = <LibraryItem>[];
    for (final g in _groups.values) {
      // Strict-folder files stay hidden until they're confirmed as real titles.
      if (g.status == ItemStatus.pending && g.files.every((f) => f.strict)) continue;
      if (g.info != null) {
        (byId[g.info!.id] ??= []).add(g);
      } else {
        out.add(LibraryItem(
          keys: [g.key],
          parsed: g.parsed,
          files: List.of(g.files),
          status: g.status,
          error: g.error,
        ));
      }
    }
    for (final gs in byId.values) {
      out.add(LibraryItem(
        keys: [for (final g in gs) g.key],
        parsed: gs.first.parsed,
        files: [for (final g in gs) ...g.files]..sort(_episodeOrder),
        info: gs.first.info,
        status: ItemStatus.matched,
      ));
    }
    return out;
  }

  static int _episodeOrder(MediaFile a, MediaFile b) {
    final s = (a.parsed.season ?? 0).compareTo(b.parsed.season ?? 0);
    if (s != 0) return s;
    final e = (a.parsed.episode ?? 0).compareTo(b.parsed.episode ?? 0);
    return e != 0 ? e : a.path.compareTo(b.path);
  }

  void _changed() {
    _items = null;
    notifyListeners();
  }

  // ---- Folders ----

  Future<void> addFolder(String path) async {
    if (store.folders.contains(path)) return;
    store.folders.add(path);
    await store.saveSettings();
    await scan();
  }

  /// Adds several folders at once (from auto-discovery). Folders already
  /// covered by a new, wider folder are replaced by it.
  Future<void> addFolders(List<({String path, bool strict})> folders) async {
    for (final f in folders) {
      store.folders.removeWhere((e) => e == f.path || p.isWithin(f.path, e));
      store.strictFolders.removeWhere((e) => e == f.path || p.isWithin(f.path, e));
      store.folders.add(f.path);
      if (f.strict) store.strictFolders.add(f.path);
    }
    await store.saveSettings();
    await scan();
  }

  Future<void> removeFolder(String path) async {
    store.folders.remove(path);
    store.strictFolders.remove(path);
    await store.saveSettings();
    await scan();
  }

  Future<void> setFolderStrict(String path, bool strict) async {
    strict ? store.strictFolders.add(path) : store.strictFolders.remove(path);
    await store.saveSettings();
    await scan();
  }

  // ---- Scanning ----

  /// Lists all video files in the configured folders and identifies them.
  /// [refresh] re-identifies everything except titles the user matched by hand.
  Future<void> scan({bool refresh = false}) async {
    final gen = ++_generation;
    scanning = true;
    progressDone = 0;
    progressTotal = 0;
    scanMessage = 'Looking for video files…';
    _changed();

    // Folders may overlap; a file seen from a non-strict folder is never filtered.
    final byPath = <String, MediaFile>{};
    for (final folder in store.folders) {
      final strict = store.strictFolders.contains(folder);
      for (final f in await _listVideos(folder, strict: strict)) {
        final existing = byPath[f.path];
        if (existing == null || (existing.strict && !strict)) byPath[f.path] = f;
      }
      if (gen != _generation) return;
    }
    // In strict folders, drop obvious non-movies before doing any lookups.
    final files = byPath.values
        .where((f) => !f.strict || (f.size >= minMediaBytes && !looksPersonal(f.path)));

    final old = Map.of(_groups);
    _groups.clear();
    for (final f in files) {
      final g = _groups[f.parsed.queryKey] ??= _Group(f.parsed.queryKey, f.parsed);
      g.files.add(f);
    }
    for (final g in _groups.values.toList()) {
      final cached = store.matches[g.key];
      final prev = old[g.key];
      if (cached != null && (!refresh || store.pinned.contains(g.key))) {
        g.info = cached;
        g.score = store.pinned.contains(g.key) ? 100 : store.scores[g.key] ?? 100;
        g.status = ItemStatus.matched;
        _applyStrict(g);
      } else if (prev != null && prev.status == ItemStatus.unmatched && !refresh) {
        g.status = ItemStatus.unmatched;
      }
    }

    // Strict-only groups that were already looked up without a match: drop them
    // instead of searching again on every scan.
    if (!refresh) {
      _groups.removeWhere((key, g) =>
          g.info == null && g.files.every((f) => f.strict) && store.scores.containsKey(key));
    }
    final queue = _groups.values.where((g) => g.status == ItemStatus.pending).toList();
    progressTotal = queue.length;
    scanMessage = queue.isEmpty ? null : 'Identifying titles…';
    _changed();

    final matcher = Matcher(provider);
    var sinceSave = 0;
    Future<void> worker() async {
      while (queue.isNotEmpty && gen == _generation) {
        final g = queue.removeAt(0);
        try {
          final r = await matcher.identifyScored(g.parsed);
          g.info = r.info;
          g.score = r.score;
          g.status = r.info == null ? ItemStatus.unmatched : ItemStatus.matched;
          store.scores[g.key] = r.score;
          if (r.info != null) store.matches[g.key] = r.info;
          _applyStrict(g);
        } catch (e) {
          g.status = ItemStatus.error;
          g.error = '$e';
        }
        if (gen != _generation) return;
        progressDone++;
        if (++sinceSave >= 10) {
          sinceSave = 0;
          unawaited(store.saveLibrary());
        }
        _changed();
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    if (gen != _generation) return;
    await store.saveLibrary();
    scanning = false;
    scanMessage = null;
    _changed();
  }

  /// Removes strict-folder files that aren't confidently recognised.
  void _applyStrict(_Group g) {
    if (!g.files.any((f) => f.strict)) return;
    g.files.removeWhere((f) =>
        f.strict && (g.info == null || !isConfidentMatch(f.path, f.parsed, g.score)));
    if (g.files.isEmpty) _groups.remove(g.key);
  }

  /// Identifies a parsed name, using the cache when possible. Used by discovery.
  Future<({MediaInfo? info, double score})> identifyCached(
      ParsedName parsed, Matcher matcher) async {
    final key = parsed.queryKey;
    final cached = store.matches[key];
    if (cached != null && store.pinned.contains(key)) return (info: cached, score: 100.0);
    final score = store.scores[key];
    if (score != null) return (info: cached, score: score);
    if (cached != null) return (info: cached, score: 100.0);
    final r = await matcher.identifyScored(parsed);
    store.scores[key] = r.score;
    if (r.info != null) store.matches[key] = r.info;
    return r;
  }

  Future<List<MediaFile>> _listVideos(String root, {bool strict = false}) async {
    final out = <MediaFile>[];
    final done = Completer<void>();
    final pending = <Future<void>>[];
    Directory(root).list(recursive: true, followLinks: false).listen(
      (e) {
        if (e is! File || !isVideoFile(e.path)) return;
        final name = p.basename(e.path);
        if (name.startsWith('.')) return; // macOS "._" resource forks etc.
        pending.add(e.length().then((size) {
          // Skip sample clips that ship with releases.
          final lower = e.path.toLowerCase();
          final isSample = RegExp(r'(^|[^a-z])sample([^a-z]|$)').hasMatch(lower);
          if (isSample && size < 400 * 1024 * 1024) return;
          out.add(MediaFile(e.path, size, parseFileName(e.path), strict: strict));
        }, onError: (_) {}));
      },
      onError: (_) {}, // unreadable sub-folders: skip them
      onDone: done.complete,
      cancelOnError: false,
    );
    await done.future;
    await Future.wait(pending);
    return out;
  }

  // ---- Manual matching & ratings ----

  Future<List<Candidate>> search(String query) => provider.search(query);

  Future<void> fixMatch(LibraryItem item, Candidate c) async {
    final info = await provider.details(c);
    for (final key in item.keys) {
      store.matches[key] = info;
      store.scores[key] = 100;
      store.pinned.add(key);
      final g = _groups[key];
      if (g != null) {
        g.info = info;
        g.status = ItemStatus.matched;
      }
    }
    await store.saveLibrary();
    _changed();
  }

  Future<void> setMyRating(String id, int? rating) async {
    if (rating == null || rating <= 0) {
      store.myRatings.remove(id);
    } else {
      store.myRatings[id] = rating;
    }
    _changed();
    await store.saveLibrary();
  }

  // ---- Settings ----

  Future<void> completeSetup({String? tmdbKey}) async {
    if (tmdbKey != null) store.tmdbKey = tmdbKey.trim();
    store.setupDone = true;
    await store.saveSettings();
    _changed();
  }

  Future<void> setTmdbKey(String key) async {
    store.tmdbKey = key.trim();
    await store.saveSettings();
    _changed();
  }
}
