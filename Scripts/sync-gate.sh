#!/bin/bash
#
# sync-gate.sh
#
# Gate G1 of the settings sync redesign (plan 28-13, decisions D-11 and D-12): no app code uses the sync engine before the
# simulator has proven it. The gate is
#
#   - the determinism lint of holzBar/Core/Sync (a self-test, then the sources),
#   - every sync test suite (the engine, the catalogue of failures, the seeded and exhaustive exploration, the fuzzing of the
#     three codecs, the control engines that must be caught),
#   - with --full, the same suites at the gate's budgets, a second process that must reproduce every trace hash of the first,
#     and the mutation gate (Scripts/sync-mutation-gate.py), which breaks the engine on purpose and needs the tests to notice.
#
#   Scripts/sync-gate.sh --quick           the lint and the suites at the budgets CI uses (a few minutes)
#   Scripts/sync-gate.sh --full            the gate's budgets: SYNC_SIM_SEEDS=10000 SYNC_SIM_STEPS=400 SYNC_SIM_DEPTH=8
#                                          SYNC_FUZZ_INPUTS=1000000, built in release mode, then the mutation gate
#   Scripts/sync-gate.sh --full --record   the same, and the result is written to
#                                          .planning/phases/28-settings-sync-redesign/28-G1-GATE.md
#
# SYNC_GATE_SEEDS, SYNC_GATE_STEPS, SYNC_GATE_DEPTH and SYNC_GATE_FUZZ lower the budgets of --full (a bounded run is recorded as it
# ran, and is never recorded as passed unless every part passed and no open exclusion stands).
#
# A --full run takes hours: start it in the background and read its log. Set SYNC_SWIFT_TEST_FLAGS for extra `swift test`
# flags (for example -Xswiftc -plugin-path ... on a Mac without Xcode), SYNC_GATE_SCRATCH for the release build directory and
# SYNC_GATE_RUNS for the most runs one exhaustive family spends (default 300000).

set -euo pipefail

cd "$(dirname "$0")/.."
root=$(pwd)

mode=quick
record=false
for argument in "$@"; do
  case "$argument" in
    --quick) mode=quick ;;
    --full) mode=full ;;
    --record) record=true ;;
    *) echo "usage: $0 [--quick|--full] [--record]" >&2; exit 2 ;;
  esac
done

record_file=".planning/phases/28-settings-sync-redesign/28-G1-GATE.md"
scratch="${SYNC_GATE_SCRATCH:-${TMPDIR:-/tmp}/sync-gate-build}"
# shellcheck disable=SC2206
extra_flags=(${SYNC_SWIFT_TEST_FLAGS:-})
report=$(mktemp)
second_report=$(mktemp)
log=$(mktemp)
trap 'rm -f "$report" "$second_report" "$log"' EXIT

# The sync suites: every struct whose name ends in Tests under Tests/HolzBarCoreTests/Sync.
suites=$(grep -rhoE '^[[:space:]]*struct [A-Za-z0-9_]+Tests\b' Tests/HolzBarCoreTests/Sync | awk '{print $2}' | sort -u | paste -sd '|' -)
if [ -z "$suites" ]; then
  echo "no sync suites found" >&2
  exit 1
fi
suite_count=$(printf '%s' "$suites" | tr '|' '\n' | wc -l | tr -d ' ')

passed=true
failures=()

step() {
  echo
  echo "==> $*"
}

# ---------------------------------------------------------------------------------------------------------------- the lint

step "Sync code rules"
python3 .github/scripts/sync-lint.py --self-test
if ! python3 .github/scripts/sync-lint.py; then
  passed=false
  failures+=("the determinism lint")
fi

# ------------------------------------------------------------------------------------------------------------- the suites

run_tests() {
  # run_tests <report file> <extra test arguments...>; the output goes to $log and to the terminal.
  local target=$1
  shift
  SYNC_GATE_REPORT="$target" swift test "${extra_flags[@]}" --filter "$suites" "$@" 2>&1 | tee "$log"
}

started=$(date +%s)
if [ "$mode" = quick ]; then
  step "The sync suites at the CI budgets ($suite_count suites)"
  export SYNC_GATE_REPORT="$report"
  if ! run_tests "$report"; then
    passed=false
    failures+=("the sync suites")
  fi
  if grep -q "✘" "$log"; then
    passed=false
    failures+=("a failing test")
  fi
  if grep -q "No matching test cases were run" "$log"; then
    passed=false
    failures+=("no test ran")
  fi
else
  export SYNC_SIM_SEEDS="${SYNC_GATE_SEEDS:-10000}" SYNC_SIM_STEPS="${SYNC_GATE_STEPS:-400}" SYNC_SIM_DEPTH="${SYNC_GATE_DEPTH:-8}" SYNC_FUZZ_INPUTS="${SYNC_GATE_FUZZ:-1000000}"
  export SYNC_SIM_RUNS="${SYNC_GATE_RUNS:-300000}"
  step "The sync suites at the gate's budgets: $SYNC_SIM_SEEDS seeds per preset, $SYNC_SIM_STEPS steps, depth $SYNC_SIM_DEPTH, $SYNC_FUZZ_INPUTS fuzz inputs"
  if ! run_tests "$report" -c release --scratch-path "$scratch" -Xswiftc -enable-testing; then
    passed=false
    failures+=("the sync suites")
  fi
  if grep -q "✘" "$log"; then
    passed=false
    failures+=("a failing test")
  fi
  step "A second process reproduces every trace hash"
  SYNC_GATE_REPORT="$second_report" swift test "${extra_flags[@]}" --filter "SimulationTests/determinism" -c release --scratch-path "$scratch" -Xswiftc -enable-testing 2>&1 | tail -3
  if ! diff <(grep '^hash ' "$report" | sort) <(grep '^hash ' "$second_report" | sort) >/dev/null; then
    echo "the trace hashes of two processes differ"
    passed=false
    failures+=("the trace hashes differ between two processes")
  else
    echo "$(grep -c '^hash ' "$report") trace hashes are the same in both processes"
  fi
fi
finished=$(date +%s)
elapsed=$((finished - started))

# ------------------------------------------------------------------------------------------------------ the mutation gate

mutations=0
mutation_log=""
if [ "$mode" = full ]; then
  step "The mutation gate"
  unset SYNC_SIM_SEEDS SYNC_SIM_STEPS SYNC_SIM_DEPTH SYNC_FUZZ_INPUTS SYNC_SIM_RUNS SYNC_GATE_REPORT
  mutations=$(python3 Scripts/sync-mutation-gate.py --list | wc -l | tr -d ' ')
  mutation_log=$(mktemp)
  shards="${SYNC_GATE_MUTATION_SHARDS:-1}"
  if [ "$shards" -gt 1 ]; then
    # Shards run side by side, each in a copy of its own; their logs are joined.
    shard_status=0
    pids=()
    for ((shard = 0; shard < shards; shard++)); do
      python3 Scripts/sync-mutation-gate.py --shard "$shard/$shards" > "$mutation_log.$shard" 2>&1 &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do
      wait "$pid" || shard_status=1
    done
    cat "$mutation_log".[0-9]* | tee "$mutation_log"
    rm -f "$mutation_log".[0-9]*
    if [ "$shard_status" -ne 0 ]; then
      passed=false
      failures+=("the mutation gate")
    fi
  elif python3 Scripts/sync-mutation-gate.py | tee "$mutation_log"; then
    :
  else
    passed=false
    failures+=("the mutation gate")
  fi
fi

# -------------------------------------------------------------------------------------------------------------- the result

step "Result"
if $passed; then
  echo "Gate parts passed ($mode)"
else
  printf 'Gate failed: %s\n' "${failures[@]}"
fi

if $record; then
  if [ "$mode" != full ]; then
    echo "--record needs --full" >&2
    exit 2
  fi
  commit=$(git rev-parse HEAD)
  # The invariants that the seeded runs leave out until their causes are known (SimExploration.openExclusions): G1 does not pass while
  # one stands, and not at a budget below the plan's.
  open_exclusions=$(awk '/static let openExclusions/{f=1; next} f && /^    \]/{f=0} f && /\("INV-/{print}' Tests/HolzBarCoreTests/Sync/Simulation/SimExploration.swift)
  if [ -n "$open_exclusions" ]; then
    passed=false
    failures+=("open exclusions")
  fi
  if [ "$SYNC_SIM_SEEDS" -lt 10000 ] || [ "$SYNC_SIM_DEPTH" -lt 8 ] || [ "$SYNC_FUZZ_INPUTS" -lt 1000000 ]; then
    passed=false
    failures+=("a budget below the plan's")
  fi
  seeds_runs=$(awk '$1 == "seeds" { total += $3 } END { print total + 0 }' "$report")
  {
    echo "# Gate G1: the simulator proves the sync engine"
    echo
    echo "- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Commit: $commit"
    echo "- Result: $($passed && echo "G1: PASSED" || echo "G1: FAILED")"
    echo
    if ! $passed; then
      echo
      echo "Not passed because: $(printf '%s; ' "${failures[@]}")"
    fi
    echo
    echo "## Budgets"
    echo
    echo "- Seeds per provider preset: ${SYNC_SIM_SEEDS}"
    echo "- Steps per seeded run: ${SYNC_SIM_STEPS}"
    echo "- Exhaustive depth: ${SYNC_SIM_DEPTH} (at most ${SYNC_SIM_RUNS} runs of one family)"
    echo "- Fuzz inputs: ${SYNC_FUZZ_INPUTS}"
    echo "- Mutations: ${mutations}"
    echo "- Suites: ${suite_count}; the release build runs them in ${elapsed} s"
    echo
    echo "## Seeded runs of the real engine"
    echo
    echo "Total seeded runs, all presets, each with its drain: ${seeds_runs}"
    echo
    echo "Clean worlds draw no event that destroys what a Mac's sync state knows and are judged by every invariant; disturbed worlds draw them too and leave out only the invariants listed in SimExploration.evidenceLossExclusions."
    echo
    awk '$1 == "seeds" { runs[$2 " " $6] += $3 } END { for (key in runs) { split(key, part, " "); print "- " part[1] ", " part[2] " worlds: " runs[key] " seeds" } }' "$report" | sort
    echo
    echo "## Metamorphic pairs"
    echo
    awk '$1 == "metamorphic" { pairs[$2] += $3 } END { for (preset in pairs) print "- " preset ": " pairs[preset] " traces" }' "$report" | sort
    echo
    echo "## Control engines (each must be caught within seeds 1 to 200)"
    echo
    sed -n 's/^control \(.*\) caught at seed \([0-9]*\)$/- \1: caught at seed \2/p' "$report" | sort
    echo
    echo "## Bounded exhaustive families"
    echo
    sed -n 's/^exhaustive \(.*\) depth \([0-9]*\) alphabet \([0-9]*\) runs \([0-9]*\) states \([0-9]*\)$/- \1: depth \2, alphabet \3, \4 runs, \5 distinct states/p' "$report" | sort
    echo
    echo "## Fuzzing"
    echo
    awk '$1 == "fuzz" { device += $2; state += $3; legacy += $4 } END { print "- device files: " device "\n- states: " state "\n- legacy files: " legacy "\n- inputs: " device + state + legacy }' "$report"
    echo
    echo "## Determinism"
    echo
    echo "- Trace hashes reproduced by a second process: $(grep -c '^hash ' "$report")"
    echo
    echo "## Open exclusions"
    echo
    if [ -n "$open_exclusions" ]; then
      echo "These invariants are left out of the seeded runs (both families) until their causes are known; each is a class that the exploration still finds at a low rate:"
      echo
      printf '%s\n' "$open_exclusions" | sed -E 's/^ *\("(INV-[A-Za-z0-9]+)", "(.*)"\),?$/- \1: \2/'
    else
      echo "None."
    fi
    echo
    echo "## Mutation gate"
    echo
    if [ -n "$mutation_log" ]; then
      sed -n 's/^  killed   \(.*\)$/- killed \1/p; s/^  SURVIVED \(.*\)$/- SURVIVED \1/p; s/^==> \(.*\)$/\n\1/p' "$mutation_log"
    fi
  } > "$record_file"
  echo "Recorded in $record_file"
fi

$passed
