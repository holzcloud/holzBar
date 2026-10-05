---
phase: audit-remediation-release
plan: release-supply-chain
subsystem: ci-release
tags: [supply-chain, signing, github-actions, slsa, scorecard, codeql, dependabot]
requirements: [F-05, F-10, F-11, F-52, F-53]
status: complete
key-files:
  created:
    - Scripts/check-signature.sh
    - .github/actionlint.yaml
    - .github/scripts/workflow-check.py
    - .github/workflows/scorecard.yml
    - .github/workflows/codeql.yml
    - .github/dependabot.yml
  modified:
    - .github/workflows/release.yml
    - .github/workflows/build.yml
    - .github/workflows/cask.yml
    - .github/workflows/lint.yml
    - .github/scripts/privacy-check.py
    - Scripts/install.sh
decisions:
  - "PR-only main with a write deploy key (CASK_DEPLOY_KEY in environment release) for the cask push"
  - "Signing secrets stay repository secrets (maintainer, 2026-10-05): F-10 stays partly open, residual risk goes into SECURITY.md"
  - "release.yml runs only on v* tag pushes; the manual trigger is removed, not turned into a dry run (build.yml already builds every PR identically)"
  - "SLSA generic generator v2.1.0 referenced by tag; cask moves only after provenance succeeded"
  - "CodeQL Swift compiles with Xcode 27.0's own Swift 6.4 (CodeQL 2.27.1 supports up to 6.3.3)"
commits: 6
---

# Release supply chain: F-05, F-10, F-11, F-52, F-53 Summary

holzBar's CI, release and local install pipeline: no build carries get-task-allow anymore, and every build checks that. A release runs only from a v* tag on main. It is split into least-privilege jobs, and only the sign job sees the signing secrets. That job fails closed and pins the certificate. The cask is pushed only with a deploy key. On top come SHA-pinned actions with a CI policy check, SLSA L3 provenance, Scorecard, CodeQL and Dependabot.

## The decision implemented

- Maintainer's choice (decision release-1): **PR-Pflicht plus Deploy Key**.
- The maintainer then asked to solve signing differently ("Können wir das mit dem signieren nicht doch anders lösen?") and decided that `SIGNING_CERTIFICATE_P12` and `SIGNING_CERTIFICATE_PASSWORD` **stay repository secrets**. They are not moved into an environment, and nobody has to re-enter anything. Environment `release` (tags `v*` only) already exists and holds only `CASK_DEPLOY_KEY`. Only the cask job uses it.

## Commits (branch audit-manual/release)

| # | Hash | Subject |
|---|------|---------|
| 1 | 092a1a3d | fix(ci): resolve F-10 — make the workflows pass actionlint |
| 2 | de59fe70 | fix(ci): resolve F-05 — build without get-task-allow and check every build's signature |
| 3 | 5b2e1db2 | fix(ci): resolve F-05 — check holzBar.app and all its code without the removed XPC service |
| 4 | f2117f4a | fix(release): resolve F-05, F-10, F-11, F-52, F-53 — sign v* tag builds in their own job, fail closed, pin the certificate |
| 5 | 613ef3dd | fix(ci): resolve F-10 — pin every action by commit SHA and check the workflows in CI |
| 6 | (this commit) | fix(ci): resolve F-10, F-53 — add SLSA provenance, OpenSSF Scorecard, CodeQL and Dependabot (also carries this summary) |

## Per finding

| Finding | What was done | Status |
|---|---|---|
| F-05 | `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` in build.yml, the release build and Scripts/install.sh. New `Scripts/check-signature.sh`: valid signature, hardened runtime on every bundle, and no entitlement on any code (get-task-allow is named). build.yml, the release build job and install.sh call it. The sign job re-signs every item with an explicit empty entitlements file and `--preserve-metadata=identifier,flags,runtime` (it no longer preserves entitlements). Its post-sign check rejects get-task-allow and any other key. | Closed (CI side) |
| F-10 | Tag-only trigger. The build refuses tags whose commit is not on main and refuses forks. Signing secrets appear only in the sign job (`permissions: {}`, no checkout, refs/tags/v* only). The cask is pushed only by the cask job over SSH with `CASK_DEPLOY_KEY` from environment `release`. Every action is pinned by SHA. The new `workflows` job (actionlint plus workflow-check.py) enforces pins, read-only top-level permissions and allowlists for secrets, write scopes and kept credentials. | Partly open (accepted: repository-level signing secrets) |
| F-11 | The sign step exits 1 without the secrets, so there is no ad hoc branch anymore. It signs only with the identity whose certificate SHA-256 is e55f0df1… and fails when the p12 lacks that certificate or its key. The post-sign check verifies every item's leaf certificate and the exact designated requirement `identifier "com.holzcloud.holzBar" and certificate leaf = H"<sha1 of leaf>"`. | Closed |
| F-52 | The build job has `contents: read`, `persist-credentials: false`, no id-token and no secrets. Write, OIDC and secrets live in jobs that build nothing. The release build, build.yml and codeql.yml assert `CI=true`, so the project's SwiftLint phase (pbxproj chain) stays skipped. The zip's SHA-256 is carried from job to job and compared with the published asset. | Closed (CI side) |
| F-53 | Only v* tags on main run release.yml, so genuine attestations name release.yml and refs/tags/v<version>. The constrained verify commands are in doc_updates_needed. SLSA provenance is verifiable with `--source-tag`. | Closed after the docs update |

## Deviations from Plan

1. **[Rule 2] Stricter secret scan in workflow-check.py.** The plan scanned `secrets.NAME` on non-comment lines. Actions expands `${{ }}` even inside shell comments of a run script, so the script instead scans every `${{ … }}` expression on every line. It also rejects dynamic access (`secrets[...]`, `toJSON(secrets)`). This avoids false positives from prose and closes the comment loophole. Tested.
2. **[Rule 1] SLSA generator by SHA.** The planned rule accepted a SHA-pinned generator with a version comment, but the plan's own behavior list demands exit 1. Commit 6 adds an explicit rule for that.
3. **Commit messages** follow the orchestrator's required `fix(<scope>): resolve <IDs> — …` format, not the plan's `ci:` subjects. Commit 1 (actionlint baseline) is filed under F-10, because it is the prerequisite of the workflows check. Commit 3 (no XPC references) is filed under F-05, because the signature and network checks now cover every piece of code generically.
4. **Small additions:** a workflow-level `concurrency` group per tag; timeouts on the holzcloud-ch job; the post-sign check also reports items without a certificate; check-signature.sh labels non-bundle items "signed" instead of "hardened runtime".
5. The plan said the sign check prints `::error::` for each failure: done. The success summary also counts the pieces of code.

## Gates (final tree)

- G1 actionlint 1.7.12 with shellcheck 0.11.0: clean (exit 0).
- G2 YAML parse (ruby): all 6 workflows, dependabot.yml, actionlint.yaml and action.yml OK.
- G3 `/bin/bash -n` and shellcheck on Scripts/check-signature.sh and Scripts/install.sh: clean. No zsh script was changed.
- G4 Python AST parse of .github/scripts/*.py: OK, no `__pycache__` left behind.
- G5 privacy-check network and logs: pass.
- G6 strings-check: pass (369 strings in 5 languages; no strings added).
- G7 former-name check (tracked and untracked, file names): no match.
- G8 workflow-check.py: `37 action references pinned …`, exit 0.
- G9 hygiene: the working tree is clean apart from the untracked plan file.

## Tests

- **Test A** (check-signature.sh, fixtures built with clang and ad hoc codesign). All passed:
  - good app: exit 0
  - get-task-allow: exit 1, named
  - no hardened runtime: exit 1
  - nested XPC bundle with get-task-allow: exit 1, the nested item is named
  - disable-library-validation: exit 1, the key is listed
  - unsigned: exit 1
  - re-signed with an empty entitlements plist plus `--preserve-metadata=identifier,flags,runtime`: get-task-allow is gone, exit 0
  - installed `/Applications/holzBar.app` 0.0.7-beta1 (read-only): exit 1, get-task-allow on the app and on MenuBarItemService.xpc
- **Test B** (workflow-check.py on mutated copies). All passed:
  - every case in the plan's behavior list gives exit 1 with file and line
  - extra cases also give exit 1: a secret inside a run-script comment, `toJSON(secrets)`, a secret in the composite action, a named checkout step without persist-credentials
  - a named checkout step with persist-credentials passes
  - the generator by tag passes; by SHA, or by `@v2`, fails
- **Test C** (the sign job's post-sign check, run on the installed app). Passed:
  - with the correct pin: only the two get-task-allow errors; leaf certificate and designated requirement pass
  - with a pin of 64 zeros: certificate errors in addition
  - on an ad hoc fixture: "still signed ad hoc" and "no certificate"
- **Test D** (awk certificate-to-SHA-1 parse on SystemRootCertificates): prints 17F3DE5E… for 018E13F0…, and nothing for an unknown value. Passed.
- **Test E** (cask edit in a scratch git repo): numstat is exactly `2\t2\tCasks/holzbar.rb`, and the second pass detects "already up to date". Passed.
- **gh checks** (read-only): the `env.ZIP` jq filter returns the v0.0.7-beta1 asset digest, which equals the cask's sha256. `gh release list --exclude-drafts --limit 1` returns v0.0.7-beta1.
- **build.yml steps** "Check the identifiers" and "Check the binaries for network code", run on a copy of the installed app: pass (2 executables scanned).

## Risks to raise with the maintainer

- **slsa-github-generator is no longer actively maintained.** Its README has said so since 2026-08-07, and its JS actions declare node20, which GitHub removed from runners on 2026-09-23. A generator failure holds back the cask, because the cask is fail-closed behind provenance. Consider dropping SLSA in favor of GitHub's attestation (the generator's README recommends that).
- **CodeQL cannot fully analyze Swift 6.4 yet** (CodeQL 2.27.1 supports up to 6.3.3). The weekly swift job may report extraction errors. It is not a required check.
- **The first v* tag after merge is the first real run of the new release.yml.** Use a beta tag.

## Self-Check: PASSED

All created files exist. Commits 092a1a3d, de59fe70, 5b2e1db2, f2117f4a and 613ef3dd are ancestors of HEAD.
