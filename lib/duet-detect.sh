#!/usr/bin/env bash
# What are this project's commands?
#
# Duet needs to know how to install, run, check and test a project, because
# every gate in every preset is one of those commands and a gate nobody can run
# is a gate that always passes. It also fills the blanks in the generated
# documents, and it is what turns the deployed leg of the done check from a
# permanent "not run" into a real result.
#
# ASKING would be six more setup questions and nobody would finish the form.
# GUESSING EVERY RUN costs a detection pass each time and gets it subtly wrong
# in a monorepo. So: detect once, show the guesses WITH THEIR EVIDENCE, let the
# human correct anything wrong, and store the answer.
#
# Showing the evidence is the part that matters. "test: npm test" is a claim.
# "test: npm test   package.json scripts" is a claim you can check at a glance,
# which is standing rule 3 applied to a config file.

# shellcheck source=duet-common.sh
# Locate siblings via DUET_ROOT, never via BASH_SOURCE alone.
#
# BASH_SOURCE IS EMPTY UNDER ZSH, which is the default shell on macOS and the
# one Claude Code's Bash tool runs. `dirname ""` yields ".", so every sibling
# source became ./duet-x.sh and failed. That made the whole goal path
# unreachable from the very shell the skills tell the orchestrator to use, and
# it survived every test that happened to run under `bash -c`.
: "${DUET_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
. "$DUET_ROOT/lib/duet-common.sh"

# duet_detect <dir> ; emits "key<TAB>command<TAB>evidence" lines
duet_detect () {
  local dir="${1:-${DUET_PROJECT:-$PWD}}"
  python3 - "$dir" <<'PY'
import json, os, re, sys

root = sys.argv[1]
def p(*a): return os.path.join(root, *a)
def exists(*a): return os.path.exists(p(*a))
def read(*a):
    try: return open(p(*a), errors="replace").read()
    except Exception: return ""

out = {}                      # key -> (command, evidence)
def put(k, cmd, why):
    if cmd and k not in out: out[k] = (cmd, why)

# ---- javascript and typescript ------------------------------------------
pkg = {}
if exists("package.json"):
    try: pkg = json.loads(read("package.json"))
    except Exception: pkg = {}
scripts = pkg.get("scripts") or {}

# The package manager is decided by the lockfile, never by preference. Getting
# this wrong is the single most common way a generated command does not run.
pm, pm_why, install = None, None, None
for lock, name, inst in (
    ("bun.lockb", "bun", "bun install"),
    ("bun.lock", "bun", "bun install"),
    ("pnpm-lock.yaml", "pnpm", "pnpm install --frozen-lockfile"),
    ("yarn.lock", "yarn", "yarn install --frozen-lockfile"),
    ("package-lock.json", "npm", "npm ci"),
):
    if exists(lock):
        pm, pm_why, install = name, lock, inst
        break
if pkg and not pm:
    pm, pm_why, install = "npm", "package.json, no lockfile", "npm install"

if pm:
    run = f"{pm} run" if pm != "npm" else "npm run"
    put("install", install, pm_why)
    for key, names in (
        ("dev",       ("dev", "start", "serve")),
        ("build",     ("build",)),
        ("test",      ("test", "test:unit")),
        ("lint",      ("lint", "eslint")),
        ("typecheck", ("typecheck", "type-check", "tsc", "types")),
    ):
        for n in names:
            if n in scripts:
                cmd = f"{pm} test" if (key == "test" and pm in ("npm", "yarn", "bun") and n == "test") else f"{run} {n}"
                put(key, cmd, f"package.json scripts.{n}")
                break
    if "typecheck" not in out and exists("tsconfig.json"):
        put("typecheck", f"{pm}x tsc --noEmit" if pm != "npm" else "npx tsc --noEmit", "tsconfig.json, no script")

# ---- python --------------------------------------------------------------
if exists("pyproject.toml"):
    t = read("pyproject.toml")
    if exists("uv.lock"):       put("install", "uv sync", "uv.lock")
    elif exists("poetry.lock"): put("install", "poetry install", "poetry.lock")
    else:                       put("install", "pip install -e .", "pyproject.toml")
    if "pytest" in t or exists("tests"): put("test", "pytest", "pytest in pyproject.toml or tests/")
    if "ruff" in t:  put("lint", "ruff check .", "ruff in pyproject.toml")
    if "mypy" in t:  put("typecheck", "mypy .", "mypy in pyproject.toml")
elif exists("requirements.txt"):
    put("install", "pip install -r requirements.txt", "requirements.txt")
    if exists("tests"): put("test", "pytest", "tests/ present")

# ---- rust, go, make ------------------------------------------------------
if exists("Cargo.toml"):
    put("install", "cargo fetch", "Cargo.toml"); put("build", "cargo build", "Cargo.toml")
    put("test", "cargo test", "Cargo.toml"); put("lint", "cargo clippy", "Cargo.toml")
    put("typecheck", "cargo check", "Cargo.toml")
if exists("go.mod"):
    put("install", "go mod download", "go.mod"); put("build", "go build ./...", "go.mod")
    put("test", "go test ./...", "go.mod"); put("typecheck", "go vet ./...", "go.mod")
if exists("Makefile"):
    mk = read("Makefile")
    for target in ("install", "dev", "build", "test", "lint", "typecheck"):
        if re.search(rf"^{target}:", mk, re.M):
            put(target, f"make {target}", f"Makefile target {target}")

# ---- deploy target -------------------------------------------------------
if exists(".vercel", "project.json"):
    put("deploy", "vercel --prod", ".vercel/project.json")
if exists("fly.toml"):
    put("deploy", "fly deploy", "fly.toml")
    m = re.search(r'^\s*app\s*=\s*"([^"]+)"', read("fly.toml"), re.M)
    if m: put("deployed", f"https://{m.group(1)}.fly.dev", "fly.toml app name")
if exists("wrangler.toml") or exists("wrangler.jsonc"):
    put("deploy", "wrangler deploy", "wrangler config")
if exists("Dockerfile") and "deploy" not in out:
    put("build", "docker build -t app .", "Dockerfile")
if exists("netlify.toml"):
    put("deploy", "netlify deploy --prod", "netlify.toml")

# CI is the most honest source there is: it is what actually has to pass.
wf = p(".github", "workflows")
if os.path.isdir(wf):
    for f in sorted(os.listdir(wf))[:5]:
        body = read(".github", "workflows", f)
        for line in body.splitlines():
            line = line.strip()
            if line.startswith("run:") and "test" in line and "test" not in out:
                put("test", line[4:].strip(), f".github/workflows/{f}")

for k in ("install", "dev", "build", "test", "lint", "typecheck", "deploy", "deployed"):
    if k in out:
        cmd, why = out[k]
        print(f"{k}\t{cmd}\t{why}")
PY
}

# The confirmation block. One glance, not six questions.
duet_detect_show () {   # <dir>
  local dir="${1:-${DUET_PROJECT:-$PWD}}" n=0
  duet_step "Detected in this project"
  while IFS=$'\t' read -r key cmd why; do
    [ -z "$key" ] && continue
    n=$((n + 1))
    printf '  %-10s %-26s %s\n' "$key" "$cmd" "$why" >&2
  done < <(duet_detect "$dir")
  if [ "$n" = "0" ]; then
    duet_say "  nothing yet. This looks like an empty project."
    duet_say "  The scaffold stage fills these in from the template it uses."
    return 1
  fi
  duet_say ""
  duet_say "  Anything wrong? (enter = all correct)"
  return 0
}

# Store what was detected or corrected. duet_detect_save k=v ...
# Called with no arguments it accepts the detected set as-is.
duet_detect_save () {
  local dir="${DUET_PROJECT:-$PWD}" pair key val
  while IFS=$'\t' read -r key val _; do
    [ -n "$key" ] && duet_cfg_set "commands.$key" "$val" local
  done < <(duet_detect "$dir")
  for pair in "$@"; do
    case "$pair" in
      *=*) key="${pair%%=*}"; val="${pair#*=}"
           duet_cfg_set "commands.${key#commands.}" "$val" local ;;
      *)   duet_warn "expected key=value, got: $pair" ;;
    esac
  done
  duet_ok "commands stored in $(duet_config_local)"
}
