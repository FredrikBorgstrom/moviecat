// Needs a WokeGauge key: flutter test --dart-define=WOKEGAUGE_KEY=test --dart-define=WOKEGAUGE_URL=http://localhost:9
// Without one (as in CI) WokeGauge is left out of the app and these tests are skipped.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moviecat/core/filename_parser.dart';
import 'package:moviecat/core/library.dart';
import 'package:moviecat/core/models.dart';
import 'package:moviecat/core/store.dart';
import 'package:moviecat/core/wokegauge.dart';
import 'package:moviecat/ui/brand.dart';
import 'package:moviecat/ui/library_page.dart';
import 'package:moviecat/ui/widgets.dart';

/// A library of three identified movies, two of them reviewed by WokeGauge.
Future<Library> _library(WidgetTester tester) async {
  late Library lib;
  await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('moviecat_ui');
    addTearDown(() => dir.delete(recursive: true));
    final media = Directory('${dir.path}/media')..createSync();
    final store = await Store.at(Directory('${dir.path}/data')..createSync());
    const titles = [
      ('tt0000001', 'Calm Film', 'none', 0.5),
      ('tt0000002', 'Loud Film', 'strong', 6.0),
      ('tt0000003', 'Plain Film', null, null),
    ];
    for (final (id, title, band, rating) in titles) {
      final f = File('${media.path}/${title.replaceAll(' ', '.')}.2001.mkv')..writeAsStringSync('x');
      store.matches[parseFileName(f.path).queryKey] =
          MediaInfo(id: id, imdbId: id, title: title, year: 2001, kind: MediaKind.movie);
      if (band != null) {
        store.wokeRatings[id] =
            WokeRating(rating: rating!, band: band, bandLabel: band, verdict: '', url: '');
      }
    }
    store.folders.add(media.path);
    store.setupDone = true;
    lib = Library(store);
    await lib.scan();
  });
  return lib;
}

double _x(String title) => find.text(title).evaluate().isEmpty
    ? double.infinity
    : (find.text(title).last.evaluate().first.renderObject as RenderBox)
        .localToGlobal(Offset.zero)
        .dx;

void main() {
  final skip = !WokeGauge.enabled;

  testWidgets('shows WokeGauge badges, filters by band and sorts by rating', (tester) async {
    final lib = await _library(tester);
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LibraryPage(library: lib)));
    await tester.pump();
    expect(find.byType(WokeBadge), findsNWidgets(2));

    // Sort: least woke first, titles without a review last.
    await tester.tap(find.textContaining('Sort:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Woke rating (least woke)'));
    await tester.pumpAndSettle();
    expect(_x('Calm Film') < _x('Loud Film') && _x('Loud Film') < _x('Plain Film'), isTrue);

    // Filter: tick Strong, then also Not reviewed.
    await tester.tap(find.text('Woke: Any'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strong (5.5–7.5)'));
    await tester.pumpAndSettle();
    expect(find.text('Calm Film'), findsNothing);
    expect(find.text('Loud Film'), findsWidgets);
    expect(find.text('Plain Film'), findsNothing);
    await tester.tap(find.text('Not reviewed'));
    await tester.pumpAndSettle();
    expect(find.text('Plain Film'), findsWidgets);
    expect(find.text('Woke: 2 selected'), findsOneWidget);
  }, skip: skip);
}
