import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moviecat/core/library.dart';
import 'package:moviecat/core/store.dart';
import 'package:moviecat/core/updater.dart';
import 'package:moviecat/ui/library_page.dart';

void main() {
  Future<void> pump(WidgetTester tester, UpdateChannel channel) async {
    late Library lib;
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('moviecat_banner');
      lib = Library(await Store.at(dir));
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final u = Updater(
      currentVersion: '1.2.0',
      install: InstallKind(channel),
      dir: dir,
      autoDownload: () => false,
      feed: 'http://localhost:9/update.json',
    )..available = const UpdateInfo(version: '1.3.0', notes: '', page: 'https://example.com', assets: {});
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LibraryPage(library: lib, updater: u)));
  }

  testWidgets('offers "Restart to update" when MovieCat can install it', (tester) async {
    await pump(tester, UpdateChannel.self);
    expect(find.textContaining('MovieCat 1.3.0 is available.'), findsOneWidget);
    expect(find.text('Restart to update'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.textContaining('MovieCat 1.3.0'), findsNothing);
  });

  testWidgets('offers a download when it cannot', (tester) async {
    await pump(tester, UpdateChannel.notify);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Restart to update'), findsNothing);
  });
}
