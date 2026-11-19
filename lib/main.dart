import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/library.dart';
import 'core/platform_access.dart';
import 'core/store.dart';
import 'core/updater.dart';
import 'ui/brand.dart';
import 'ui/library_page.dart';
import 'ui/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformAccess.init();
  final library = Library(await Store.open());
  await library.restoreAccess();
  final updater = Updater(
    currentVersion: (await PackageInfo.fromPlatform()).version,
    install: detectInstall(
      os: Platform.operatingSystem,
      exe: Platform.resolvedExecutable,
      env: Platform.environment,
      sandboxed: PlatformAccess.sandboxed,
    ),
    dir: library.store.dir,
    autoDownload: () => library.store.autoUpdate,
  )..start();
  runApp(MovieCatApp(library: library, updater: updater));
  if (library.store.setupDone && library.store.folders.isNotEmpty) {
    library.scan();
  }
}

class MovieCatApp extends StatelessWidget {
  final Library library;
  final Updater? updater;
  const MovieCatApp({super.key, required this.library, this.updater});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MovieCat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: library,
        builder: (context, _) => library.store.setupDone
            ? LibraryPage(library: library, updater: updater)
            : SetupPage(library: library),
      ),
    );
  }
}
