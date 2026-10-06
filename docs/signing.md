# Signing and build provenance

holzBar has no Apple Developer ID, so it is not notarized and Gatekeeper does not assess it (the Homebrew cask removes the quarantine flag; see the README). Two things still let you trust a release:

1. **A stable signature.** The release workflow signs holzBar with the project's own self-signed code signing certificate. Every release then has the same designated requirement — `identifier "com.holzcloud.holzBar" and certificate leaf = H"…"` — instead of an ad hoc signature, whose only identity is the hash of the code.
   - macOS keeps holzBar's Accessibility permission across updates, so you are no longer asked to grant it again after every update.
   - A `holzBar.app` whose main executable was replaced and signed with any other key does not get the permission: macOS asks for it again, which is now unusual and worth a second look.
   - From 0.0.7-beta2, holzBar ships no nested code: `Contents/MacOS/holzBar` is the only executable in the bundle, so there is nothing else that could be swapped and keep holzBar's permissions. Up to 0.0.7-beta1, the menu bar item XPC service could: on macOS 26, a copy of the app with a swapped service kept the permissions without a prompt ([SECURITY.md](../SECURITY.md), F-04).
2. **Build provenance.** Every release zip carries a [GitHub artifact attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations): a statement, signed with the release workflow's identity through Sigstore, that the zip was built by `.github/workflows/release.yml` in this repository, from a given tag and commit. From 0.0.7-beta2, the release also carries [SLSA Build Level 3](https://slsa.dev) provenance, `holzBar-<version>.intoto.jsonl`, made by the [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator). You can check both before you install.

The hardened runtime stays on, and holzBar has no entitlements, not even `com.apple.security.get-task-allow`, which would let any process of the same user attach a debugger and act with holzBar's permissions. `Scripts/check-signature.sh` fails the pull-request build, the release build and `Scripts/install.sh` when any code in the app carries an entitlement, or when the bundle holds any code besides `Contents/MacOS/holzBar`. Releases up to 0.0.7-beta1 carried get-task-allow; it is gone from 0.0.7-beta2.

The release workflow never publishes an ad hoc build: without the two secrets below, or with a certificate whose SHA-256 is not holzBar's (`e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`, pinned in `.github/workflows/release.yml`), it fails. Releases up to 0.0.5 are signed ad hoc and carry no attestation.

## For the maintainer: create the certificate

Do this once, on a Mac. The certificate is valid for 20 years; keep it for as long as holzBar exists, because a new certificate means every user grants Accessibility once more.

### With Keychain Access

1. Open **Keychain Access** and choose **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `holzBar Release Signing`. Identity Type: **Self-Signed Root**. Certificate Type: **Code Signing**. Turn on **Let me override defaults** and click **Continue**.
3. Validity Period: `7300` days. Continue.
4. Enter an email address and the name if you like, and leave **Organizational Unit** empty.
5. Key Pair Information: **RSA, 2048 bits** or more (or **ECC, 256 bits**). Keep the defaults for the extensions and click **Create**.
6. In **My Certificates**, Control-click **holzBar Release Signing** (it has the private key under it) and choose **Export "holzBar Release Signing"…**. Save it as `holzbar-signing.p12` and give it a long, random password.

### With openssl

macOS's own `/usr/bin/openssl` (LibreSSL) writes a `.p12` file that `security import` reads. With OpenSSL 3 (for example from Homebrew), add `-legacy` to the last command.

```sh
cat > holzbar-signing.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = holzBar Release Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
openssl req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes \
  -keyout holzbar-signing.key -out holzbar-signing.crt -config holzbar-signing.cnf
openssl pkcs12 -export -name "holzBar Release Signing" \
  -inkey holzbar-signing.key -in holzbar-signing.crt -out holzbar-signing.p12
rm holzbar-signing.key holzbar-signing.cnf
```

`openssl pkcs12` asks for the export password: use a long, random one.

### Check it

```sh
# The certificate's SHA-256 fingerprint, to publish in the README and pin in release.yml:
openssl pkcs12 -in holzbar-signing.p12 -nokeys -clcerts | openssl x509 -outform DER | shasum -a 256
```

To try it, import it into your login keychain (`security import holzbar-signing.p12 -T /usr/bin/codesign`), then sign a copy of holzBar the way the release does, with empty entitlements, and check it:

```sh
plutil -create xml1 empty.entitlements
codesign --force --options runtime --entitlements empty.entitlements \
  --sign "holzBar Release Signing" holzBar.app
Scripts/check-signature.sh holzBar.app
codesign -d -r- holzBar.app
```

## For the maintainer: add the secrets

The release workflow reads two secrets:

| Secret | Value |
|---|---|
| `SIGNING_CERTIFICATE_P12` | The `.p12` file, base64-encoded |
| `SIGNING_CERTIFICATE_PASSWORD` | Its export password |

With the GitHub CLI, from the folder with the file:

```sh
base64 -i holzbar-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 -R holzcloud/holzBar
gh secret set SIGNING_CERTIFICATE_PASSWORD -R holzcloud/holzBar   # asks for the password
```

Or in the browser: **Settings → Secrets and variables → Actions → New repository secret**, once for each (`base64 -i holzbar-signing.p12 | pbcopy` copies the first value).

Then:

- Keep `holzbar-signing.p12` and its password in your password manager, and delete other copies. Whoever has both can sign code that macOS treats as holzBar.
- Write the fingerprint into the README, next to the comparison row "Stable signature", and into `EXPECTED_CERT_SHA256` in `.github/workflows/release.yml`. The release job prints it in its summary ("Signature: holzBar's certificate, SHA-256 …").

**The secrets are still repository secrets**, by the maintainer's decision of 2026-10-05; they move into the environment `release` for the beta after 0.0.7-beta2. Until then a residual risk remains ([SECURITY.md](../SECURITY.md), T-06-L7): a workflow file pushed to any branch by a credential with the `workflow` scope can read them. Keep that scope out of agent and automation tokens. The sign job already runs in the environment `release`, which only `v*` tag runs may use, and an environment secret takes precedence over a repository secret of the same name, so the move needs no workflow change:

```sh
base64 -i holzbar-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 --env release -R holzcloud/holzBar
gh secret set SIGNING_CERTIFICATE_PASSWORD --env release -R holzcloud/holzBar
# After the next beta was signed with them:
gh secret delete SIGNING_CERTIFICATE_P12 -R holzcloud/holzBar
gh secret delete SIGNING_CERTIFICATE_PASSWORD -R holzcloud/holzBar
```

A fresh `.p12` exported from Keychain Access with a new password works too, as long as it holds the same certificate and key.

### How the workflow uses them

`.github/workflows/release.yml` runs only for a pushed `v*` tag whose commit is on `main`, in separate jobs, each with only what it needs:

1. **Build**: builds holzBar ad hoc without get-task-allow, with a read-only token, no persisted credentials, no secrets and no OIDC token, and runs `Scripts/check-signature.sh`.
2. **Sign with holzBar's certificate**: the only job that sees the signing secrets. It has no token permissions and checks out no code from the repository. It checks that the build is exactly the zip the build job made, imports the certificate into a temporary keychain with a random password, and signs only with the certificate whose SHA-256 is pinned, with empty entitlements and `codesign --options runtime` (inside out, without `--deep`). It then fails unless every piece of code carries that certificate, the hardened runtime and no entitlement, the bundle has no code besides `Contents/MacOS/holzBar`, and the designated requirement is exactly the identifier and the certificate. The keychain is deleted, also when a step failed. The key is never in a keychain while the project builds.
3. **Publish the release**: checks the signed zip's SHA-256, creates the GitHub attestation and publishes the release with its notes. It completes a release that already exists, but never replaces a zip it already carries.
4. **SLSA provenance**: the slsa-github-generator attaches `holzBar-<version>.intoto.jsonl` to the release.
5. **Update the Homebrew cask**: runs in the environment `release` and pushes `Casks/holzbar.rb` to `main` with its deploy key, only after both provenances exist, only when the published zip has the signed zip's SHA-256, and only to a version newer than the cask's (0.0.7-beta1 < 0.0.7 < 0.0.8).
6. **Show the version on holzcloud.ch**.

### If the certificate is lost or leaks

Create a new one, replace both secrets, and change `EXPECTED_CERT_SHA256` in `.github/workflows/release.yml` in a pull request; without that, the release fails. The next release asks every user for Accessibility once more, and the README's fingerprint changes; say so in its release notes. A leaked certificate cannot be revoked, as no authority issued it. Replace it at once: once users have updated and granted Accessibility to the release signed with the new certificate, code signed with the leaked one no longer gets the permission.

## For the maintainer: release

`main` accepts only pull requests with green checks, and there is no Run workflow button: a release starts with a tag.

1. Merge the pull request with the release notes, `docs/release-notes/v<version>.md` (the release fails without them).
2. Tag `main` and push the tag:

   ```sh
   git switch main && git pull --ff-only
   git tag -a v<version> -m "holzBar <version>"
   git push origin v<version>
   ```

3. The workflow signs, publishes, attaches the provenance and updates the cask with its deploy key.

Never create the release or the tag in the web UI first, and never push a `v*` tag as a test: every one publishes. If a run fails, use **Re-run failed jobs** in the Actions tab, never **Re-run all jobs**: once publish has run, a rebuild makes a different zip, which publish refuses. The ad hoc build is kept for 7 days, so the sign job can be re-run within a week. A defect in the workflow needs a fix pull request and a new tag.

## The first signed release

The designated requirement changes from the code's hash to the certificate, so the first release signed with the certificate asks for Accessibility once more, like every ad hoc update did. Every release after it keeps the permission. Say so in that release's notes.

## No nested code

Code nested in the bundle, such as an XPC service or a helper, runs with holzBar's Accessibility and Screen Recording permissions, and macOS checks those permissions against the main executable only. In a copy of the app, such code could be swapped while the main executable stays genuine. So holzBar ships none. Up to 0.0.7-beta1, holzBar's menu bar item service (`MenuBarItemService.xpc`) found the app behind each menu bar item on macOS 26; from 0.0.7-beta2 holzBar does that lookup itself, on a background queue with time limits. `Scripts/check-signature.sh` and the release's signature check fail on any Mach-O file besides `Contents/MacOS/holzBar` and on any `XPCServices`, `PlugIns`, `Helpers` or `Frameworks` folder.

## For users: verify a download

### The signature

```sh
codesign -dv /Applications/holzBar.app 2>&1 | grep -E 'Authority|Signature'
codesign -d --extract-certificates=/tmp/holzbar-certificate /Applications/holzBar.app
shasum -a 256 /tmp/holzbar-certificate0
codesign -d --entitlements - --xml /Applications/holzBar.app
```

The authority is `holzBar Release Signing`, and the SHA-256 is the one in the README. `Signature=adhoc` means an ad hoc build (releases up to 0.0.5, or one built without the certificate). From 0.0.7-beta2, the last command prints no entitlements.

### The build provenance

With the [GitHub CLI](https://cli.github.com) (`brew install gh`, then `gh auth login`), for the version you downloaded (such as `0.0.7-beta2`):

```sh
gh attestation verify holzBar-<version>.zip -R holzcloud/holzBar \
  --signer-workflow holzcloud/holzBar/.github/workflows/release.yml \
  --source-ref refs/tags/v<version> \
  --deny-self-hosted-runners
```

For the zip Homebrew downloaded:

```sh
V=$(brew list --cask --versions holzbar | awk '{print $2}')
gh attestation verify "$(brew --cache --cask holzbar)" -R holzcloud/holzBar \
  --signer-workflow holzcloud/holzBar/.github/workflows/release.yml \
  --source-ref "refs/tags/v$V" --deny-self-hosted-runners
```

The command checks that the zip's SHA-256 has an attestation signed by the release workflow of `holzcloud/holzBar`, run for that tag on a GitHub-hosted runner, and prints the commit it was built from. A zip that was changed after the build, or built anywhere else, fails. Without `--signer-workflow` and `--source-ref`, an attestation from any workflow of the repository, on any branch, would pass.

The SLSA provenance, with [slsa-verifier](https://github.com/slsa-framework/slsa-verifier) (`brew install slsa-verifier`):

```sh
gh release download v<version> -R holzcloud/holzBar \
  -p 'holzBar-<version>.zip' -p 'holzBar-<version>.intoto.jsonl'
slsa-verifier verify-artifact holzBar-<version>.zip \
  --provenance-path holzBar-<version>.intoto.jsonl \
  --source-uri github.com/holzcloud/holzBar --source-tag v<version>
```

Older releases:

- 0.0.7-beta1 was built from its tag: use `--source-ref refs/tags/v0.0.7-beta1`.
- 0.0.6-beta1, 0.0.6-beta2 and 0.0.6 were built by a manual run on `main`: use `--source-ref refs/heads/main`.
- No release before 0.0.7-beta2 has SLSA provenance, and releases up to 0.0.5 have no attestation.

Verifying uses the network (GitHub and Sigstore) from your terminal; holzBar itself never connects to the network.
