import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Banner for ABCx3, the author's word game. Opens the Mac App Store on macOS
/// and the download page everywhere else. The download page passes its UTM
/// parameters on to ABCx3 signups; the Mac App Store drops them.
class PromoBanner extends StatelessWidget {
  final double height;
  const PromoBanner({super.key, this.height = 92});

  static Uri get url => Uri.parse(Platform.isMacOS
      ? 'https://apps.apple.com/se/app/abcx3/id6474488261?platform=mac'
      : 'https://play.abcx3.com/get/?utm_source=moviecat&utm_medium=partner&utm_campaign=moviecat_app');

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'ABCx3 – multiplayer word game. Free to play, no ads.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => launchUrl(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/abcx3_banner.webp',
              height: height,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
