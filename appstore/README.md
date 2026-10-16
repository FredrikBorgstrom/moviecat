# Mac App Store release

Everything for the Mac App Store is prepared. The App Store Connect API can't do two things, so they need a person signed in to App Store Connect, once.

## Already done

- Bundle ID `com.abcx3.moviecat` registered for team AB Cx3 (F3C7B92SZG).
- Provisioning profile **MovieCat Mac App Store** created and installed.
- App is sandboxed (network + user-selected folders + security-scoped bookmarks).
- Signed package: `build/macos/export/MovieCat.pkg` (version 1.0.0, build 3). Rebuild with `appstore/build.sh`.
- Listing text, keywords, URLs, review notes: `appstore/metadata.json`.
- Screenshots (2880×1800): `appstore/screenshots/`.
- Privacy policy: [PRIVACY.md](../PRIVACY.md).

## Your part (about 3 minutes)

1. **Create the app record.** Go to <https://appstoreconnect.apple.com/apps>, click **+** and then **New App**:
   - Platforms: **macOS**
   - Name: **MovieCat**. If the name is taken, try "MovieCat: Movie Library" and put the same name in `metadata.json`.
   - Primary language: **English (U.S.)**
   - Bundle ID: **MovieCat – com.abcx3.moviecat**
   - SKU: **moviecat**
   - User access: **Full Access**
2. **Answer App Privacy.** In the new app, open **App Privacy**, click **Get Started**, choose **"No, we do not collect data from this app"**, save, then click **Publish**.
3. **Upload and submit.** Run:

   ```bash
   node appstore/publish.mjs --submit
   ```

   This uploads the build, waits for Apple to process it (about 5–20 minutes), fills in the listing, screenshots, category, free price, all territories, age rating (4+) and review notes, then submits for review. Leave out `--submit` to fill everything in without submitting. You can also ask Claude to run it.

## Things to be aware of

- **Content rights.** `metadata.json` declares `USES_THIRD_PARTY_CONTENT`, because the app shows posters and data from IMDb, Cinemeta, TVmaze and TMDB. In App Store Connect this means confirming you have the rights needed.
- **App Review risk.** The keyless lookup uses IMDb's public search endpoint and Cinemeta. Apple may ask about permission to use IMDb data (guideline 5.2). If that happens, the fallback is to ship with TMDB as the default source (their free API allows apps, with the attribution already shown in Settings).
- **Age rating "advertising".** Answered **yes** because of the ABCx3 banner. This does not change the 4+ rating.
- **Each new upload needs a higher build number.** Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+4`), then run `appstore/build.sh` and `appstore/publish.mjs`.
