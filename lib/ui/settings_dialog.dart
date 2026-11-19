import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/library.dart';
import '../core/updater.dart';
import 'setup_page.dart';

class SettingsDialog extends StatefulWidget {
  final Library library;
  final Updater? updater;
  const SettingsDialog({super.key, required this.library, this.updater});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _form = GlobalKey<TmdbKeyFormState>();
  bool _saving = false;

  Future<void> _save() async {
    final form = _form.currentState!;
    setState(() => _saving = true);
    final ok = await form.test();
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    final changed = form.text != widget.library.store.tmdbKey;
    await widget.library.setTmdbKey(form.text);
    if (!mounted) return;
    Navigator.pop(context);
    if (changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            form.text.isEmpty ? 'TMDB key removed. Using keyless sources.' : 'TMDB key saved. Use "Re-identify all" to match existing titles again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Metadata source', style: t.titleSmall),
              const SizedBox(height: 4),
              Text(
                lib.store.tmdbKey.isEmpty
                    ? 'Using IMDb search + Cinemeta + TVmaze (no key needed).'
                    : 'Using TMDB, plus IMDb ratings via Cinemeta.',
              ),
              const SizedBox(height: 16),
              Text('TMDB key (optional)', style: t.titleSmall),
              const SizedBox(height: 4),
              TmdbKeyForm(key: _form, initialKey: lib.store.tmdbKey),
              const SizedBox(height: 20),
              Text('Library', style: t.titleSmall),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: lib.store.folders.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        lib.scan(refresh: true);
                      },
                icon: const Icon(Icons.sync),
                label: const Text('Re-identify all titles'),
              ),
              const SizedBox(height: 4),
              Text('Titles you matched by hand are kept.', style: t.bodySmall),
              if (widget.updater case final u?) ...[
                const SizedBox(height: 20),
                _UpdateSettings(updater: u, library: lib),
              ],
              const SizedBox(height: 20),
              Text('About & data sources', style: t.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Titles are looked up using IMDb search, Cinemeta and TVmaze '
                '(TV data licensed CC BY-SA). With a key, data also comes from TMDB. '
                'This product uses the TMDB API but is not endorsed or certified by TMDB. '
                'MovieCat is not affiliated with IMDb.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Privacy: MovieCat has no account and collects no data. Only titles read from file names '
                '(as search terms) are sent to the services above to identify titles, and the IDs of '
                'recognised titles to WokeWarn for their woke ratings. Downloaded copies also check '
                'GitHub for new versions.',
                style: t.bodySmall,
              ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://github.com/FredrikBorgstrom/moviecat/blob/main/PRIVACY.md',
                      ),
                    ),
                    child: const Text('Privacy policy'),
                  ),
                  TextButton(
                    onPressed: () =>
                        launchUrl(Uri.parse('https://www.tvmaze.com')),
                    child: const Text('TVmaze'),
                  ),
                  TextButton(
                    onPressed: () =>
                        launchUrl(Uri.parse('https://www.themoviedb.org')),
                    child: const Text('TMDB'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => launchUrl(Uri.directory(lib.store.dir.path)),
                child: Text(
                  'Data folder: ${lib.store.dir.path}',
                  style: t.bodySmall?.copyWith(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Version, the automatic-update switch and "Check for updates".
class _UpdateSettings extends StatefulWidget {
  final Updater updater;
  final Library library;
  const _UpdateSettings({required this.updater, required this.library});

  @override
  State<_UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends State<_UpdateSettings> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final store = widget.library.store;
    return ListenableBuilder(
      listenable: widget.updater,
      builder: (context, _) {
        final u = widget.updater;
        final status = u.checking
            ? 'Checking…'
            : u.error ??
                  (u.available != null
                      ? 'MovieCat ${u.available!.version} is available.'
                      : u.lastCheck != null
                      ? 'MovieCat is up to date.'
                      : '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Updates', style: t.titleSmall),
            const SizedBox(height: 4),
            Text('MovieCat ${u.currentVersion}'),
            if (!u.enabled)
              Text('Updates come from ${u.install.source}.', style: t.bodySmall)
            else ...[
              if (u.canInstall)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Download and install updates automatically',
                  ),
                  subtitle: const Text(
                    'New versions download in the background and install when you click "Restart to update".',
                  ),
                  value: store.autoUpdate,
                  onChanged: (v) async {
                    setState(() => store.autoUpdate = v);
                    await store.saveSettings();
                    if (v && u.available != null) await u.download();
                  },
                ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: u.checking ? null : u.check,
                    icon: const Icon(Icons.update),
                    label: const Text('Check for updates'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(status, style: t.bodySmall)),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
