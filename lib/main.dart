import 'package:flutter/material.dart';

import 'core/library.dart';
import 'core/platform_access.dart';
import 'core/store.dart';
import 'ui/brand.dart';
import 'ui/library_page.dart';
import 'ui/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformAccess.init();
  final library = Library(await Store.open());
  await library.restoreAccess();
  runApp(MovieCatApp(library: library));
  if (library.store.setupDone && library.store.folders.isNotEmpty) {
    library.scan();
  }
}

class MovieCatApp extends StatelessWidget {
  final Library library;
  const MovieCatApp({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MovieCat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: library,
        builder: (context, _) => library.store.setupDone
            ? LibraryPage(library: library)
            : SetupPage(library: library),
      ),
    );
  }
}
