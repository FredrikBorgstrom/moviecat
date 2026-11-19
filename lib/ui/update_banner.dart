import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/library.dart';
import '../core/updater.dart';

/// Tells the user a new version is out: "Restart to update" when MovieCat can install
/// it itself, otherwise a link to download it.
class UpdateBanner extends StatefulWidget {
  final Updater updater;
  final Library library;
  const UpdateBanner({super.key, required this.updater, required this.library});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _dismissed = false;
  bool _installing = false;

  Future<void> _install() async {
    final u = widget.updater;
    setState(() => _installing = true);
    await widget.library.store.saveLibrary();
    final ok = await u.installAndRestart();
    if (!mounted || ok) return;
    setState(() => _installing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(u.error ?? 'The update could not be installed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.updater,
      builder: (context, _) {
        final u = widget.updater;
        final info = u.available;
        if (info == null || _dismissed) return const SizedBox.shrink();
        final c = Theme.of(context).colorScheme;
        final busy = _installing || u.downloading;
        final status = u.downloading
            ? 'Downloading… ${((u.progress ?? 0) * 100).round()}%'
            : u.ready != null
            ? 'It is downloaded and ready to install.'
            : '';
        return Material(
          color: c.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Icon(Icons.system_update_alt, color: c.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'MovieCat ${info.version} is available. $status',
                    style: TextStyle(color: c.onSecondaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(info.page)),
                  child: const Text("What's new"),
                ),
                if (u.canInstall)
                  FilledButton(
                    onPressed: busy ? null : _install,
                    child: Text(
                      _installing ? 'Installing…' : 'Restart to update',
                    ),
                  )
                else
                  FilledButton(
                    onPressed: () => launchUrl(Uri.parse(info.page)),
                    child: const Text('Download'),
                  ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  child: const Text('Later'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
