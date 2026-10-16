import 'filename_parser.dart';

/// A search hit from a metadata source, before full details are fetched.
class Candidate {
  /// Source-specific id: an IMDb id (`tt0133093`) or `tmdb:movie:603`.
  final String id;
  final String? imdbId;
  final String title;
  final int? year;
  final MediaKind kind;
  final String? posterUrl;
  final String? subtitle;

  /// Popularity rank where lower is more popular (IMDb), if known.
  final int? rank;

  const Candidate({
    required this.id,
    required this.title,
    required this.kind,
    this.imdbId,
    this.year,
    this.posterUrl,
    this.subtitle,
    this.rank,
  });
}

/// Everything we show about an identified movie or series.
class MediaInfo {
  final String id;
  final String? imdbId;
  final String title;
  final int? year;
  final MediaKind kind;
  final String? posterUrl;

  /// Audience ratings on a 0–10 scale keyed by source, e.g. {'IMDb': 8.7}.
  /// The first entry is the primary one.
  final Map<String, double> ratings;
  final String? summary;
  final List<String> genres;
  final String? runtime;

  const MediaInfo({
    required this.id,
    required this.title,
    required this.kind,
    this.imdbId,
    this.year,
    this.posterUrl,
    this.ratings = const {},
    this.summary,
    this.genres = const [],
    this.runtime,
  });

  MapEntry<String, double>? get primaryRating =>
      ratings.isEmpty ? null : ratings.entries.first;

  String? get webUrl => imdbId != null
      ? 'https://www.imdb.com/title/$imdbId/'
      : id.startsWith('tmdb:')
          ? 'https://www.themoviedb.org/${id.split(':')[1]}/${id.split(':')[2]}'
          : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'imdbId': imdbId,
        'title': title,
        'year': year,
        'kind': kind.name,
        'posterUrl': posterUrl,
        'ratings': ratings,
        'summary': summary,
        'genres': genres,
        'runtime': runtime,
      };

  factory MediaInfo.fromJson(Map<String, dynamic> j) => MediaInfo(
        id: j['id'] as String,
        imdbId: j['imdbId'] as String?,
        title: j['title'] as String,
        year: j['year'] as int?,
        kind: MediaKind.values.byName(j['kind'] as String? ?? 'movie'),
        posterUrl: j['posterUrl'] as String?,
        ratings: {
          for (final e in ((j['ratings'] as Map?) ?? {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        summary: j['summary'] as String?,
        genres: ((j['genres'] as List?) ?? []).cast<String>(),
        runtime: j['runtime'] as String?,
      );
}

/// Shared interface for keyless and API-key based metadata sources.
abstract class MetadataProvider {
  String get name;
  Future<List<Candidate>> search(String query, {int? year, MediaKind? kind});
  Future<MediaInfo> details(Candidate c);
}
