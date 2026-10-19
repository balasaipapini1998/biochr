#!/usr/bin/env bash
# ===========================================================================
# Shared helpers — GitHub REST API over curl. No GitHub CLI required.
#
# Needs only: git, curl, python3   (all present in Git Bash + a Python install)
#
# Authentication: a classic Personal Access Token with scopes  repo  workflow
#   Create at: https://github.com/settings/tokens  (Tokens classic)
#   Then either:
#       export GITHUB_TOKEN=ghp_xxxxxxxx
#   or put it in a file next to the repo root called  .sandbox-env :
#       GITHUB_TOKEN=ghp_xxxxxxxx
#   (.sandbox-env is listed in .gitignore — never commit a token)
# ===========================================================================
set -euo pipefail

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
PASSED=0; FAILED=0

step()  { echo; echo "${BOLD}==> $*${OFF}"; }
info()  { echo "    $*"; }
pass()  { PASSED=$((PASSED+1)); echo "    ${GREEN}PASS${OFF}  $*"; }
fail()  { FAILED=$((FAILED+1)); echo "    ${RED}FAIL${OFF}  $*"; }
warn()  { echo "    ${YEL}WARN${OFF}  $*"; }

summary() {
  echo
  echo "${BOLD}-------------------------------------------${OFF}"
  printf "  %sPassed: %d%s    %sFailed: %d%s\n" "$GREEN" "$PASSED" "$OFF" \
         "$( ((FAILED>0)) && echo "$RED" || echo "$OFF")" "$FAILED" "$OFF"
  echo "${BOLD}-------------------------------------------${OFF}"
  ((FAILED==0))
}

# ---------------------------------------------------------------- deps ----
PY=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [[ -z "$PY" ]]; then
  echo "ERROR: python3 is required (used only to read JSON responses)."
  echo "       Install from https://www.python.org/downloads/ and reopen Git Bash."
  exit 1
fi
command -v curl >/dev/null || { echo "ERROR: curl not found"; exit 1; }
command -v git  >/dev/null || { echo "ERROR: git not found";  exit 1; }

# --------------------------------------------------------------- token ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${GITHUB_TOKEN:-}" && -f "$SCRIPT_DIR/../.sandbox-env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../.sandbox-env"
fi
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: no token. Create a classic PAT (scopes: repo, workflow) at"
  echo "       https://github.com/settings/tokens   then run:"
  echo "         export GITHUB_TOKEN=ghp_xxxxxxxx"
  echo "       or create .sandbox-env in the repo root containing that line."
  exit 1
fi

# ---------------------------------------------------------------- repo ----
ORIGIN_URL="$(git remote get-url origin)"
REPO="$(printf '%s' "$ORIGIN_URL" | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
OWNER="${REPO%%/*}"

# ----------------------------------------------------------------- api ----
# api METHOD /path [json-body]       -> prints the response body
api() {
  local method="$1" path="$2" body="${3:-}" url
  if [[ "$path" == http* ]]; then url="$path"; else url="https://api.github.com$path"; fi
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      --data "$body"
  else
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28"
  fi
}

# api_code METHOD /path [json]       -> prints only the HTTP status code
api_code() {
  local method="$1" path="$2" body="${3:-}" url
  if [[ "$path" == http* ]]; then url="$path"; else url="https://api.github.com$path"; fi
  if [[ -n "$body" ]]; then
    curl -sS -o /dev/null -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" -H "Content-Type: application/json" --data "$body"
  else
    curl -sS -o /dev/null -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28"
  fi
}

# jget '<json>' 'a.b[0].c'           -> prints the value, or empty
# JSON goes through a temp file: python cannot read its own script from stdin
# AND the data from stdin, and Windows has a short command-line limit.
jget() {
  local tmp; tmp=$(mktemp)
  printf '%s' "$1" > "$tmp"
  "$PY" -c '
import sys, json
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print(""); sys.exit()
cur = d
try:
    for part in sys.argv[2].split("."):
        if not part:
            continue
        while part.endswith("]"):
            name, _, idx = part[:-1].rpartition("[")
            if name:
                cur = cur[name]
            cur = cur[int(idx)]
            part = ""
        if part:
            cur = cur[part]
except Exception:
    print(""); sys.exit()
print("" if cur is None else cur)
' "$tmp" "$2"
  rm -f "$tmp"
}

# jobj k1 v1 k2 v2 ...               -> a flat JSON object (strings)
jobj() {
  "$PY" - "$@" <<'PYEOF'
import sys, json
a = sys.argv[1:]
print(json.dumps(dict(zip(a[0::2], a[1::2]))))
PYEOF
}

# ------------------------------------------------------- pull requests ----
pr_create() {   # head base title body  -> prints PR number
  local resp
  resp=$(api POST "/repos/$REPO/pulls" "$(jobj head "$1" base "$2" title "$3" body "$4")")
  local n; n=$(jget "$resp" 'number')
  if [[ -z "$n" ]]; then
    echo "pr_create failed: $(jget "$resp" 'message')" >&2
    return 1
  fi
  printf '%s' "$n"
}

pr_find() {     # head base -> PR number of the open PR, or empty
  jget "$(api GET "/repos/$REPO/pulls?head=$OWNER:$1&base=$2&state=open")" '[0].number'
}

pr_merge() {    # number [merge|squash|rebase]
  local out; out=$(api PUT "/repos/$REPO/pulls/$1/merge" "$(jobj merge_method "${2:-merge}")")
  if [[ "$(jget "$out" 'merged')" == "True" ]]; then return 0; fi
  echo "    merge of PR #$1 refused: $(jget "$out" 'message')" >&2
  return 1
}

pr_close() {    # number
  api PATCH "/repos/$REPO/pulls/$1" "$(jobj state closed)" >/dev/null
}

pr_label_add()    { api POST   "/repos/$REPO/issues/$1/labels" "{\"labels\":[\"$2\"]}" >/dev/null; }
pr_label_remove() { api DELETE "/repos/$REPO/issues/$1/labels/$2" >/dev/null 2>&1 || true; }

pr_head_sha()  { jget "$(api GET "/repos/$REPO/pulls/$1")" 'head.sha'; }
pr_automerge() { jget "$(api GET "/repos/$REPO/pulls/$1")" 'auto_merge.merge_method'; }

# Enable auto-merge. REST cannot do this; it is a GraphQL mutation.
pr_enable_automerge() {   # number
  local nid q resp
  nid=$(jget "$(api GET "/repos/$REPO/pulls/$1")" 'node_id')
  [[ -z "$nid" ]] && return 1
  q=$("$PY" - "$nid" <<'PYEOF'
import sys, json
print(json.dumps({
  "query": "mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:MERGE}){clientMutationId}}",
  "variables": {"id": sys.argv[1]}
}))
PYEOF
)
  resp=$(api POST "https://api.github.com/graphql" "$q")
  printf '%s' "$resp" | grep -q '"errors"' && return 1
  return 0
}

# --------------------------------------------------------- check status ---
# check_state SHA NAME_SUBSTRING -> conclusion (success/failure) or status
check_state() {
  local tmp; tmp=$(mktemp)
  api GET "/repos/$REPO/commits/$1/check-runs?per_page=100" > "$tmp"
  "$PY" -c '
import sys, json
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print(""); sys.exit()
needle = sys.argv[2].lower()
out = ""
for c in d.get("check_runs", []):
    if needle in (c.get("name") or "").lower():
        out = c.get("conclusion") or c.get("status") or ""
        break
print(out)
' "$tmp" "$2"
  rm -f "$tmp"
}

# gate_conclusion PR -> SUCCESS | FAILURE | TIMEOUT
gate_conclusion() {
  local pr="$1" sha waited=0 s
  sleep 8
  sha=$(pr_head_sha "$pr")
  while ((waited < 240)); do
    s=$(check_state "$sha" "gate")
    case "$s" in
      success) echo "SUCCESS"; return ;;
      failure|cancelled|timed_out) echo "FAILURE"; return ;;
    esac
    sleep 10; waited=$((waited+10))
  done
  echo "TIMEOUT"
}

# ------------------------------------------------------------ workflows ---
wf_latest_run() { jget "$(api GET "/repos/$REPO/actions/workflows/$1/runs?per_page=1")" 'workflow_runs[0].id'; }

# wait_for_run WORKFLOW_FILE [timeout] -> conclusion
wait_for_run() {
  local wf="$1" timeout="${2:-600}" waited=0 id resp status concl
  sleep 10
  id=$(wf_latest_run "$wf")
  [[ -z "$id" ]] && { echo "none"; return; }
  while ((waited < timeout)); do
    resp=$(api GET "/repos/$REPO/actions/runs/$id")
    status=$(jget "$resp" 'status'); concl=$(jget "$resp" 'conclusion')
    [[ "$status" == "completed" ]] && { echo "$concl"; return; }
    sleep 10; waited=$((waited+10))
  done
  echo "timeout"
}

wf_disable() { api_code PUT "/repos/$REPO/actions/workflows/$1/disable" >/dev/null; }
wf_enable()  { api_code PUT "/repos/$REPO/actions/workflows/$1/enable"  >/dev/null; }
wf_state()   { jget "$(api GET "/repos/$REPO/actions/workflows/$1")" 'state'; }

# wf_dispatch FILE REF k1 v1 k2 v2 ...
wf_dispatch() {
  local file="$1" ref="$2"; shift 2
  local body
  body=$("$PY" - "$ref" "$@" <<'PYEOF'
import sys, json
ref = sys.argv[1]; a = sys.argv[2:]
print(json.dumps({"ref": ref, "inputs": dict(zip(a[0::2], a[1::2]))}))
PYEOF
)
  api POST "/repos/$REPO/actions/workflows/$file/dispatches" "$body" >/dev/null
}

# ----------------------------------------------------------------- repo ---
repo_visibility() { jget "$(api GET "/repos/$REPO")" 'visibility'; }
secret_exists()   { api GET "/repos/$REPO/actions/secrets?per_page=100" | grep -q "\"name\":\"$1\""; }

label_create() {  # name color description
  api_code POST "/repos/$REPO/labels" "$(jobj name "$1" color "$2" description "$3")"
}

# ------------------------------------------------------------- git bits ---
make_feature() {  # branch file content  — always cut from master
  local name="$1" file="$2" content="${3:-change}"
  git fetch origin --quiet
  git checkout -q -B "$name" origin/master
  mkdir -p "$(dirname "$file")"
  echo "$content" >> "$file"
  git add "$file"
  git commit -qm "$name: $content"
  git push -q -u origin "$name" --force
  info "created $name from master"
}

open_pr() { pr_create "$1" "$2" "$1 -> $2" "sandbox test"; }
