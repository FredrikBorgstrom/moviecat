# MovieCat vector graphics

Created 17 October 2026 from the approved white cat with black back stripes,
yellow eyes and an orange television with a blank screen.

All five files contain editable Scalable Vector Graphics (SVG) paths and have
transparent backgrounds. They contain no embedded raster images, text objects,
external resources or font dependencies.

| File | Vector paths | Size |
| --- | ---: | ---: |
| `moviecat-icon.svg` | 15 | 17.5 KB |
| `moviecat-wordmark-light.svg` | 9 | 7.5 KB |
| `moviecat-wordmark-dark.svg` | 9 | 7.5 KB |
| `moviecat-logo-light.svg` | 24 | 24.8 KB |
| `moviecat-logo-dark.svg` | 24 | 24.8 KB |

The standalone icon uses named groups for the outline, screen, orange television,
white fur/details and gold eyes. The two wordmarks use `movie` and `cat` groups;
change their `fill` values to edit colors. The light and dark wordmarks share
identical geometry. The combined logos compose these same vector masters.

The approved raster edges were traced into smooth curves. Subtle raster shading
and texture have been consolidated into five flat colors for the icon and two
for each wordmark. This is a vector interpretation rather than a pixel-identical
copy. Combined logo spacing is based on the standalone masters.

## Validation

- Parsed and structurally checked all five final SVG files.
- Rendered every final file with resvg; checked light and dark presentations.
- Checked the icon at 1,254, 64 and 32 pixels wide.
- Confirmed transparent corners and zero image/font references.
- Confirmed identical letter paths in both themes and unchanged source files.
- Binary silhouette intersection-over-union against the originals: icon
  99.78%; wordmark
  99.09%. This measures the shapes, not color similarity.

## Sources and reproducibility

Source artwork: `05-fat-cat-app-icon-v7.png` and
`06-moviecat-wordmark-v1.png` in `outputs/MovieCat Logo Concepts`.
The dark wordmark derives from the same light letter paths, with a soft-white
`Movie` fill. Original dark raster reference:
`06-moviecat-wordmark-dark-v1.png`.

Workspace source revision: `a8700362566b57fab0869added2507c381bf78db`.
The export helper is `scripts/branding/vectorize_moviecat.py`; its exact checksum,
dependency versions and source checksums are in `asset-manifest.json`.

Supporting review renders, the comparison sheet and detailed validation are
stored at `/Users/fredrik/Documents/abcx3_bun/artifacts/MovieCat Vectorization/`.
The final comparison sheet is `final-vector-review.png`.

Tracing: [VTracer Python library](https://github.com/visioncortex/vtracer/tree/master/crates/vtracer-py),
version 1.0.0a4. Rendering: `@resvg/resvg-js` 2.6.2.
The final SVG files do not require either tool to use them.
