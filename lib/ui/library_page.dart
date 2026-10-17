import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../core/filename_parser.dart';
import '../core/library.dart';
import '../core/platform_access.dart';
import 'brand.dart';
import 'detail_dialog.dart';
import 'discovery_dialog.dart';
import 'settings_dialog.dart';
import 'promo_banner.dart';
import 'widgets.dart';

enum _Filter { all, movies, series, unmatched }

enum _Sort { title, year, rating, myRating }

class LibraryPage extends StatefulWidget {
  final Library library;
  const LibraryPage({super.key, required this.library});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.title;
  String _query = '';

  Library get lib => widget.library;

  Future<void> _addFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Add folder');
    if (path != null) await lib.addFolder(path);
  }

  /// Auto-discovery needs to read whole drives, which the macOS App Sandbox
  /// (Mac App Store build) doesn't allow, so it's only offered outside it.
  bool get _canDiscover => !PlatformAccess.sandboxed;

  void _discover() => showDialog(
    context: context,
    builder: (_) => DiscoveryDialog(library: lib),
  );

  List<LibraryItem> _visible() {
    final q = normalizeTitle(_query);
    final items = lib.items.where((i) {
      switch (_filter) {
        case _Filter.movies:
          if (i.info == null || i.kind != MediaKind.movie) return false;
        case _Filter.series:
          if (i.info == null || i.kind != MediaKind.series) return false;
        case _Filter.unmatched:
          if (i.status == ItemStatus.matched) return false;
        case _Filter.all:
      }
      if (q.isEmpty) return true;
      return normalizeTitle(i.displayTitle).contains(q) ||
          normalizeTitle(i.parsed.title).contains(q);
    }).toList();

    int byTitle(LibraryItem a, LibraryItem b) =>
        _sortTitle(a.displayTitle).compareTo(_sortTitle(b.displayTitle));
    int desc(num? a, num? b) => (b ?? -1).compareTo(a ?? -1);
    items.sort((a, b) {
      final r = switch (_sort) {
        _Sort.title => 0,
        _Sort.year => desc(a.displayYear, b.displayYear),
        _Sort.rating => desc(
          a.info?.primaryRating?.value,
          b.info?.primaryRating?.value,
        ),
        _Sort.myRating => desc(
          a.info == null ? null : lib.myRating(a.info!.id),
          b.info == null ? null : lib.myRating(b.info!.id),
        ),
      };
      return r != 0 ? r : byTitle(a, b);
    });
    return items;
  }

  static String _sortTitle(String t) =>
      normalizeTitle(t).replaceFirst(RegExp(r'^(the|a|an) '), '');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final items = _visible();
        return Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(context),
              if (lib.store.folders.isNotEmpty) _folders(context),
              if (lib.scanning) _progress(context),
              Expanded(child: _body(context, items)),
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
        child: Row(
          children: [
            // Same height as the ABCx3 banner, filling the header.
            SvgPicture.asset('assets/images/moviecat-icon.svg', height: 92),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Buttons lose their labels when space is short, so the
                  // search field stays usable.
                  LayoutBuilder(
                    builder: (context, box) => _toolbarRow(
                      context,
                      compact: box.maxWidth < 880,
                      showWordmark: box.maxWidth >= 560,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<_Filter>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: _Filter.all, label: Text('All')),
                          ButtonSegment(
                            value: _Filter.movies,
                            label: Text('Movies'),
                          ),
                          ButtonSegment(
                            value: _Filter.series,
                            label: Text('TV'),
                          ),
                          ButtonSegment(
                            value: _Filter.unmatched,
                            label: Text('Unrecognised'),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) =>
                            setState(() => _filter = s.first),
                      ),
                      PopupMenuButton<_Sort>(
                        tooltip: 'Sort',
                        initialValue: _sort,
                        onSelected: (s) => setState(() => _sort = s),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _Sort.title,
                            child: Text('Title'),
                          ),
                          PopupMenuItem(
                            value: _Sort.year,
                            child: Text('Year (newest)'),
                          ),
                          PopupMenuItem(
                            value: _Sort.rating,
                            child: Text('Rating (highest)'),
                          ),
                          PopupMenuItem(
                            value: _Sort.myRating,
                            child: Text('My rating (highest)'),
                          ),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.sort, size: 18),
                          label: Text(
                            'Sort: ${switch (_sort) {
                              _Sort.title => 'Title',
                              _Sort.year => 'Year',
                              _Sort.rating => 'Rating',
                              _Sort.myRating => 'My rating',
                            }}',
                          ),
                        ),
                      ),
                      Text(
                        '${lib.items.length} titles',
                        style: TextStyle(color: c.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Only when there's room for it next to the toolbar.
            if (MediaQuery.sizeOf(context).width >= 1150) ...[
              const SizedBox(width: 12),
              const PromoBanner(height: 92),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolbarRow(
    BuildContext context, {
    required bool compact,
    required bool showWordmark,
  }) {
    return Row(
      children: [
        if (showWordmark) ...[
          SvgPicture.asset(
            'assets/images/moviecat-wordmark-dark.svg',
            height: 34,
            semanticsLabel: 'MovieCat',
          ),
          const SizedBox(width: 20),
        ],
        Flexible(
          flex: 6,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search library',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        const Spacer(),
        if (compact) ...[
          if (_canDiscover) ...[
            IconButton.outlined(
              tooltip: 'Find movies automatically',
              onPressed: _discover,
              icon: const Icon(Icons.travel_explore),
            ),
            const SizedBox(width: 6),
          ],
          IconButton.filled(
            tooltip: 'Add folder',
            onPressed: _addFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ] else ...[
          if (_canDiscover) ...[
            OutlinedButton.icon(
              onPressed: _discover,
              icon: const Icon(Icons.travel_explore),
              label: const Text('Find automatically'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: _addFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add folder'),
          ),
        ],
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Rescan folders',
          onPressed: lib.store.folders.isEmpty ? null : () => lib.scan(),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => SettingsDialog(library: lib),
          ),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _folders(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final f in lib.store.folders)
            Tooltip(
              message: lib.store.strictFolders.contains(f)
                  ? '$f\nOnly recognised movies & TV are shown. Click to show all videos.'
                  : '$f\nClick to show only recognised movies & TV.',
              child: InputChip(
                avatar: Icon(
                  lib.store.strictFolders.contains(f)
                      ? Icons.filter_alt_outlined
                      : Icons.folder_outlined,
                  size: 18,
                ),
                label: Text(p.basename(f).isEmpty ? f : p.basename(f)),
                onPressed: () => lib.setFolderStrict(
                  f,
                  !lib.store.strictFolders.contains(f),
                ),
                onDeleted: () => lib.removeFolder(f),
                deleteButtonTooltipMessage:
                    'Remove folder from library (files are not touched)',
              ),
            ),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final total = lib.progressTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: total == 0 ? null : lib.progressDone / total,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            total == 0
                ? (lib.scanMessage ?? '')
                : '${lib.scanMessage ?? ''} ${lib.progressDone}/$total',
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<LibraryItem> items) {
    final t = Theme.of(context).textTheme;
    if (lib.store.folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined, size: 72),
            const SizedBox(height: 16),
            Text(
              _canDiscover
                  ? 'Let MovieCat find your movies, or add a folder yourself'
                  : 'Add a folder with movies or TV shows to get started',
              style: t.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canDiscover) ...[
                  FilledButton.icon(
                    onPressed: _discover,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Find movies automatically'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add folder'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add folder'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          lib.scanning
              ? 'Scanning…'
              : lib.items.isEmpty
              ? 'No video files found in these folders.'
              : 'Nothing matches the current filter.',
          style: t.titleMedium,
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 18,
        crossAxisSpacing: 16,
        childAspectRatio: 0.5,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _PosterCard(library: lib, item: items[i]),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final Library library;
  final LibraryItem item;
  const _PosterCard({required this.library, required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final info = item.info;
    final rating = info?.primaryRating;
    final mine = info == null ? null : library.myRating(info.id);
    final episodes = item.files.length;

    final subtitle = [
      if (item.displayYear != null) '${item.displayYear}',
      if (item.status == ItemStatus.matched)
        item.kind == MediaKind.series ? 'TV · $episodes ep.' : 'Movie',
      if (item.status == ItemStatus.unmatched) 'Not recognised',
      if (item.status == ItemStatus.error) 'Lookup failed',
      if (item.status == ItemStatus.pending) 'Identifying…',
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showDialog(
        context: context,
        builder: (_) => DetailDialog(library: library, item: item),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Poster(
                    url: info?.posterUrl,
                    title: item.displayTitle,
                    placeholderIcon: switch (item.status) {
                      ItemStatus.unmatched => Icons.help_outline,
                      ItemStatus.error => Icons.cloud_off,
                      ItemStatus.pending => Icons.hourglass_empty,
                      ItemStatus.matched => Icons.movie,
                    },
                  ),
                  if (rating != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: RatingBadge(rating: rating.value),
                    ),
                  if (item.status == ItemStatus.pending)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.titleSmall,
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          if (mine != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: brandOrange,
                  ),
                  const SizedBox(width: 3),
                  Text('My rating $mine', style: t.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
