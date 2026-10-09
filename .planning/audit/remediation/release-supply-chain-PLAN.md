---
phase: audit-remediation-release
plan: release-supply-chain
type: execute
wave: 1
depends_on: []
files_modified:
  - .github/actionlint.yaml
  - .github/dependabot.yml
  - .github/scripts/privacy-check.py
  - .github/scripts/workflow-check.py
  - .github/workflows/build.yml
  - .github/workflows/cask.yml
  - .github/workflows/codeql.yml
  - .github/workflows/lint.yml
  - .github/workflows/release.yml
  - .github/workflows/scorecard.yml
  - Scripts/check-signature.sh
  - Scripts/install.sh
autonomous: true
requirements: [F-05, F-10, F-11, F-52, F-53]

must_haves:
  truths:
    - "Only a push of a v* tag starts release.yml; its build job refuses any ref that is not refs/tags/v*, any repository other than holzcloud/holzBar, and any tag whose commit is not an ancestor of origin/main (F-10, F-53)."
    - "Only the sign job of release.yml references SIGNING_CERTIFICATE_P12 and SIGNING_CERTIFICATE_PASSWORD (they stay repository secrets, per the maintainer); that job runs only for refs/tags/v*, has permissions {} and runs no repository code. The build job has contents: read, persist-credentials: false, no secrets and no id-token (F-10 partly, F-52)."
    - "A release without the signing secrets, or with a p12 whose certificate SHA-256 is not e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95, fails before anything is published, and the cask is not touched (F-11)."
    - "Every piece of code in a released holzBar.app has the hardened runtime (bundles), no entitlements at all (com.apple.security.get-task-allow named explicitly), the leaf certificate e55f0df1..., and the app's designated requirement is exactly identifier \"com.holzcloud.holzBar\" and certificate leaf = H\"<SHA-1 of that certificate>\"; any deviation fails the run before publishing (F-05, F-11)."
    - "build.yml, the release build and Scripts/install.sh build with CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO and fail through Scripts/check-signature.sh when any code in the app carries an entitlement (F-05)."
    - "The cask commit reaches main only from release.yml's cask job (environment release, CASK_DEPLOY_KEY over SSH via actions/checkout ssh-key), after publish and SLSA provenance succeeded and the published asset's digest equals the signed zip's SHA-256 (F-10)."
    - "Every third-party action in every workflow and composite action is pinned by full commit SHA with a '# vX.Y.Z' comment (the SLSA generator only by tag), every workflow has read-only top-level permissions, and build.yml's workflows job (actionlint + workflow-check.py) fails a pull request that breaks this, uses a secret or a write permission outside its allowlist, or persists checkout credentials (F-10)."
    - "Each release gets holzBar-<version>.intoto.jsonl from slsa-framework/slsa-github-generator generator_generic_slsa3.yml@v2.1.0 in addition to the actions/attest-build-provenance attestation; scorecard.yml, codeql.yml (swift and actions) and dependabot.yml (github-actions, weekly, one grouped PR, composite action directory included) exist."
    - "No file under .github/ or Scripts/install.sh or Scripts/check-signature.sh names the removed XPC service; the checks cover holzBar.app and whatever code it contains."
  artifacts:
    - path: Scripts/check-signature.sh
      provides: "Shared check: valid signature, hardened runtime on bundles, no entitlements, for the app and every nested code item"
    - path: .github/workflows/release.yml
      provides: "Jobs build -> sign -> publish -> provenance -> cask -> holzcloud-ch with per-job least privilege"
    - path: .github/scripts/workflow-check.py
      provides: "Pin, permission, secret and credential policy for workflows and composite actions"
    - path: .github/actionlint.yaml
      provides: "actionlint knows the xcode-27 runner label"
    - path: .github/workflows/scorecard.yml
      provides: "OpenSSF Scorecard with publish_results and SARIF upload"
    - path: .github/workflows/codeql.yml
      provides: "CodeQL swift (xcode-27, manual build) and actions (ubuntu, no build), weekly and on demand"
    - path: .github/dependabot.yml
      provides: "Weekly grouped github-actions updates for / and /.github/actions/*"
  key_links:
    - from: "release.yml build job"
      to: "release.yml sign job"
      via: "artifact holzBar-adhoc + output adhoc-sha256, compared after download"
    - from: "release.yml sign job"
      to: "publish, provenance, cask jobs"
      via: "artifact holzBar-release + outputs zip, sha256, hashes"
    - from: "release.yml cask job"
      to: "main"
      via: "environment release -> secrets.CASK_DEPLOY_KEY -> actions/checkout ssh-key -> git push origin HEAD:main, allowed by ruleset main bypass actor DeployKey"
    - from: "build.yml, release.yml build job, Scripts/install.sh"
      to: "Scripts/check-signature.sh"
      via: "direct call on the built holzBar.app"
    - from: "build.yml workflows job"
      to: ".github/scripts/workflow-check.py and docker://rhysd/actionlint (reads .github/actionlint.yaml)"
      via: "required status check 'workflows'"
---

# Release supply chain (F-05, F-10, F-11, F-52, F-53)

<objective>
Make holzBar's CI, release and local install pipeline ship only what the maintainer intends: release builds without `com.apple.security.get-task-allow` (F-05), a signed release that is only possible from a protected `v*` tag on main, with the signing key reachable from as few places as possible while it stays a repository secret (F-10, partly), a signing step that fails closed and pins holzBar's certificate (F-11), a build that runs without write credentials or OIDC (F-52), and provenance that can be verified against the release workflow and the tag (F-53), plus the supply-chain measures the maintainer chose (SLSA Build L3 provenance, OpenSSF Scorecard, CodeQL, Dependabot, SHA-pinned actions).

Purpose: today any workflow on any branch can read the signing key and push the cask that every Homebrew user installs, and the shipped 0.0.7-beta1 app lets a debugger attach and act with holzBar's Accessibility and Screen Recording grants.

Output: the changed and new files listed in `files_modified`, committed in six atomic commits on branch `audit-manual/release`, plus the `doc_updates_needed` and repository settings below, which the orchestrator applies after the merge.
</objective>

## The decision being implemented

- Maintainer's choice (decision file `release-1.md`): **"PR-Pflicht plus Deploy Key"** — main accepts only pull requests with green checks; the only direct writer to main is the release workflow's cask update, through a write deploy key that only `v*` tag runs can use.
- Later maintainer decision (the user asked to solve the signing part differently; recorded in the orchestrator's task): the signing secrets **stay repository-level secrets** (`SIGNING_CERTIFICATE_P12`, `SIGNING_CERTIFICATE_PASSWORD`). They are NOT moved into an environment and the maintainer re-enters nothing. Consequences for this plan:
  - The GitHub environment `release` already exists (deployment policy: tags `v*` only) and holds only `CASK_DEPLOY_KEY` (already set; the matching write deploy key already exists). Only the cask job uses `environment: release`.
  - The signing job does NOT use an environment: an environment would add nothing for repository secrets (a branch workflow can omit it) and would hand the deploy key to the job that holds the certificate.
  - F-10 stays partly open. Mitigations without moving the secrets: signing only in one job, only for `refs/tags/v*`, with `permissions: {}` and no repository code; no secrets in any other workflow, enforced by CI; tag ruleset; tag-on-main check; PR-only main. The residual risk goes into SECURITY.md (see doc_updates_needed).
- Releases start with a tag push. The manual dispatch trigger of release.yml is **removed** (not turned into a dry run): build.yml already performs the identical build and checks on every pull request, and the steps that a dry run cannot exercise (signing, publishing, provenance, cask) are exactly the ones a dry run would have to skip.
- Out of scope here: `project.pbxproj` (another chain makes the SwiftLint phase skip when `CI` is set and sandboxes it), the removal of the XPC service itself (another chain), all docs (README, docs/, SECURITY.md, release notes, CLAUDE.md). F-54 is already resolved on the base branch (commits 6b1176fc and 04596d0f); nothing to do.

## Hard rules for the executor

- Work only in `WT=/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/release` (branch `audit-manual/release`). Never touch `/Users/cheidenreich/privat/holzBar` or other worktrees, never switch branches, never push, never run `gh` commands that write, never `gh auth switch`, never change git config.
- Never run `Scripts/install.sh` (it quits holzBar, resets TCC and launches the app). Never launch, quit or relaunch holzBar, never run `tccutil` or `defaults write` on real domains. Reading `/Applications/holzBar.app` with `codesign -d` is allowed (read-only) and is used by the tests below.
- This Mac has no Xcode (Command Line Tools only): no `xcodebuild`. All gates are static or run on fixtures in the scratchpad (`SCRATCH=/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`).
- Tools already downloaded by the planner (verified against the release checksums file): `TOOLS=$SCRATCH/tools`, `$TOOLS/actionlint` (1.7.12) and `$TOOLS/shellcheck-v0.11.0/shellcheck`. Never install anything system-wide.
- English in code, comments and commits. Match the surrounding comment style (each workflow step has a short "why" comment). Do not put audit IDs (F-xx) into code comments; they belong in commit messages.
- Commit with `git -C "$WT" add <paths>` and `git -C "$WT" commit` using the message format in "Commits" below, with the two trailer lines exactly. If a gate fails and cannot be fixed: restore the uncommitted changes (`git -C "$WT" restore --staged --worktree -- <changed paths>`, and delete only the new files this task created, by explicit path), report `fix-failed` with the reason and stop the part.
- Before writing any pin, re-check that the release below is still the latest stable one (read-only): `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name` and `git ls-remote https://github.com/<owner>/<repo> refs/tags/<tag> 'refs/tags/<tag>^{}'` (use the peeled `^{}` SHA when present). If a newer stable release exists, use it (CLAUDE.md: latest stable) and say so in the commit body.

## Reference values (verified read-only on 2026-10-05)

| Reference | Pin to write |
|---|---|
| actions/checkout | `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1` |
| actions/upload-artifact | `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1` |
| actions/download-artifact | `actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1` |
| actions/attest-build-provenance | `actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2` |
| github/codeql-action (init, analyze, upload-sarif) | `github/codeql-action/<sub>@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2` (annotated tag 88585263 peeled to this commit; bundle CodeQL 2.27.1) |
| ossf/scorecard-action | `ossf/scorecard-action@2d1146689b8cda280b9bc96326124645441f03bc # v2.4.4` (annotated tag peeled) |
| SLSA generic generator (by tag, required by the generator) | `slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0` (latest release; tag commit f7dd8c54c2067bafc12ca7a55595d5ee9b75204a, for the record only) |
| actionlint in CI (Docker image by digest) | `docker://rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667` (multi-arch index digest from Docker Hub) |

- Certificate pin: `EXPECTED_CERT_SHA256=e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95` (planner re-measured it on `/Applications/holzBar.app` 0.0.7-beta1 with `codesign -d --extract-certificates`; README.md line 81 shows the same). Its SHA-1 is `c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e`, and the shipped designated requirement is `identifier "com.holzcloud.holzBar" and certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"`. The workflow derives the SHA-1 from the verified certificate instead of pinning it a second time.
- `security find-certificate -a -Z <keychain>` prints, per certificate, a line `SHA-256 hash: <UPPERCASE HEX>` followed by `SHA-1 hash: <UPPERCASE HEX>` (checked on this Mac). `security find-identity -p codesigning <keychain>` lists identities as `  1) <SHA-1> "<name>"`; without `-v` it lists the untrusted self-signed identity too (the current workflow relies on that).
- Release assets expose `digest` (`gh release view <tag> --json assets` shows `sha256:<hex>`; verified on v0.0.6).
- Existing attestations: v0.0.6 was attested from `workflow_dispatch` on `refs/heads/main`; v0.0.7-beta1 from a tag push on `refs/tags/v0.0.7-beta1` (read-only API check). Releases up to 0.0.5 carry no attestation.
- CodeQL 2.27.1 analyzes Swift 5.4 to 6.3.3 (github/codeql `supported-versions-compilers.rst` and `swift/ql/lib/CHANGELOG.md` at tag codeql-cli/v2.27.1; no Swift 6.4 change note on main yet). holzBar builds with Swift 6.4 and the macOS 27 SDK on the `xcode-27` image, which has only Xcode 27.0, 27.1 and 27.2 beta (actions/runner-images `xcode-27-arm64-Readme.md`). The swift.org 6.4.0 package is notarized (CI log of run 37281428844), so its compiler runs with the hardened runtime; Apple's `swift-frontend` is signed without it (`flags=0x0(none)`, checked on the Command Line Tools copy).
- The slsa-github-generator README says since 2026-08-07 that the project is no longer actively maintained and may not receive updates for GitHub Actions runtime deprecations; its JS actions declare `node20`. It is still what the maintainer chose (see Risks).
- actionlint 1.7.12 baseline on the unchanged tree: `label "xcode-27" is unknown` (build.yml lines 11, 200, 318; release.yml line 18) and shellcheck findings in build.yml: SC2016 (network step, the regex `PATTERN`), SC2012 (languages step, two `ls`), SC2010 (compat crash-report lookup), SC2012 (newest-Xcode step). `Scripts/install.sh` is shellcheck-clean. privacy-check (network, logs), strings-check and the former-name check pass.

### Permission and secret matrix (target state)

| Workflow / job | permissions | secrets | checkout credentials |
|---|---|---|---|
| every workflow, top level | `contents: read` | — | — |
| release.yml `build` | `contents: read` | none | `persist-credentials: false` |
| release.yml `sign` | `{}` | `SIGNING_CERTIFICATE_P12`, `SIGNING_CERTIFICATE_PASSWORD` (signing step env only) | no checkout at all |
| release.yml `publish` | `contents: write`, `id-token: write`, `attestations: write` | none | `persist-credentials: false` |
| release.yml `provenance` (reusable workflow) | `actions: read`, `id-token: write`, `contents: write` | none | (generator) |
| release.yml `cask` | `contents: read`, `environment: release` | `CASK_DEPLOY_KEY` | SSH key kept (it pushes) |
| release.yml `holzcloud-ch` | `contents: read` | `CMS_TOKEN` (unchanged, not set today) | `persist-credentials: false` |
| build.yml, cask.yml, lint.yml jobs | inherit `contents: read` | none | `persist-credentials: false` |
| codeql.yml `swift`, `actions` | `contents: read`, `security-events: write` | none | `persist-credentials: false` |
| scorecard.yml `analysis` | `contents: read`, `security-events: write`, `id-token: write` | none | `persist-credentials: false` |

### Gates (run after every task, before its commit)

- G1 actionlint: `cd "$WT" && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline` prints nothing and exits 0.
- G2 YAML parse of every changed or new YAML file: `cd "$WT" && ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' <files>` exits 0.
- G3 shell: for each changed shell script, `/bin/bash -n <file>` (bash 3.2, the macOS `/bin/bash` that `#!/bin/bash` uses) and `"$TOOLS/shellcheck-v0.11.0/shellcheck" <file>` exit 0. No zsh script is changed, so `zsh -n` has nothing to check.
- G4 Python syntax without writing `__pycache__`: `cd "$WT" && python3 -c 'import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' .github/scripts/*.py`.
- G5 privacy: `cd "$WT" && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs`.
- G6 strings: `cd "$WT" && python3 .github/scripts/strings-check.py`.
- G7 former name (also covers new, not yet added files): `git -C "$WT" grep --untracked -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'` exits 1 (no match), and `git -C "$WT" ls-files --cached --others --exclude-standard | grep -i -E 'holz[ -]?[i]ce'` prints nothing.
- G8 (from Task 4 on) workflow policy: `cd "$WT" && python3 .github/scripts/workflow-check.py` exits 0.
- G9 hygiene: `git -C "$WT" status --porcelain -- . ':(exclude).planning/audit/remediation'` lists only the task's files (and nothing after the commit); no `__pycache__`, no scratch files. This plan file itself is untracked and stays out of the code commits; the orchestrator decides whether to commit it.
- The executor's shell is zsh: quote every glob that is meant for grep or find (for example `--include='*.yml'`), or zsh aborts with "no matches found".

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1 (tracer): builds without get-task-allow, checked end to end — shared check script, PR build, local install</name>
  <files>.github/actionlint.yaml, .github/workflows/build.yml, Scripts/check-signature.sh, Scripts/install.sh</files>
  <read_first>.github/workflows/build.yml (whole file), Scripts/install.sh, .github/workflows/release.yml lines 112-138 (the current sign and runtime checks), .planning/audit/FULL-AUDIT-2026-10-05.md section "F-05"</read_first>
  <behavior>
    - Fixture app signed ad hoc with the hardened runtime and no entitlements: check-signature.sh exits 0 and prints one "hardened runtime, no entitlements" line per code item.
    - Same fixture signed with an entitlements plist that sets com.apple.security.get-task-allow: exits 1 and the error names get-task-allow and the item.
    - Fixture signed without the hardened runtime: exits 1, error says hardened runtime.
    - Fixture with a nested XPC bundle (CFBundlePackageType XPC!) that carries get-task-allow while the app does not: exits 1 naming the nested item.
    - Fixture with an unrelated entitlement key (com.apple.security.cs.disable-library-validation): exits 1 listing the key.
    - The installed release /Applications/holzBar.app (0.0.7-beta1, read-only): exits 1 because of get-task-allow (proves the check catches the shipped defect).
  </behavior>
  <action>
    Step 1a, lint baseline (own commit, no behavior change): create .github/actionlint.yaml with a short comment (the xcode-27 image is GitHub's public preview with Xcode 27, actions/runner-images#14404, unknown to actionlint 1.7.12) and the key self-hosted-runner with labels: [xcode-27]. In build.yml add shellcheck directives with a reason, directly above the flagged lines: SC2016 above the PATTERN assignment in the network step (a regular expression, not a shell expansion); SC2012 above the two ls listings in the languages step (they only list the folder for the log); SC2010 above the crash-report lookup in the compat launch step (report names contain no newlines); SC2012 above the ls in the newest-Xcode step. Run G1 (must now be clean), G2, G7, then commit 1a.

    Step 1b, F-05 slice. Create Scripts/check-signature.sh (mode 755, #!/bin/bash, set -euo pipefail, bash 3.2 compatible: no mapfile, no associative arrays) with a header in the style of install.sh: what it checks and why (Xcode adds com.apple.security.get-task-allow to builds signed to run locally; with it, a debugger can attach to holzBar and act with its Accessibility and Screen Recording permissions; holzBar has no entitlements at all), usage `Scripts/check-signature.sh path/to/holzBar.app`, and its callers (Scripts/install.sh, build.yml, the release workflow's build job). Behavior: require one argument that is a directory; a report function prints `::error::<message>` when GITHUB_ACTIONS is true, otherwise `error: <message>` to stderr; run `codesign --verify --deep --strict` on the app and report on failure; collect the code items with `find "$APP/Contents" -depth \( -name '*.xpc' -o -name '*.appex' -o -name '*.framework' -o -name '*.app' -o -name '*.dylib' \) -print0` read in a while-read -d '' loop, then the app itself last; for each item: capture `codesign -dv` output (report "not signed" and continue on failure); for items whose name ends in .app, .xpc or .appex require the runtime flag with the same regex the release workflow uses today (`^CodeDirectory.*flags=0x[0-9a-f]+\([^)]*runtime`); capture `codesign -d --entitlements - --xml` (stderr to /dev/null, `|| true`); if it contains com.apple.security.get-task-allow report that it lets a debugger attach, else if it contains `<key>` report "carries entitlements; holzBar has none:" followed by the key names; print `==> <item relative to the app>: hardened runtime, no entitlements` for passing items; exit 1 if anything was reported. Use here-strings (`<<<`) with grep, never `| grep -q` under pipefail (install.sh documents the SIGPIPE problem).

    In build.yml, Build step: append `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` to the xcodebuild overrides and extend the step comment: the build is signed ad hoc with the hardened runtime and without get-task-allow, which Xcode otherwise adds to code signed to run locally. Replace the body of the "Check the signature" step with a call to `Scripts/check-signature.sh build/Build/Products/Release/holzBar.app` and rewrite its comment: every build is hardened and carries no entitlement; the script checks the app and every piece of code inside it (no bundle names hard-coded).

    In Scripts/install.sh: add `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` to the xcodebuild overrides (one more continuation line before `| tail -3`) and extend the comment block above xcodebuild with one sentence on why (no get-task-allow, same as CI). In the "Verifying the signature before installing" section, replace the bare `codesign --verify --deep --strict "$APP"` with `"$ROOT/Scripts/check-signature.sh" "$APP"` (it verifies too) and keep the `codesign -dv | grep` detail line. Do not change anything else in install.sh.

    Tests (scratchpad only, not committed): build the fixtures under "$SCRATCH/sigfix" with clang from the Command Line Tools (`printf 'int main(void){return 0;}\n' | clang -x c - -o <bundle>/Contents/MacOS/<name>`), Info.plist files written with `plutil -create xml1` plus `plutil -insert CFBundleExecutable -string <name>`, `CFBundleIdentifier -string com.example.<name>`, `CFBundlePackageType -string APPL` (or XPC! for the nested service), entitlement plists written with printf as XML, and sign with `codesign --force -s - [--options runtime] [--entitlements <plist>]` (nested code first). Run every case from the behavior list and compare exit codes and messages. Then run the script once on /Applications/holzBar.app (read-only) and expect exit 1 with get-task-allow. Delete nothing outside "$SCRATCH/sigfix".
  </action>
  <verify>
    <automated>cd "$WT" && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline && /bin/bash -n Scripts/check-signature.sh && /bin/bash -n Scripts/install.sh && "$TOOLS/shellcheck-v0.11.0/shellcheck" Scripts/check-signature.sh Scripts/install.sh && test -x Scripts/check-signature.sh && grep -q 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO' .github/workflows/build.yml && grep -q 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO' Scripts/install.sh && grep -q 'Scripts/check-signature.sh' .github/workflows/build.yml && grep -q 'check-signature.sh' Scripts/install.sh && ! Scripts/check-signature.sh /Applications/holzBar.app</automated>
  </verify>
  <done>actionlint is clean on the whole tree; all six fixture cases behave as listed; the installed 0.0.7-beta1 fails the check on get-task-allow; build.yml and install.sh build with CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO and call check-signature.sh; two commits exist (1a lint baseline, 1b F-05).</done>
</task>

<task type="auto">
  <name>Task 2: CI checks holzBar.app without the removed XPC service</name>
  <files>.github/workflows/build.yml, .github/scripts/privacy-check.py</files>
  <read_first>.github/workflows/build.yml steps "Check the identifiers", "Check the binaries for network code", compat "Launch the app"; .github/scripts/privacy-check.py lines 1-40</read_first>
  <action>
    <!-- planner-discipline-allow: MenuBarItemService -->
    Another chain removes the MenuBarItemService XPC service from the app. Remove every reference to it from CI while keeping each check meaningful for the app, and write no comment that names the removed service.

    build.yml "Check the identifiers": drop the service variables, the read of Shared/Services, and both service comparisons. Keep printing app identifier, name, display name and URL schemes, and turn them into assertions (CLAUDE.md naming rules; a changed bundle identifier would lose every user's settings and permissions, and the URL scheme is how Shortcuts, Raycast and scripts reach holzBar): CFBundleIdentifier equals com.holzcloud.holzBar, CFBundleName equals holzBar, CFBundleDisplayName equals holzBar, and the URL scheme list contains "holzbar"; report each mismatch as ::error:: and fail once at the end. Rewrite the step comment accordingly.

    build.yml "Check the binaries for network code": scan every Mach-O in the app instead of two fixed paths: `find "$APP" -type f \( -path '*/Contents/MacOS/*' -o -name '*.dylib' \) -print0` in a while-read loop, label each by its path relative to the app, count them and fail if none was found. Keep the nm/swift-demangle pattern and the WebKit check unchanged. Delete the per-bundle network-entitlement loop and say in the comment that "Check the signature" already rejects every entitlement, network ones included.

    build.yml compat "Launch the app": replace the chmod of two fixed binaries with `find "$APP" -type f -path '*/Contents/MacOS/*' -exec chmod +x {} +` and a comment (upload-artifact keeps no file modes). Leave the rest of the step as it is.

    privacy-check.py: remove the service directory from SOURCE_DIRS (leaving "holzBar" and "Shared") and from the header comment's directory list. The script already tolerates missing directories (os.walk). If the XPC-removal chain has already changed these lines when merging, keep its version.
  </action>
  <verify>
    <automated>cd "$WT" && ! grep -rn 'MenuBarItemService' .github/workflows .github/scripts Scripts/install.sh Scripts/check-signature.sh && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs</automated>
  </verify>
  <done>No CI, script or install file names the removed service; the identifier step asserts the four app identity values; the network scan covers every Mach-O in the app; compat makes every bundled executable executable; privacy-check passes; one commit.</done>
</task>

<task type="auto">
  <name>Task 3: release.yml in least-privilege jobs — tag only, fail closed, certificate pinned, empty entitlements, cask via deploy key</name>
  <files>.github/workflows/release.yml, .github/workflows/build.yml</files>
  <read_first>.github/workflows/release.yml (whole file), .github/actions/select-xcode/action.yml, Casks/holzbar.rb, .github/workflows/cask.yml, .planning/audit/FULL-AUDIT-2026-10-05.md sections F-10, F-11, F-52, F-53, the decision file $SCRATCH/decisions/release-1.md</read_first>
  <action>
    Rewrite release.yml. Keep the file's comment style (each job and step says why). Pin every action as in "Reference values". Pass every expression value to scripts through env, never by interpolating into run. Start every non-trivial script with set -euo pipefail.

    Top level: name Release; trigger only push of tags "v*" (remove the manual dispatch trigger and its version input entirely, and do not mention the removed trigger in comments); permissions contents: read with the existing "read-only unless a job asks for more" comment; concurrency group release-${{ github.ref }} with cancel-in-progress false.

    Job build (name "Build"): if `github.repository == 'holzcloud/holzBar' && startsWith(github.ref, 'refs/tags/v')` (forks never release; a fork needs its own certificate and pin); runs-on xcode-27; timeout-minutes 60; permissions contents: read; outputs version and adhoc-sha256. Steps: (1) checkout with fetch-depth 0 and persist-credentials false; (2) "Determine version": VERSION from GITHUB_REF_NAME without the leading v, require GITHUB_REF_TYPE to be tag and the existing regex `^[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]+)?$` (keep the comment that the rejected value is not echoed), write VERSION to GITHUB_ENV and version to GITHUB_OUTPUT; (3) "Check that the tag is on main": `git merge-base --is-ancestor "$GITHUB_SHA" origin/main` or ::error:: (only reviewed code from main is released; origin/main comes from the full fetch); (4) "Check the release notes" as today; (5) uses ./.github/actions/select-xcode; (6) "Build": first line asserts `[ "${CI:-}" = true ]` or fails with an error saying the project's SwiftLint build phase skips only when CI is set (nothing in this workflow may unset it); then the existing xcodebuild call with MARKETING_VERSION, CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER, CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= and CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO; comment: built and signed ad hoc first, without write token, OIDC or secrets, so no build script can reach them; (7) "Check the build": `Scripts/check-signature.sh build/Build/Products/Release/holzBar.app`; (8) "Package the build": `ditto -c -k --keepParent` of the app to build/holzBar-adhoc.zip, write its SHA-256 (shasum -a 256) to output adhoc-sha256; (9) upload-artifact name holzBar-adhoc, path build/holzBar-adhoc.zip, retention-days 1, if-no-files-found error.

    Job sign (name "Sign with holzBar's certificate"): needs build; if startsWith(github.ref, 'refs/tags/v'); runs-on xcode-27; timeout-minutes 20; permissions {} (comment: it holds the certificate, so it gets no token permission and runs no code from the repository: no checkout, only the commands written here); job env EXPECTED_CERT_SHA256 with the pinned value (comment: holzBar's certificate as published in the README; a different one would change holzBar's identity for macOS and drop every user's Accessibility grant) and VERSION from needs.build.outputs.version; outputs zip, sha256, hashes from the package step. Steps:
    (1) download-artifact holzBar-adhoc to ${{ runner.temp }}/adhoc.
    (2) "Unpack the build": compare shasum -a 256 of the zip with env ADHOC_SHA256 from needs.build.outputs.adhoc-sha256 (fail on mismatch), `ditto -x -k` into $RUNNER_TEMP/release.
    (3) "Sign" with env SIGNING_CERTIFICATE_P12 and SIGNING_CERTIFICATE_PASSWORD from the repository secrets (the only place they appear in the repository). If either is empty: ::error:: that holzBar is never released signed ad hoc (users would lose Accessibility and Screen Recording; docs/signing.md) and exit 1 — there is no ad hoc branch any more. Then the existing temporary keychain sequence (create with a random masked password, set-keychain-settings -lut 1800, unlock, decode the p12 under umask 077, import with -T /usr/bin/codesign, delete the p12, set-key-partition-list). Certificate pin before signing: uppercase the expected value with tr, read `security find-certificate -a -Z "$KEYCHAIN"` and use awk to print the SHA-1 that follows the SHA-256 line equal to the expected value (fields: $1 is SHA-256 or SHA-1, $3 is the hash); if empty, ::error:: that SIGNING_CERTIFICATE_P12 does not hold holzBar's certificate (name the expected SHA-256) and exit 1. Require that `security find-identity -p codesigning "$KEYCHAIN"` lists that SHA-1 (keep the comment why -v is not used); otherwise ::error:: that the private key is missing. Create the empty entitlements file with `plutil -create xml1 "$RUNNER_TEMP/empty.entitlements"`. The sign function: `codesign --force --sign "$SHA1" --keychain "$KEYCHAIN" --options runtime --timestamp=none --entitlements "$RUNNER_TEMP/empty.entitlements" --preserve-metadata=identifier,flags,runtime "$1"` — preserve only identifier, flags and runtime, never the build's entitlements. Keep the existing inside-out loop over nested code (same find expression, -depth, print0) and then the app, with the existing comments updated: empty entitlements explicitly, the build job already proved the build had none, so nothing real can be dropped silently; no timestamp, as today. Remove the comment paragraph about the XPC service.
    (4) "Remove the signing keychain": if always(), as today.
    (5) "Check the signature" (inline; no repository code in this job): the app path comes from the step's env, `APP: ${{ runner.temp }}/release/holzBar.app`; codesign --verify --deep --strict; for every code item (same find list plus the app): fail on Signature=adhoc; require the runtime flag for .app, .xpc and .appex items; fail if the entitlements XML contains com.apple.security.get-task-allow (named) or any `<key>`; extract the certificates with `codesign -d --extract-certificates="$CERTS/<n>-"` and require that the SHA-256 of `<n>-0` equals EXPECTED_CERT_SHA256 (lowercase compare). For the app: compute the leaf SHA-1 with shasum -a 1 and require the designated requirement (`codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p'`) to equal exactly `identifier "com.holzcloud.holzBar" and certificate leaf = H"<sha1>"`. Collect all failures, print ::error:: for each, exit 1 if any. On success append to GITHUB_STEP_SUMMARY: certificate SHA-256, designated requirement, "no entitlements". Write this step so that its script runs unchanged outside Actions with only APP, EXPECTED_CERT_SHA256, RUNNER_TEMP and GITHUB_STEP_SUMMARY set (Test C runs it locally).
    (6) "Package": ZIP=holzBar-$VERSION.zip created with `ditto -c -k --keepParent` in $RUNNER_TEMP; outputs zip (the file name), sha256, and hashes = the output of `shasum -a 256 "$ZIP"` run inside $RUNNER_TEMP (so the subject name is the bare file name), piped through `base64 | tr -d '\n'` (the SLSA generator's base64-subjects format: sha256sum lines, base64-encoded).
    (7) upload-artifact name holzBar-release, path the zip, retention-days 7, if-no-files-found error.

    Job publish (name "Publish the release"): needs [build, sign]; runs-on ubuntu-latest; timeout-minutes 15; permissions contents: write, id-token: write, attestations: write, each with a one-line reason; env VERSION, ZIP, SHA256 from needs, GH_REPO ${{ github.repository }}. Steps: checkout with sparse-checkout docs/release-notes and persist-credentials false (data only, no code runs); download-artifact holzBar-release to dist; "Check the signed zip": sha256sum of dist/$ZIP equals SHA256; attest-build-provenance with subject-path dist/${{ needs.sign.outputs.zip }} (keep the comment and update the documented command to the constrained form: --signer-workflow holzcloud/holzBar/.github/workflows/release.yml --source-ref refs/tags/v<version>); "Publish the release" with GH_TOKEN github.token: TAG=v$VERSION; IS_PRERELEASE true for v0.* or any tag with a suffix (as today); if `gh release view "$TAG"` succeeds (a rerun, or a release created by hand): read the asset digest with `gh release view "$TAG" --json assets --jq '.assets[] | select(.name == env.ZIP) | .digest'`; if present it must equal sha256:$SHA256 (else ::error:: never replace a published zip, exit 1); if absent `gh release upload "$TAG" "dist/$ZIP"`; then `gh release edit "$TAG" --title "holzBar $TAG" --notes-file docs/release-notes/$TAG.md --prerelease="$IS_PRERELEASE" --draft=false`; otherwise `gh release create "$TAG" "dist/$ZIP" --verify-tag --title "holzBar $TAG" --notes-file docs/release-notes/$TAG.md --prerelease="$IS_PRERELEASE"` (--verify-tag: the tag must already exist; the workflow never creates tags).

    Job cask (name "Update the Homebrew cask"): needs [build, sign, publish] (Task 5 adds provenance); runs-on macos-26; timeout-minutes 20; environment release (comment: the environment, which only v* tag runs may use, holds CASK_DEPLOY_KEY, the write deploy key that the main ruleset lets push; GITHUB_TOKEN cannot); permissions contents: read; env VERSION, ZIP, SHA256, GH_REPO, HOMEBREW_NO_AUTO_UPDATE "1", HOMEBREW_NO_ENV_HINTS "1". Steps: (1) checkout with ref main and ssh-key ${{ secrets.CASK_DEPLOY_KEY }}, credentials kept (default; the push below needs the key); (2) "Check the published zip" with GH_TOKEN github.token: re-validate VERSION (same regex) and SHA256 (`^[0-9a-f]{64}$`); require `gh release list --exclude-drafts --limit 1 --json tagName --jq '.[0].tagName'` to equal v$VERSION (never move the cask back to an older release when an old run is re-run); require the published asset's digest to equal sha256:$SHA256; (3) "Update the cask on main": run `brew update --quiet` once (as cask.yml), then up to three attempts: `git fetch --quiet origin main`, `git checkout --quiet -B main origin/main`; if Casks/holzbar.rb already has exactly this version and sha256 line, print a notice and stop with success (rerun after a successful push); apply the existing two sed expressions (sed -i '' -E on version and sha256); require `git diff --numstat` to be exactly one line "2<TAB>2<TAB>Casks/holzbar.rb" and nothing else changed, otherwise print the diff and fail; commit as github-actions[bot] with the existing name/email via `git -c user.name=... -c user.email=... commit -qam "holzbar $VERSION"`; style-check the committed cask the way cask.yml does (clone $GITHUB_WORKSPACE to $RUNNER_TEMP/tap-src, `brew untap holzcloud/holzbar` ignoring failure, `brew tap holzcloud/holzbar "$SRC"`, `brew trust --cask holzcloud/holzbar/holzbar`, `brew style --cask holzcloud/holzbar/holzbar`); `git push origin HEAD:main` and stop on success; otherwise sleep 15 s times the attempt and retry. The retry re-applies the edit on the fresh main instead of rebasing (equivalent to the decision's fetch/rebase retry, but no conflict can occur). After three failures ::error:: and exit 1.

    Job holzcloud-ch: keep its comment and script; needs [build, cask]; VERSION from needs.build.outputs.version; checkout pinned with persist-credentials false (plus the existing sparse checkout); permissions contents: read.

    build.yml Build step: add the same CI assertion as the release build as its first line, with the same reason.
  </action>
  <verify>
    <automated>cd "$WT" && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline && ruby -ryaml -e 'w = YAML.load_file(".github/workflows/release.yml"); abort("triggers") unless w[true].keys == ["push"] && w[true]["push"].keys == ["tags"]; j = w["jobs"]; abort("jobs") unless (%w[build sign publish cask holzcloud-ch] - j.keys).empty?; abort("sign perms") unless j["sign"]["permissions"] == {}; abort("build perms") unless j["build"]["permissions"] == {"contents" => "read"}; abort("cask env") unless j["cask"]["environment"] == "release"; abort("sign env") if j["sign"].key?("environment"); abort("signing secrets outside sign") if (j.keys - ["sign"]).any? { |k| j[k].to_s.include?("secrets.SIGNING_CERTIFICATE") }; abort("signing secrets not in one sign step") unless j["sign"]["steps"].count { |s| s.to_s.include?("secrets.SIGNING_CERTIFICATE") } == 1; puts "release.yml structure ok"' && ! grep -rn 'secrets\.SIGNING_CERTIFICATE' .github/workflows --include='*.yml' | grep -v '^.github/workflows/release.yml:' && ! grep -nE 'preserve-metadata=[^ ]*entitlements' .github/workflows/release.yml && grep -q 'e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95' .github/workflows/release.yml && grep -q 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO' .github/workflows/release.yml && ! grep -q 'is signed ad hoc and users must grant' .github/workflows/release.yml</automated>
  </verify>
  <done>release.yml has jobs build, sign, publish, cask, holzcloud-ch with the permission matrix above; the only trigger is a v* tag push; tests A to E below pass; one commit.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 4: pin every action and police the workflows in CI</name>
  <files>.github/workflows/build.yml, .github/workflows/cask.yml, .github/workflows/lint.yml, .github/scripts/workflow-check.py</files>
  <read_first>.github/scripts/privacy-check.py (style, annotate(), --root handling), all four workflow files after Task 3, .github/actions/select-xcode/action.yml</read_first>
  <behavior>
    - The real tree: exit 0 with a one-line summary.
    - A copy of .github where one action reference is changed to a version tag (for example checkout at v7): exit 1 naming file and line.
    - A pin without the "# vX.Y.Z" comment: exit 1.
    - The SLSA generator referenced by a commit SHA instead of its tag: exit 1; by its tag: accepted.
    - A docker:// reference without @sha256 digest: exit 1.
    - build.yml referencing a signing secret: exit 1; release.yml's cask job referencing the signing secret: exit 1.
    - A workflow without top-level permissions, or with write-all, or with contents: write at top level: exit 1.
    - A job with contents: write that is not in the allowlist: exit 1.
    - A checkout step without persist-credentials: false outside release.yml's cask job: exit 1.
    - A pull_request_target or workflow_run trigger, or "secrets: inherit": exit 1.
  </behavior>
  <action>
    Pin and harden the remaining workflows: in build.yml (jobs build, compat, former-name, no-network, strings, test), cask.yml and lint.yml replace every actions/checkout reference with the pinned one and add `with: persist-credentials: false` (none of them pushes; cask.yml clones the workspace locally, former-name uses git grep); pin upload-artifact (build job) and download-artifact (compat). select-xcode uses no action, nothing to pin.

    Create .github/scripts/workflow-check.py (Python 3 standard library only, executable, same header style as privacy-check.py: what each rule proves, how to run it locally, that it parses line by line and relies on the two-space indentation all workflows use). CLI: optional --root DIR (default: repository root two levels up from the script). Files: .github/workflows/*.yml and *.yaml, .github/actions/*/action.yml and action.yaml, sorted. Track the current job in workflow files: after a column-0 `jobs:` line, a line matching two spaces + job id + colon starts a job; any other column-0 key ends the jobs section. Rules, each violation printed as `::error file=<path>,line=<n>::<message>` and the exit status 1 at the end:
    - pins: every `uses:` value (quotes stripped, trailing comment split off) is local (`./`), or `docker://...@sha256:<64 hex>`, or `owner/repo[/path]@<40 hex>` followed by a comment matching `# v<major>.<minor>.<patch>`; the only tag-pinned exception is `slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v<major>.<minor>.<patch>` (the generator verifies itself by its tag).
    - permissions: each workflow file has a column-0 `permissions:`; inline value `{}` or `read-all`, or a block whose values are only read or none. Inside jobs, a four-space `permissions:` block may contain write only for scopes in WRITE_ALLOWED: (release.yml, publish) contents, id-token, attestations; (release.yml, provenance) contents, id-token; (codeql.yml, swift) and (codeql.yml, actions) security-events; (scorecard.yml, analysis) security-events, id-token. Inline write-all anywhere is a violation.
    - secrets: every `secrets.NAME` occurrence on a non-comment line: GITHUB_TOKEN is allowed anywhere; otherwise (file, job) must allow NAME in SECRETS_ALLOWED: (release.yml, sign) SIGNING_CERTIFICATE_P12 and SIGNING_CERTIFICATE_PASSWORD; (release.yml, cask) CASK_DEPLOY_KEY; (release.yml, holzcloud-ch) CMS_TOKEN. Composite actions may reference none. `secrets: inherit`, and the triggers pull_request_target and workflow_run, are violations.
    - credentials: each step using actions/checkout must contain `persist-credentials: false` within that step (the lines until the next step at the same or lower indentation), except (release.yml, cask), which pushes with the deploy key.
    On success print one line: `==> Workflows: <n> action references pinned, read-only top-level permissions, secrets and write permissions only where allowed`.

    Add job workflows to build.yml (place it after strings, with a comment: actionlint with shellcheck finds broken expressions and scripts before a tag runs release.yml, which cannot run before a tag; workflow-check.py enforces pinned actions, read-only tokens and where secrets may be used; runs locally too): runs-on ubuntu-latest; steps: pinned checkout with persist-credentials false; "Lint the workflows" with uses docker://rhysd/actionlint pinned by digest and `with: args: -color` (comment: the official image with shellcheck, pinned by digest like the SwiftLint image in lint.yml; bumping means updating tag and digest; Dependabot does not update docker:// references); "Pinned actions, read-only tokens, secrets only where they are needed": `python3 .github/scripts/workflow-check.py`.

    Tests (scratchpad, not committed): for each behavior case, `rm -rf "$SCRATCH/wfcheck" && mkdir -p "$SCRATCH/wfcheck" && cp -R "$WT/.github" "$SCRATCH/wfcheck/"`, apply the mutation with sed on the copy, run `python3 "$WT/.github/scripts/workflow-check.py" --root "$SCRATCH/wfcheck"` and check the exit status and message. The SLSA cases run after Task 5 (or against a copy with a hand-written provenance job).
  </action>
  <verify>
    <automated>cd "$WT" && python3 .github/scripts/workflow-check.py && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline && ! grep -rnE 'uses: *[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@v[0-9]' .github/workflows/build.yml .github/workflows/cask.yml .github/workflows/lint.yml</automated>
  </verify>
  <done>All third-party actions in build.yml, cask.yml, lint.yml and release.yml are SHA-pinned with version comments; every checkout outside the cask job has persist-credentials false; workflow-check.py passes on the tree and fails every mutation in the behavior list; build.yml has the workflows job; one commit.</done>
</task>

<task type="auto">
  <name>Task 5: SLSA Build L3 provenance, OpenSSF Scorecard, CodeQL and Dependabot</name>
  <files>.github/workflows/release.yml, .github/workflows/scorecard.yml, .github/workflows/codeql.yml, .github/dependabot.yml</files>
  <read_first>.github/workflows/release.yml after Task 3, .github/actions/select-xcode/action.yml, $SCRATCH/slsa-generic.yml (the generator v2.1.0 inputs, fetched read-only by the planner)</read_first>
  <action>
    <!-- planner-discipline-allow: workflow_dispatch -->
    release.yml: add job provenance (name "SLSA provenance") between publish and cask: needs [build, sign, publish]; permissions actions: read, id-token: write, contents: write (each with a reason: read the run, sign through Sigstore, upload to the release); uses the generator reusable workflow by its tag v2.1.0 with base64-subjects ${{ needs.sign.outputs.hashes }}, provenance-name holzBar-${{ needs.build.outputs.version }}.intoto.jsonl, upload-assets true (upload-tag-name left empty: the run is on the tag). Comment: SLSA Build Level 3 provenance next to GitHub's attestation, verifiable with slsa-verifier --source-uri github.com/holzcloud/holzBar --source-tag v<version>; the generator must be referenced by its version tag, not a SHA (it checks its own ref); the project announced in August 2026 that it is no longer actively maintained, GitHub's attestation in publish is the maintained provenance. It runs after publish so it uploads into the release with the hand-written notes. Change cask to needs [build, sign, publish, provenance] (fail closed: the cask moves only when the release carries both provenances).

    .github/workflows/scorecard.yml: header comment (what Scorecard checks, that results go to scorecard.dev for the README badge and to code scanning, that publish_results restricts the workflow to the approved actions with no run steps, no env and no defaults). name Scorecard; on: push branches [main], schedule weekly (a fixed cron such as "41 5 * * 1"), branch_protection_rule; top-level permissions contents: read; job analysis (name "Scorecard analysis"), runs-on ubuntu-latest, timeout-minutes 15, permissions contents: read, security-events: write (SARIF upload), id-token: write (publish_results); steps only: pinned checkout with persist-credentials false; ossf/scorecard-action pinned with results_file results.sarif, results_format sarif, publish_results true (no repo_token: no new secret; Branch-Protection then scores what the default token can read); upload-artifact pinned (name scorecard-results, path results.sarif, retention-days 5); github/codeql-action/upload-sarif pinned with sarif_file results.sarif.

    .github/workflows/codeql.yml: header comment (weekly and on demand from Actions, never on pull requests: the Swift analysis needs a full macOS build; not a required check). name CodeQL; on: schedule weekly (for example "17 3 * * 1") and workflow_dispatch only; top-level permissions contents: read. Job swift (name "Analyze (swift)"): runs-on xcode-27, timeout-minutes 60, permissions contents: read, security-events: write; steps: pinned checkout with persist-credentials false; uses ./.github/actions/select-xcode (same runner and Xcode as build.yml); github/codeql-action/init pinned with languages swift and build-mode manual; "Build": the CI assertion line from the release build, then `unset TOOLCHAINS`, then `xcodebuild -project holzBar.xcodeproj -scheme holzBar -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build build CODE_SIGNING_ALLOWED=NO` (one architecture, as CodeQL recommends; no signing needed); github/codeql-action/analyze pinned with category /language:swift. The toolchain choice goes into a comment above the Build step: CodeQL 2.27.1 (the bundle of codeql-action v4.38.2) analyzes Swift 5.4 to 6.3.3; holzBar needs Swift 6.4 and the macOS 27 SDK (Xcode 27.0, as in build.yml), and no toolchain CodeQL supports can build it, so this job keeps the runner, Xcode and Swift version of build.yml but compiles with Xcode 27.0's own Swift 6.4 instead of the swift.org build select-xcode installs: CodeQL traces the compiler by injecting a library, which Xcode's compiler allows, while the notarized swift.org compiler runs with the hardened runtime; until a CodeQL bundle supports Swift 6.4 (Dependabot brings it with codeql-action), the analysis may report extraction errors. Job actions (name "Analyze (actions)"): runs-on ubuntu-latest, timeout-minutes 15, same permissions; steps: pinned checkout with persist-credentials false; init with languages actions and build-mode none; analyze with category /language:actions (it reviews the workflows themselves, for example injection and untrusted checkouts).

    .github/dependabot.yml: comment (one grouped pull request per week for every action the workflows and the composite action use; it keeps the SHA pins and their version comments current; the actionlint and SwiftLint images are pinned by digest and bumped by hand). version 2; one update entry: package-ecosystem github-actions, directories "/" and "/.github/actions/*", schedule interval weekly, day monday, time "05:00", timezone Europe/Zurich, groups github-actions with patterns ["*"], commit-message prefix ci.

    Run workflow-check.py (all new jobs are in its allowlists already) and the SLSA cases of the Task 4 tests.
  </action>
  <verify>
    <automated>cd "$WT" && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline && python3 .github/scripts/workflow-check.py && ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }; r = YAML.load_file(".github/workflows/release.yml")["jobs"]; abort("provenance") unless r["provenance"]["uses"] == "slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0" && r["cask"]["needs"].include?("provenance"); s = YAML.load_file(".github/workflows/scorecard.yml"); abort("scorecard steps") unless s["jobs"]["analysis"]["steps"].all? { |st| st.key?("uses") } && !s.key?("env"); c = YAML.load_file(".github/workflows/codeql.yml"); abort("codeql triggers") unless c[true].keys.sort == ["schedule", "workflow_dispatch"]; d = YAML.load_file(".github/dependabot.yml"); abort("dependabot") unless d["updates"][0]["directories"] == ["/", "/.github/actions/*"]; puts "ok"' .github/workflows/scorecard.yml .github/workflows/codeql.yml .github/dependabot.yml .github/actionlint.yaml</automated>
  </verify>
  <done>release.yml attaches holzBar-version.intoto.jsonl before the cask moves; scorecard.yml, codeql.yml and dependabot.yml exist, are pinned and pass actionlint and workflow-check; one commit.</done>
</task>

<task type="auto">
  <name>Task 6: final gates and report</name>
  <files>(none changed; verification only)</files>
  <read_first>this plan's Gates, Tests and doc_updates_needed sections</read_first>
  <action>
    Run G1 to G9 on the final tree, tests A to E, and `git -C "$WT" log --oneline audit/remediation-2026-10-05..HEAD` (six commits, messages as in Commits). Report to the orchestrator: commit list, gate results, the test results, and the doc_updates_needed and repository settings sections of this plan verbatim (they are the orchestrator's input; nothing in docs is edited here).
  </action>
  <verify>
    <automated>cd "$WT" && "$TOOLS/actionlint" -shellcheck="$TOOLS/shellcheck-v0.11.0/shellcheck" -oneline && python3 .github/scripts/workflow-check.py && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/strings-check.py && test -z "$(git status --porcelain -- . ':(exclude).planning/audit/remediation')"</automated>
    <human-check>After merge and settings, the maintainer runs the checklist in "What the maintainer must test by hand".</human-check>
  </verify>
  <done>All gates green, working tree clean, six commits on audit-manual/release, report delivered.</done>
</task>

</tasks>

## Commits (in this order; message format and trailers exactly)

Every message ends with a blank line and:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

1. `ci: make the workflows pass actionlint` — .github/actionlint.yaml, build.yml directives. Body: actionlint 1.7.12 does not know the xcode-27 preview label; the four shellcheck findings are intended (regex in single quotes, folder listings for the log, report lookup); no behavior change; prepares the workflows check.
2. `fix(ci): resolve F-05 — build without get-task-allow and check every build's signature` — Scripts/check-signature.sh, Scripts/install.sh, build.yml. Body: the shipped 0.0.7-beta1 app and its XPC service carry com.apple.security.get-task-allow because Xcode injects it into code signed to run locally; CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO in CI and install.sh; the new script fails any build whose code carries an entitlement or lacks the hardened runtime.
3. `ci: check holzBar.app without the XPC service` — build.yml, privacy-check.py. Body: the XPC service is removed by another chain; identifiers, network scan and compat launch now cover the app and any code inside it; the identifier check asserts the app's identity.
4. `fix(release): resolve F-05, F-10, F-11, F-52 — sign v* tag builds in their own job, fail closed, pin the certificate` — release.yml, build.yml. Body: maintainer chose PR-only main with a deploy key for the cask and kept the signing secrets as repository secrets; release.yml now runs only for v* tags on main; build without token, OIDC or secrets; signing in a job with no permissions and no repository code, failing without the secrets or with another certificate; empty entitlements, leaf certificate and designated requirement checked; cask pushed by the deploy key from environment release; F-10 stays partly open (repository secrets), F-53's tag restriction is in place.
5. `fix(ci): resolve F-10 — pin every action by commit SHA and check the workflows in CI` — build.yml, cask.yml, lint.yml, workflow-check.py. Body: tag-pinned actions could change under the release; every action is pinned with its version, checkouts keep no credentials, and the workflows job (actionlint, workflow-check.py) keeps pins, read-only tokens and the secret allowlist from regressing.
6. `ci: add SLSA provenance, OpenSSF Scorecard, CodeQL and Dependabot` — release.yml, scorecard.yml, codeql.yml, dependabot.yml. Body: maintainer's chosen measures; SLSA generic generator v2.1.0 by tag (unmaintained since 2026-08, see plan), Scorecard with published results, CodeQL for Swift (Xcode's Swift 6.4; CodeQL supports up to 6.3.3) and Actions, Dependabot weekly grouped for actions.

## How each finding's failure scenario is closed

| Finding | Failure scenario (audit) | Closed by | Status |
|---|---|---|---|
| F-05 | A same-user process attaches lldb to holzBar (or its service) and injects a dylib that uses holzBar's Accessibility and Screen Recording | No build injects get-task-allow (CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO in build.yml, release build, install.sh); the release re-signs every code item with an explicit empty entitlements file and never preserves the build's entitlements; check-signature.sh (PR build, release build, install.sh) and the sign job's own check fail on any entitlement, get-task-allow named. Without get-task-allow the hardened runtime refuses the attach. | Closed (CI side) |
| F-10 (a) | A prompt-injected agent or leaked token pushes a branch workflow that exfiltrates the p12 and password | Not closable while the secrets stay repository secrets (maintainer decision). Narrowed: only release.yml's sign job references them, only for refs/tags/v*, with permissions {} and no repository code; workflow-check.py fails any PR that references them elsewhere; pushing a workflow file needs a credential with the workflow scope. Residual risk documented in SECURITY.md. | Partly open (accepted) |
| F-10 (b) | A tag v0.0.8 on an unreviewed commit ships to every brew user; a dispatch from any ref signs and publishes it | The dispatch trigger is gone; the tag ruleset lets only the admin create, move or delete v* tags; the build job refuses a tag whose commit is not on main; main accepts only PRs with green checks. | Closed (with the rulesets) |
| F-10 (c) | Any workflow gets contents: write and force-updates the cask on main | The main ruleset blocks every push but PR merges and the deploy key; the deploy key lives in environment release, which only v* tag runs can use, and only the cask job references it. | Closed (with the ruleset) |
| F-11 | Secrets moved or missing: an ad hoc zip is published and the cask bumped, every user loses Accessibility; a replaced p12 changes holzBar's identity silently | The sign step exits 1 without the secrets; it signs only with the identity whose certificate SHA-256 is e55f0df1...; after signing every code item's leaf certificate and the app's exact designated requirement are checked; any failure stops the run before publish, so nothing is published and the cask stays. | Closed |
| F-52 | A Homebrew SwiftLint (or a compromised tool) runs in the release build with a persisted write token and OIDC and pushes to main, rewrites assets or attests a substitute zip | The build job has contents: read, persist-credentials: false, no id-token, no secrets; write, OIDC and secrets live in jobs that build nothing; the build asserts CI is true so the project's SwiftLint phase (other chain) skips; the zip's SHA-256 is carried and compared job to job and against the published asset. | Closed (CI side; pbxproj by the other chain) |
| F-53 | An attacker attests a trojan zip from a branch workflow and the documented check passes | release.yml only runs for v* tags on main, so genuine attestations carry signer workflow release.yml and source ref refs/tags/v<version>; the docs (orchestrator) switch to --signer-workflow, --source-ref and --deny-self-hosted-runners, plus slsa-verifier --source-tag. A branch run fails the ref constraint. | Closed after the docs update |

## Tests

- Test A (Task 1): check-signature.sh on six fixtures plus the installed 0.0.7-beta1 app, as listed in Task 1's behavior.
- Test B (Task 4 and 5): workflow-check.py on the tree (exit 0) and on mutated copies of .github (each exit 1), as listed in Task 4's behavior.
- Test C (Task 3), the sign job's post-sign check on real data, read-only: extract the "Check the signature" run script of job sign with `ruby -ryaml -e 'puts YAML.load_file(".github/workflows/release.yml")["jobs"]["sign"]["steps"].find { |s| s["name"] == "Check the signature" }["run"]'` into "$SCRATCH/sign-check.sh" and run it with `APP=/Applications/holzBar.app RUNNER_TEMP="$SCRATCH/rt" GITHUB_STEP_SUMMARY="$SCRATCH/summary.md" EXPECTED_CERT_SHA256=e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95 /bin/bash "$SCRATCH/sign-check.sh"` (create "$SCRATCH/rt" first). Expected: exit 1, and the only errors are the get-task-allow ones (app and, while it still exists, the nested service); no certificate or designated-requirement error. Then run it with a wrong EXPECTED_CERT_SHA256 (64 zeros) and expect certificate errors in addition.
- Test D (Task 3), the certificate-to-identity parse, read-only: run the sign step's awk expression against `security find-certificate -a -Z /System/Library/Keychains/SystemRootCertificates.keychain` with the first listed SHA-256 as the wanted value; it must print the SHA-1 printed right after it (the planner saw 018E13F0... -> 17F3DE5E...). With a value that is not in the keychain it must print nothing.
- Test E (Task 3), the cask edit: in "$SCRATCH/casktest", `git init -q`, copy Casks/holzbar.rb, commit, apply the cask job's two sed expressions with VERSION=0.0.7-beta2 and a 64-hex SHA256, and check that `git diff --numstat` is exactly "2<TAB>2<TAB>Casks/holzbar.rb"; apply them again on the result and check the "already up to date" condition the job uses is true. Never push from there.
- The CI checks themselves are the regression tests that run on GitHub: check-signature.sh in build.yml (every PR), the release build check and the sign job's post-sign check (every tag), the workflows job (every PR).

## Threat model

### Trust boundaries

| Boundary | Description |
|---|---|
| Branch push -> Actions secrets | Any credential with the workflow scope can run a workflow that reads repository secrets |
| Build job -> sign job | The ad hoc app crosses jobs as an artifact; the build may have run untrusted build-time tools |
| Release workflow -> main | The cask that every Homebrew user loads is written by CI |
| Release -> user | The signature, its designated requirement and the provenance are what users and macOS TCC trust |
| Third-party actions -> every job | Action code runs with the job's token and secrets |

### STRIDE threat register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|---|---|---|---|---|---|
| T-RSC-01 | Information disclosure | SIGNING_CERTIFICATE_P12 / PASSWORD (repository secrets) | high | accept (maintainer decision 2026-10-05) + partial mitigate | Referenced only in release.yml sign job (permissions {}, no repo code, refs/tags/v* only); workflow-check.py blocks other references in PRs; recommend no workflow scope in agent tokens; residual in SECURITY.md |
| T-RSC-02 | Tampering | Cask push to main | high | mitigate | Ruleset main (PR + required checks, bypass DeployKey only); CASK_DEPLOY_KEY only in environment release (v* tags); cask job checks newest release and asset digest, exact two-line diff, brew style |
| T-RSC-03 | Elevation of privilege | get-task-allow on shipped code | medium | mitigate | INJECT=NO, explicit empty entitlements at re-sign, checks in PR build, release (twice) and install.sh |
| T-RSC-04 | Spoofing | Replaced or missing p12 | medium | mitigate | Fail closed; SHA-256 pin before signing; leaf certificate and exact designated requirement after signing |
| T-RSC-05 | Tampering | Build-time tools (SwiftLint phase, toolchain) during the release build | low | mitigate | Build job read-only, no persisted credentials, no OIDC, no secrets; CI assertion keeps the SwiftLint skip; artifact SHA-256 compared across jobs |
| T-RSC-06 | Spoofing | Attestation from a branch workflow | low | mitigate | Tags-only release workflow on main; constrained verify commands in docs; SLSA --source-tag |
| T-RSC-07 | Tampering | Third-party actions by mutable tag | medium | mitigate | Full SHA pins with version comments; Dependabot grouped weekly; workflows job enforces |
| T-RSC-08 | Tampering | SLSA generator referenced by tag, unmaintained | low | accept | Required by the generator; GitHub attestation stays the maintained provenance; risk noted for the maintainer |
| T-RSC-09 | Denial of service | Provenance, brew style or cask push failure blocks the cask | low | accept | Fail closed by design; rerun failed jobs; workflow defects need a fixed PR and a new beta tag |
| T-RSC-10 | Repudiation | Who pushed the cask commit | low | mitigate | Commit author github-actions[bot], pushed only by the single deploy key, visible in ruleset insights |
| T-RSC-SC | Tampering | npm/pip/cargo installs | low | mitigate | None in this plan; actionlint and shellcheck binaries live only in the scratchpad (checksum-verified), CI uses the actionlint image by digest |

## Risks

macOS 26 and 27:
- TCC continuity depends on an unchanged designated requirement. Removing entitlements changes the cdhash, not the requirement (identifier plus certificate leaf), so Accessibility and Screen Recording stay granted after `brew upgrade` on macOS 26 and 27. The sign job enforces the exact requirement string; the maintainer must still confirm by hand on both systems.
- Without get-task-allow nobody can attach lldb, Instruments or sample to release or install.sh builds without admin rights. That is the intent; developers debug from Xcode (Debug configuration). No holzBar script relies on attaching (checked: no lldb, sample, leaks, vmmap or dtrace use in Scripts/).
- If the XPC-removal chain is merged later than this one, the service is still re-signed (generic nested-code loop) with empty entitlements; its Listener pins the app's cdhashes read at launch, so it keeps working. The build.yml identifier check no longer compares the service's identifier in that window.
- An empty entitlements blob (`<dict/>`) is valid on macOS 14 to 27; the compat matrix keeps launching the app on macOS 14, 15, 26 and 27.
- The xcode-27 image is a public preview; build, sign and CodeQL depend on it (unchanged from today).

CI and release:
- The first v* tag after the merge is the first run of the new release.yml (it cannot run earlier). Use a beta tag. A failure before publish leaves users untouched. A failure after publish leaves a pre-release without cask bump; rerun failed jobs (reruns use the workflow at the tag, so a workflow defect needs a fix PR and a new beta tag, and the maintainer deletes the half-published pre-release by hand).
- slsa-github-generator is no longer actively maintained (README notice 2026-08-07) and its JS actions declare node20, which GitHub removed from runners on 2026-09-23. If the provenance job fails for that reason, the cask does not move (fail closed). The maintainer then decides between waiting for a generator fix and dropping SLSA provenance in favor of the GitHub attestation (the generator's own README recommends that). Surface this to the user; it is a reason to reconsider the choice, not to weaken this plan silently.
- CodeQL Swift: Swift 6.4 is outside CodeQL 2.27.1's range (up to 6.3.3); the weekly swift job may fail or extract partially until a newer bundle arrives. It is not a required check, and the CodeQL badge may be red until then.
- Required check names must match job names exactly (build, test, former-name, no-network, strings, workflows, compat (macos-26), compat (xcode-27)); renaming a job later blocks every PR until the ruleset is updated. swiftlint and cask are path-filtered and must never be required.
- Scorecard: Branch-Protection cannot reach the top tier with one maintainer and a bypass actor; Pinned-Dependencies flags the generator tag and the curl download in select-xcode; Token-Permissions flags the publishing jobs. Accepted.
- brew style in the cask job uses the runner's current Homebrew; a new style rule unrelated to the version line would stop the cask update (fail closed; fix the cask by PR).
- Settings order matters: if the main ruleset lands before this release.yml is on main, a release in between cannot push its cask (the old job pushes with GITHUB_TOKEN).
- Release immutability (a GitHub repository setting) must stay off while the SLSA generator uploads its file after the release is published.
- workflow-check.py parses YAML line by line; a workflow written with other indentation than two spaces would be misread (documented in its header; actionlint still validates the YAML).

## Coordination with other chains

- XPC-removal chain: removes the service and its sources; may also touch privacy-check.py's SOURCE_DIRS (keep its version on conflict). CLAUDE.md "Naming" (XPC identifier) and docs/signing.md "The XPC service" section belong to the docs pass. Merge both before the next release.
- pbxproj chain: makes the SwiftLint phase skip when CI is set (and for Release) and turns on user-script sandboxing. This plan only guarantees that CI keeps CI=true in every xcodebuild job (build.yml, release.yml, codeql.yml). Scripts/install.sh does not set CI on purpose; whether the phase runs for local Release builds is that chain's decision.

## What the maintainer must test by hand (after merge and settings)

1. Push the next beta tag from main (annotated): `git switch main && git pull --ff-only && git tag -a v<next>-beta<N> -m "holzBar <next>-beta<N>" && git push origin v<next>-beta<N>`, after its release-notes PR is merged. Never push a v* tag to test anything: every v* tag on main publishes.
2. Watch the run: jobs Build, Sign with holzBar's certificate, Publish the release, SLSA provenance, Update the Homebrew cask, Show the version on holzcloud.ch are green; the Sign summary shows SHA-256 e55f0df1... and the designated requirement; the release has the zip and holzBar-<version>.intoto.jsonl; main has the commit "holzbar <version>" by github-actions[bot].
3. On a Mac with macOS 26 and on one with macOS 27: `brew update && brew upgrade --cask holzbar`; holzBar starts, keeps Accessibility and Screen Recording without a prompt, hides and shows items as before.
4. `codesign -d --entitlements - --xml /Applications/holzBar.app` prints nothing or an empty dict; `codesign -d -r- /Applications/holzBar.app` still shows `certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"`. Optional: `lldb -p "$(pgrep -x holzBar)"` is refused without admin approval.
5. Verify the download with the new commands (doc_updates_needed): gh attestation verify with --signer-workflow, --source-ref and --deny-self-hosted-runners, and slsa-verifier with --source-uri and --source-tag; both pass.
6. A direct push to main from a local clone is rejected; a PR merges only after the required checks are green.
7. Actions -> CodeQL -> Run workflow once; check both jobs (swift may report extraction problems until CodeQL supports Swift 6.4). Check that Scorecard ran on main and the badge shows a score. Check that Dependabot lists the github-actions configuration and that its first grouped PR runs CI.
8. On a Mac with Xcode 27: `Scripts/install.sh` builds, passes check-signature.sh and installs; `codesign -d --entitlements - --xml ~/Applications/holzBar.app` shows no get-task-allow.

## doc_updates_needed (for the orchestrator; nothing here is edited by the executor)

### README.md

- Badges (top, with the existing ones):

```markdown
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/holzcloud/holzBar/badge)](https://scorecard.dev/viewer/?uri=github.com/holzcloud/holzBar)
[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](https://slsa.dev)
[![CodeQL](https://github.com/holzcloud/holzBar/actions/workflows/codeql.yml/badge.svg)](https://github.com/holzcloud/holzBar/actions/workflows/codeql.yml)
```

  Add the CodeQL badge only after its first green run (Swift 6.4 support), or it shows failing.
- Line 81: "carries a build provenance attestation" -> "carries a build provenance attestation and SLSA Build Level 3 provenance" (from the first release built by the new workflow), keep the fingerprint and the link to docs/signing.md.
- Comparison table and docs/comparison.md line 86: extend "Build provenance attestation" with SLSA Build Level 3 provenance; add rows only for what is true after the first green release (actions pinned by commit SHA with Dependabot; OpenSSF Scorecard; no entitlements, not even get-task-allow). Do not claim a CodeQL Swift analysis until it runs green.

### Verification commands (docs/signing.md "For users: verify a download", README, every release note's install section) — F-53

```sh
# GitHub's attestation: built by release.yml from the tag, on a GitHub-hosted runner
gh attestation verify holzBar-<version>.zip -R holzcloud/holzBar \
  --signer-workflow holzcloud/holzBar/.github/workflows/release.yml \
  --source-ref refs/tags/v<version> \
  --deny-self-hosted-runners

# The zip Homebrew downloaded
V=$(brew list --cask --versions holzbar | awk '{print $2}')
gh attestation verify "$(brew --cache --cask holzbar)" -R holzcloud/holzBar \
  --signer-workflow holzcloud/holzBar/.github/workflows/release.yml \
  --source-ref "refs/tags/v$V" \
  --deny-self-hosted-runners

# SLSA provenance (brew install slsa-verifier, v2.7.1 or newer)
gh release download v<version> -R holzcloud/holzBar -p 'holzBar-<version>.zip' -p 'holzBar-<version>.intoto.jsonl'
slsa-verifier verify-artifact holzBar-<version>.zip \
  --provenance-path holzBar-<version>.intoto.jsonl \
  --source-uri github.com/holzcloud/holzBar \
  --source-tag v<version>
```

- Older releases: 0.0.6-beta1, 0.0.6-beta2 and 0.0.6 were built by a manual run on main, so use `--source-ref refs/heads/main` for them (checked for v0.0.6); 0.0.7-beta1 was a tag push (`--source-ref refs/tags/v0.0.7-beta1`). No release before the new workflow has SLSA provenance; releases up to 0.0.5 have no attestation.
- docs/release-notes/v0.0.6.md line 76 (F-53 fix item 2): "proves that a zip was built by this repository's release workflow" -> "proves that a zip was built by `.github/workflows/release.yml` in this repository, when you pin the workflow and the ref as in docs/signing.md". Line 118 gets the constrained command with `--source-ref refs/heads/main`.

### docs/signing.md

- Line 10: keep "holzBar still has no entitlements", add that CI, the release and Scripts/install.sh fail when any code in the app carries one, and that releases up to 0.0.7-beta1 carried `com.apple.security.get-task-allow` (fixed from the next release).
- Line 12: replace with: without the two repository secrets, or with a certificate whose SHA-256 is not e55f0df1..., the release workflow fails; it never publishes an ad hoc build.
- Line 61: the trial signing command signs only the app (the XPC service is gone; coordinate with the XPC chain) and add `--entitlements` with an empty plist, so a local test matches the release.
- Lines 63-85: the secrets stay repository secrets. Replace "Better still, move the two secrets into a GitHub environment" with the maintainer's decision and its residual risk (see SECURITY.md T-06-L7), and the rule to keep the workflow scope out of agent and automation tokens.
- Line 87 "How the workflow uses them": describe the jobs: Build (ad hoc, no token permissions beyond read, no secrets), Sign (only job with the secrets, no repository code, pins the certificate, empty entitlements, checks leaf certificate and designated requirement, deletes the keychain), Publish (attestation, release), SLSA provenance, Update the Homebrew cask (deploy key in environment release).
- New section "For the maintainer: release": merge the release-notes PR, push an annotated tag `v<version>` on main; there is no Run workflow button any more; never create the release or the tag in the GitHub web UI first; never push a v* tag for a test; the cask is updated by the workflow's deploy key; a failed run is re-run from the Actions tab, a workflow defect needs a fix PR and a new tag.
- Lines 97-99 "The XPC service": remove with the XPC chain.
- Lines 113-127: the commands above as the default, and the older-release note.

### SECURITY.md

- "What holzBar promises": Least privilege -> "No entitlements, not even get-task-allow (CI and the release fail on any), and the hardened runtime." (drop "and its XPC service" with the XPC chain). Releases -> add "and SLSA Build Level 3 provenance" and "verify them against the release workflow and the tag (docs/signing.md)".
- T-06-L6 Status -> **Mitigated** (2026-10-05 audit F-52, F-10): the release runs in separate jobs; the build job has a read-only token without persisted credentials, no secrets and no OIDC token, and CI keeps the project's SwiftLint phase skipped; the signing job holds only the certificate, has no token permissions and runs no repository code; attestation, SLSA provenance and the release need no secret; every third-party action is pinned by commit SHA (Dependabot keeps them current) and CI lints the workflows; the signed zip's SHA-256 is compared from job to job and with the published asset before the cask changes.
- T-06-L7 Status -> **Partly mitigated** (F-10): main accepts only pull requests with green checks; only the release workflow's deploy key, kept in environment `release` that only v* tag runs can use, may push the cask commit; only the admin may create, move or delete v* tags; a release only builds a tag whose commit is on main. **Residual risk, accepted by the maintainer on 2026-10-05:** the signing certificate and its password stay repository secrets, so a workflow file pushed to any branch by a credential with the workflow scope can read them, and the key cannot be revoked (docs/signing.md). Keep the workflow scope out of agent and automation tokens.
- New rows (audit 2026-10-05): get-task-allow lets a debugger inject code with holzBar's grants (Medium, Mitigate, **Mitigated**: no build carries entitlements; CI, release and install.sh fail on any); missing or replaced signing secrets publish an ad hoc or differently signed release (Medium, Mitigate, **Mitigated**: release fails without the secrets, on another certificate, or on a different designated requirement); the documented attestation check accepts any workflow on any ref (Low, Mitigate, **Mitigated** by the constrained commands and the tags-only workflow).

### CLAUDE.md

- Releases: releases start with an annotated tag push on main after the release-notes PR is merged; never create a release or tag in the web UI; never push a v* tag to test; main takes only pull requests with green checks (list the required checks); the release workflow pushes the cask with its deploy key.
- Layout: release.yml (jobs build, sign, publish, provenance, cask, holzcloud-ch; v* tags only); codeql.yml, scorecard.yml, dependabot.yml, actionlint.yaml, .github/scripts/workflow-check.py, Scripts/check-signature.sh; build.yml gains the workflows job.
- Dependencies: actions are pinned by full commit SHA with a `# vX.Y.Z` comment (Dependabot keeps them current, one grouped PR per week); the SLSA generator is referenced by tag; the actionlint and SwiftLint images are pinned by digest and bumped by hand.
- Building: Scripts/install.sh builds without get-task-allow and runs Scripts/check-signature.sh before installing.

### Next release notes

- Changed: holzBar no longer carries get-task-allow (no debugger can attach without admin approval); releases carry SLSA Build Level 3 provenance; verification commands as above; nothing changes for permissions (same certificate and designated requirement).

## Repository settings for the orchestrator (after merge; read-only checks first)

Nothing has to be re-entered: SIGNING_CERTIFICATE_P12 and SIGNING_CERTIFICATE_PASSWORD stay repository secrets (do NOT delete them); environment `release` and CASK_DEPLOY_KEY already exist.

0. Check (read-only): `gh api repos/holzcloud/holzBar/environments/release/deployment-branch-policies --jq '.branch_policies[] | {name, type}'` shows only `{"name":"v*","type":"tag"}`; `gh api repos/holzcloud/holzBar/environments/release/secrets --jq '.secrets[].name'` shows only CASK_DEPLOY_KEY; `gh api repos/holzcloud/holzBar/keys --jq '.[] | {title, read_only}'` shows exactly one key with read_only false (a DeployKey bypass covers every deploy key, so never add a second write key); `gh secret list -R holzcloud/holzBar` shows the two signing secrets; `gh api repos/holzcloud/holzBar/code-scanning/default-setup --jq .state` is not-configured (codeql.yml is an advanced setup).
1. Merge the workflow PR (one PR with the other chains, per CLAUDE.md) before any ruleset on main.
2. Ruleset `main` (keep ruleset 24305254): `gh api -X POST repos/holzcloud/holzBar/rulesets --input main-ruleset.json` with

```json
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": null, "actor_type": "DeployKey", "bypass_mode": "always" } ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "build", "integration_id": 15368 },
          { "context": "test", "integration_id": 15368 },
          { "context": "former-name", "integration_id": 15368 },
          { "context": "no-network", "integration_id": 15368 },
          { "context": "strings", "integration_id": 15368 },
          { "context": "workflows", "integration_id": 15368 },
          { "context": "compat (macos-26)", "integration_id": 15368 },
          { "context": "compat (xcode-27)", "integration_id": 15368 } ] } }
  ]
}
```

   No admin bypass (the maintainer can disable the ruleset in an emergency). Never require swiftlint or cask (path-filtered) or the CodeQL and Scorecard jobs; compat (macos-14) and compat (macos-15) stay optional. If the API rejects DeployKey on this user-owned repository, fall back to a GitHub App as Integration bypass (the user must create the app) and change the cask job to push with that app's token.
3. Ruleset `release tags`: `gh api -X POST repos/holzcloud/holzBar/rulesets --input tag-ruleset.json` with

```json
{
  "name": "release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ],
  "rules": [ { "type": "creation" }, { "type": "update" }, { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
```

4. Optional: `gh api -X PATCH repos/holzcloud/holzBar -F allow_auto_merge=true` (web-editor commits now become PRs; auto-merge waits for the checks).
5. Verify with the next beta tag (maintainer checklist above).
6. Optional, after the first green release, with one test PR and the next tag: Actions permissions "selected" with GitHub-owned actions allowed and patterns `ossf/scorecard-action@*`, `slsa-framework/*` and `softprops/action-gh-release@*` (used inside the generator, with actions/upload-artifact); keep sha_pinning_required off (the generator calls its own actions by tag). Check that the workflows job's docker:// actionlint step still runs.
7. Do not enable release immutability while the SLSA generator uploads after publishing. If CMS_TOKEN is ever set, put it into its own v*-only environment (for example `cms`) instead of a repository secret, and add that environment to the holzcloud-ch job.
8. Optional hardening from the decision (test the merge UX first): a second ruleset on main with the `update` rule, bypassed only by RepositoryRole 5 and DeployKey, so that GITHUB_TOKEN of other workflows cannot merge green PRs.

<verification>
G1 to G9 green on the final tree; tests A to E pass; `git -C "$WT" log --oneline audit/remediation-2026-10-05..HEAD` shows the six commits in order; `git -C "$WT" status --porcelain -- . ':(exclude).planning/audit/remediation'` is empty.
</verification>

<success_criteria>
- Every must_haves truth holds on the final tree, as proven by the Task verify commands and tests.
- F-05, F-11, F-52 (CI side) and F-53 (code side) are closed; F-10 is closed except the accepted residual risk of repository-level signing secrets, which is documented for SECURITY.md.
- No app code, no project.pbxproj and no documentation file was changed; the doc updates and repository settings are reported to the orchestrator.
</success_criteria>

<output>
Report to the orchestrator: the six commit hashes and subjects, gate and test results, and the "doc_updates_needed" and "Repository settings" sections of this plan.
</output>
