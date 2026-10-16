import 'dart:math';

import 'filename_parser.dart';
import 'models.dart';

/// Picks the best search candidate for a parsed file name.
class Matcher {
  final MetadataProvider provider;
  Matcher(this.provider);

  static const minScore = 35.0;

  /// Score at or above which a match is trusted even without other evidence.
  static const confidentScore = 72.0;

  Future<MediaInfo?> identify(ParsedName parsed) async =>
      (await identifyScored(parsed)).info;

  /// Like [identify], but also returns the match score (0 when nothing matched).
  Future<({MediaInfo? info, double score})> identifyScored(ParsedName parsed) async {
    final best = await bestCandidate(parsed);
    if (best == null) return (info: null, score: 0.0);
    return (info: await provider.details(best.candidate), score: best.score);
  }

  Future<({Candidate candidate, double score})?> bestCandidate(ParsedName parsed) async {
    if (parsed.title.isEmpty) return null;
    final words = parsed.title.split(' ');
    // Try the full title first, then with the year, then progressively shorter
    // (release names sometimes carry extra words like a language or edition).
    final queries = <String>[
      parsed.title,
      if (parsed.year != null) '${parsed.title} ${parsed.year}',
      for (var n = words.length - 1; n >= 2 && n >= words.length - 2; n--)
        words.take(n).join(' '),
    ];
    for (final (qi, q) in queries.indexed) {
      final results = await provider.search(q, year: parsed.year, kind: parsed.kind);
      // A weak title resemblance is only trusted for the search engine's top hit on
      // the plain title (it matches foreign/alternative titles, e.g. "Det Sjunde
      // Inseglet" -> "The Seventh Seal"). Fallback queries must really resemble it.
      final scored = [
        for (final (i, c) in results.indexed)
          if (titleScore(parsed.title, c.title) >= 24 || (qi == 0 && i == 0))
            (c, score(parsed, c))
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      if (scored.isNotEmpty && scored.first.$2 >= minScore) {
        return (candidate: scored.first.$1, score: scored.first.$2);
      }
    }
    return null;
  }

  /// 0–50: how much two titles resemble each other.
  static double titleScore(String parsedTitle, String candidateTitle) {
    final a = normalizeTitle(parsedTitle);
    final b = normalizeTitle(candidateTitle);
    if (a == b) return 50;
    if (_stripArticle(a) == _stripArticle(b)) return 45;
    // "Frieren" -> "Frieren: Beyond Journey's End"
    if (a.isNotEmpty && (b.startsWith('$a ') || a.startsWith('$b '))) return 30;
    final ta = a.split(' ').toSet(), tb = b.split(' ').toSet();
    return 40 * ta.intersection(tb).length / ta.union(tb).length;
  }

  static double score(ParsedName parsed, Candidate c) {
    var s = titleScore(parsed.title, c.title);

    if (parsed.year != null && c.year != null) {
      final diff = (parsed.year! - c.year!).abs();
      s += diff == 0 ? 30 : diff == 1 ? 15 : -25;
    }

    if (parsed.kind == MediaKind.series) {
      s += c.kind == MediaKind.series ? 20 : -30;
    } else if (c.kind == MediaKind.movie) {
      s += 5;
    }

    // Popularity tiebreaker: the famous one is more likely to be on someone's disk.
    if (c.rank != null && c.rank! > 0) {
      s += max(0, 10 - log(c.rank!) / ln10 * 2);
    }
    return s;
  }

  static String _stripArticle(String s) =>
      s.replaceFirst(RegExp(r'^(the|a|an) '), '');
}
