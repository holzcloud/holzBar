#!/usr/bin/env python3
#
# sync-mutation-gate.py
#
# The mutation gate of the settings sync engine (analysis section 5.7, requirement R-TEST-5, decision D-11).
#
# A test suite that never fails proves nothing, so this gate breaks the engine on purpose: each mutation below removes or
# weakens one guard of holzBar/Core/Sync (an exact text found exactly once in its file), and the sync tests have to fail.
# A mutation that no test notices means a test is missing or too weak; a mutation whose text is gone or no longer unique
# means the table went stale, and both fail the gate.
#
#   python3 Scripts/sync-mutation-gate.py             # baseline, then every mutation
#   python3 Scripts/sync-mutation-gate.py --list      # the mutations, one per line, and nothing else
#   python3 Scripts/sync-mutation-gate.py --only NAME # one mutation, or several separated by commas (after the baseline)
#
# The repository itself is never patched: the sources the Swift package needs are copied into a temporary directory, and
# every mutation is applied there, tested and undone. Exit status: 0 when the baseline passes, every text is unique and every
# mutation is killed; 1 when the baseline fails or a mutation survives; 2 when a mutation is stale. The tests run with
# `swift test`; SYNC_SWIFT_TEST_FLAGS adds flags (for example -Xswiftc -plugin-path ... on a Mac without Xcode).
# Python standard library only.

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYNC = "holzBar/Core/Sync"
TESTS = "Tests/HolzBarCoreTests/Sync"
COPIED = [
    "Package.swift",
    "holzBar/Core",
    "holzBar/MenuBar/MacOS27/Core",
    "Shared/CodeSigning",
    "Tests/HolzBarCoreTests",
    "Tests/HolzBarMacOS27CoreTests",
    "Tests/SharedCodeSigningTests",
    # UnitTableTests compares the unit table with this checked-in list (found from the test file's path, so the copy needs it):
    # without it that test fails in every copy and "kills" every mutation.
    ".github/sync-synced-keys.txt",
]

# (name, file under holzBar/Core/Sync, text found exactly once, its replacement, the guard it breaks)
MUTATIONS = [
    ("applied-filter-removed", "SyncCapture.swift",
     "} else if environment.guards.contains(.appliedContext) {",
     "} else if false {",
     "a change supersedes only the dots this Mac applied; without it a change replaces an entry its user never saw"),
    ("covers-strict", "SyncDot.swift",
     "self[dot.mac] >= dot.n",
     "self[dot.mac] > dot.n",
     "a context covers the dot at its own counter"),
    ("reuse-check-skipped", "SyncMerge.swift",
     "if !reused.isEmpty {",
     "if false && !reused.isEmpty {",
     "a dot minted twice by two installations of one identity is found, and the Mac re-identifies"),
    ("generation-check-skipped", "SyncLaunch.swift",
     "        case .rolledBack:\n            return .untrusted",
     "        case .rolledBack:\n            return .trusted",
     "rolled-back preferences are no evidence at launch"),
    ("tripwire-check-skipped", "SyncLaunch.swift",
     "guard hasState, tripwireMatches, !identityChangedWithDifferences else {",
     "guard hasState, !identityChangedWithDifferences else {",
     "a write of the old sync build to the defaults makes the state untrusted"),
    ("refused-file-as-missing", "SyncMerge.swift",
     "            if file.macID == state.mac {\n                result.ownOutcome = file.state\n            }",
     "            if file.macID == state.mac, case .contents = file.state {\n                result.ownOutcome = file.state\n            }",
     "an own file that cannot be read is not an absent file, and is never written over"),
    ("passthrough-dropped", "SyncDeviceFile.swift",
     "extra: top.filter { !knownKeys.contains($0.key) }",
     "extra: [:]",
     "fields of a newer build are carried through a read and a write"),
    ("local-only-applied", "SyncPlan.swift",
     "} else if state.localOnly[key] != nil {\n                outcomes[key] = .protectedLocalOnly",
     "} else if false {\n                outcomes[key] = .protectedLocalOnly",
     "a value this Mac keeps (unusable, too large) is never replaced by the group's"),
    ("clash-check-skipped", "SyncPlan.swift",
     "let clashes = clashes(fastForwards: payloads, snapshot: snapshot)",
     "let clashes: [SyncClash] = []",
     "two hotkeys that would share a combination are asked about, never applied"),
    ("join-with-unread-files", "SyncJoin.swift",
     "if case .waiting? = SyncJoin.overall(of: read, waiting: waiting) {",
     "if case .waiting? = SyncJoin.overall(of: read, waiting: 0) {",
     "a join waits for files it could not read yet"),
    ("unread-own-file-overwritten", "SyncPublish.swift",
     "            case .unread:\n                return .none(.ownFileNotRead)",
     "            case .unread:\n                expectation = .unchecked",
     "the own file is read in this session before it is written"),
    ("own-file-not-dominated", "SyncPublish.swift",
     "                guard isDominated else {\n                    return .none(.ownFileNotDominated)\n                }",
     "                _ = isDominated",
     "an own file that holds what the state does not is never overwritten"),
    ("answer-without-fresh-dot", "SyncAnswer.swift",
     "guard SyncCapture.mint(target.unit, payload: target.payload, digest: digest, state: &state, environment: environment, superseding: shown) else {",
     "state.baseline[target.unit] = digest\n        guard true else {",
     "an answer is one fresh entry that the group sees"),
    ("answer-supersedes-everything", "SyncAnswer.swift",
     "let shown = Set(question.shown[target.unit] ?? [])\n                let local",
     "let shown = Set(state.replica.live(target.unit).map(\\.dot))\n                let local",
     "an answer supersedes exactly the dots its sheet showed"),
    ("counter-floors-ignored", "SyncIdentity.swift",
     "for floor in [stateCounter, mirror, highWater, maxSeenSelf] {",
     "for floor in [stateCounter] {",
     "a counter never goes back below what the mirror, the high-water mark or the replica say was minted"),
    ("capture-during-join", "SyncEngine.swift",
     "guard let snapshot = draft.state.session.snapshot, draft.state.pendingJoin == nil else {",
     "guard let snapshot = draft.state.session.snapshot else {",
     "nothing is captured while a join waits"),
    ("bystander-menu-hint", "SyncPlan.swift",
     "        if questionRows > 0 {\n            return .choose",
     "        if questionRows + bystanderRows > 0 {\n            return .choose",
     "a conflict between other Macs gives no hint in the menu"),
    ("pre-row-suppressed", "SyncPlan.swift",
     "} else if local != nil, state.localOrigin[key] == .preexisting {\n                outcomes[key] = .preRow",
     "} else if false {\n                outcomes[key] = .preRow",
     "a value that was there before sync and differs from the group's is asked about"),
    ("absent-equals-default", "SyncCapture.swift",
     "} else if environment.guards.contains(.absentMeansNoValue) {",
     "} else if false {",
     "no user value is the key's absence, never equal to the default"),
    ("aliased-unit-captured", "SyncCapture.swift",
     "                !snapshot.aliased.contains(key),\n                !SyncLayout27.isIntentCaptured(key)",
     "                !SyncLayout27.isIntentCaptured(key)",
     "the old key of an item that changes its key is relayed, never captured as a deletion"),
    ("writer-limit-raised", "SyncDeviceFile.swift",
     "static let maximumWriteSize = 1 << 20",
     "static let maximumWriteSize = 1 << 21",
     "the writer's limit equals the reader's, so no Mac writes a file another refuses"),
    ("generation-26-authors-l27", "SyncUnits.swift",
     "return descriptor.scope.map { $0 == generation } ?? true",
     "return true",
     "the macOS 27 families are authored and applied by macOS 27 Macs only"),
    ("automatic-store-mints", "SyncCapture.swift",
     "                !snapshot.aliased.contains(key),\n                !SyncLayout27.isIntentCaptured(key)\n            else {",
     "                !snapshot.aliased.contains(key)\n            else {",
     "an automatic placement of the arrangement mints no dot"),
    ("absent-l27-as-deletion", "SyncLayout27.swift",
     "return SyncUnitIntent(unit: .split(family: SyncUnitTable.layout27Family, item: bundleID), from: before, to: .value(after))",
     "return SyncUnitIntent(unit: .split(family: SyncUnitTable.layout27Family, item: bundleID), from: before, to: after == visible ? .deleted : .value(after))",
     "moving an application back to visible is the explicit value, never a deletion"),
    ("profile-apply-replaces-sections", "SyncProjection.swift",
     "var profile = index.map { profiles[$0] } ?? [\"profileID\": id, \"itemSections\": [String: Int]()]",
     "var profile: [String: Any] = [\"profileID\": id, \"itemSections\": [String: Int]()]",
     "applying a profile keeps its macOS 26 part, its bindings and the fields this build does not know"),
    ("digest-unsorted", "SyncValue.swift",
     "for key in values.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {\n                Self.append(key.utf8, to: &bytes)",
     "for key in values.keys {\n                Self.append(key.utf8, to: &bytes)",
     "a digest does not depend on the order a dictionary holds its keys in"),
]


def suites():
    """The sync test suites: the names of the structs ending in Tests under Tests/HolzBarCoreTests/Sync."""
    names = set()
    for directory, _, files in os.walk(os.path.join(ROOT, TESTS)):
        for name in sorted(files):
            if name.endswith(".swift"):
                with open(os.path.join(directory, name), encoding="utf-8") as file:
                    names.update(re.findall(r"^\s*struct (\w+Tests)\b", file.read(), re.MULTILINE))
    return sorted(names)


def filter_regex(names):
    return "|".join(names)


def swift_test(directory, names, label):
    """Runs the suites. A run that does not end within SYNC_MUTATION_TIMEOUT seconds (default 1500) is stopped, and the tests that had
    failed by then are the kill: a mutated engine can livelock a suite (the unsorted digest does), and a gate that waits for ever
    decides nothing."""
    command = ["swift", "test", "--filter", filter_regex(names)] + os.environ.get("SYNC_SWIFT_TEST_FLAGS", "").split()
    started = time.time()
    process = subprocess.Popen(command, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=float(os.environ.get("SYNC_MUTATION_TIMEOUT", "1500")))
        code = process.returncode
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        output = (output or "") + "\n(the run did not end: stopped by the gate)"
        code = -9
    failing = re.findall(r'✘ Test "([^"]+)"', output)
    ran = re.search(r"Test run with (\d+) tests", output)
    return code, failing, bool(ran) or code == -9, output, time.time() - started


def main():
    parser = argparse.ArgumentParser(description="Mutation gate of the settings sync engine")
    parser.add_argument("--list", action="store_true", help="list the mutations and exit")
    parser.add_argument("--only", metavar="NAME[,NAME...]", help="run the named mutation(s), one after the other in one copy of the sources")
    parser.add_argument("--no-baseline", action="store_true", help="skip the baseline (only to re-run a mutation whose table entry was repaired after the baseline of the same sources passed in another run)")
    parser.add_argument("--shard", metavar="K/N", help="run the mutations K, K+N, K+2N, ... (several shards run side by side)")
    arguments = parser.parse_args()
    if arguments.list:
        for name, file, _, _, guard in MUTATIONS:
            print(f"{name}\t{file}\t{guard}")
        return 0
    wanted = arguments.only.split(",") if arguments.only else None
    chosen = [m for m in MUTATIONS if wanted is None or m[0] in wanted]
    if arguments.shard:
        index, count = (int(part) for part in arguments.shard.split("/"))
        chosen = chosen[index::count]
    if not chosen:
        print(f"no mutation named {arguments.only}")
        return 2

    # Every text must exist exactly once in the repository's own source.
    stale = []
    for name, file, find, _, _ in chosen:
        with open(os.path.join(ROOT, SYNC, file), encoding="utf-8") as source:
            count = source.read().count(find)
        if count != 1:
            stale.append(f"stale mutation {name}: the text occurs {count} times in {SYNC}/{file}")
    if stale:
        print("\n".join(stale))
        return 2

    names = suites()
    unit = [n for n in names if not n.startswith(("Sim", "Catalogue", "Simulation"))]
    work = tempfile.mkdtemp(prefix="sync-mutation-")
    print(f"==> Copying the sources to {work}")
    try:
        for path in COPIED:
            source = os.path.join(ROOT, path)
            target = os.path.join(work, path)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if os.path.isdir(source):
                shutil.copytree(source, target, symlinks=True)
            else:
                shutil.copy2(source, target)
        if arguments.no_baseline:
            print("==> Baseline skipped (--no-baseline)")
        else:
            print(f"==> Baseline: {len(names)} suites")
            code, failing, ran, output, seconds = swift_test(work, names, "baseline")
            if code != 0 or failing or not ran:
                print(output[-4000:])
                print("==> The baseline fails: no mutation can be judged")
                return 1
            print(f"    the baseline passes ({seconds:.0f} s)")
        survivors = []
        staled = []
        for name, file, find, replace, guard in chosen:
            path = os.path.join(work, SYNC, file)
            with open(path, encoding="utf-8") as source:
                original = source.read()
            with open(path, "w", encoding="utf-8") as target:
                target.write(original.replace(find, replace, 1))
            try:
                # The suites that need no simulation first: most mutations die there, within a minute.
                code, failing, ran, output, seconds = swift_test(work, unit, name)
                stage = "unit suites"
                if code == 0 and ran and not failing:
                    code, failing, ran, output, seconds2 = swift_test(work, names, name)
                    seconds += seconds2
                    stage = "all suites"
            finally:
                with open(path, "w", encoding="utf-8") as target:
                    target.write(original)
            if code != 0 and not failing and not ran:
                staled.append(name)
                print(f"  stale mutation {name}: the mutated source does not build\n{output[-1500:]}")
            elif code != 0 and failing:
                others = f" (and {len(failing) - 1} more: {'; '.join(failing[1:4])})" if len(failing) > 1 else ""
                print(f"  killed   {name} by {failing[0]}{others} ({stage}, {seconds:.0f} s)")
            else:
                survivors.append(name)
                print(f"  SURVIVED {name}: {guard} ({seconds:.0f} s)")
        if staled:
            print(f"==> {len(staled)} stale mutation(s): {', '.join(staled)}")
            return 2
        if survivors:
            print(f"==> {len(survivors)} mutation(s) survived: {', '.join(survivors)}")
            return 1
        print(f"==> All {len(chosen)} mutations killed")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
