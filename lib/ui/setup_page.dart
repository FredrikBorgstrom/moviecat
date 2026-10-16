import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/library.dart';
import '../core/providers/tmdb.dart';

/// First-run welcome: explains that no key is needed, and optionally walks the
/// user through getting a free TMDB key.
class SetupPage extends StatefulWidget {
  final Library library;
  const SetupPage({super.key, required this.library});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _key = GlobalKey<TmdbKeyFormState>();
  bool _showTmdb = false;
  bool _busy = false;

  Future<void> _continue() async {
    final form = _key.currentState;
    if (_showTmdb && form != null && form.text.isNotEmpty) {
      setState(() => _busy = true);
      final ok = await form.test();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!ok) return;
      await widget.library.completeSetup(tmdbKey: form.text);
    } else {
      await widget.library.completeSetup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.movie_filter_rounded, size: 64, color: c.primary),
                const SizedBox(height: 16),
                Text('Welcome to MovieCat', style: t.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Point MovieCat at your movie and TV folders. It recognises each title from '
                  'the file name and shows its poster, rating, year and a short summary.',
                  style: t.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle, color: c.primary),
                    title: const Text('No API key or account needed'),
                    subtitle: const Text(
                        'By default MovieCat uses IMDb\'s public search, Cinemeta and TVmaze, '
                        'which all work without signing up.'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.key),
                        title: const Text('Optional: also use TMDB'),
                        subtitle: const Text(
                            'A free TMDB key improves matching of foreign and less-known titles. '
                            'Takes about two minutes. You can add it later in Settings.'),
                        value: _showTmdb,
                        onChanged: (v) => setState(() => _showTmdb = v),
                      ),
                      if (_showTmdb)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TmdbKeyForm(key: _key),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _continue,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: Text(_showTmdb ? 'Save and continue' : 'Get started'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Step-by-step TMDB key entry with links and a live "Test" button.
class TmdbKeyForm extends StatefulWidget {
  final String initialKey;
  const TmdbKeyForm({super.key, this.initialKey = ''});

  @override
  State<TmdbKeyForm> createState() => TmdbKeyFormState();
}

class TmdbKeyFormState extends State<TmdbKeyForm> {
  late final _controller = TextEditingController(text: widget.initialKey);
  String? _error;
  bool? _ok;
  bool _testing = false;

  String get text => _controller.text.trim();

  /// Checks the key against TMDB and shows the result. Empty counts as valid.
  Future<bool> test() async {
    if (text.isEmpty) return true;
    setState(() {
      _testing = true;
      _error = null;
      _ok = null;
    });
    final error = await TmdbProvider.validate(text);
    if (!mounted) return false;
    setState(() {
      _testing = false;
      _error = error;
      _ok = error == null;
    });
    return error == null;
  }

  Widget _step(int n, String text, {String? linkLabel, String? url}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(radius: 12, child: Text('$n', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          if (url != null)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(url)),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(linkLabel!),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _step(1, 'Create a free TMDB account (or log in).',
            linkLabel: 'Sign up', url: 'https://www.themoviedb.org/signup'),
        _step(2, 'Open API settings and click "Create" → "Developer". '
            'Any app name and URL is fine (e.g. "MovieCat", "localhost").',
            linkLabel: 'API settings', url: 'https://www.themoviedb.org/settings/api'),
        _step(3, 'Copy the "API Read Access Token" (or the shorter "API Key") and paste it below.'),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'TMDB API key or Read Access Token',
            border: const OutlineInputBorder(),
            errorText: _error,
            helperText: _ok == true ? 'Key works!' : null,
            helperStyle: TextStyle(color: c.primary),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _controller.text = data!.text!.trim();
                      test();
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton(
                    onPressed: _testing ? null : test,
                    child: _testing
                        ? const SizedBox.square(
                            dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Test'),
                  ),
                ),
              ],
            ),
          ),
          onChanged: (_) => setState(() {
            _ok = null;
            _error = null;
          }),
          onSubmitted: (_) => test(),
        ),
      ],
    );
  }
}
