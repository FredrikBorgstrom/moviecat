import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'filename_parser.dart';
import 'matcher.dart';
import 'models.dart';
import 'providers/keyless.dart';
import 'providers/tmdb.dart';
import 'store.dart';

enum ItemStatus { pending, matched, unmatched, error }

class MediaFile {
  final String path;
  final int size;
  final ParsedName parsed;
  const MediaFile(this.path, this.size, this.parsed);
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

  Future<void> removeFolder(String path) async {
    store.folders.remove(path);
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

    final files = <MediaFile>[];
    for (final folder in store.folders) {
      files.addAll(await _listVideos(folder));
      if (gen != _generation) return;
    }

    final old = Map.of(_groups);
    _groups.clear();
    for (final f in files) {
      final g = _groups[f.parsed.queryKey] ??= _Group(f.parsed.queryKey, f.parsed);
      g.files.add(f);
    }
    for (final g in _groups.values) {
      final cached = store.matches[g.key];
      final prev = old[g.key];
      if (cached != null && (!refresh || store.pinned.contains(g.key))) {
        g.info = cached;
        g.status = ItemStatus.matched;
      } else if (prev != null && prev.status == ItemStatus.unmatched && !refresh) {
        g.status = ItemStatus.unmatched;
      }
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
          final info = await matcher.identify(g.parsed);
          g.info = info;
          g.status = info == null ? ItemStatus.unmatched : ItemStatus.matched;
          if (info != null) store.matches[g.key] = info;
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

  Future<List<MediaFile>> _listVideos(String root) async {
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
          out.add(MediaFile(e.path, size, parseFileName(e.path)));
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
