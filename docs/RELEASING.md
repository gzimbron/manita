# Releasing Manita (GitHub + Homebrew)

Users install with `brew install --cask gzimbron/tap/manita`. Getting there takes a one-time setup and then either one tag push (automatic) or three commands (manual).

## Why each piece exists

| Piece | Why |
| --- | --- |
| **Developer ID signature** | Tells macOS who made the app. Without it Gatekeeper blocks the download, and the Accessibility permission (presentation mode) is lost on every update. |
| **Notarization** | Apple scans the signed app and issues a ticket. Without it, a downloaded app shows "cannot be opened because Apple cannot check it". |
| **GitHub Release** | A public URL for the zip. Homebrew downloads from there. |
| **Tap (`gzimbron/homebrew-tap`)** | Your own Homebrew catalog. The official catalog only accepts well-known apps. |

## One-time setup

1. **Certificate.** "Developer ID Application" must be in the keychain (`security find-identity -v -p codesigning`). Already done.
2. **Notarization password.** At <https://account.apple.com> → Sign-In and Security → App-Specific Passwords, create one named `manita-notary`.
3. **Store the credentials** in the keychain (you type the password; it is never written to the repo):
   ```sh
   xcrun notarytool store-credentials manita-notary --apple-id <your Apple ID email> --team-id R26Z5H75H2
   ```
4. **Repos.** Create the public repos `gzimbron/manita` (this code) and `gzimbron/homebrew-tap` (holds `Casks/manita.rb`, copied from `packaging/homebrew/manita.rb`).

## Automatic releases with release-please (recommended)

Releases come from the commit history, like `release-please`/changesets in JS repos:

1. Commit to `main` with [Conventional Commits](https://www.conventionalcommits.org/): `fix: …` → patch, `feat: …` → minor, `feat!: …` or `BREAKING CHANGE:` → major.
2. On each push, `.github/workflows/release-please.yml` keeps a **Release PR** open that bumps the version (`.release-please-manifest.json`, `Resources/Info.plist`, `packaging/homebrew/manita.rb`) and writes the new `CHANGELOG.md` section.
3. Merge the Release PR when you want to ship. release-please tags `vX.Y.Z` and creates the GitHub Release with those notes; the same workflow then calls `release.yml`, which signs, notarizes, attaches `Manita-X.Y.Z.zip` and updates the Homebrew tap.

The in-repo `packaging/homebrew/manita.rb` is a template: its `sha256` is filled in only in the tap. Manual fallback: push a tag, then run **Actions → Release → Run workflow** with that tag. Pushing a tag alone builds nothing, so the first release (v1.0.0, built and notarized locally) does not run the workflow.

## What release.yml does

`.github/workflows/release.yml` (called by release-please, or run by hand from the Actions tab with a tag) builds, signs (Developer ID), notarizes, attaches `Manita-X.Y.Z.zip` to the GitHub Release (creating it from the CHANGELOG section if it does not exist yet) and updates `Casks/manita.rb` in the tap.

Add these repository secrets (Settings → Secrets and variables → Actions) once:

| Secret | How to produce it |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | In Keychain Access, My Certificates, select **Developer ID Application: …** (with its private key), right-click → Export → `cert.p12` with a password. Then run `base64 -i cert.p12 \| pbcopy` and paste. Delete `cert.p12` afterwards. |
| `MACOS_CERTIFICATE_PASSWORD` | The password you chose when exporting the .p12. |
| `APPLE_ID` | The Apple ID email of the developer account. |
| `APPLE_TEAM_ID` | `R26Z5H75H2` |
| `APPLE_APP_PASSWORD` | App-specific password from <https://account.apple.com> → Sign-In and Security → App-Specific Passwords. |
| `TAP_GITHUB_TOKEN` | Fine-grained personal access token (Settings → Developer settings), resource owner `gzimbron`, only repository `gzimbron/homebrew-tap`, permission **Contents: Read and write**. |

`GITHUB_TOKEN` is provided automatically. The workflow imports the certificate into a temporary keychain, stores the notary credentials there as `manita-notary` (`MANITA_NOTARY_KEYCHAIN` makes `scripts/release.sh` use it) and deletes the keychain at the end. The tag must match the produced zip; the cask is `packaging/homebrew/manita.rb` with its `version` and `sha256` lines replaced.

`.github/workflows/ci.yml` builds and tests every push to `main` and every pull request.

## Every release (manual)

```sh
scripts/release.sh 1.0.0                      # sign, notarize, staple, zip; prints the sha256
gh release create v1.0.0 dist/Manita-1.0.0.zip --repo gzimbron/manita --title "Manita 1.0.0" --notes-file CHANGELOG.md
# In homebrew-tap: set version and sha256 in Casks/manita.rb, commit, push.
```

Check it like a user would: `brew install --cask gzimbron/tap/manita`, then `brew upgrade --cask manita` on the next release.
