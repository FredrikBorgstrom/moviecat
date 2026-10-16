import 'dart:convert';

import 'package:http/http.dart' as http;

class HttpError implements Exception {
  final int status;
  final String url;
  HttpError(this.status, this.url);
  @override
  String toString() => 'HTTP $status for $url';
}

final _client = http.Client();

/// GET a JSON document. Retries once on rate limiting / transient errors.
/// Returns null on 404.
Future<dynamic> getJson(Uri url, {Map<String, String> headers = const {}}) async {
  for (var attempt = 0;; attempt++) {
    try {
      final res = await _client.get(url, headers: {
        'User-Agent': 'MovieCat/1.0 (+https://github.com/FredrikBorgstrom/moviecat)',
        'Accept': 'application/json',
        ...headers,
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) return null;
      if ((res.statusCode == 429 || res.statusCode >= 500) && attempt < 2) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        continue;
      }
      if (res.statusCode != 200) throw HttpError(res.statusCode, url.toString());
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on HttpError {
      rethrow;
    } catch (_) {
      if (attempt >= 1) rethrow;
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}

String stripHtml(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .trim();
