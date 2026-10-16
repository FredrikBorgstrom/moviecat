import 'package:flutter/material.dart';

import '../core/discovery.dart';
import '../core/library.dart';

/// Runs auto-discovery and lets the user pick which proposed folders to add.
class DiscoveryDialog extends StatefulWidget {
  final Library library;
  const DiscoveryDialog({super.key, required this.library});

  @override
  State<DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<DiscoveryDialog> {
  late final _discovery = Discovery(widget.library);
  List<DiscoveredFolder>? _results;
  final _selected = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _discovery.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final r = await _discovery.run();
      if (!mounted) return;
      setState(() {
        _results = r;
        _selected.addAll(r.where((f) => !f.alreadyInLibrary).map((f) => f.path));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _add() async {
    final chosen = _results!
        .where((f) => _selected.contains(f.path))
        .map((f) => (path: f.path, strict: f.strict))
        .toList();
    Navigator.pop(context);
    if (chosen.isNotEmpty) await widget.library.addFolders(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return AlertDialog(
      title: const Text('Find movies automatically'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: _error != null
            ? Center(child: Text('Search failed: $_error'))
            : results == null
                ? _searching(context)
                : _list(context, results),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (results != null && results.isNotEmpty)
          FilledButton(
            onPressed: _selected.isEmpty ? null : _add,
            child: Text('Add ${_selected.length} folder${_selected.length == 1 ? '' : 's'}'),
          ),
      ],
    );
  }

  Widget _searching(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _discovery.progress,
      builder: (context, pr, _) {
        final t = Theme.of(context).textTheme;
        final checking = pr.toCheck > 0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.travel_explore, size: 56),
            const SizedBox(height: 16),
            Text(pr.phase, style: t.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: 360,
              child: LinearProgressIndicator(
                  value: checking ? pr.checked / pr.toCheck : null),
            ),
            const SizedBox(height: 12),
            Text(
              checking
                  ? '${pr.checked} of ${pr.toCheck} possible titles checked '
                      '(${pr.videosFound} videos found)'
                  : '${pr.foldersSearched} folders searched, ${pr.videosFound} videos found',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text(
              'Looking in your home folder and external drives. Home videos, screen '
              'recordings and tutorials are left out.\nYour computer may ask for '
              'permission to access some folders.',
              textAlign: TextAlign.center,
              style: t.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Widget _list(BuildContext context, List<DiscoveredFolder> results) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (results.isEmpty) {
      return const Center(
        child: Text('No folders with recognisable movies or TV shows were found.\n'
            'You can still add folders by hand with "Add folder".',
            textAlign: TextAlign.center),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Found ${results.length} folder${results.length == 1 ? '' : 's'} with movies or TV shows:',
            style: t.bodyMedium),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (_, i) {
              final f = results[i];
              final preview = f.titles.take(4).join(', ') +
                  (f.titles.length > 4 ? ' and ${f.titles.length - 4} more' : '');
              return CheckboxListTile(
                value: _selected.contains(f.path),
                onChanged: f.alreadyInLibrary
                    ? null
                    : (v) => setState(() => v! ? _selected.add(f.path) : _selected.remove(f.path)),
                title: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      f.alreadyInLibrary
                          ? 'Already in your library'
                          : f.otherFiles == 0 && !f.strict
                              ? 'Only movies/TV · ${f.mediaFiles} files'
                              : f.otherFiles == 0
                                  ? '${f.mediaFiles} movie/TV files · new non-movie files will be hidden'
                                  : '${f.mediaFiles} movie/TV files · ${f.otherFiles} other videos will be hidden',
                      style: t.bodySmall?.copyWith(
                          color: f.strict ? c.tertiary : c.onSurfaceVariant),
                    ),
                  ],
                ),
                isThreeLine: true,
                secondary: Icon(f.strict ? Icons.filter_alt_outlined : Icons.folder_outlined),
              );
            },
          ),
        ),
      ],
    );
  }
}
