import 'package:flutter_test/flutter_test.dart';
import 'package:moviecat/core/filename_parser.dart';

void main() {
  void expectParsed(String path, String title,
      {int? year, MediaKind kind = MediaKind.movie, int? season, int? episode}) {
    final r = parseFileName(path);
    expect(r.title, title, reason: path);
    expect(r.year, year, reason: path);
    expect(r.kind, kind, reason: path);
    if (season != null) expect(r.season, season, reason: path);
    if (episode != null) expect(r.episode, episode, reason: path);
  }

  test('movies', () {
    expectParsed('/m/The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv', 'The Matrix', year: 1999);
    expectParsed('/m/The Matrix (1999).mkv', 'The Matrix', year: 1999);
    expectParsed('/m/Blade.Runner.2049.2017.2160p.UHD.mkv', 'Blade Runner 2049', year: 2017);
    expectParsed('/m/2001.A.Space.Odyssey.1968.mkv', '2001 A Space Odyssey', year: 1968);
    expectParsed('/m/1917.2019.1080p.WEB-DL.mp4', '1917', year: 2019);
    expectParsed('/m/1917.mp4', '1917');
    expectParsed('/m/Spider-Man.2002.720p.mkv', 'Spider-Man', year: 2002);
    expectParsed('/m/Spider-Man.mkv', 'Spider-Man');
    expectParsed('/m/Amélie [2001] DVDRip XviD.avi', 'Amélie', year: 2001);
    expectParsed('/m/Inception 1080p BluRay.mkv', 'Inception');
    expectParsed('/m/A.Complete.Unknown.2024.1080p.mkv', 'A Complete Unknown', year: 2024);
  });

  test('generic file names use the folder', () {
    expectParsed('/m/Heat (1995)/movie.mkv', 'Heat', year: 1995);
    expectParsed('/m/Heat (1995)/CD1.avi', 'Heat', year: 1995);
    expectParsed('/m/Alien.1979.Directors.Cut/VIDEO_TS/VTS_01_1.vob', 'Alien', year: 1979);
  });

  test('tv episodes', () {
    expectParsed('/tv/Breaking.Bad.S01E02.720p.HDTV.mkv', 'Breaking Bad',
        kind: MediaKind.series, season: 1, episode: 2);
    expectParsed('/tv/the office us 2x05.avi', 'the office us',
        kind: MediaKind.series, season: 2, episode: 5);
    expectParsed('/tv/Doctor.Who.2005.S03E10.mkv', 'Doctor Who',
        year: 2005, kind: MediaKind.series, season: 3, episode: 10);
    expectParsed('/tv/Fargo/Season 2/S02E03.mkv', 'Fargo',
        kind: MediaKind.series, season: 2, episode: 3);
    expectParsed('/tv/[SubsPlease] Frieren - 05 (1080p) [ABC123].mkv', 'Frieren',
        kind: MediaKind.series, episode: 5);
  });

  test('episodes of one show share a query key', () {
    expect(parseFileName('/a/Lost.S01E01.mkv').queryKey,
        parseFileName('/b/lost.s04e10.720p.mkv').queryKey);
  });

  test('video extension filter', () {
    expect(isVideoFile('/a/b.MKV'), isTrue);
    expect(isVideoFile('/a/b.srt'), isFalse);
  });
}
