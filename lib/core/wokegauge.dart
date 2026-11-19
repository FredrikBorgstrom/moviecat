import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'net.dart';

/// A title's rating on wokegauge.com: how prominent progressive messaging is, 0–10.
class WokeRating {
  final double rating;

  /// none, mild, moderate, strong or pervasive.
  final String band;
  final String bandLabel;

  /// Spoiler-free one-sentence verdict.
  final String verdict;

  /// The review on wokegauge.com.
  final String url;

  const WokeRating({
    required this.rating,
    required this.band,
    required this.bandLabel,
    required this.verdict,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'band': band,
        'bandLabel': bandLabel,
        'verdict': verdict,
        'url': url,
      };

  factory WokeRating.fromJson(Map<String, dynamic> j) => WokeRating(
        rating: (j['rating'] as num).toDouble(),
        band: j['band'] as String,
        bandLabel: j['bandLabel'] as String,
        verdict: j['verdict'] as String? ?? '',
        url: j['url'] as String,
      );
}

/// The rating bands of wokegauge.com, in order.
const wokeBands = [
  (id: 'none', label: 'None or negligible', range: '0–1'),
  (id: 'mild', label: 'Mild', range: '1.5–3'),
  (id: 'moderate', label: 'Moderate', range: '3.5–5'),
  (id: 'strong', label: 'Strong', range: '5.5–7.5'),
  (id: 'pervasive', label: 'Pervasive', range: '8–10'),
];

/// WokeGauge's private ratings API. Only MovieCat can use it: each request is signed
/// with a key that release builds get at build time (`--dart-define-from-file=wokegauge.env`)
/// and that is not in the source code.
class WokeGauge {
  static const _key = String.fromEnvironment('WOKEGAUGE_KEY');
  static const _base =
      String.fromEnvironment('WOKEGAUGE_URL', defaultValue: 'https://wokegauge.com');
  static const path = '/api/moviecat/v1/ratings';

  /// Builds without the key, such as builds from source, leave WokeGauge out.
  static bool get enabled => _key.isNotEmpty;

  /// HMAC-SHA256 of `POST <path>\n<unix time>\n<body>`, as the worker checks it.
  static String sign(String key, String time, String body) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode('POST $path\n$time\n$body')).toString();

  /// Ratings for the given title ids (IMDb ids, or `tmdb:movie:603`-style ids).
  /// Titles WokeGauge hasn't reviewed are left out.
  static Future<Map<String, WokeRating>> lookup(List<String> ids) async {
    if (!enabled || ids.isEmpty) return {};
    final body = jsonEncode({'ids': ids});
    final time = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final url = Uri.parse('$_base$path');
    final res = await http.post(url, body: body, headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'MovieCat/1.0 (+https://github.com/FredrikBorgstrom/moviecat)',
      'X-MovieCat-Time': time,
      'X-MovieCat-Signature': sign(_key, time, body),
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw HttpError(res.statusCode, url.toString());
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return {
      for (final e in ((j['ratings'] as Map?) ?? {}).entries)
        e.key as String: WokeRating.fromJson((e.value as Map).cast()),
    };
  }
}
