// Dev tool: shows how file names are parsed and matched.
//   dart run tool/identify.dart "The.Matrix.1999.1080p.mkv" "Breaking.Bad.S01E01.mkv"
// Set TMDB_KEY in the environment to use TMDB instead of the keyless sources.
import 'dart:io';

import 'package:moviecat/core/filename_parser.dart';
import 'package:moviecat/core/matcher.dart';
import 'package:moviecat/core/models.dart';
import 'package:moviecat/core/providers/keyless.dart';
import 'package:moviecat/core/providers/tmdb.dart';

Future<void> main(List<String> args) async {
  final key = Platform.environment['TMDB_KEY'];
  final MetadataProvider provider =
      key != null && key.isNotEmpty ? TmdbProvider(key) : KeylessProvider();
  final matcher = Matcher(provider);
  for (final a in args) {
    final parsed = parseFileName(a);
    stdout.writeln('$a\n  parsed: $parsed');
    final info = await matcher.identify(parsed);
    if (info == null) {
      stdout.writeln('  -> no match');
      continue;
    }
    stdout.writeln('  -> ${info.title} (${info.year}) [${info.kind.name}] ${info.id} '
        '${info.ratings} ${info.genres.join(', ')} ${info.runtime ?? ''}');
    stdout.writeln('     ${(info.summary ?? '').replaceAll('\n', ' ')}');
    stdout.writeln('     poster: ${info.posterUrl}');
  }
  exit(0);
}
