import 'package:path/path.dart' as p;

/// File extensions treated as video files.
const videoExtensions = {
  '.mkv', '.mp4', '.m4v', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mpg',
  '.mpeg', '.ts', '.m2ts', '.mts', '.vob', '.iso', '.divx', '.ogm', '.ogv',
  '.3gp', '.rmvb', '.asf',
};

bool isVideoFile(String path) =>
    videoExtensions.contains(p.extension(path).toLowerCase());

enum MediaKind { movie, series }

/// What we could learn about a title from a file name alone.
class ParsedName {
  final String title;
  final int? year;
  final MediaKind kind;
  final int? season;
  final int? episode;

  const ParsedName({
    required this.title,
    this.year,
    this.kind = MediaKind.movie,
    this.season,
    this.episode,
  });

  /// Stable key used to cache lookups; all episodes of a show share it.
  String get queryKey =>
      '${kind.name}|${normalizeTitle(title)}|${kind == MediaKind.movie ? (year ?? '') : ''}';

  @override
  String toString() =>
      'ParsedName($title, $year, ${kind.name}, S$season E$episode)';
}

/// Lowercase, strip accents/punctuation, collapse spaces. Used for comparing titles.
String normalizeTitle(String s) {
  var t = s.toLowerCase().replaceAll('&', ' and ');
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i',
    'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
    'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y',
    'ÿ': 'y', 'ß': 'ss',
  };
  accents.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll(RegExp(r"['’]"), '');
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return t;
}

// Release-name noise. Everything from the first of these tokens onwards is dropped.
final _junk = RegExp(
  r'\b('
  r'2160p|1080p|1080i|720p|576p|480p|4k|uhd|hdr|hdr10|dv|dolby|vision|'
  r'bluray|blu ray|bdrip|brrip|bdremux|remux|web|webrip|web dl|webdl|hdtv|hdrip|'
  r'dvdrip|dvdscr|dvd|dvd5|dvd9|xvid|divx|x264|x265|h264|h 264|h265|h 265|hevc|avc|'
  r'10bit|8bit|aac|aac2|ac3|dts|dts hd|truehd|atmos|ddp|ddp5|dd5|eac3|flac|mp3|'
  r'5 1|7 1|2 0|proper|repack|rerip|extended|unrated|uncut|remastered|'
  r'directors cut|theatrical|limited|internal|complete|multi|multisubs|subbed|'
  r'dubbed|nordic|swesub|nlsub|hc|cam|ts|tc|r5|imax|amzn|nf|dsnp|hmax|atvp|hulu'
  r')\b',
  caseSensitive: false,
);

// Names that tell us nothing; fall back to the parent folder.
final _genericName = RegExp(
  r'^(movie|film|video|main|feature|title\d*|vts \d+ \d+|cd ?\d|disc ?\d|part ?\d|\d{1,3})$',
);

final _seasonEpisode = [
  RegExp(r'\bs(\d{1,2})[ ._-]?e(\d{1,3})', caseSensitive: false), // S01E02, s1e2
  RegExp(r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false), // 1x02
  RegExp(r'\bseason[ ._-]?(\d{1,2})[ ._-]*episode[ ._-]?(\d{1,3})',
      caseSensitive: false),
];
final _seasonOnly = RegExp(r'\b(?:s|season[ ._-]?)(\d{1,2})\b', caseSensitive: false);

/// Parses something like `The.Matrix.1999.1080p.BluRay.x264-GRP.mkv`
/// or `Breaking.Bad.S01E02.720p.mkv` into a title, year and kind.
ParsedName parseFileName(String path) {
  final base = p.basenameWithoutExtension(path);
  var parsed = parseName(base);

  // Generic names ("movie.mkv", "CD1.avi") or bare episode names ("S01E02.mkv")
  // carry no title, so use the containing folder(s).
  final segments = p.split(p.dirname(path));
  var i = segments.length - 1;
  while ((parsed.title.isEmpty || _genericName.hasMatch(normalizeTitle(parsed.title))) &&
      i >= 0) {
    final folder = parseName(segments[i]);
    i--;
    if (folder.title.isEmpty || _genericName.hasMatch(normalizeTitle(folder.title))) {
      continue;
    }
    // A "Season 2" folder: keep climbing to find the show name.
    if (RegExp(r'^(season|series|s) ?\d+$').hasMatch(normalizeTitle(folder.title))) {
      continue;
    }
    parsed = ParsedName(
      title: folder.title,
      year: parsed.year ?? folder.year,
      kind: parsed.kind == MediaKind.series ? MediaKind.series : folder.kind,
      season: parsed.season ?? folder.season,
      episode: parsed.episode ?? folder.episode,
    );
  }
  return parsed;
}

/// Parses a single name (file or folder name without extension).
ParsedName parseName(String raw) {
  var s = raw;
  // Drop bracketed release-group tags at the start: "[Group] Title".
  s = s.replaceFirst(RegExp(r'^(\[[^\]]*\]\s*)+'), '');
  // Dots/underscores are word separators in release names.
  s = s.replaceAll(RegExp(r'[._]+'), ' ');
  // Trailing "-GROUP" release tag (only on release-style names, so "Spider-Man" survives).
  if (_junk.hasMatch(s)) s = s.replaceFirst(RegExp(r'-[A-Za-z0-9]+$'), '');

  // TV episode markers.
  for (final re in _seasonEpisode) {
    final m = re.firstMatch(s);
    if (m != null) {
      final before = s.substring(0, m.start);
      final yearInTitle = _findYear(before);
      return ParsedName(
        title: _cleanTitle(yearInTitle?.title ?? before),
        year: yearInTitle?.year,
        kind: MediaKind.series,
        season: int.parse(m.group(1)!),
        episode: int.parse(m.group(2)!),
      );
    }
  }
  // Anime style: "Show Name - 05".
  final anime = RegExp(r'^(.+?)\s+-\s+(\d{1,4})(?:v\d)?(?:\s|$|\[|\()').firstMatch(s);
  if (anime != null && raw.startsWith('[')) {
    return ParsedName(
      title: _cleanTitle(anime.group(1)!, stripJunk: true),
      kind: MediaKind.series,
      episode: int.parse(anime.group(2)!),
    );
  }

  final y = _findYear(s);
  if (y != null) {
    return ParsedName(title: _cleanTitle(y.title), year: y.year);
  }

  final season = _seasonOnly.firstMatch(s);
  if (season != null && season.start > 0) {
    return ParsedName(
      title: _cleanTitle(s.substring(0, season.start), stripJunk: true),
      kind: MediaKind.series,
      season: int.parse(season.group(1)!),
    );
  }
  return ParsedName(title: _cleanTitle(s, stripJunk: true));
}

class _YearSplit {
  final String title;
  final int year;
  _YearSplit(this.title, this.year);
}

/// Finds the release year. Picks the last plausible year that isn't at the very
/// start, so "Blade Runner 2049 2017", "2001 A Space Odyssey 1968" and "1917" work.
_YearSplit? _findYear(String s) {
  final maxYear = DateTime.now().year + 1;
  final matches = RegExp(r'\b(19\d{2}|20\d{2})\b')
      .allMatches(s)
      .where((m) => int.parse(m.group(1)!) <= maxYear)
      .toList();
  for (final m in matches.reversed) {
    if (s.substring(0, m.start).trim().isEmpty) continue;
    return _YearSplit(s.substring(0, m.start), int.parse(m.group(1)!));
  }
  return null;
}

String _cleanTitle(String s, {bool stripJunk = false}) {
  var t = s;
  if (stripJunk) {
    final junk = _junk.firstMatch(t);
    if (junk != null && junk.start > 0) t = t.substring(0, junk.start);
  }
  t = t.replaceAll(RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]'), ' '); // bracketed bits
  t = t.replaceAll(RegExp(r'[\[\]\(\)\{\}]'), ' ');
  t = t.replaceAll(RegExp(r'\s+-\s*$'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'[\s\-,:]+$'), '');
  return t;
}
