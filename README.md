# MovieCat

A desktop app for **macOS, Windows and Linux** that scans your folders for movie and TV files, recognises each title from its file name, and shows the poster, rating, year and a short summary.

**No API key or account needed.** MovieCat works out of the box with free public sources. A free TMDB key is optional.

## Features

- Add any number of folders; they're scanned recursively for video files (`.mkv`, `.mp4`, `.avi`, `.mov`, `.m4v`, `.iso`, …).
- **Find movies automatically**: searches your home folder and external drives, checks every video against IMDb, and proposes the folders that hold movies or TV shows. Home videos, screen recordings, phone clips and tutorials are left out. Folders that mix movies with other videos are added in *strict* mode (filter icon on the folder chip): only recognised titles are shown, also for files added later. Click a folder chip to switch strict mode on or off.
- Understands typical release names:
  - `The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv` → *The Matrix* (1999)
  - `Breaking.Bad.S01E02.720p.mkv`, `the office 2x05.avi` → TV episodes, grouped per show
  - `Heat (1995)/movie.mkv`, `Fargo/Season 2/S02E03.mkv` → falls back to folder names
  - `[SubsPlease] Frieren - 05 (1080p).mkv` → anime-style episodes
  - Foreign titles: `Det.Sjunde.Inseglet.1957.mkv` → *The Seventh Seal*
- Poster grid with IMDb rating, filter (Movies / TV / Unrecognised), search and sort.
- Detail view with summary, genres, runtime, your own 1–10 rating, the files (play or show in folder) and a link to IMDb.
- **Fix match**: if a title is wrong or unrecognised, search and pick the right one. Your choice is remembered.
- Results are cached, so rescans are instant.

## Where the data comes from

| Source | Used for | Key needed |
|---|---|---|
| IMDb search suggestions (`v3.sg.media-imdb.com`) | Finding titles, posters | No |
| [Cinemeta](https://v3-cinemeta.strem.io) (Stremio's open metadata API) | IMDb rating, plot, genres, runtime | No |
| [TVmaze](https://www.tvmaze.com/api) | Fallback for TV show info | No |
| [TMDB](https://www.themoviedb.org) | Optional: better matching of foreign / obscure titles | Free key |

TheTVDB was left out on purpose: it now requires a paid subscription or project key, while TVmaze and TMDB cover the same ground for free.

### Optional: adding a TMDB key

The welcome screen (and **Settings**) walks you through it:

1. Create a free account at <https://www.themoviedb.org/signup>.
2. Go to <https://www.themoviedb.org/settings/api>, click **Create → Developer**; any app name/URL works.
3. Copy the **API Read Access Token** (or the shorter **API Key**), paste it in MovieCat and press **Test**.

The key is stored only on your computer, in the app's data folder (shown in Settings).

## Download

Prebuilt apps are attached to each [release](https://github.com/FredrikBorgstrom/moviecat/releases):

- **macOS**: `MovieCat-macos.zip`. The app is not signed, so the first time right-click it → **Open**, or run `xattr -cr MovieCat.app`.
- **Windows**: `MovieCat-windows-x64.zip`, unzip and run `moviecat.exe`.
- **Linux**: `MovieCat-linux-x64.tar.gz`, extract and run `./moviecat` (needs GTK 3).

## Building from source

Requires [Flutter](https://docs.flutter.dev/get-started/install) (stable channel) plus the desktop toolchain for your OS (Xcode on macOS, Visual Studio with "Desktop development with C++" on Windows, `clang cmake ninja-build pkg-config libgtk-3-dev` on Linux).

```bash
flutter pub get
flutter run -d macos      # or: windows, linux
flutter build macos       # release build
```

Run the tests:

```bash
flutter test
```

Try the matcher on file names from the command line:

```bash
dart run tool/identify.dart "The.Matrix.1999.1080p.mkv" "Breaking.Bad.S01E01.mkv"
```

## Project layout

```
lib/core/filename_parser.dart   file name → title / year / season / episode
lib/core/matcher.dart           scores search results and picks the best match
lib/core/providers/             keyless (IMDb + Cinemeta + TVmaze) and TMDB sources
lib/core/library.dart           folder scanning, grouping, caching
lib/core/discovery.dart         "Find movies automatically"
lib/core/media_filter.dart      tells movies/episodes apart from home videos and tutorials
lib/core/store.dart             settings and cache (JSON in the app data folder)
lib/ui/                         setup screen, library grid, detail and settings dialogs
```

## License

MIT
