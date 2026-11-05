# Store packages

| Store | Files | Built | Published |
|---|---|---|---|
| Snap Store | [snap/snapcraft.yaml](../snap/snapcraft.yaml) | CI, every push (`moviecat-snap` artifact) | CI, stable channel |
| AUR (`moviecat-bin`) | [aur/PKGBUILD](aur/PKGBUILD) | from the GitHub release | CI |
| Chocolatey (`moviecat`) | [chocolatey/](chocolatey/) | CI, every push | CI, then human moderation |
| Microsoft Store | see [msstore/README.md](../msstore/README.md) | CI (MSIX) | by hand in Partner Center |
| Homebrew, Scoop, winget, AppImageHub | see the main README | | |

CI publishes when a `v*` tag is pushed, or when you run the **Build** workflow by hand (Actions → Build → Run workflow), as long as the store's secret is set. Without the secret, that store is skipped.

## One-time account setup

Each store needs an account in your name, which only you can create. Afterwards, CI handles every release.

### Snap Store

1. Sign up at <https://snapcraft.io/account> (an Ubuntu One account) with fredrik@abcx3.com.
2. Register the name: <https://snapcraft.io/register-snap>, enter `moviecat`.
3. Create a CI login. On this Mac:

   ```bash
   brew install snapcraft
   snapcraft export-login --snaps=moviecat --acls package_access,package_push,package_update,package_release snap-login.txt
   gh secret set SNAPCRAFT_STORE_CREDENTIALS -R FredrikBorgstrom/moviecat < snap-login.txt && rm snap-login.txt
   ```

   `export-login` asks for your Ubuntu One email and password.

Note: the snap is confined. It can read your home folder and drives under `/media` and `/mnt`. "Move to Trash" puts files in the snap's own trash, not the desktop trash.

### AUR

As of 18 October 2026, new AUR account registrations are temporarily closed.
Existing accounts can still sign in and publish. Follow the
[Arch news feed](https://archlinux.org/news/) for reopening announcements.

1. Sign up at <https://aur.archlinux.org/register>.
2. Under **My Account → SSH Public Key**, paste the existing MovieCat public key (`~/.ssh/aur_moviecat.pub`) and save.
3. Verify that the account accepts this key before adding its private key to the
   `FredrikBorgstrom/moviecat` repository's `AUR_SSH_PRIVATE_KEY` secret and
   publishing `moviecat-bin`. The public key goes in the AUR account; the private
   key goes only in the repository secret.

The recipe fixes Flutter plugin library paths while packaging the release bundle,
so the plugins find the bundled runtime beside them instead of a build-machine
directory. The bundle is installed under `/usr/lib/moviecat`, with a launcher in
`/usr/bin`. `patchelf` is a build dependency for this step.

### Chocolatey

The `abcx3` Chocolatey account and the repository's `CHOCOLATEY_API_KEY`
secret were configured on 18 October 2026. Version 1.1.0 was submitted using
the existing Build workflow. Check the
[package page](https://community.chocolatey.org/packages/moviecat/1.1.0) for
moderation status.

1. Sign up at <https://community.chocolatey.org/account/Register> and confirm the email.
2. Copy your API key from <https://community.chocolatey.org/account>.
3. Save it as a secret (paste the key when asked):

   ```bash
   gh secret set CHOCOLATEY_API_KEY -R FredrikBorgstrom/moviecat
   ```

New Chocolatey packages are reviewed by a moderator, which usually takes a few days.
