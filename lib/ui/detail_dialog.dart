import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/filename_parser.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/platform_access.dart';
import 'widgets.dart';

class DetailDialog extends StatelessWidget {
  final Library library;
  final LibraryItem item;
  const DetailDialog({super.key, required this.library, required this.item});

  /// The item may change while the dialog is open (rated, re-matched, rescanned).
  LibraryItem _current() => library.items.firstWhere(
        (i) => i.keys.any(item.keys.contains),
        orElse: () => item,
      );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 920, maxHeight: size.height * 0.88),
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) => _content(context, _current()),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, LibraryItem item) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final info = item.info;
    final narrow = MediaQuery.sizeOf(context).width < 700;

    final poster = SizedBox(
      width: narrow ? 160 : 300,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Poster(url: info?.posterUrl, title: item.displayTitle),
      ),
    );

    final meta = [
      if (item.displayYear != null) '${item.displayYear}',
      item.kind == MediaKind.series ? 'TV series' : 'Movie',
      if (info?.runtime != null) info!.runtime!,
    ].join(' · ');

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.displayTitle, style: t.headlineSmall),
        const SizedBox(height: 4),
        Text(meta, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
        if (info != null && info.genres.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in info.genres)
              Chip(label: Text(g), visualDensity: VisualDensity.compact),
          ]),
        ],
        const SizedBox(height: 16),
        if (info == null)
          Text(
            item.status == ItemStatus.error
                ? 'Lookup failed: ${item.error}'
                : 'This title was not recognised automatically. '
                    'Use "Fix match" to search for it.',
            style: t.bodyMedium,
          ),
        if (info == null) const SizedBox(height: 16) else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in info.ratings.entries) RatingBadge(rating: r.value, label: r.key),
            if (info.ratings.isEmpty) Text('No rating available', style: t.bodySmall),
          ]),
          const SizedBox(height: 16),
          Text('My rating', style: t.labelLarge),
          const SizedBox(height: 4),
          StarRating(
            value: library.myRating(info.id),
            onChanged: (v) => library.setMyRating(info.id, v),
          ),
          const SizedBox(height: 16),
          if (info.summary != null && info.summary!.isNotEmpty) ...[
            Text('Summary', style: t.labelLarge),
            const SizedBox(height: 4),
            Text(info.summary!, style: t.bodyLarge),
            const SizedBox(height: 16),
          ],
        ],
        Text(item.files.length == 1 ? 'File' : 'Files (${item.files.length})', style: t.labelLarge),
        for (final f in item.files) _FileTile(file: f),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (info?.webUrl case final url?)
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(url)),
              icon: const Icon(Icons.open_in_new),
              label: Text(info?.imdbId != null ? 'Open on IMDb' : 'Open on TMDB'),
            ),
          OutlinedButton.icon(
            onPressed: () => showDialog(
                context: context, builder: (_) => FixMatchDialog(library: library, item: item)),
            icon: const Icon(Icons.manage_search),
            label: Text(info == null ? 'Fix match' : 'Wrong title? Fix match'),
          ),
        ]),
      ],
    );

    return Stack(children: [
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: poster),
                const SizedBox(height: 16),
                details,
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: poster),
                const SizedBox(width: 24),
                Expanded(child: details),
              ]),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    ]);
  }
}

class _FileTile extends StatelessWidget {
  final MediaFile file;
  const _FileTile({required this.file});

  Future<void> _reveal() async {
    if (Platform.isMacOS) {
      await PlatformAccess.reveal(file.path);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', file.path]);
    } else {
      await launchUrl(Uri.file(p.dirname(file.path)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = file.parsed;
    final epLabel = ep.kind == MediaKind.series && ep.episode != null
        ? 'S${(ep.season ?? 1).toString().padLeft(2, '0')}E${ep.episode.toString().padLeft(2, '0')} · '
        : '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.video_file_outlined),
      title: Text(p.basename(file.path), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$epLabel${formatSize(file.size)} · ${p.dirname(file.path)}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Play',
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () => launchUrl(Uri.file(file.path)),
        ),
        IconButton(
          tooltip: 'Show in folder',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: _reveal,
        ),
      ]),
    );
  }
}

/// Lets the user search manually and pick the right title.
class FixMatchDialog extends StatefulWidget {
  final Library library;
  final LibraryItem item;
  const FixMatchDialog({super.key, required this.library, required this.item});

  @override
  State<FixMatchDialog> createState() => _FixMatchDialogState();
}

class _FixMatchDialogState extends State<FixMatchDialog> {
  late final _controller = TextEditingController(text: widget.item.parsed.title);
  List<Candidate>? _results;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.library.search(_controller.text);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(Candidate c) async {
    setState(() => _busy = true);
    try {
      await widget.library.fixMatch(widget.item, c);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results ?? [];
    return AlertDialog(
      title: const Text('Find the right title'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Title',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: results.isEmpty && !_busy && _results != null
                ? const Center(child: Text('No results. Try a shorter or different title.'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final c = results[i];
                      return ListTile(
                        enabled: !_busy,
                        leading: SizedBox(
                          width: 40,
                          height: 60,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Poster(url: c.posterUrl, title: ''),
                          ),
                        ),
                        title: Text(c.title),
                        subtitle: Text([
                          if (c.year != null) '${c.year}',
                          c.kind == MediaKind.series ? 'TV series' : 'Movie',
                          if (c.subtitle != null && c.subtitle!.isNotEmpty) c.subtitle!,
                        ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _pick(c),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
