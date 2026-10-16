import '../filename_parser.dart';
import '../models.dart';
import '../net.dart';

/// Works without any API key:
/// - IMDb's public search-suggestion endpoint for finding titles,
/// - Cinemeta (Stremio's open metadata service) for IMDb rating, plot and genres,
/// - TVmaze as a fallback for TV shows.
class KeylessProvider implements MetadataProvider {
  @override
  String get name => 'IMDb + Cinemeta';

  static const _movieTypes = {'movie', 'tvMovie', 'video', 'short', 'tvSpecial', 'tvShort'};
  static const _seriesTypes = {'tvSeries', 'tvMiniSeries'};

  @override
  Future<List<Candidate>> search(String query, {int? year, MediaKind? kind}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final first = RegExp(r'[a-z0-9]').firstMatch(q)?.group(0) ?? 'x';
    final url = Uri.parse(
        'https://v3.sg.media-imdb.com/suggestion/$first/${Uri.encodeComponent(q)}.json');
    final json = await getJson(url);
    final list = (json?['d'] as List?) ?? [];
    final out = <Candidate>[];
    for (final d in list.cast<Map<String, dynamic>>()) {
      final id = d['id'] as String? ?? '';
      final qid = d['qid'] as String?;
      if (!id.startsWith('tt') || qid == null) continue;
      final MediaKind k;
      if (_seriesTypes.contains(qid)) {
        k = MediaKind.series;
      } else if (_movieTypes.contains(qid)) {
        k = MediaKind.movie;
      } else {
        continue;
      }
      out.add(Candidate(
        id: id,
        imdbId: id,
        title: d['l'] as String? ?? '',
        year: d['y'] as int?,
        kind: k,
        posterUrl: resizeImdbImage((d['i'] as Map?)?['imageUrl'] as String?),
        subtitle: d['s'] as String?,
        rank: d['rank'] as int?,
      ));
    }
    return out;
  }

  @override
  Future<MediaInfo> details(Candidate c) => imdbDetails(c.imdbId!, c.kind, fallback: c);
}

/// Fetches IMDb rating, plot and genres for an IMDb id via Cinemeta, with TVmaze
/// as fallback for shows. Also used by the TMDB provider to add the IMDb rating.
Future<MediaInfo> imdbDetails(String imdbId, MediaKind kind, {Candidate? fallback}) async {
  final type = kind == MediaKind.series ? 'series' : 'movie';
  Map<String, dynamic>? meta;
  try {
    final json = await getJson(Uri.parse('https://v3-cinemeta.strem.io/meta/$type/$imdbId.json'));
    meta = (json?['meta'] as Map?)?.cast<String, dynamic>();
  } catch (_) {}

  final ratings = <String, double>{};
  final imdbRating = double.tryParse('${meta?['imdbRating'] ?? ''}');
  if (imdbRating != null && imdbRating > 0) ratings['IMDb'] = imdbRating;

  String? summary = meta?['description'] as String?;
  String? poster = fallback?.posterUrl ?? meta?['poster'] as String?;
  final genres = ((meta?['genres'] ?? meta?['genre']) as List?)?.cast<String>() ?? <String>[];
  String? runtime = meta?['runtime'] as String?;

  if (kind == MediaKind.series && (summary == null || ratings.isEmpty || poster == null)) {
    try {
      final show = await getJson(Uri.parse('https://api.tvmaze.com/lookup/shows?imdb=$imdbId'));
      if (show is Map) {
        final r = (show['rating'] as Map?)?['average'];
        if (r is num && ratings.isEmpty) ratings['TVmaze'] = r.toDouble();
        summary ??= show['summary'] is String ? stripHtml(show['summary'] as String) : null;
        poster ??= (show['image'] as Map?)?['medium'] as String?;
        if (genres.isEmpty) genres.addAll(((show['genres'] as List?) ?? []).cast<String>());
        final rt = show['averageRuntime'] ?? show['runtime'];
        if (runtime == null && rt is num) runtime = '$rt min';
      }
    } catch (_) {}
  }

  final yearStr = '${meta?['year'] ?? meta?['releaseInfo'] ?? ''}';
  return MediaInfo(
    id: imdbId,
    imdbId: imdbId,
    title: (meta?['name'] as String?) ?? fallback?.title ?? imdbId,
    // IMDb's own year is the original release; Cinemeta sometimes has a regional one.
    year: fallback?.year ?? int.tryParse(RegExp(r'\d{4}').firstMatch(yearStr)?.group(0) ?? ''),
    kind: kind,
    posterUrl: poster,
    ratings: ratings,
    summary: summary,
    genres: genres,
    runtime: runtime,
  );
}

/// IMDb image URLs can be resized by rewriting the `_V1_` suffix.
String? resizeImdbImage(String? url) {
  if (url == null) return null;
  return url.replaceFirst(RegExp(r'\._V1_.*\.jpg$'), '._V1_QL75_UX400_.jpg');
}
