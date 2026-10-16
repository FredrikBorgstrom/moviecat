import 'package:path/path.dart' as p;

import 'filename_parser.dart';
import 'matcher.dart';

/// Rules for telling real movies/TV episodes apart from home videos, screen
/// recordings, tutorials and the like. Used by auto-discovery and by "strict"
/// folders, where only confidently recognised titles are shown.

/// Smaller files are almost never a movie or a TV episode.
const minMediaBytes = 30 * 1024 * 1024;

// Camera, phone and recorder file names: IMG_1234.MOV, PXL_20240101_..., GOPR0042.MP4,
// 20230501_123456.mp4, 2023-05-01 12.30.00.mov, Screen Recording 2024-...
final _deviceName = RegExp(
  r'^(img|dsc[nf]?|mvi|vid|pxl|gopr|gh\d\d|gx\d\d|dji|mah|clip|mov|rec|untitled|video|movie)[ _-]?\d{3,}'
  r'|^\d{8}[ _-]\d{4,6}'
  r'|^\d{4}-\d{2}-\d{2}'
  r'|^(screen recording|skarminspelning|bildschirmaufnahme|screencast|screenshot|whatsapp video|signal-)',
);

// Anywhere in the path, these mean "not a movie".
const _strongWords = {
  'tutorial', 'tutorials', 'lesson', 'lessons', 'lecture', 'lectures', 'course',
  'courses', 'webinar', 'webinars', 'udemy', 'coursera', 'skillshare', 'pluralsight',
  'egghead', 'screencast', 'screencasts', 'gameplay', 'vlog', 'dcim', 'imovie',
  'whatsapp', 'obs', 'camtasia', 'loom',
};
const _strongPhrases = [
  'camera roll', 'camera uploads', 'screen recording', 'screen recordings',
  'final cut', 'linkedin learning', 'how to', 'iphone videos', 'phone videos',
  'home video', 'home videos',
];

// In the file name, these mean "not a movie" unless it looks like a release.
const _weakWords = {
  'wedding', 'birthday', 'vacation', 'meeting', 'recording', 'presentation',
  'demo', 'zoom', 'teams', 'interview', 'module', 'chapter', 'workshop', 'training',
};

/// True if [path] looks like a personal video, recording or tutorial.
bool looksPersonal(String path) {
  final base = p.basenameWithoutExtension(path);
  final name = normalizeTitle(base);
  if (_deviceName.hasMatch(base.toLowerCase()) || _deviceName.hasMatch(name)) return true;

  final segments = p.split(p.dirname(path)).map(normalizeTitle).toList();
  for (final s in [...segments, name]) {
    final words = s.split(' ');
    if (words.any(_strongWords.contains)) return true;
    if (_strongPhrases.any((ph) => ' $s '.contains(' $ph '))) return true;
  }

  final parsed = parseFileName(path);
  final looksLikeRelease = hasReleaseTokens(base) || parsed.episode != null;
  if (!looksLikeRelease && name.split(' ').any(_weakWords.contains)) return true;
  return false;
}

/// Whether a match is trustworthy enough to show a file from a strict folder.
bool isConfidentMatch(String path, ParsedName parsed, double score) {
  if (score >= Matcher.confidentScore) return true;
  if (score < Matcher.minScore) return false;
  // A reasonable match plus a year, an episode number or release tokens.
  return parsed.year != null ||
      parsed.episode != null ||
      hasReleaseTokens(p.basenameWithoutExtension(path));
}
