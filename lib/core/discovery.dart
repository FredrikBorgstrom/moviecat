import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'filename_parser.dart';
import 'library.dart';
import 'matcher.dart';
import 'media_filter.dart';

/// A folder that auto-discovery suggests adding.
class DiscoveredFolder {
  final String path;

  /// Also contains other videos, so only recognised titles will be shown.
  final bool strict;
  final int mediaFiles;
  final int otherFiles;
  final List<String> titles;
  final bool alreadyInLibrary;

  const DiscoveredFolder({
    required this.path,
    required this.strict,
    required this.mediaFiles,
    required this.otherFiles,
    required this.titles,
    required this.alreadyInLibrary,
  });
}

class DiscoveryProgress {
  final String phase;
  final int foldersSearched;
  final int videosFound;
  final int checked;
  final int toCheck;
  const DiscoveryProgress(this.phase,
      {this.foldersSearched = 0, this.videosFound = 0, this.checked = 0, this.toCheck = 0});
}

class _Video {
  final String path;
  final String root;
  final int size;
  bool media = false;
  String? title;
  _Video(this.path, this.root, this.size);
}

class _Counts {
  int media = 0;
  int other = 0;
}

/// Searches the computer's usual places for folders with movies and TV shows,
/// checks each video against the metadata sources, and proposes folders:
/// pure movie/TV folders as-is, mixed folders as "strict" (non-titles hidden).
class Discovery {
  final Library library;
  Discovery(this.library);

  final progress = ValueNotifier(const DiscoveryProgress('Starting…'));
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get cancelled => _cancelled;

  static const _maxDepth = 8;

  static final _home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

  // Folder names never worth descending into.
  static const _skipNames = {
    'library', 'applications', 'appdata', 'application data', 'node_modules',
    r'$recycle.bin', 'system volume information', 'windows', 'program files',
    'program files (x86)', 'programdata', 'pods', 'deriveddata', 'build', 'venv',
    'site-packages', 'vendor', 'target', 'dist', 'caches', 'cache', 'tmp', 'temp',
    'backups.backupdb', 'snap', 'go', 'android', 'flutter', 'sdk', 'sdks',
  };
  // Package folders (apps, photo/video libraries, projects).
  static const _skipExtensions = {
    '.app', '.photoslibrary', '.fcpbundle', '.imovielibrary', '.tvlibrary',
    '.musiclibrary', '.bundle', '.framework', '.xcodeproj', '.xcworkspace',
    '.lrlibrary', '.cocatalog', '.logicx', '.band', '.rcproject', '.dtBase2',
  };

  /// Where to look: the home folder plus external and secondary drives.
  static List<String> defaultRoots() {
    final roots = <String>{};
    void addChildren(String dir) {
      try {
        for (final e in Directory(dir).listSync(followLinks: false)) {
          if (e is Directory && !p.basename(e.path).startsWith('.')) roots.add(e.path);
        }
      } catch (_) {}
    }

    if (_home.isNotEmpty) roots.add(_home);
    if (Platform.isMacOS) {
      roots.add('/Users/Shared');
      try {
        for (final e in Directory('/Volumes').listSync(followLinks: false)) {
          final name = p.basename(e.path).toLowerCase();
          if (name.contains('time machine') || name.startsWith('com.apple')) continue;
          // The startup disk shows up as a link to "/".
          if (e.resolveSymbolicLinksSync() == '/') continue;
          roots.add(e.path);
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      final public = Platform.environment['PUBLIC'];
      if (public != null) roots.add(public);
      for (var c = 'D'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final drive = '${String.fromCharCode(c)}:\\';
        if (Directory(drive).existsSync()) roots.add(drive);
      }
    } else {
      final user = Platform.environment['USER'] ?? '';
      addChildren('/media/$user');
      addChildren('/run/media/$user');
      addChildren('/mnt');
    }
    return roots.where((r) => Directory(r).existsSync()).toList();
  }

  Future<List<DiscoveredFolder>> run({List<String>? roots}) async {
    roots ??= defaultRoots();
    final videos = await _findVideos(roots);
    if (_cancelled) return [];
    await _classify(videos);
    if (_cancelled) return [];
    return _propose(roots, videos);
  }

  // ---- 1. Walk the disk ----

  Future<List<_Video>> _findVideos(List<String> roots) async {
    final videos = <String, _Video>{};
    var folders = 0;
    for (final root in roots) {
      final stack = <(Directory, int)>[(Directory(root), 0)];
      while (stack.isNotEmpty && !_cancelled) {
        final (dir, depth) = stack.removeLast();
        folders++;
        if (folders % 50 == 0) {
          progress.value = DiscoveryProgress('Searching folders…',
              foldersSearched: folders, videosFound: videos.length);
        }
        List<FileSystemEntity> entries;
        try {
          entries = await dir.list(followLinks: false).toList();
        } catch (_) {
          continue; // no permission etc.
        }
        for (final e in entries) {
          final name = p.basename(e.path);
          if (name.startsWith('.')) continue;
          if (e is Directory) {
            final lower = name.toLowerCase();
            if (depth >= _maxDepth ||
                _skipNames.contains(lower) ||
                _skipExtensions.contains(p.extension(lower))) {
              continue;
            }
            stack.add((e, depth + 1));
          } else if (e is File && isVideoFile(e.path) && !videos.containsKey(e.path)) {
            try {
              videos[e.path] = _Video(e.path, root, await e.length());
            } catch (_) {}
          }
        }
      }
    }
    return videos.values.toList();
  }

  // ---- 2. Decide which videos are real movies / episodes ----

  Future<void> _classify(List<_Video> videos) async {
    final byKey = <String, List<_Video>>{};
    final parsedByKey = <String, ParsedName>{};
    for (final v in videos) {
      if (v.size < minMediaBytes || looksPersonal(v.path)) continue;
      final parsed = parseFileName(v.path);
      if (parsed.title.isEmpty) continue;
      (byKey[parsed.queryKey] ??= []).add(v);
      parsedByKey[parsed.queryKey] = parsed;
    }

    final keys = byKey.keys.toList();
    var checked = 0;
    final matcher = Matcher(library.provider);
    void report() => progress.value = DiscoveryProgress('Checking titles…',
        videosFound: videos.length, checked: checked, toCheck: keys.length);
    report();

    Future<void> worker() async {
      while (keys.isNotEmpty && !_cancelled) {
        final key = keys.removeLast();
        try {
          final r = await library.identifyCached(parsedByKey[key]!, matcher);
          if (r.info != null) {
            for (final v in byKey[key]!) {
              if (isConfidentMatch(v.path, parseFileName(v.path), r.score)) {
                v.media = true;
                v.title = r.info!.title;
              }
            }
          }
        } catch (_) {
          // Network trouble: leave as "not a title".
        }
        checked++;
        report();
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    await library.store.saveLibrary();
  }

  // ---- 3. Pick folders ----

  List<DiscoveredFolder> _propose(List<String> roots, List<_Video> videos) {
    final total = <String, _Counts>{}; // whole subtree
    final direct = <String, _Counts>{}; // files directly inside
    final children = <String, Set<String>>{};
    final titles = <String, Set<String>>{};

    for (final v in videos) {
      var dir = p.dirname(v.path);
      final d = direct[dir] ??= _Counts();
      v.media ? d.media++ : d.other++;
      while (true) {
        final t = total[dir] ??= _Counts();
        v.media ? t.media++ : t.other++;
        if (v.media) (titles[dir] ??= {}).add(v.title!);
        if (p.equals(dir, v.root)) break;
        final parent = p.dirname(dir);
        if (parent == dir) break;
        (children[parent] ??= {}).add(dir);
        dir = parent;
      }
    }

    final general = {
      _home,
      for (final n in ['Downloads', 'Desktop', 'Documents']) p.join(_home, n),
    };
    final existing = library.store.folders;
    final out = <DiscoveredFolder>[];

    void add(String dir, {required bool strict}) {
      final t = total[dir]!;
      out.add(DiscoveredFolder(
        path: dir,
        strict: strict,
        mediaFiles: t.media,
        otherFiles: t.other,
        titles: (titles[dir] ?? {}).toList()..sort(),
        alreadyInLibrary: existing.any((e) => p.equals(e, dir) || p.isWithin(e, dir)),
      ));
    }

    void select(String dir) {
      final t = total[dir];
      if (t == null || t.media == 0) return;
      final isHome = p.equals(dir, _home);
      if (!isHome && t.other == 0) {
        // Only movies/TV below here. Catch-all folders (Downloads…) still get
        // strict mode so future non-movie downloads stay hidden.
        add(dir, strict: general.contains(dir));
        return;
      }
      if (!isHome && (direct[dir]?.media ?? 0) > 0) {
        add(dir, strict: true); // mixed right here: keep the folder, hide the rest
        return;
      }
      for (final c in children[dir] ?? const <String>{}) {
        select(c);
      }
    }

    for (final r in roots) {
      select(r);
    }
    // Overlapping roots (e.g. a drive mounted inside home) can propose a folder twice.
    final seen = <String>{};
    out.retainWhere((f) => seen.add(f.path));
    out.sort((a, b) => b.mediaFiles.compareTo(a.mediaFiles));
    return out;
  }
}
