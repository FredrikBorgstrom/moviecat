import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moviecat/core/store.dart';
import 'package:moviecat/core/wokegauge.dart';

void main() {
  test('signs requests the way the wokegauge.com worker checks them', () {
    // Expected value from Python's hmac module.
    expect(
      WokeGauge.sign('test-key', '1700000000', '{"ids":["tt0133093"]}'),
      '6e65a95cc5405746ce0fda09735dcb1baa1b3eaac8f0833ad575c044779b6b12',
    );
  });

  test('WokeGauge ratings survive a save and reload', () async {
    final dir = await Directory.systemTemp.createTemp('moviecat_test');
    addTearDown(() => dir.delete(recursive: true));
    final store = await Store.at(dir);
    store.wokeRatings['tt0133093'] = const WokeRating(
      rating: 2.5,
      band: 'mild',
      bandLabel: 'Mild',
      verdict: 'A verdict.',
      url: 'https://wokegauge.com/movies/x/',
    );
    await store.saveLibrary();
    final again = await Store.at(dir);
    final w = again.wokeRatings['tt0133093']!;
    expect([w.rating, w.band, w.bandLabel, w.verdict, w.url],
        [2.5, 'mild', 'Mild', 'A verdict.', 'https://wokegauge.com/movies/x/']);
  });
}
