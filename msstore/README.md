# Microsoft Store release

MovieCat goes to the Microsoft Store as an MSIX package. The Store signs it, so no code-signing certificate is needed. GitHub Actions builds the package (`MovieCat-windows-x64-store.msix`, in the Windows job's artifacts) on every push once the Store identity is set.

## Your part

1. **Create the developer account** at <https://storedeveloper.microsoft.com> with your Microsoft account. It's free.
   - **Individual**: fastest; it needs ID verification (a photo of an ID and a selfie). The publisher name shown in the Store is your choice; use **AB Cx3** so it matches the Mac App Store.
   - **Company** (AB Cx3): also free now, but the business verification can take a few days.
2. **Reserve the name.** In Partner Center go to **Apps and games → New product → MSIX or PWA app** and reserve **MovieCat**. If it's taken, try "MovieCat: Movie Library".
3. **Send Claude the identity.** Open the app's **Product management → Product identity** page and copy three values:
   - `Package/Identity/Name` (looks like `12345ABCx3.MovieCat`)
   - `Package/Identity/Publisher` (looks like `CN=1A2B3C4D-…`)
   - `Package/Properties/PublisherDisplayName`

   Claude sets them as repository variables and starts a build; the `.msix` comes out of GitHub Actions.
4. **Submit.** In Partner Center, start a submission and fill it in from the list below. Upload the `.msix` under **Packages**, then click **Submit to the Store**. Certification usually takes 1–3 working days.

## Submission details

| Section | Value |
|---|---|
| Pricing | Free, all markets |
| Category | Entertainment (secondary: Utilities & tools) |
| Privacy policy URL | https://moviecat.org/privacy |
| Website | https://moviecat.org |
| Support contact | https://github.com/FredrikBorgstrom/moviecat/issues |
| Age rating (IARC questionnaire) | No violence, sexual content, gambling or user interaction. Answer "no" to sharing location and user-generated content. Expected rating: 3+ / Everyone |
| System requirements | Windows 10 version 1809 or later, x64 |
| Notes for certification | No sign-in needed. Add a folder with video files; empty placeholder files work, e.g. `Big.Buck.Bunny.2008.mkv`, `Sintel.2010.mkv`. Titles are looked up in public movie databases (IMDb search suggestions, Cinemeta, TVmaze). The trash buttons move files to the Recycle Bin after a confirmation. The banner in the top-right corner links to our other app, ABCx3. |

**Product name:** MovieCat

**Short description** (shown in search results):
> Your movie and TV files as a poster library: posters, ratings and summaries, no account or API key needed.

**Description:**
> MovieCat turns folders full of video files into a browsable movie library.
>
> Point it at your movie and TV folders and MovieCat recognises each title from its file name, even messy release names like "The.Matrix.1999.1080p.BluRay.x264". It then shows the poster, rating, year, genres, runtime and a short summary.
>
> FEATURES
> • Works instantly: no account, no sign-up, no API key
> • Find movies automatically: searches your user folder and drives and proposes the folders that hold movies and TV shows
> • Recognises movies and TV episodes from file names, including season/episode numbers and foreign titles
> • Groups TV episodes by show
> • Leaves out home videos, screen recordings and tutorials
> • Rate titles yourself with 1 to 10 stars
> • Search, filter (Movies, TV, Unrecognised) and sort by title, year, rating or date modified
> • Fix a wrong match in seconds
> • Play a file or show it in File Explorer with one click
> • Optional free TMDB key for even better matching
>
> PRIVATE BY DESIGN
> MovieCat has no account and collects no data. Your library stays on your PC; only titles are sent to public movie databases to look them up.
>
> MovieCat is free and open source (MIT).
>
> MovieCat is not affiliated with IMDb. TV data from TVmaze. This product uses the TMDB API but is not endorsed or certified by TMDB.

**Features** (up to 20, one per line):
> No account, sign-up or API key
> Recognises movies and TV episodes from file names
> Finds your movie folders automatically
> Posters, IMDb ratings and summaries
> TV episodes grouped per show
> Your own 1–10 ratings
> Search, filter and sort
> Play or show a file in one click

**Search terms** (up to 7): movies, movie library, tv shows, film collection, media organizer, posters, catalog

**Screenshots:** at least one, 1366×768 or larger. The Mac screenshots in `appstore/screenshots/` (2880×1800) show the same interface. Windows screenshots are safer, because the Store asks that screenshots show the app as it runs on Windows. Take them on a Windows PC if you can.

**Logos:** the Store makes tiles from the package. A 1:1 box art (2160×2160) is optional; use `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png` scaled up, or the SVG in `assets/images/`.
