#!/bin/bash
# SessionStart hook: links the private planning repository (holzcloud/holzBar-planning)
# into this working tree as .planning/. Planning, research and the design concept are
# private on purpose and never belong in this public repository.
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PRIVATE="${HOLZBAR_PLANNING_DIR:-$ROOT/../holzbar-planning}"

if [ ! -d "$PRIVATE/.git" ]; then
  if ! git clone --depth 1 https://github.com/holzcloud/holzBar-planning "$PRIVATE" >/dev/null 2>&1; then
    echo "holzBar-planning is not available in this session: attach the repository holzcloud/holzBar-planning to it (.planning/ is missing)." >&2
    exit 0
  fi
fi

if [ ! -e "$ROOT/.planning" ]; then
  ln -s "$PRIVATE/planning" "$ROOT/.planning"
fi
exit 0
