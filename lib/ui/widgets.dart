import 'package:flutter/material.dart';

import 'brand.dart';

/// Poster image with a tidy placeholder while loading or when missing.
class Poster extends StatelessWidget {
  final String? url;
  final String title;
  final IconData placeholderIcon;
  const Poster({super.key, this.url, required this.title, this.placeholderIcon = Icons.movie});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: c.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(placeholderIcon, size: 40, color: c.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.onSurfaceVariant)),
        ],
      ),
    );
    if (url == null) return placeholder;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      cacheWidth: 400,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, sync) => sync || frame != null
          ? child
          : Stack(fit: StackFit.expand, children: [placeholder]),
    );
  }
}

/// A small "★ 8.7" pill.
class RatingBadge extends StatelessWidget {
  final double rating;
  final String? label;
  const RatingBadge({super.key, required this.rating, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 15, color: brandOrangeLight),
        const SizedBox(width: 3),
        Text(
          label == null ? rating.toStringAsFixed(1) : '$label ${rating.toStringAsFixed(1)}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ]),
    );
  }
}

/// 1–10 star rating. Tapping the current value clears it.
class StarRating extends StatefulWidget {
  final int? value;
  final ValueChanged<int?>? onChanged;
  final double size;
  const StarRating({super.key, this.value, this.onChanged, this.size = 26});

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final shown = _hover ?? widget.value ?? 0;
    final c = Theme.of(context).colorScheme;
    return MouseRegion(
      onExit: (_) => setState(() => _hover = null),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 10; i++)
            MouseRegion(
              cursor: widget.onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
              onEnter: widget.onChanged == null ? null : (_) => setState(() => _hover = i),
              child: GestureDetector(
                onTap: widget.onChanged == null
                    ? null
                    : () => widget.onChanged!(widget.value == i ? null : i),
                child: Icon(
                  i <= shown ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: widget.size,
                  color: i <= shown ? brandOrange : c.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String formatSize(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
