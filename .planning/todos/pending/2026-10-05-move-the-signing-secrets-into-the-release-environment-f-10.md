---
created: 2026-10-05T16:00:30.418Z
title: Move the signing secrets into the release environment (F-10)
area: release
severity: major
files:
  - .github/workflows/release.yml
  - SECURITY.md
  - docs/signing.md
  - .planning/audit/FULL-AUDIT-2026-10-05.md (F-10)
---

## Problem

Audit finding F-10 (2026-10-05) is only partly fixed. The signing secrets `SIGNING_CERTIFICATE_P12` (the base64 `.p12`) and `SIGNING_CERTIFICATE_PASSWORD` are still repository-level secrets, so a workflow pushed to any branch can read the signing key. The fix is to move them into the GitHub environment `release`.

The maintainer deferred this to the beta after 0.0.7-beta2. They need access to `holzbar-signing.p12` and its password again first, because GitHub secrets cannot be read back or moved, only re-entered.

Current state:
- The environment `release` exists, and its deployment policy allows only `v*` tags.
- It already holds `CASK_DEPLOY_KEY`, the write deploy key the cask job uses to push to the protected `main`.
- The release workflow signs with the repository-level secrets, fails closed when they are missing, and pins the certificate's SHA-256 fingerprint (`e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`).

## Solution

1. The maintainer re-enters both secrets into the environment:
   - `base64 -i holzbar-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 --env release -R holzcloud/holzBar`
   - `pbpaste | gh secret set SIGNING_CERTIFICATE_PASSWORD --env release -R holzcloud/holzBar`, with the password copied from the password manager.
2. In `.github/workflows/release.yml`, the signing job gets `environment: release`.
3. Run one beta release. After it succeeds, delete the repository-level secrets (`gh secret delete SIGNING_CERTIFICATE_P12` and `gh secret delete SIGNING_CERTIFICATE_PASSWORD`).
4. Remove the residual-risk note for F-10 from `SECURITY.md` and `docs/signing.md`, and mark F-10 fixed in the audit follow-up.
