import 'package:flutter_test/flutter_test.dart';
import 'package:moviecat/core/filename_parser.dart';
import 'package:moviecat/core/media_filter.dart';

void main() {
  test('personal videos, recordings and tutorials are recognised', () {
    for (final path in [
      '/u/Downloads/IMG_1234.MOV',
      '/u/Movies/PXL_20240101_123456.mp4',
      '/u/Desktop/Screen Recording 2024-03-01 at 10.00.00.mov',
      '/u/Movies/20230501_123456.mp4',
      '/u/Movies/2023-05-01 party.mp4',
      '/u/Downloads/React Hooks Tutorial.mp4',
      '/u/Courses/Flutter Bootcamp/01 - Introduction.mp4',
      '/u/Udemy/Section 3/Widgets.mp4',
      '/u/Videos/Birthday party 2019.mp4',
      '/u/Videos/our wedding.mov',
      '/u/Pictures/Camera Roll/clip.mp4',
      '/u/Movies/GOPR0042.MP4',
    ]) {
      expect(looksPersonal(path), isTrue, reason: path);
    }
  });

  test('real movie and episode names are not treated as personal', () {
    for (final path in [
      '/u/Movies/The.Matrix.1999.1080p.BluRay.x264-GRP.mkv',
      '/u/Movies/Heat (1995)/movie.mkv',
      '/u/Downloads/Wedding.Crashers.2005.1080p.WEB-DL.mkv',
      '/u/TV/Breaking Bad/Season 1/Breaking.Bad.S01E01.mkv',
      '/u/Movies/Inception (2010).mkv',
      '/u/Movies/1917.2019.mkv',
      '/u/Movies/Movie.43.2013.mkv',
    ]) {
      expect(looksPersonal(path), isFalse, reason: path);
    }
  });

  test('confidence needs a strong score or supporting evidence', () {
    final withYear = parseFileName('/m/Heat.1995.mkv');
    final bare = parseFileName('/m/Heat.mkv');
    expect(isConfidentMatch('/m/Heat.1995.mkv', withYear, 50), isTrue);
    expect(isConfidentMatch('/m/Heat.mkv', bare, 50), isFalse);
    expect(isConfidentMatch('/m/Heat.mkv', bare, 80), isTrue);
    expect(isConfidentMatch('/m/Heat.1080p.mkv', parseFileName('/m/Heat.1080p.mkv'), 50), isTrue);
    expect(isConfidentMatch('/m/Heat.1995.mkv', withYear, 20), isFalse);
  });
}
