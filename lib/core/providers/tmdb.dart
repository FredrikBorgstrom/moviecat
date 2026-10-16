import '../filename_parser.dart';
import '../models.dart';
import '../net.dart';
import 'keyless.dart';

/// The Movie Database (themoviedb.org). Needs a free API key, but handles
/// non-English and alternative titles better than the keyless search.
class TmdbProvider implements MetadataProvider {
  final String apiKey;
  TmdbProvider(this.apiKey);

  @override
  String get name => 'TMDB';

  /// Accepts both a v3 "API Key" (32 hex chars) and a v4 "API Read Access Token" (JWT).
  bool get _isBearer => apiKey.length > 40 && apiKey.contains('.');

  Future<dynamic> _get(String path, [Map<String, String> params = const {}]) {
    final query = {...params, if (!_isBearer) 'api_key': apiKey};
    return getJson(
      Uri.https('api.themoviedb.org', '/3$path', query),
      headers: _isBearer ? {'Authorization': 'Bearer $apiKey'} : const {},
    );
  }

  /// Returns null if the key works, otherwise a human-readable problem.
  static Future<String?> validate(String key) async {
    try {
      await TmdbProvider(key.trim())._get('/configuration');
      return null;
    } on HttpError catch (e) {
      return e.status == 401
          ? 'TMDB rejected this key. Copy the "API Key" or "API Read Access Token" exactly.'
          : 'TMDB answered with error ${e.status}.';
    } catch (e) {
      return 'Could not reach TMDB: $e';
    }
  }

  @override
  Future<List<Candidate>> search(String query, {int? year, MediaKind? kind}) async {
    final out = <Candidate>[];
    Future<void> run(MediaKind k) async {
      final isTv = k == MediaKind.series;
      final json = await _get(isTv ? '/search/tv' : '/search/movie', {
        'query': query,
        'include_adult': 'false',
        if (year != null) (isTv ? 'first_air_date_year' : 'year'): '$year',
      });
      final results = ((json?['results'] as List?) ?? []).cast<Map<String, dynamic>>();
      for (final (i, r) in results.take(10).indexed) {
        final date = (r['release_date'] ?? r['first_air_date']) as String? ?? '';
        final poster = r['poster_path'] as String?;
        out.add(Candidate(
          id: 'tmdb:${isTv ? 'tv' : 'movie'}:${r['id']}',
          title: (r['title'] ?? r['name']) as String? ?? '',
          year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
          kind: k,
          posterUrl: poster == null ? null : 'https://image.tmdb.org/t/p/w342$poster',
          subtitle: (r['original_title'] ?? r['original_name']) as String?,
          // TMDB orders by relevance; turn position into a rank-like number.
          rank: (i + 1) * 500,
        ));
      }
    }

    if (kind == MediaKind.series) {
      await run(MediaKind.series);
    } else {
      await run(MediaKind.movie);
      if (kind == null || out.isEmpty) await run(MediaKind.series);
    }
    return out;
  }

  @override
  Future<MediaInfo> details(Candidate c) async {
    final parts = c.id.split(':'); // tmdb:movie:603
    final type = parts[1];
    final j = await _get('/$type/${parts[2]}', {'append_to_response': 'external_ids'});
    final imdbId = (j['imdb_id'] ?? j['external_ids']?['imdb_id']) as String?;
    final date = (j['release_date'] ?? j['first_air_date']) as String? ?? '';
    final runtimes = j['runtime'] ?? ((j['episode_run_time'] as List?)?.firstOrNull);
    final poster = j['poster_path'] as String?;

    final ratings = <String, double>{};
    MediaInfo? imdb;
    if (imdbId != null && imdbId.isNotEmpty) {
      try {
        imdb = await imdbDetails(imdbId, c.kind);
        ratings.addAll(imdb.ratings);
      } catch (_) {}
    }
    final vote = j['vote_average'];
    if (vote is num && vote > 0) ratings['TMDB'] = vote.toDouble();

    return MediaInfo(
      id: (imdbId != null && imdbId.isNotEmpty) ? imdbId : c.id,
      imdbId: (imdbId != null && imdbId.isNotEmpty) ? imdbId : null,
      title: (j['title'] ?? j['name']) as String? ?? c.title,
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : c.year,
      kind: c.kind,
      posterUrl: poster != null ? 'https://image.tmdb.org/t/p/w500$poster' : imdb?.posterUrl,
      ratings: ratings,
      summary: (j['overview'] as String?)?.isNotEmpty == true ? j['overview'] as String : imdb?.summary,
      genres: [for (final g in (j['genres'] as List? ?? [])) g['name'] as String],
      runtime: runtimes is num && runtimes > 0 ? '$runtimes min' : imdb?.runtime,
    );
  }
}
