import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart'
    show KeyPairType, Signature, SimplePublicKey;
import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// How this copy of MovieCat gets new versions.
enum UpdateChannel {
  /// Downloads, checks and installs updates itself (direct downloads).
  self,

  /// Shows that a new version exists, with a link to download it.
  notify,

  /// Updated by a store or package manager, such as the Mac App Store.
  managed,
}

/// Where a copy of MovieCat was installed from, and so how it is updated.
class InstallKind {
  final UpdateChannel channel;

  /// What updates this copy when [channel] is managed, e.g. "the Mac App Store".
  final String? source;
  const InstallKind(this.channel, [this.source]);
}

/// One platform's download in the update feed.
class UpdateAsset {
  final String name;
  final String url;
  final String sha256;
  final int size;
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> j) => UpdateAsset(
    name: j['name'] as String,
    url: j['url'] as String,
    sha256: j['sha256'] as String,
    size: j['size'] as int,
  );
}

/// The newest release, as described by the signed update feed.
class UpdateInfo {
  final String version;
  final String notes;

  /// The release page, for "What's new" and manual downloads.
  final String page;

  /// Keyed by platform: macos, windows, linux.
  final Map<String, UpdateAsset> assets;
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.page,
    required this.assets,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
    version: j['version'] as String,
    notes: j['notes'] as String? ?? '',
    page: j['page'] as String,
    assets: {
      for (final e in (j['assets'] as Map).entries)
        e.key as String: UpdateAsset.fromJson((e.value as Map).cast()),
    },
  );
}

/// Compares dotted version numbers such as "1.10.0" and "1.9.2".
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Finds out how this copy of MovieCat was installed. [os] is Platform.operatingSystem,
/// [exe] the running executable and [env] the environment.
InstallKind detectInstall({
  required String os,
  required String exe,
  required Map<String, String> env,
  required bool sandboxed,
  bool Function(String path)? writable,
}) {
  final canWrite = writable ?? _writable;
  switch (os) {
    case 'macos':
      if (sandboxed) {
        return const InstallKind(UpdateChannel.managed, 'the Mac App Store');
      }
      // …/MovieCat.app/Contents/MacOS/MovieCat
      final app = p.dirname(p.dirname(p.dirname(exe)));
      // Opened straight from a download, macOS runs the app from a read-only copy.
      if (!app.endsWith('.app') || app.contains('/AppTranslocation/')) {
        return const InstallKind(UpdateChannel.notify);
      }
      return InstallKind(
        canWrite(p.dirname(app)) && canWrite(app)
            ? UpdateChannel.self
            : UpdateChannel.notify,
      );
    case 'windows':
      final dir = p.windows.dirname(exe).toLowerCase();
      if (dir.contains(r'\windowsapps\')) {
        return const InstallKind(UpdateChannel.managed, 'the Microsoft Store');
      }
      if (dir.contains(r'\scoop\apps\')) {
        return const InstallKind(UpdateChannel.managed, 'Scoop');
      }
      final choco = env['ChocolateyInstall'];
      if (choco != null &&
          Directory(p.windows.join(choco, 'lib', 'moviecat')).existsSync()) {
        return const InstallKind(UpdateChannel.managed, 'Chocolatey');
      }
      // Installed with the setup program (it leaves its uninstaller next to the app).
      if (File(p.windows.join(p.windows.dirname(exe), 'unins000.exe')).existsSync()) {
        return const InstallKind(UpdateChannel.self);
      }
      return const InstallKind(UpdateChannel.notify);
    case 'linux':
      if (env['SNAP'] != null) {
        return const InstallKind(UpdateChannel.managed, 'the Snap Store');
      }
      final appImage = env['APPIMAGE'];
      if (appImage != null) {
        return InstallKind(
          canWrite(p.dirname(appImage))
              ? UpdateChannel.self
              : UpdateChannel.notify,
        );
      }
      if (exe.startsWith('/usr/')) {
        return const InstallKind(UpdateChannel.managed, 'your package manager');
      }
      return const InstallKind(UpdateChannel.notify);
  }
  return const InstallKind(UpdateChannel.notify);
}

bool _writable(String dir) {
  try {
    final probe = File(p.join(dir, '.moviecat-write-test-$pid'));
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// Checks GitHub for a newer MovieCat, downloads it in the background and installs it
/// when the user restarts. The feed is signed with Ed25519 and lists the SHA-256 of
/// every download, so only files built and signed by MovieCat's CI are installed.
class Updater extends ChangeNotifier {
  static const defaultFeed = String.fromEnvironment(
    'MOVIECAT_UPDATE_FEED',
    defaultValue: 'https://github.com/FredrikBorgstrom/moviecat/releases/latest/download/update.json',
  );

  /// Public half of the key in the UPDATE_SIGNING_KEY secret (raw Ed25519, base64).
  static const defaultPublicKey =
      'KCNRjCoTIJTWB9H4MNzS+q6/isiIjdlwNtlRx+lM7g8=';

  final String currentVersion;
  final InstallKind install;

  /// Where downloads are kept until they are installed.
  final Directory dir;
  final String feed;
  final String publicKey;

  /// Downloads updates as soon as they're found (the "update automatically" setting).
  final bool Function() autoDownload;

  /// Platform key in the feed: macos, windows or linux.
  final String platform;

  /// The running app: MovieCat.app on macOS, the .exe on Windows, the AppImage on Linux.
  final String appPath;

  final http.Client _http;

  Updater({
    required this.currentVersion,
    required this.install,
    required this.dir,
    required this.autoDownload,
    String? platform,
    String? appPath,
    this.feed = defaultFeed,
    this.publicKey = defaultPublicKey,
    http.Client? client,
  }) : platform = platform ?? Platform.operatingSystem,
       appPath = appPath ?? _appPath(),
       _http = client ?? http.Client();

  static String _appPath() {
    final exe = Platform.resolvedExecutable;
    if (Platform.isMacOS) return p.dirname(p.dirname(p.dirname(exe)));
    if (Platform.isLinux) return Platform.environment['APPIMAGE'] ?? exe;
    return exe;
  }

  bool get enabled => install.channel != UpdateChannel.managed;
  bool get canInstall => install.channel == UpdateChannel.self;

  /// A newer version than this one, if there is one.
  UpdateInfo? available;

  /// The verified download of [available], ready to install.
  File? ready;

  bool checking = false;
  bool downloading = false;
  double? progress;
  DateTime? lastCheck;
  String? error;
  Timer? _timer;

  /// Checks a few seconds after launch and then every six hours.
  void start() {
    if (!enabled) return;
    Timer(const Duration(seconds: 5), check);
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> check() async {
    if (!enabled || checking || downloading) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final info = await fetchFeed();
      available =
          info != null && compareVersions(info.version, currentVersion) > 0
          ? info
          : null;
      if (available == null) ready = null;
    } catch (e) {
      error = 'Could not check for updates: $e';
    }
    checking = false;
    lastCheck = DateTime.now();
    notifyListeners();
    if (available != null && canInstall && autoDownload()) await download();
  }

  /// The feed, if its signature is valid. Null when no release has a feed yet.
  Future<UpdateInfo?> fetchFeed() async {
    final res = await _http
        .get(Uri.parse(feed))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} for $feed');
    }
    final sig = await _http
        .get(Uri.parse('$feed.sig'))
        .timeout(const Duration(seconds: 30));
    if (sig.statusCode != 200) {
      throw HttpException('HTTP ${sig.statusCode} for $feed.sig');
    }
    final valid = await DartEd25519().verify(
      res.bodyBytes,
      signature: Signature(
        sig.bodyBytes,
        publicKey: SimplePublicKey(
          base64.decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) {
      throw const FormatException('the update feed has an invalid signature');
    }
    return UpdateInfo.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Downloads this platform's file for [available] and checks its size and SHA-256.
  Future<void> download() async {
    final info = available;
    final asset = info?.assets[platform];
    if (info == null || asset == null || downloading) return;
    final updates = Directory(p.join(dir.path, 'updates'));
    final file = File(p.join(updates.path, '${info.version}-${asset.name}'));
    if (ready?.path == file.path) return;
    downloading = true;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      await updates.create(recursive: true);
      // Remove downloads of older versions.
      for (final f in updates.listSync()) {
        if (f.path != file.path) f.deleteSync(recursive: true);
      }
      if (!(await file.exists() && await _sha256(file) == asset.sha256)) {
        final part = File('${file.path}.part');
        final res = await _http.send(http.Request('GET', Uri.parse(asset.url)));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode} for ${asset.url}');
        }
        final sink = part.openWrite();
        var got = 0;
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          final before = ((progress ?? 0) * 100).floor();
          progress = got / asset.size;
          if ((progress! * 100).floor() != before) notifyListeners();
        }
        await sink.close();
        if (got != asset.size || await _sha256(part) != asset.sha256) {
          await part.delete();
          throw const FormatException(
            'the download does not match the update feed',
          );
        }
        await part.rename(file.path);
      }
      ready = file;
    } catch (e) {
      error = 'Could not download the update: $e';
    }
    downloading = false;
    progress = null;
    notifyListeners();
  }

  static Future<String> _sha256(File f) async =>
      (await crypto.sha256.bind(f.openRead()).first).toString();

  /// Downloads the update if needed, installs it once MovieCat has quit, and opens the
  /// new version. Returns false (with [error] set) if it couldn't start. Tests pass
  /// [quit] false and the id of a process that has already ended as [waitFor].
  Future<bool> installAndRestart({
    bool relaunch = true,
    bool quit = true,
    int? waitFor,
  }) async {
    if (!canInstall) return false;
    if (ready == null) await download();
    final file = ready;
    if (file == null) return false;
    try {
      switch (platform) {
        case 'macos':
          await _installMac(file, relaunch: relaunch, waitFor: waitFor ?? pid);
        case 'windows':
          await _installWindows(
            file,
            relaunch: relaunch,
            waitFor: waitFor ?? pid,
          );
        case 'linux':
          await _installAppImage(file, relaunch: relaunch);
        default:
          return false;
      }
    } catch (e) {
      error = 'Could not install the update: $e';
      notifyListeners();
      return false;
    }
    if (quit) exit(0);
    return true;
  }

  /// Unzips the new MovieCat.app; a script swaps it in once this process has quit.
  Future<void> _installMac(
    File zip, {
    required bool relaunch,
    required int waitFor,
  }) async {
    final stage = Directory(p.join(dir.path, 'updates', 'new'));
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create(recursive: true);
    final unzip = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      zip.path,
      stage.path,
    ]);
    if (unzip.exitCode != 0) {
      throw ProcessException('ditto', [], '${unzip.stderr}', unzip.exitCode);
    }
    final app = Directory(p.join(stage.path, 'MovieCat.app'));
    if (!await app.exists()) {
      throw const FormatException('the download has no MovieCat.app');
    }
    final script = File(p.join(dir.path, 'updates', 'install.sh'));
    await script.writeAsString(macInstallScript);
    await Process.start('/bin/sh', [
      script.path,
      '$waitFor',
      appPath,
      app.path,
      relaunch ? '1' : '0',
    ], mode: ProcessStartMode.detached);
  }

  /// Waits for MovieCat to quit, swaps in the new app (putting the old one back if
  /// that fails) and opens it. Arguments: pid, app, new app, 1 to open it.
  @visibleForTesting
  static const macInstallScript = r'''#!/bin/sh
pid="$1"; app="$2"; new="$3"; relaunch="$4"
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
rm -rf "$app.old"
if mv "$app" "$app.old"; then
  if mv "$new" "$app" 2>/dev/null || ditto "$new" "$app"; then
    rm -rf "$app.old"
  else
    rm -rf "$app"; mv "$app.old" "$app"
  fi
fi
rm -rf "$(dirname "$new")"
[ "$relaunch" = 1 ] && open "$app"
exit 0
''';

  /// Runs the new setup program silently once MovieCat has quit, then starts MovieCat.
  Future<void> _installWindows(
    File setup, {
    required bool relaunch,
    required int waitFor,
  }) async {
    final programFiles = [
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramW6432'],
    ].whereType<String>().map((d) => d.toLowerCase());
    // Install the same way as before: for all users (Program Files) or just this one.
    final scope = programFiles.any((d) => appPath.toLowerCase().startsWith(d))
        ? '/ALLUSERS'
        : '/CURRENTUSER';
    final script = File(p.join(dir.path, 'updates', 'install.cmd'));
    await script.writeAsString(windowsInstallScript);
    await Process.start('cmd', [
      '/c',
      script.path,
      '$waitFor',
      setup.path,
      scope,
      relaunch ? appPath : '',
    ], mode: ProcessStartMode.detached);
  }

  /// Arguments: pid, setup program, /ALLUSERS or /CURRENTUSER, app to start afterwards.
  @visibleForTesting
  static const windowsInstallScript =
      '@echo off\r\n'
      ':wait\r\n'
      'tasklist /FI "PID eq %1" 2>nul | find " %1 " >nul && (ping -n 2 127.0.0.1 >nul & goto wait)\r\n'
      '"%~2" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- %3\r\n'
      'if not "%~4"=="" start "" "%~4"\r\n';

  /// Replaces the AppImage file (Linux allows that while it runs) and starts the new one.
  Future<void> _installAppImage(File image, {required bool relaunch}) async {
    final next = File('$appPath.new');
    await image.copy(next.path);
    final chmod = await Process.run('chmod', ['755', next.path]);
    if (chmod.exitCode != 0) {
      throw ProcessException('chmod', [], '${chmod.stderr}', chmod.exitCode);
    }
    await next.rename(appPath);
    await image.delete();
    if (relaunch) {
      await Process.start(appPath, [], mode: ProcessStartMode.detached);
    }
  }
}
