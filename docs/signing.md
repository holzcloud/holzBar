# Signing and build provenance

holzBar has no Apple Developer ID, so it is not notarized and Gatekeeper does not assess it (the Homebrew cask removes the quarantine flag; see the README). Two things still let you trust a release:

1. **A stable signature.** The release workflow signs holzBar with the project's own self-signed code signing certificate. Every release then has the same designated requirement — `identifier "com.holzcloud.holzBar" and certificate leaf = H"…"` — instead of an ad hoc signature, whose only identity is the hash of the code.
   - macOS keeps holzBar's Accessibility permission across updates, so you are no longer asked to grant it again after every update.
   - A `holzBar.app` whose binary was replaced and signed with any other key does not get the permission: macOS asks for it again, which is now unusual and worth a second look.
2. **Build provenance.** Every release zip carries a [GitHub artifact attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations): a statement, signed with the release workflow's identity through Sigstore, that the zip was built by `.github/workflows/release.yml` in this repository, from a given commit. You can check it before you install.

The hardened runtime stays on in both cases, and holzBar still has no entitlements.

Without the two repository secrets below, the release workflow signs ad hoc, as before, and prints a warning. Releases up to 0.0.5 are signed ad hoc and carry no attestation.

## For the maintainer: create the certificate

Do this once, on a Mac. The certificate is valid for 20 years; keep it for as long as holzBar exists, because a new certificate means every user grants Accessibility once more.

### With Keychain Access

1. Open **Keychain Access** and choose **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `holzBar Release Signing`. Identity Type: **Self-Signed Root**. Certificate Type: **Code Signing**. Turn on **Let me override defaults** and click **Continue**.
3. Validity Period: `7300` days. Continue.
4. Enter an email address and the name if you like, but leave **Organizational Unit** empty: a code signing certificate that is not from Apple has no team, and holzBar's XPC service then pins the app's exact code (see [below](#the-xpc-service)).
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
# The certificate's SHA-256 fingerprint, to publish in the README:
openssl pkcs12 -in holzbar-signing.p12 -nokeys -clcerts | openssl x509 -outform DER | shasum -a 256
```

To try it, import it into your login keychain (`security import holzbar-signing.p12 -T /usr/bin/codesign`), then sign a copy of holzBar, the XPC service first: `codesign --force --options runtime --sign "holzBar Release Signing" holzBar.app/Contents/XPCServices/MenuBarItemService.xpc holzBar.app`, and look at `codesign -d -r- holzBar.app`.

## For the maintainer: add the secrets

The release workflow reads two repository secrets:

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
- After the first release signed with it, write the fingerprint into the README, next to the comparison row "Stable signature". The release job also prints it in its summary ("Signature: holzBar's certificate, SHA-256 …").
- Better still, move the two secrets into a GitHub environment, such as `release`, that only `v*` tags may use.

How the workflow uses them: after the build, it imports the certificate into a temporary keychain with a random password, signs the XPC service and then the app with `codesign --options runtime` (inside out, without `--deep`), checks that both keep the hardened runtime and are no longer ad hoc, and deletes the keychain, also when a step failed. The key is never in a keychain while the project builds.

### If the certificate is lost or leaks

Create a new one and replace both secrets. The next release asks every user for Accessibility once more, and the README's fingerprint changes; say so in its release notes. A leaked certificate cannot be revoked, as no authority issued it. Replace it at once: once users have updated and granted Accessibility to the release signed with the new certificate, code signed with the leaked one no longer gets the permission.

## The first signed release

The designated requirement changes from the code's hash to the certificate, so the first release signed with the certificate asks for Accessibility once more, like every ad hoc update did. Every release after it keeps the permission. Say so in that release's notes.

## The XPC service

holzBar's menu bar item service (`MenuBarItemService.xpc`) accepts only holzBar's own code on macOS 26 and later. A self-signed certificate carries no Apple team, so it takes the same path as an ad hoc build: the service requires holzBar's signing identifier and one of the code directory hashes of the app it is embedded in, read when the service starts (`MenuBarItemService/Listener.swift`). That pins exactly the app it ships in, release after release, with no change needed.

## For users: verify a download

### The signature

```sh
codesign -dv /Applications/holzBar.app 2>&1 | grep -E 'Authority|Signature'
codesign -d --extract-certificates=/tmp/holzbar-certificate /Applications/holzBar.app
shasum -a 256 /tmp/holzbar-certificate0
```

The authority is `holzBar Release Signing`, and the SHA-256 is the one in the README. `Signature=adhoc` means an ad hoc build (releases up to 0.0.5, or one built without the certificate).

### The build provenance

With the [GitHub CLI](https://cli.github.com) (`brew install gh`, then `gh auth login`):

```sh
gh attestation verify holzBar-0.0.6.zip -R holzcloud/holzBar
```

For the zip Homebrew downloaded:

```sh
gh attestation verify "$(brew --cache --cask holzbar)" -R holzcloud/holzBar
```

The command checks that the zip's SHA-256 has an attestation signed by a workflow of `holzcloud/holzBar`, and prints the workflow and the commit it was built from. To require the release workflow itself, add `--signer-workflow holzcloud/holzBar/.github/workflows/release.yml`. A zip that was changed after the build, or built anywhere else, fails.

Verifying uses the network (GitHub and Sigstore) from your terminal; holzBar itself never connects to the network.
