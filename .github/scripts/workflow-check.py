#!/usr/bin/env python3
#
# workflow-check.py
#
# Proves that the GitHub Actions workflows (.github/workflows) and composite
# actions (.github/actions) keep the release supply chain closed:
#
#   pins         Every action is pinned by its full commit SHA with a
#                "# vX.Y.Z" comment, so a moved tag cannot change what runs;
#                local actions (./) and docker:// images pinned by digest pass.
#                The only tag reference allowed is the SLSA generic generator,
#                which verifies itself by its tag.
#   permissions  Every workflow sets read-only top-level permissions, and a job
#                asks for write access only where WRITE_ALLOWED says so.
#   secrets      A secret appears only in the jobs SECRETS_ALLOWED names
#                (GITHUB_TOKEN anywhere); no "secrets: inherit", no dynamic
#                secret access, and no pull_request_target or workflow_run
#                trigger, which run with secrets on code from others.
#   credentials  Every checkout sets persist-credentials: false, so no later
#                step finds a token in .git/config; only the release
#                workflow's cask job keeps its deploy key, to push the cask.
#
# It runs in the workflows job of .github/workflows/build.yml and locally:
#
#   python3 .github/scripts/workflow-check.py [--root DIR]
#
# It reads the files line by line instead of parsing YAML (Python's standard
# library has no YAML parser) and relies on the two-space indentation every
# workflow here uses: jobs at two spaces, job keys at four. actionlint, in the
# same job, validates the YAML itself. Every violation is printed as a GitHub
# annotation and makes the script exit with status 1. Python standard library
# only.

import argparse
import glob
import os
import re
import sys

# (workflow file, job) -> scopes the job may write.
WRITE_ALLOWED = {
    ("release.yml", "publish"): {"contents", "id-token", "attestations"},
    ("release.yml", "provenance"): {"contents", "id-token"},
    ("codeql.yml", "swift"): {"security-events"},
    ("codeql.yml", "actions"): {"security-events"},
    ("scorecard.yml", "analysis"): {"security-events", "id-token"},
}

# (workflow file, job) -> secrets the job may use. GITHUB_TOKEN is allowed everywhere.
SECRETS_ALLOWED = {
    ("release.yml", "sign"): {"SIGNING_CERTIFICATE_P12", "SIGNING_CERTIFICATE_PASSWORD"},
    ("release.yml", "cask"): {"CASK_DEPLOY_KEY"},
    ("release.yml", "holzcloud-ch"): {"CMS_TOKEN"},
}

# (workflow file, job) whose checkout keeps its credentials.
CREDENTIALS_ALLOWED = {("release.yml", "cask")}

SLSA_GENERATOR = re.compile(
    r"^slsa-framework/slsa-github-generator/\.github/workflows/generator_generic_slsa3\.yml@v\d+\.\d+\.\d+$")
SHA_PINNED = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
VERSION_COMMENT = re.compile(r"^v\d+\.\d+\.\d+$")
DOCKER_PINNED = re.compile(r"^docker://\S+@sha256:[0-9a-f]{64}$")

USES = re.compile(r"^(\s*)(-\s+)?uses:\s*(.*)$")
TOP_LEVEL_KEY = re.compile(r"^([\"']?[A-Za-z_][A-Za-z0-9_-]*[\"']?):(.*)$")
JOB = re.compile(r"^  ([A-Za-z0-9_-]+):\s*(#.*)?$")
JOB_PERMISSIONS = re.compile(r"^    permissions:\s*(.*)$")
SCOPE = re.compile(r"^\s+([a-z-]+):\s*([a-z-]+)\s*(#.*)?$")
EXPRESSION = re.compile(r"\$\{\{(.*?)\}\}")
SECRET = re.compile(r"\bsecrets\.([A-Za-z_][A-Za-z0-9_]*)")
DYNAMIC_SECRET = re.compile(r"\bsecrets\s*\[|\(\s*secrets\s*\)")
INHERIT = re.compile(r"^\s*secrets:\s*inherit\b")
UNSAFE_TRIGGER = re.compile(r"\b(pull_request_target|workflow_run)\b")
STEP = re.compile(r"^(\s*)-\s")
PERSIST_FALSE = re.compile(r"^\s*persist-credentials:\s*false\s*(#.*)?$")

errors = 0


def annotate(path, line, message):
    global errors
    errors += 1
    print(f"::error file={path},line={line}::{message}")


def indentation(line):
    return len(line) - len(line.lstrip(" "))


def is_blank_or_comment(line):
    stripped = line.strip()
    return not stripped or stripped.startswith("#")


def split_comment(value):
    """Splits `value # comment` into the value without quotes and the comment."""
    comment = ""
    if " #" in value:
        value, comment = value.split(" #", 1)
    elif value.startswith("#"):
        value, comment = "", value[1:]
    return value.strip().strip("\"'"), comment.strip()


def files(root):
    paths = []
    for pattern in (".github/workflows/*.yml", ".github/workflows/*.yaml",
                    ".github/actions/*/action.yml", ".github/actions/*/action.yaml"):
        paths.extend(glob.glob(os.path.join(root, pattern)))
    return sorted(os.path.relpath(path, root) for path in paths)


def jobs_by_line(lines):
    """The job each line belongs to (None outside jobs), and the top-level key of each line."""
    jobs, keys = [], []
    key, job = None, None
    for line in lines:
        match = TOP_LEVEL_KEY.match(line)
        if match and not line.startswith(" "):
            key = match.group(1).strip("\"'")
            job = None
        elif key == "jobs":
            match = JOB.match(line)
            if match:
                job = match.group(1)
        jobs.append(job)
        keys.append(key)
    return jobs, keys


def block_end(lines, start, parent_indentation):
    """The index after the block that starts below lines[start]."""
    end = start + 1
    while end < len(lines):
        if not is_blank_or_comment(lines[end]) and indentation(lines[end]) <= parent_indentation:
            break
        end += 1
    return end


def check_pins(path, lines):
    count = 0
    for number, line in enumerate(lines, 1):
        if is_blank_or_comment(line):
            continue
        match = USES.match(line)
        if not match:
            continue
        value, comment = split_comment(match.group(3))
        count += 1
        if value.startswith("./"):
            continue
        if value.startswith("docker://"):
            if not DOCKER_PINNED.match(value):
                annotate(path, number, f"{value} is not pinned by an image digest (@sha256:...)")
            continue
        if SLSA_GENERATOR.match(value):
            continue
        if not SHA_PINNED.match(value):
            annotate(path, number, f"{value} is not pinned by a full commit SHA")
        elif not VERSION_COMMENT.match(comment):
            annotate(path, number, f"{value} needs a '# vX.Y.Z' comment naming the pinned release")
    return count


def check_permission_block(path, lines, start, parent_indentation, allowed, where):
    """Checks the scopes below a `permissions:` line; allowed is None for read-only."""
    for index in range(start + 1, block_end(lines, start, parent_indentation)):
        if is_blank_or_comment(lines[index]):
            continue
        match = SCOPE.match(lines[index])
        if not match:
            annotate(path, index + 1, f"Unreadable permission line in {where}")
            continue
        scope, level = match.group(1), match.group(2)
        if level in ("read", "none"):
            continue
        if level != "write":
            annotate(path, index + 1, f"Unknown permission level {level} for {scope} in {where}")
        elif allowed is None or scope not in allowed:
            annotate(path, index + 1, f"{where} may not have {scope}: write")


def check_permissions(path, lines, jobs):
    name = os.path.basename(path)
    top_level = False
    for index, line in enumerate(lines):
        if is_blank_or_comment(line):
            continue
        if line.startswith("permissions:"):
            top_level = True
        if re.search(r"\bpermissions:\s*write-all\b", line):
            annotate(path, index + 1, "permissions: write-all is never allowed")
            continue
        if line.startswith("permissions:"):
            value, _ = split_comment(line[len("permissions:"):].strip())
            if value in ("{}", "read-all"):
                continue
            if value:
                annotate(path, index + 1, f"Top-level permissions must be read-only, not {value}")
                continue
            check_permission_block(path, lines, index, 0, None, "The workflow's top-level permissions")
            continue
        match = JOB_PERMISSIONS.match(line)
        if match and jobs[index]:
            job = jobs[index]
            value, _ = split_comment(match.group(1))
            if value in ("{}", "read-all"):
                continue
            if value:
                annotate(path, index + 1, f"Job {job} sets permissions {value}; list the scopes instead")
                continue
            check_permission_block(path, lines, index, 4, WRITE_ALLOWED.get((name, job)), f"Job {job}")
    if not top_level:
        annotate(path, 1, "The workflow sets no top-level permissions; add permissions: contents: read")


def check_secrets(path, lines, jobs, keys, is_action):
    name = os.path.basename(path)
    for index, line in enumerate(lines):
        number = index + 1
        if INHERIT.match(line):
            annotate(path, number, "secrets: inherit hands every secret to another workflow")
        if keys[index] == "on" and not line.lstrip().startswith("#") and UNSAFE_TRIGGER.search(line):
            annotate(path, number, "pull_request_target and workflow_run run with secrets on code from others")
        # Expressions count even in comments of a run script: Actions expands them anyway.
        for expression in EXPRESSION.findall(line):
            if DYNAMIC_SECRET.search(expression):
                annotate(path, number, "Secrets may only be named one by one (secrets.NAME)")
            for secret in SECRET.findall(expression):
                if secret == "GITHUB_TOKEN":
                    continue
                if is_action:
                    annotate(path, number, f"A composite action may not use secrets.{secret}")
                elif secret not in SECRETS_ALLOWED.get((name, jobs[index]), set()):
                    where = f"job {jobs[index]}" if jobs[index] else "this place"
                    annotate(path, number, f"secrets.{secret} is not allowed in {where} of {name}")


def check_credentials(path, lines, jobs):
    name = os.path.basename(path)
    for index, line in enumerate(lines):
        if is_blank_or_comment(line):
            continue
        match = USES.match(line)
        if not match:
            continue
        value, _ = split_comment(match.group(3))
        if not value.startswith("actions/checkout@"):
            continue
        if (name, jobs[index]) in CREDENTIALS_ALLOWED:
            continue
        # The step starts at its "- " line: this one, or the nearest one above it.
        start = index
        if match.group(2):
            dash = len(match.group(1))
        else:
            while start > 0:
                start -= 1
                step = STEP.match(lines[start])
                if step and len(step.group(1)) < indentation(line):
                    break
            dash = indentation(lines[start])
        end = block_end(lines, start, dash)
        if not any(PERSIST_FALSE.match(lines[i]) for i in range(start, end)):
            annotate(path, index + 1, "actions/checkout must set persist-credentials: false")


def main():
    default_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser = argparse.ArgumentParser(description="holzBar's workflow supply-chain checks.")
    parser.add_argument("--root", default=default_root, help="repository root (default: %(default)s)")
    arguments = parser.parse_args()
    root = os.path.abspath(arguments.root)
    paths = files(root)
    if not paths:
        annotate(".github/workflows", 1, "No workflow found")
    references = 0
    for path in paths:
        with open(os.path.join(root, path), encoding="utf-8") as file:
            lines = file.read().splitlines()
        is_action = path.startswith(os.path.join(".github", "actions"))
        jobs, keys = jobs_by_line(lines)
        references += check_pins(path, lines)
        if not is_action:
            check_permissions(path, lines, jobs)
        check_secrets(path, lines, jobs, keys, is_action)
        check_credentials(path, lines, jobs)
    if errors:
        return 1
    print(f"==> Workflows: {references} action references pinned, read-only top-level permissions, "
          "secrets and write permissions only where allowed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
