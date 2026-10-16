import 'package:flutter/material.dart';

import 'core/library.dart';
import 'core/platform_access.dart';
import 'core/store.dart';
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
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5B301), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'MovieCat',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: ListenableBuilder(
        listenable: library,
        builder: (context, _) => library.store.setupDone
            ? LibraryPage(library: library)
            : SetupPage(library: library),
      ),
    );
  }
}
