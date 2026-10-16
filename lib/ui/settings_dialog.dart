import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/library.dart';
import 'setup_page.dart';

class SettingsDialog extends StatefulWidget {
  final Library library;
  const SettingsDialog({super.key, required this.library});

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(form.text.isEmpty
            ? 'TMDB key removed. Using keyless sources.'
            : 'TMDB key saved. Use "Re-identify all" to match existing titles again.'),
      ));
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
              Text(lib.store.tmdbKey.isEmpty
                  ? 'Using IMDb search + Cinemeta + TVmaze (no key needed).'
                  : 'Using TMDB, plus IMDb ratings via Cinemeta.'),
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
              const SizedBox(height: 12),
              InkWell(
                onTap: () => launchUrl(Uri.directory(lib.store.dir.path)),
                child: Text('Data folder: ${lib.store.dir.path}',
                    style: t.bodySmall?.copyWith(decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
