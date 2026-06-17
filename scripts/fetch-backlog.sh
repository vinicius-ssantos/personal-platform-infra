#!/bin/bash
# fetch-backlog.sh — Fetch all open issues from every platform repo and
# output a prioritized markdown snapshot.
#
# Usage:
#   bash scripts/fetch-backlog.sh [options] [output-file]
#
# Options:
#   --ttl N    Cache TTL in minutes (reuse cached data if fresh)
#   --prs      Include open PRs alongside issues
#
# Examples:
#   just backlog
#   just backlog --ttl 5
#   just backlog --prs docs/prs-snapshot.md
#
# Requires: gh (GitHub CLI) authenticated, python3

set -euo pipefail

# ====================================================================
# Config
# ====================================================================
CONFIG_FILE="docs/repos.json"
CACHE_DIR=".tmp-backlog"
CACHE_FILE="$CACHE_DIR/cache.json"

TTL=""
INCLUDE_PRS=false
OUTPUT=""

# ====================================================================
# Parse args
# ====================================================================
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ttl)
      TTL="$2"; shift 2 ;;
    --prs)
      INCLUDE_PRS=true; shift ;;
    -*)
      echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      OUTPUT="$1"; shift ;;
  esac
done
OUTPUT="${OUTPUT:-docs/backlog-snapshot.md}"

# ====================================================================
# Helpers
# ====================================================================
GH_BIN=""
for candidate in gh gh.exe; do
  if command -v "$candidate" &>/dev/null; then
    GH_BIN="$candidate"
    break
  fi
done

MKTEMP() {
  if command -v mktemp &>/dev/null; then
    mktemp
  else
    printf '/tmp/backlog-%s-%s' "$(date +%s)" "$$"
  fi
}

MKTEMP_DIR() {
  if command -v mktemp &>/dev/null; then
    mktemp -d
  else
    local d="/tmp/backlog-$(date +%s)-$$"
    mkdir -p "$d"
    printf '%s' "$d"
  fi
}

info()  { printf "[INFO]  %s\n" "$*" >&2; }
ok()    { printf "[OK]    %s\n" "$*" >&2; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; }

cleanup() {
  [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

# ====================================================================
# Pre-flight
# ====================================================================
if [ -z "$GH_BIN" ]; then
  error "gh (GitHub CLI) not found."
  exit 1
fi
if ! "$GH_BIN" auth status 2>/dev/null; then
  error "Not authenticated. Run '$GH_BIN auth login'."
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  error "python3 not found."
  exit 1
fi
if [ ! -f "$CONFIG_FILE" ]; then
  error "Config file not found: $CONFIG_FILE"
  exit 1
fi

# ====================================================================
# Read config
# ====================================================================
OWNER=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['owner'])")
REPOS_JSON=$(python3 -c "
import json
print(json.dumps(json.load(open('$CONFIG_FILE'))['repos']))
")
eval "REPOS=($(python3 -c "
import json
repos = json.load(open('$CONFIG_FILE'))['repos']
print(' '.join(f'\"{r}\"' for r in repos))
"))"

# ====================================================================
# Cache check
# ====================================================================
CACHE_HIT=false
if [ -n "$TTL" ] && [ -f "$CACHE_FILE" ]; then
  CACHE_AGE=$(python3 -c "
import os, time
try:
    age = int(time.time() - os.path.getmtime('$CACHE_FILE'))
    print(age)
except:
    print('999999')
")
  if [ "$CACHE_AGE" -lt "$((TTL * 60))" ]; then
    info "Cache hit ($CACHE_AGE sec old, TTL=${TTL}min)"
    CACHE_HIT=true
  else
    info "Cache expired ($CACHE_AGE sec old, TTL=${TTL}min)"
  fi
fi

# ====================================================================
# Fetch
# ====================================================================
if [ "$CACHE_HIT" = true ]; then
  cp "$CACHE_FILE" "$(MKTEMP)"
  DATA_FILE=$(MKTEMP)
  python3 -c "
import json
d = json.load(open('$CACHE_FILE'))
json.dump(d['data'], open('$DATA_FILE', 'w'))
"
else
  TMPDIR=$(MKTEMP_DIR)
  ISSUES_DIR="$TMPDIR/issues"
  mkdir -p "$ISSUES_DIR"

  info "Fetching ${#REPOS[@]} repos from $OWNER ..."

  # Parallel fetch — each repo writes to own JSON file
  for repo in "${REPOS[@]}"; do
    (
      FULL="$OWNER/$repo"
      OUTFILE="$ISSUES_DIR/$repo.json"

      # Fetch issues
      "$GH_BIN" issue list \
        -R "$FULL" \
        --state open \
        --json number,title,state,labels,assignees,createdAt,updatedAt,body \
        --limit 100 2>/dev/null \
      > "$OUTFILE" || {
        echo "[]" > "$OUTFILE"
        warn "  Could not fetch $FULL — skipping"
        exit 0
      }

      # Tag with repo metadata
      python3 -c "
import json
issues = json.load(open('$OUTFILE'))
for i in issues:
    i['repo'] = '$repo'
    i['full_repo'] = '$FULL'
    i['type'] = 'issue'
json.dump(issues, open('$OUTFILE', 'w'))
" 2>/dev/null

      # Optionally fetch PRs
      if [ "$INCLUDE_PRS" = true ]; then
        PR_FILE=$(mktemp)
        "$GH_BIN" pr list \
          -R "$FULL" \
          --state open \
          --json number,title,state,labels,assignees,createdAt,updatedAt,headRefName \
          --limit 100 2>/dev/null \
        > "$PR_FILE" || true

        if [ -s "$PR_FILE" ]; then
          python3 -c "
import json
existing = json.load(open('$OUTFILE'))
prs = json.load(open('$PR_FILE'))
for p in prs:
    p['repo'] = '$repo'
    p['full_repo'] = '$FULL'
    p['type'] = 'pr'
    p['body'] = ''
    p['headRefName'] = p.get('headRefName', '')
existing.extend(prs)
json.dump(existing, open('$OUTFILE', 'w'))
" 2>/dev/null
        fi
        rm -f "$PR_FILE"
      fi

      count=$(python3 -c "import json; print(len(json.load(open('$OUTFILE'))))" 2>/dev/null || echo "0")
      ok "  $FULL — $count items"
    ) &
  done

  wait
  echo ""

  # Merge all per-repo JSONs into one
  DATA_FILE=$(MKTEMP)
  python3 -c "
import json, glob, sys
all_issues = []
for f in sorted(glob.glob('$ISSUES_DIR/*.json')):
    try:
        all_issues.extend(json.load(open(f)))
    except:
        pass
json.dump(all_issues, open('$DATA_FILE', 'w'))
print(len(all_issues))
" 2>&1 | while read n; do info "Merged $n total items"; done

  # Update cache if TTL is set
  if [ -n "$TTL" ]; then
    mkdir -p "$CACHE_DIR"
    python3 -c "
import json, time
data = json.load(open('$DATA_FILE'))
json.dump({'fetched_at': time.time(), 'data': data}, open('$CACHE_FILE', 'w'))
"
    info "Cache written to $CACHE_FILE"
  fi
fi

# ====================================================================
# Generate Markdown
# ====================================================================
info "Generating $OUTPUT ..."

PYSCRIPT=$(MKTEMP)
cat > "$PYSCRIPT" <<'PYEOF'
import json, sys, os
from datetime import datetime, timezone

data_file = sys.argv[1]
repos_json = sys.argv[2]
output_file = sys.argv[3]

issues = json.load(open(data_file))
REPOS = json.loads(repos_json)

# --- Priority scoring ---
def score(i):
    text = (i.get("title") or "") + " "
    text += " ".join(l.get("name","") for l in (i.get("labels") or []))
    tl = text.lower()
    s = 0
    if any(w in tl for w in ["bug","fix ","security","blocker","broken","crash",
                              "emergency","ops: validate","ops: configure"]):
        s += 100
    if any(w in tl for w in ["feat","feature","ci: add","ci: route","implement",
                              "migration","prep","initialize","controlled operation"]):
        s += 50
    for l in (i.get("labels") or []):
        n = l.get("name","").lower()
        if n in ("bug","security","blocker","critical","high"): s += 80
        if n in ("enhancement","feature","ci","infrastructure"): s += 40
    b = (i.get("body") or "").lower()
    if any(w in b for w in ["blocker","acceptance criteria","deploy","production"]): s += 20
    return s

def prio_label(s):
    if s >= 100: return "🔴 High"
    if s >= 50:  return "🟡 Medium"
    return "🟢 Low"

def fmt_date(d):
    return (d or "")[:10]

def days_open(d):
    if not d: return ""
    try:
        created = datetime.fromisoformat(d.replace("Z", "+00:00"))
        delta = datetime.now(timezone.utc) - created
        days = delta.days
        if days < 1: return "today"
        if days == 1: return "1 day"
        return f"{days} days"
    except:
        return ""

def assignee_str(a):
    if not a:
        return "—"
    return ", ".join(u.get("login","?") for u in a)

OWNER = "vinicius-ssantos"

issues.sort(key=lambda i: (-score(i), i.get("repo",""), i.get("number",0)))

# Separate issues and PRs
pure_issues = [i for i in issues if i.get("type","issue") == "issue"]
prs = [i for i in issues if i.get("type") == "pr"]
show_prs = len(prs) > 0

# Group by repo
by_repo = {}
for i in issues:
    by_repo.setdefault(i.get("repo","unknown"), []).append(i)

repo_order = [r for r in REPOS if r in by_repo] + [r for r in by_repo if r not in REPOS]

# Count stats
def count_by_repo(items):
    cnt = {"total": len(items), "high": 0, "med": 0, "low": 0}
    for i in items:
        s = score(i)
        if s >= 100: cnt["high"] += 1
        elif s >= 50: cnt["med"] += 1
        else: cnt["low"] += 1
    return cnt

lines = []
now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
lines.append(f"# Backlog Snapshot  ({now_str})")
lines.append("")
lines.append(f"> **{len(pure_issues)} open issues** | {len(prs)} open PRs | {len(REPOS)} repos")
lines.append("")

# --- Summary table ---
lines.append("## Summary")
lines.append("")
lines.append("| Repo | Issues | 🔴 High | 🟡 Med | 🟢 Low | PRs |")
lines.append("|:---|---:|---:|---:|---:|---:|")
grand = {"issues": 0, "high": 0, "med": 0, "low": 0, "prs": 0}
for r in repo_order:
    items = by_repo[r]
    r_issues = [i for i in items if i.get("type","issue") == "issue"]
    r_prs = [i for i in items if i.get("type") == "pr"]
    cnt = count_by_repo(r_issues)
    pr_count = len(r_prs)
    rurl = f"https://github.com/{OWNER}/{r}"
    lines.append(f"| [{r}]({rurl}) | {cnt['total']} | {cnt['high']} | {cnt['med']} | {cnt['low']} | {pr_count} |")
    grand["issues"] += cnt["total"]
    grand["high"] += cnt["high"]
    grand["med"] += cnt["med"]
    grand["low"] += cnt["low"]
    grand["prs"] += pr_count
lines.append(f"| **Total** | **{grand['issues']}** | **{grand['high']}** | **{grand['med']}** | **{grand['low']}** | **{grand['prs']}** |")
lines.append("")

# --- Issues by Repository ---
lines.append("---")
lines.append("## Issues by Repository")
lines.append("")

for r in repo_order:
    items = by_repo[r]
    r_issues = [i for i in items if i.get("type","issue") == "issue"]
    r_prs = [i for i in items if i.get("type") == "pr"]
    if not r_issues and not r_prs:
        continue
    rurl = f"https://github.com/{OWNER}/{r}"

    if r_issues:
        lines.append(f"### [{r}]({rurl}) — {len(r_issues)} issues")
        lines.append("")
        lines.append("| # | Title | Prio | Labels | Age | Assignee | Updated |")
        lines.append("|---|---|:---:|---|---|---|---|")
        for i in r_issues:
            s = score(i)
            num = i.get("number", 0)
            t = i.get("title","").strip()
            labels_str = ", ".join(l.get("name","") for l in (i.get("labels") or [])) or "—"
            age = days_open(i.get("createdAt",""))
            assignee = assignee_str(i.get("assignees"))
            updated = fmt_date(i.get("updatedAt",""))
            url = f"{rurl}/issues/{num}"
            lines.append(f"| [#{num}]({url}) | {t} | {prio_label(s)} | {labels_str} | {age} | {assignee} | {updated} |")
        lines.append("")

    if r_prs and show_prs:
        lines.append(f"<details><summary>Open PRs ({len(r_prs)})</summary>")
        lines.append("")
        lines.append("| # | Title | Branch | Prio | Labels | Age | Assignee |")
        lines.append("|---|---|:---:|:---:|---|---|---|")
        for p in r_prs:
            s = score(p)
            num = p.get("number", 0)
            t = p.get("title","").strip()
            branch = p.get("headRefName","")
            labels_str = ", ".join(l.get("name","") for l in (p.get("labels") or [])) or "—"
            age = days_open(p.get("createdAt",""))
            assignee = assignee_str(p.get("assignees"))
            url = f"{rurl}/pull/{num}"
            lines.append(f"| [#{num}]({url}) | {t} | `{branch}` | {prio_label(s)} | {labels_str} | {age} | {assignee} |")
        lines.append("")
        lines.append("</details>")
        lines.append("")

# --- All Issues (Flat) ---
lines.append("---")
lines.append("## All Items (Flat)")
lines.append("")
lines.append("| # | Repo | Type | Title | Prio | Labels | Age | Assignee | Created |")
lines.append("|---:|:---|:---:|:---|:---:|---|---|---|---|")
for i in issues:
    s = score(i)
    num = i.get("number", 0)
    r = i.get("repo","")
    typ = "🔀PR" if i.get("type") == "pr" else "🐛IS"
    t = i.get("title","").strip()
    labels_str = ", ".join(l.get("name","") for l in (i.get("labels") or [])) or "—"
    age = days_open(i.get("createdAt",""))
    assignee = assignee_str(i.get("assignees"))
    created = fmt_date(i.get("createdAt",""))
    url = f"https://github.com/{OWNER}/{r}/issues/{num}"
    lines.append(f"| [#{num}]({url}) | {r} | {typ} | {t} | {prio_label(s)} | {labels_str} | {age} | {assignee} | {created} |")

out = "\n".join(lines)
with open(output_file, "w", encoding="utf-8") as f:
    f.write(out)
print(f"Written {len(pure_issues)} issues + {len(prs)} PRs to {output_file}")
PYEOF

# Execute Python markdown generator
python3 "$PYSCRIPT" "$DATA_FILE" "$REPOS_JSON" "$OUTPUT"

# Clean temp script (DATA_FILE cleaned by trap on EXIT)
rm -f "$PYSCRIPT"
echo ""
ok "Done — $OUTPUT generated"