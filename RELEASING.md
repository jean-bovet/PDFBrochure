# Releasing PDFBrochure

How to ship a new version end-to-end: signed, notarized DMG on GitHub Releases
plus a refreshed Sparkle appcast for in-app auto-updates.

## Prerequisites (one-time per machine)

You'll need:

- **Xcode** (a recent version) and Command Line Tools.
- **An Apple Developer account** with a `Developer ID Application` certificate
  in your login keychain.
- **`create-dmg`**: `brew install create-dmg`.
- **A `notarytool` keychain profile.** Generate an app-specific password at
  <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords,
  then:
  ```bash
  xcrun notarytool store-credentials PB_NOTARY \
      --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
  ```
  `scripts/release.sh` defaults to a profile named `PB_NOTARY`; override with
  `NOTARY_PROFILE=…`.
- **Sparkle EdDSA private key** stored in the login keychain under account
  `pdfbrochure` (separate from AudioXplorer's default `ed25519` account so
  the two apps' signing keys can't be confused). On a fresh machine, restore
  it from your password manager and re-import:
  ```bash
  scripts/sparkle/generate_keys --account pdfbrochure -f /path/to/key/file
  ```
- **Push access** to the repo (for the appcast and the GitHub Release).

## Cutting a release

1. **Bump the version** in `project.yml`: increment `CFBundleShortVersionString`
   (e.g. `1.0` → `1.1`) and `CFBundleVersion` (e.g. `1` → `2`). The release
   script regenerates `PDFBrochure.xcodeproj` and `Sources/Info.plist` for
   you on every run, so a manual `xcodegen generate` is only needed if
   you want to open the bumped project in Xcode first.

2. **Write release notes** at `docs/releasenotes/<CFBundleShortVersionString>.md`
   (Markdown). The release script copies this file alongside the DMG so
   `generate_appcast` embeds it as the appcast item's `<description>`, which
   is what Sparkle's update prompt displays. If the file is missing, the
   script warns and produces an item with no description.

3. **Run the release script.** Set `SIGN_IDENTITY` to the full identity
   string if you have multiple Developer ID certs:
   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
   ```
   The script will:
   - `xcodebuild` Release into `build/Release/`
   - Sign the `.app` with hardened runtime + entitlements
   - Package a DMG into `dist/` via `create-dmg`
   - Sign the DMG
   - Submit to Apple's notary service and `wait` (~3–5 min)
   - Staple the ticket
   - Regenerate `docs/appcast.xml` with EdDSA signatures via
     `scripts/sparkle/generate_appcast --account pdfbrochure`

   For a quick packaging-only test (no notarization round-trip), use
   `SKIP_NOTARIZE=1`.

4. **Sanity-check the artifacts.**
   ```bash
   open dist/PDFBrochure-X.Y.dmg                # visual layout check
   git diff docs/appcast.xml                     # confirm new <item> for X.Y, EdDSA signature populated
   ```

5. **Commit, tag, push.** (`Sources/Info.plist` and `PDFBrochure.xcodeproj/`
   are gitignored — only the inputs and the appcast move.)
   ```bash
   git add project.yml docs/appcast.xml docs/releasenotes/X.Y.md
   git commit -m "Release X.Y"
   git tag -a vX.Y -m "PDFBrochure X.Y"
   git push origin main --tags
   ```

6. **Create the GitHub Release.** The appcast's enclosure URL points at
   `https://github.com/jean-bovet/PDFBrochure/releases/download/vX.Y/PDFBrochure-X.Y.dmg`,
   so the asset filename and tag name must match:
   ```bash
   gh release create vX.Y dist/PDFBrochure-X.Y.dmg \
       --title "PDFBrochure X.Y" \
       --notes "Release notes…"
   ```

## Verification

After publishing, confirm the update path actually works:

1. **Appcast served**:
   ```bash
   curl -sI https://jean-bovet.github.io/PDFBrochure/appcast.xml
   # → HTTP/2 200, content-type: application/xml
   ```
2. **DMG reachable** via the URL inside the appcast — should `302` to
   GitHub's CDN and return the correct `content-length`.
3. **End-to-end Sparkle prompt**: revert your local `project.yml` to a
   *lower* version, regenerate, rebuild, launch, click "Check For Updates…".
   Sparkle should prompt with the new version's release notes and successfully
   install.

## One-time GitHub setup

The appcast is served from this repo's `/docs` folder via GitHub Pages.
Enable it once:

1. Repo → Settings → Pages.
2. Source: **Deploy from a branch**.
3. Branch: **main**, folder: **/docs**.
4. Save. Within ~1 minute, `https://jean-bovet.github.io/PDFBrochure/appcast.xml`
   should serve.

## Common pitfalls

- **`notarytool` rejects the submission** — fetch the log to see why:
  ```bash
  xcrun notarytool log <submission-id> --keychain-profile PB_NOTARY
  ```
  The most common cause is a nested bundle that isn't signed with your
  Developer ID. Re-sign and re-run.
- **`generate_appcast` not found** — the Sparkle CLI tools live in
  `scripts/sparkle/`, not inside `Frameworks/Sparkle.framework`. The release
  script knows the right path.
- **Sparkle reports "you're up to date" after publishing** — the appcast
  version must be strictly greater than the locally installed
  `CFBundleShortVersionString`. Bump *both* the short version and the build
  number when releasing.
- **Tag/asset name mismatch** — the appcast bakes in the URL
  `…/releases/download/vX.Y/PDFBrochure-X.Y.dmg`. Stick to `vX.Y` and
  `PDFBrochure-X.Y.dmg`.
- **"unable to find a key with account pdfbrochure"** — your keychain doesn't
  have the PDFBrochure key. Either run `scripts/sparkle/generate_keys --account
  pdfbrochure` (creates a new keypair, but existing installs won't trust
  releases signed with it!) or restore the existing key with
  `scripts/sparkle/generate_keys --account pdfbrochure -f path/to/key`.

## What to do if you lose the Sparkle private key

Existing installs verify updates against the public key baked into their
`Info.plist` (`SUPublicEDKey`). If you sign a new release with a different
key, those installs will reject it. Recovery options, in order of preference:

1. **Restore the key** from your password manager into the login keychain
   (`generate_keys --account pdfbrochure -f`).
2. **Generate a new key**, embed the new public key, and ship the next
   release manually (users have to download it from GitHub Releases). Future
   updates from that point onward use the new key.

There is no Sparkle key-rotation feature in 2.x — once shipped, the public
key is what existing installs trust.

## Files involved

- `scripts/release.sh` — orchestrates the whole pipeline.
- `scripts/sparkle/{generate_appcast,sign_update,generate_keys}` — vendored
  Sparkle CLI tools.
- `Frameworks/Sparkle.framework/` — vendored Sparkle 2 runtime.
- `PDFBrochure.entitlements` — hardened-runtime entitlements (includes
  `com.apple.security.cs.disable-library-validation` so Sparkle's bundled
  XPC services load).
- `project.yml` — `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`,
  plus the version fields.
- `docs/appcast.xml` — published via GitHub Pages from the `/docs` folder of
  `main`.
