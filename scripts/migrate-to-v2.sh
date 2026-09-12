#!/usr/bin/env bash
# migrate-to-v2.sh — one-time migration of aibox v1 data into the v2
# aibox-home volume. Standalone: not part of the aibox CLI, run it once.
#
# Usage:
#   ./migrate-to-v2.sh [--map OLD_PATH=NEW_PATH]... [old-backup-dir ...]
#
# Steps (numbered like the sections below; the volume is created first if
# missing):
#   1. Merges every `aibox-auth-*` Docker volume (v1 kept one per image
#      string) into aibox-home. Sources are mounted READ-ONLY and are never
#      modified or deleted.
#   2. Merges any old backup folders passed as arguments. Two layouts are
#      accepted: a folder that *is* a Claude config dir (contains
#      .claude.json / projects/), or a folder containing a `.claude/` dir
#      (with .claude.json beside or inside it).
#   3. Merges `.claude.json`: the newest copy is the base, and the
#      `projects` map is merged across all copies with newest-wins per key.
#      (All other files merge file-by-file, no-clobber — each session is
#      its own .jsonl keyed by UUID, so a plain union is correct.)
#   4. `--map OLD=NEW` rekeys sessions recorded under a container-side path
#      (v1 --copy/--worktree used /workspace/...) to a real host path, e.g.
#      --map /workspace/myapp=/Users/me/code/myapp. Renames both the
#      projects/<escaped-path> directories and the .claude.json keys.
#      Matching respects path boundaries (/workspace/myapp does not match
#      /workspace/myapp2), but escaping is lossy — /a/b, /a.b and /a-b all
#      escape identically — so only use --map for paths you recognize.
#   5. Normalizes ownership to uid 1000 (the v2 container user).
#
# Idempotent: run it twice and the second run copies nothing new. Merges
# never overwrite an existing file, and nothing in the destination is
# deleted unless it is byte-identical to the copy at its mapped location.
# The script ends by PRINTING the cleanup commands for old
# volumes/containers — it never runs them. Verify sessions in v2 first.

set -euo pipefail
unset CDPATH

VOLUME="aibox-home"
HELPER_IMAGE="alpine:3.20"

info() { echo "· $*"; }
ok()   { echo "✓ $*"; }
die()  { echo "✗ $*" >&2; exit 1; }

usage() { awk '/^# migrate/,/^[^#]/{if(/^#/) print}' "$0" | sed 's/^# \{0,1\}//'; }

command -v docker >/dev/null 2>&1 || die "docker not found"
docker info >/dev/null 2>&1 || die "Docker daemon not running"
command -v python3 >/dev/null 2>&1 || die "python3 not found (needed for the .claude.json merge)"

# Must byte-match Claude Code's own project-path escaping (used for
# projects/<escaped-cwd> dir names) — do not "improve" its lossiness.
escape() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'; }

# ── Args ─────────────────────────────────────────────────────────
MAPS=()          # OLD=NEW pairs
BACKUP_DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --map)
      [[ "${2:-}" == *=* ]] || die "--map needs OLD_PATH=NEW_PATH"
      old="${2%%=*}"; new="${2#*=}"
      [[ -n "$old" && -n "$new" ]] || die "--map: OLD and NEW must both be non-empty"
      [[ "$(escape "$old")" == "$(escape "$new")" ]] \
        && die "--map ${2}: OLD and NEW escape to the same key ($(escape "$old")) — refusing (escaping turns every non-alphanumeric character into '-')"
      MAPS+=("$2"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      [[ -d "$1" ]] || die "Not a directory: $1"
      dir_abs="$(cd "$1" && pwd)"
      [[ "$dir_abs" == *:* ]] && die "Backup dir path contains ':' — docker cannot mount it: ${dir_abs}"
      BACKUP_DIRS+=("$dir_abs"); shift ;;
  esac
done

if docker ps -q --filter label=aibox.instance | grep -q .; then
  info "WARNING: v1 aibox containers are RUNNING. For a consistent snapshot,"
  info "         stop them first (aibox down / docker stop <name>). Continuing anyway."
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

docker volume create "$VOLUME" >/dev/null 2>&1 || true
docker run --rm -v "${VOLUME}:/dst" "$HELPER_IMAGE" mkdir -p /dst/.claude

# ── Helpers ──────────────────────────────────────────────────────
# --map pairs in escaped form ("old=new;old2=new2") so the copy step can
# land files directly at their mapped path (keeps re-runs copy-free).
# ';' and '=' are safe separators: escaped keys contain only [a-zA-Z0-9-].
# (${arr[@]+"${arr[@]}"} throughout: empty-array expansion is an error
# under set -u on macOS bash 3.2.)
ESC_MAPS=""
for m in ${MAPS[@]+"${MAPS[@]}"}; do
  ESC_MAPS="${ESC_MAPS}$(escape "${m%%=*}")=$(escape "${m#*=}");"
done

# Copy everything except .claude.json from /src into /dst/.claude,
# entry-by-entry (files and symlinks), never overwriting; paths under
# projects/ are rewritten through ESC_MAPS with path-boundary matching
# (OLD exactly, OLD/<file>, or OLD-<subproject>). Copies go via a temp name
# so an interrupted run never leaves a truncated file that blocks re-runs.
# Prints the number of entries copied; failures and skipped
# newline-containing names go to stderr.
COPY_SCRIPT='map_path() {
  case "$1" in projects/*) ;; *) printf "%s" "$1"; return;; esac
  rest="${1#projects/}"
  oldifs="$IFS"; IFS=";"
  for pair in $ESC_MAPS; do
    old="${pair%%=*}"; new="${pair#*=}"
    case "$rest" in
      "$old")   rest="$new"; break;;
      "$old"/*) rest="${new}${rest#"$old"}"; break;;
      "$old"-*) rest="${new}${rest#"$old"}"; break;;
    esac
  done
  IFS="$oldifs"
  printf "projects/%s" "$rest"
}
cd /src || exit 1
lines=$(find . \( -type f -o -type l \) | wc -l)
true_count=$(find . \( -type f -o -type l \) -exec printf x \; | wc -c)
[ "$lines" -eq "$true_count" ] \
  || echo "WARNING: source has file names containing newlines - those files are NOT copied" >&2
find . \( -type f -o -type l \) ! -path "./.claude.json" | while IFS= read -r f; do
  s="${f#./}"
  [ -e "./$s" ] || [ -L "./$s" ] || continue   # newline-split fragment of a bad name
  d="$(map_path "$s")"
  if [ ! -e "/dst/.claude/$d" ] && [ ! -L "/dst/.claude/$d" ]; then
    mkdir -p "/dst/.claude/$(dirname "$d")" \
      && cp -a "./$s" "/dst/.claude/$d.aibox-tmp" \
      && mv "/dst/.claude/$d.aibox-tmp" "/dst/.claude/$d" \
      && echo x \
      || echo "COPY FAILED: $s" >&2
  fi
done | wc -l'

# Save one source .claude.json into staging as <mtime>.<n>.json — this
# filename is the wire format parsed by the Python merge step below.
# mtime 0 is the "file absent" sentinel (see host_mtime and _read_json).
JSON_N=0
stage_json() {  # $1 = mtime, stdin = content
  local content
  content="$(cat)"
  [[ -z "$content" || -z "$1" || "$1" == "0" ]] && return 0
  JSON_N=$((JSON_N + 1))
  printf '%s' "$content" > "${STAGING}/${1}.${JSON_N}.json"
}

_copy_into_dst() {  # $1 = docker mount source (volume name or host dir)
  docker run --rm -e ESC_MAPS="$ESC_MAPS" -v "${1}:/src:ro" -v "${VOLUME}:/dst" \
    "$HELPER_IMAGE" sh -c "$COPY_SCRIPT"
}

_read_json() {  # $1 = mount source, $2 = .claude.json path inside it → "mtime\ncontent"
  docker run --rm -v "${1}:/src:ro" "$HELPER_IMAGE" sh -c \
    "stat -c %Y '/src/${2}' 2>/dev/null || echo 0; cat '/src/${2}' 2>/dev/null || true"
}

merge_from_volume() {  # $1 = volume name
  local vol="$1" copied meta content
  copied="$(_copy_into_dst "$vol")"
  { read -r meta; content="$(cat)"; } <<< "$(_read_json "$vol" .claude.json)"
  # Not a pipeline: stage_json must run in this shell so JSON_N increments
  # (same-mtime sources would otherwise overwrite each other in staging).
  stage_json "$meta" <<< "$content"
  ok "volume ${vol}: ${copied// /} new file(s)"   # wc pads with spaces on some platforms
}

host_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

merge_from_dir() {  # $1 = backup dir
  local dir="$1" src jsons=() j
  if [[ -d "${dir}/.claude" ]]; then
    src="${dir}/.claude"
    [[ -f "${dir}/.claude.json" ]] && jsons+=("${dir}/.claude.json")
    [[ -f "${dir}/.claude/.claude.json" ]] && jsons+=("${dir}/.claude/.claude.json")
    [[ -d "${dir}/projects" ]] \
      && info "note: ${dir} has BOTH .claude/ and a top-level projects/ — using .claude/, ignoring the top-level projects/"
  elif [[ -d "${dir}/projects" || -f "${dir}/.claude.json" ]]; then
    src="$dir"
    [[ -f "${dir}/.claude.json" ]] && jsons+=("${dir}/.claude.json")
  else
    info "skipping ${dir}: no Claude data recognized (expected .claude/ or projects/)"
    return 0
  fi
  local copied
  copied="$(_copy_into_dst "$src")"
  for j in ${jsons[@]+"${jsons[@]}"}; do
    stage_json "$(host_mtime "$j")" < "$j"
  done
  ok "backup ${dir}: ${copied// /} new file(s)"
}

# ── 1. Live v1 volumes ───────────────────────────────────────────
AUTH_VOLS="$(docker volume ls --format '{{.Name}}' | grep '^aibox-auth-' || true)"
if [[ -n "$AUTH_VOLS" ]]; then
  while IFS= read -r vol; do
    merge_from_volume "$vol"
  done <<< "$AUTH_VOLS"
else
  info "no aibox-auth-* volumes found"
fi

# ── 2. Old backup folders ────────────────────────────────────────
for dir in ${BACKUP_DIRS[@]+"${BACKUP_DIRS[@]}"}; do
  merge_from_dir "$dir"
done

# ── 3. Merge .claude.json ────────────────────────────────────────
# Include the destination's CURRENT .claude.json as a source. In v2 the
# volume root is /home/aibox, so the live file sits at .claude/.claude.json
# relative to the volume root — without this, a re-run after using v2 would
# rebuild the file from old sources only and lose v2-era state.
{ read -r DST_META; DST_CONTENT="$(cat)"; } <<< "$(_read_json "$VOLUME" .claude/.claude.json)"
stage_json "$DST_META" <<< "$DST_CONTENT"

if ls "${STAGING}"/*.json >/dev/null 2>&1; then
  python3 - "$STAGING" ${MAPS[@]+"${MAPS[@]}"} <<'PY'
import json, sys, glob, os
staging = sys.argv[1]
maps = [m.split("=", 1) for m in sys.argv[2:]]
sources = []
for path in glob.glob(os.path.join(staging, "*.json")):
    parts = os.path.basename(path).split(".")
    order = (int(parts[0]), int(parts[1]))   # (mtime, staging seq) — stable ties
    try:
        with open(path) as f:
            doc = json.load(f)
    except (json.JSONDecodeError, ValueError):
        print(f"· skipping unparseable {os.path.basename(path)}", file=sys.stderr)
        continue
    if not isinstance(doc, dict):
        print(f"· skipping non-object .claude.json ({os.path.basename(path)})", file=sys.stderr)
        continue
    sources.append((order, doc))
sources.sort(key=lambda s: s[0])
if not sources:
    sys.exit(0)
base = dict(sources[-1][1])            # newest copy wins for oauth etc.
projects = {}
for _, doc in sources:                 # oldest→newest: newest wins per key
    p = doc.get("projects", {})
    if isinstance(p, dict):
        projects.update(p)
for old, new in maps:
    old = old.rstrip("/")
    for key in list(projects):
        if key == old or key.startswith(old + "/"):
            newkey = new + key[len(old):] if key != old else new
            # setdefault: on a collision the existing (new-path) entry wins
            # and the popped one is dropped — same no-clobber rule as files.
            projects.setdefault(newkey, projects.pop(key))
base["projects"] = projects
with open(os.path.join(staging, "merged.out"), "w") as f:
    json.dump(base, f, indent=2)
print(f"· merged .claude.json from {len(sources)} source(s), {len(projects)} project(s)")
PY
  if [[ -f "${STAGING}/merged.out" ]]; then
    # Pipe via stdin, don't bind-mount: $STAGING is under macOS's /var/folders,
    # which Colima doesn't share into its VM (the mount appears empty there).
    docker run --rm -i -v "${VOLUME}:/dst" "$HELPER_IMAGE" \
      sh -c 'cat > /dst/.claude/.claude.json && chmod 600 /dst/.claude/.claude.json' \
      < "${STAGING}/merged.out"
    ok "wrote merged .claude.json"
  fi
else
  info "no .claude.json found in any source"
fi

# ── 4. --map: rename session directories already in the volume ───
# New copies are mapped at copy time; this handles data that landed in the
# volume before the map was applied (an earlier migration run). It must
# stay: step 3 rekeys .claude.json unconditionally, so leaving old dirs
# unmoved would orphan those sessions (key/dir mismatch).
# Safety rules: never touch a dir that IS the target or is itself a mapped
# target; move whole entries no-clobber; delete a leftover file only when it
# is byte-identical to the copy at the target; leave anything else in place
# with a warning. Nothing here can destroy data that exists nowhere else.
for m in ${MAPS[@]+"${MAPS[@]}"}; do
  esc_old="$(escape "${m%%=*}")"
  esc_new="$(escape "${m#*=}")"
  docker run --rm -v "${VOLUME}:/dst" -e OLD="$esc_old" -e NEW="$esc_new" "$HELPER_IMAGE" sh -c '
    base=/dst/.claude/projects
    for d in "$base/$OLD" "$base/$OLD"-*; do
      [ -d "$d" ] || continue
      case "$d" in "$base/$NEW"|"$base/$NEW"-*) continue;; esac   # already a mapped target
      rest="${d#"$base/$OLD"}"
      tgt="$base/${NEW}${rest}"
      [ "$d" = "$tgt" ] && continue
      if [ ! -e "$tgt" ] && [ ! -L "$tgt" ]; then
        mv "$d" "$tgt" && echo "moved $(basename "$d") -> $(basename "$tgt")"
        continue
      fi
      ( cd "$d" || exit 1
        find . -mindepth 1 | sort | while IFS= read -r f; do
          f="${f#./}"
          [ -e "./$f" ] || [ -L "./$f" ] || continue   # parent already moved
          if [ ! -e "$tgt/$f" ] && [ ! -L "$tgt/$f" ]; then
            mkdir -p "$tgt/$(dirname "$f")" && mv "./$f" "$tgt/$f"
          elif [ -f "./$f" ] && [ ! -L "./$f" ] && [ -f "$tgt/$f" ] && cmp -s "./$f" "$tgt/$f"; then
            rm "./$f"   # identical duplicate — safe to drop
          fi
        done )
      find "$d" -depth -type d -empty -exec rmdir {} \; 2>/dev/null || true
      if [ -d "$d" ]; then
        echo "WARNING: kept $(basename "$d") — it still holds entries that differ from $(basename "$tgt"); reconcile manually" >&2
      else
        echo "merged $(basename "$d") into $(basename "$tgt")"
      fi
    done'
done

# ── 5. Normalize ownership for the v2 container user (uid 1000) ──
docker run --rm -v "${VOLUME}:/dst" "$HELPER_IMAGE" chown -R 1000:1000 /dst
ok "ownership normalized (uid 1000)"

# ── Summary ──────────────────────────────────────────────────────
TOTAL="$(docker run --rm -v "${VOLUME}:/v:ro" "$HELPER_IMAGE" sh -c 'find /v -type f | wc -l')"
SESSIONS="$(docker run --rm -v "${VOLUME}:/v:ro" "$HELPER_IMAGE" sh -c 'find /v/.claude/projects -name "*.jsonl" 2>/dev/null | wc -l')"
echo ""
ok "Done. ${VOLUME} now holds ${TOTAL// /} file(s), ${SESSIONS// /} session file(s)."
echo ""
echo "Verify with:  cd <a project> && aibox claude --resume"
echo ""
echo "Nothing was deleted. Once you've verified v2 sees your sessions, clean up"
echo "the old v1 resources manually:"
# v1 labels: aibox.instance = project containers, aibox.pf.target = socat
# port-forward helpers. Docker names contain no whitespace, so unquoted
# expansion into printf is safe.
V1_CONTAINERS="$(docker ps -a --filter label=aibox.instance --format '{{.Names}}' || true)"
V1_PORTFWD="$(docker ps -a --filter label=aibox.pf.target --format '{{.Names}}' || true)"
# shellcheck disable=SC2086
{
  [[ -n "$V1_CONTAINERS$V1_PORTFWD" ]] && printf '  docker rm -f %s\n' $V1_CONTAINERS $V1_PORTFWD
  [[ -n "$AUTH_VOLS" ]] && printf '  docker volume rm %s\n' $AUTH_VOLS
  [[ -z "$V1_CONTAINERS$V1_PORTFWD$AUTH_VOLS" ]] && echo "  (none found)"
  true
}
