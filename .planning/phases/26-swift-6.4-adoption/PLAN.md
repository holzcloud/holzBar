---
phase: 26-swift-6.4-adoption
status: planned (behaviour-neutral cleanup; CI is the verifier; run /gsd-plan-phase 26)
requirements: [SWIFT-01, SWIFT-02, SWIFT-03]
depends_on: Phases 8 to 25 (so the sweep covers the new code and one CI run verifies everything); the pinned toolchain is Swift 6.4.0 already (`.github/actions/select-xcode/action.yml`)
---

# Phase 26: Swift 6.4 adoption

## Goal

Use what Swift 6.4.0 really offers where it makes the code simpler, remove workarounds the 6.4 toolchain no longer needs, and change no behaviour.

## What is in Swift 6.4.0 (verified) and what is not

Verified from swift.org's release announcement (swift.org/blog/swift-6.4-released, read 2026-10-04) and the InfoQ report of 2026-09:

- `defer` can contain `await`: SE-0493, "any asynchronous code you write in a defer block is awaited and runs to completion before it exits" (swift.org).
- `@diagnose` source-level warning control (SE-0522); module selectors `Module::name` (SE-0491); `some P?` without parentheses (SE-0521); `withTaskCancellationShield` (SE-0504); non-copyable and `Iterable` additions (SE-0516, 0519, 0527, 0532); `Observable` fine-grained tracking changes (SE-0506); Subprocess 1.0 (a package, not used: holzBar has no dependencies); Swift Build the default in SwiftPM; SBOM generation (SE-0509).
- **`anyAppleOS` availability**: reported by InfoQ, mjtsai.com and the ecorpit article as a Swift 6.4 language change ("a single shorthand replaces all five platform names in an `@available` attribute or `#if` condition"), but the swift.org release summary I fetched did **not** list it, and I found no proposal number. **Unverified for 6.4.0**: the plan's first task checks the Swift Evolution proposal's "Implemented in" field and compiles a one-line test with the pinned toolchain; if it is not in 6.4.0 the item is dropped.
- **"Faster Foundation URL parsing"**: not found in any source I read (swift.org, InfoQ, the ecorpit article, the Xcode 27.2 release notes). **Unverified, probably an SDK/Foundation library change and not a language feature**; no code change is planned for it; if a measured benefit exists, it arrives for free with the SDK.
- The Xcode 27.2 release notes (beta 2, developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes) say only "Xcode 27.2 beta 2 includes Swift 6.4"; they list no Swift language features. They do list the JSON project format `.xcproj` (not selected, see the backlog).
- The language mode stays `SWIFT_VERSION = 6.2` (CLAUDE.md: Swift 6.4 offers no newer mode).

## Tasks

1. **SWIFT-01 Availability sweep**: holzBar has 81 `#available` uses. Review each: where a check collapses to a plain `if #available(macOS 26, *)` there is nothing to simplify; `anyAppleOS` helps only where several platform names are spelled out (the target is macOS only, so likely **very few or none**: record the finding; do not change code for its own sake). Where the deployment target (macOS 14) already makes a check always true, remove it. Replace `defer { Task { await ... } }` patterns with `defer { await ... }` where such code exists (SE-0493).
2. **SWIFT-02 Workarounds**: re-test the one known Swift 6.3.3 workaround: `ObservationLoop.swift` `LastValue` is non-generic with `Any` and a cast because "the Release optimizer of Swift 6.3.3 crashes on the deinitializer of a generic main-actor class" (commit dd67acf). With Swift 6.4.0: restore the generic `LastValue<Value>` in a branch and let CI build **Release/`-Osize`** (the configuration that crashed); keep the simplification only if the CI release build is green and the tests pass; otherwise keep the workaround and update its comment to say it was re-tested on 6.4.0. Search for other workaround comments (`grep -rn "optimizer\|6.3\|workaround" holzBar`) and `SWIFT_OPTIMIZATION_LEVEL` overrides in the project file; handle each the same way. Also review the README/CLAUDE.md remarks that refer to 6.3.
3. **SWIFT-03 Adopt only what simplifies**: `@diagnose` is not needed unless a warning has to be silenced locally (prefer fixing); module selectors only if a name clash exists; `Subprocess` is **not adopted** (dependency, and `Process` is used once). Everything else stays.
4. **Verification**: behaviour-neutral by rule: no setting, string, UI or logic change. CI is the verifier: build (Xcode 27.0 with Swift 6.4.0, Release and Debug), `swift test`, SwiftLint `--strict`, the compat launch on macOS 14, 15, 26, 27. One commit per kind of change so a failure reverts alone.

## Privacy and permission analysis

None; no runtime change.

## Plans (outline)

1. **26-01 Verify the toolchain claims**: Evolution proposals and a compile test for `anyAppleOS` and `await` in `defer`; write the findings (what 6.4.0 really has) into `26-01-NOTES.md`.
2. **26-02 Workaround re-test**: `LastValue` generic version through a CI Release build; other workaround sites.
3. **26-03 Sweep**: availability and `defer` where it simplifies; update comments and `CLAUDE.md` if its Swift section changes (the 6.3 crash note, if any).

## Risks

- Another optimizer crash appears only in the Release configuration, which only the macOS CI runner builds: expect one extra CI round; this is why the phase is last before the release and runs as one push.
- Removing a workaround that is still needed on the older Xcode used by the compat legs (macOS 14, 15, 26 compile with the runner's Xcode and the pinned toolchain): they must be green too.
- Churn for no gain: the rule "do not change code just to use a new spelling".

## Open design question

35. **When does the Swift 6.4 cleanup run?** A. After all feature phases and before the release, so the sweep sees all new code and one CI run verifies it (**recommended**); B. At the start of the milestone, so new code is written in the new style from day one; C. Split: the availability and `defer` sweep now (cheap), the workaround re-test at the end.
