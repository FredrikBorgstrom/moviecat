import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moviecat/core/updater.dart';
import 'package:path/path.dart' as p;

/// Serves files from a map of path -> bytes on localhost.
Future<HttpServer> serve(Map<String, List<int>> files) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = files[req.uri.path];
    req.response.statusCode = body == null ? 404 : 200;
    if (body != null) req.response.add(body);
    req.response.close();
  });
  return server;
}

void main() {
  test('compares versions numerically', () {
    expect(compareVersions('1.10.0', '1.9.2'), greaterThan(0));
    expect(compareVersions('1.2.0', '1.2.0+9'), 0);
    expect(compareVersions('1.2', '1.2.1'), lessThan(0));
    expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
  });

  group('detectInstall', () {
    InstallKind detect(String os, String exe,
            {Map<String, String> env = const {}, bool sandboxed = false, bool writable = true}) =>
        detectInstall(os: os, exe: exe, env: env, sandboxed: sandboxed, writable: (_) => writable);

    test('Mac App Store and read-only copies are not updated in place', () {
      const exe = '/Applications/MovieCat.app/Contents/MacOS/MovieCat';
      expect(detect('macos', exe).channel, UpdateChannel.self);
      expect(detect('macos', exe, sandboxed: true).channel, UpdateChannel.managed);
      expect(detect('macos', exe, writable: false).channel, UpdateChannel.notify);
      expect(
          detect('macos', '/private/var/folders/x/AppTranslocation/y/d/MovieCat.app/Contents/MacOS/MovieCat')
              .channel,
          UpdateChannel.notify);
    });

    test('Linux: AppImage updates itself, Snap and system packages do not', () {
      expect(detect('linux', '/tmp/.mount_x/moviecat', env: {'APPIMAGE': '/home/a/MovieCat.AppImage'}).channel,
          UpdateChannel.self);
      expect(detect('linux', '/snap/moviecat/1/moviecat', env: {'SNAP': '/snap/moviecat/1'}).channel,
          UpdateChannel.managed);
      expect(detect('linux', '/usr/lib/moviecat/moviecat').channel, UpdateChannel.managed);
      expect(detect('linux', '/home/a/moviecat/moviecat').channel, UpdateChannel.notify);
    });

    test('Windows: Store and Scoop copies are managed, a zip copy only notifies', () {
      expect(detect('windows', r'C:\Program Files\WindowsApps\AB.MovieCat_1.0\moviecat.exe').channel,
          UpdateChannel.managed);
      expect(detect('windows', r'C:\Users\a\scoop\apps\moviecat\current\moviecat.exe').channel,
          UpdateChannel.managed);
      expect(detect('windows', r'C:\Users\a\Downloads\MovieCat\moviecat.exe').channel, UpdateChannel.notify);
    });
  });

  group('Updater', () {
    late Directory dir;
    late HttpServer server;
    late String publicKey;
    final files = <String, List<int>>{};
    final payload = utf8.encode('new MovieCat build');

    Future<void> publish(Map<String, dynamic> feed, {bool tamper = false}) async {
      final kp = await DartEd25519().newKeyPair();
      publicKey = base64.encode((await kp.extractPublicKey()).bytes);
      final bytes = utf8.encode(jsonEncode(feed));
      final sig = await DartEd25519().sign(bytes, keyPair: kp);
      files['/update.json'] = tamper ? utf8.encode(jsonEncode({...feed, 'version': '9.9.9'})) : bytes;
      files['/update.json.sig'] = sig.bytes;
    }

    Map<String, dynamic> feed(String version, {List<int>? file}) => {
          'version': version,
          'notes': 'What is new.',
          'page': 'https://example.com/release',
          'assets': {
            'linux': {
              'name': 'MovieCat-x86_64.AppImage',
              'url': 'http://localhost:${server.port}/app',
              'sha256': crypto.sha256.convert(file ?? payload).toString(),
              'size': (file ?? payload).length,
            },
          },
        };

    Updater updater({String current = '1.2.0'}) => Updater(
          currentVersion: current,
          install: const InstallKind(UpdateChannel.self),
          dir: dir,
          autoDownload: () => true,
          platform: 'linux',
          appPath: p.join(dir.path, 'MovieCat.AppImage'),
          feed: 'http://localhost:${server.port}/update.json',
          publicKey: publicKey,
        );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('moviecat_update');
      files.clear();
      server = await serve(files);
      files['/app'] = payload;
    });
    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    test('finds a newer version, downloads and checks it', () async {
      await publish(feed('1.3.0'));
      final u = updater();
      await u.check();
      expect(u.error, isNull);
      expect(u.available?.version, '1.3.0');
      expect(await u.ready!.readAsBytes(), payload);
    });

    test('ignores the same or an older version', () async {
      await publish(feed('1.2.0'));
      final u = updater();
      await u.check();
      expect(u.available, isNull);
      expect(u.error, isNull);
    });

    test('no feed yet is not an error', () async {
      final kp = await DartEd25519().newKeyPair();
      publicKey = base64.encode((await kp.extractPublicKey()).bytes);
      final u = updater();
      await u.check();
      expect(u.available, isNull);
      expect(u.error, isNull);
    });

    test('rejects a feed whose signature does not match', () async {
      await publish(feed('1.3.0'), tamper: true);
      final u = updater();
      await u.check();
      expect(u.available, isNull);
      expect(u.error, contains('invalid signature'));
    });

    test('rejects a download that does not match the feed', () async {
      await publish(feed('1.3.0', file: utf8.encode('something else')));
      final u = updater();
      await u.check();
      expect(u.available?.version, '1.3.0');
      expect(u.ready, isNull);
      expect(u.error, contains('does not match'));
      expect(Directory(p.join(dir.path, 'updates')).listSync(), isEmpty);
    });

    test('AppImage: replaces the file in place', () async {
      await publish(feed('1.3.0'));
      final app = File(p.join(dir.path, 'MovieCat.AppImage'))..writeAsStringSync('old');
      final u = updater();
      await u.check();
      expect(await u.installAndRestart(relaunch: false, quit: false), isTrue, reason: u.error);
      expect(await app.readAsBytes(), payload);
      if (!Platform.isWindows) {
        expect((await app.stat()).modeString(), 'rwxr-xr-x');
      }
    });

    test('macOS: swaps in the new MovieCat.app once the app has quit', () async {
      // The new version, zipped the way CI does it (ditto -c -k --keepParent).
      final build = Directory(p.join(dir.path, 'build', 'MovieCat.app', 'Contents'))..createSync(recursive: true);
      File(p.join(build.path, 'version')).writeAsStringSync('1.3.0');
      final zip = p.join(dir.path, 'MovieCat-macos.zip');
      await Process.run('ditto', ['-c', '-k', '--keepParent', p.dirname(build.path), zip]);
      final bytes = await File(zip).readAsBytes();
      files['/app'] = bytes;
      final f = feed('1.3.0', file: bytes);
      f['assets'] = {'macos': {...(f['assets'] as Map)['linux'], 'name': 'MovieCat-macos.zip'}};
      await publish(f);

      final installed = Directory(p.join(dir.path, 'Applications', 'MovieCat.app', 'Contents'))
        ..createSync(recursive: true);
      File(p.join(installed.path, 'version')).writeAsStringSync('1.2.0');
      final u = Updater(
        currentVersion: '1.2.0',
        install: const InstallKind(UpdateChannel.self),
        dir: Directory(p.join(dir.path, 'support'))..createSync(),
        autoDownload: () => true,
        platform: 'macos',
        appPath: p.dirname(installed.path),
        feed: 'http://localhost:${server.port}/update.json',
        publicKey: publicKey,
      );
      await u.check();
      final ended = await Process.start('true', []);
      await ended.exitCode;
      expect(await u.installAndRestart(relaunch: false, quit: false, waitFor: ended.pid), isTrue,
          reason: u.error);
      final version = File(p.join(installed.path, 'version'));
      for (var i = 0; i < 50 && version.readAsStringSync() != '1.3.0'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(version.readAsStringSync(), '1.3.0');
      expect(Directory('${p.dirname(installed.path)}.old').existsSync(), isFalse);
    }, skip: !Platform.isMacOS);
  });
}
