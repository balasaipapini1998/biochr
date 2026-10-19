#!/usr/bin/env bash
# Shared helpers. Sourced by every test script.
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

need() { command -v "$1" >/dev/null || { echo "Missing required tool: $1"; exit 1; }; }
need git; need gh

# Wait for the newest run of a workflow to finish. Returns its conclusion.
wait_for_run() {
  local wf="$1" timeout="${2:-600}" waited=0 id status concl
  sleep 8                                   # let GitHub register the run
  id=$(gh run list --workflow "$wf" --limit 1 --json databaseId --jq '.[0].databaseId' || true)
  [[ -z "$id" ]] && { echo "none"; return; }
  while ((waited < timeout)); do
    read -r status concl < <(gh run view "$id" --json status,conclusion \
                              --jq '[.status,.conclusion]|@tsv')
    [[ "$status" == "completed" ]] && { echo "$concl"; return; }
    sleep 10; waited=$((waited+10))
  done
  echo "timeout"
}

# Create a feature branch from master with one commit.
make_feature() {
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

# Open a PR and print its number.
open_pr() {
  local head="$1" base="$2"
  gh pr create --base "$base" --head "$head" \
     --title "$head -> $base" --body "sandbox test" 2>/dev/null \
     | grep -oE '[0-9]+$'
}

# Did the promotion_gate check pass on this PR?
gate_conclusion() {
  local pr="$1" waited=0 c
  sleep 8
  while ((waited < 180)); do
    c=$(gh pr checks "$pr" --json name,state \
          --jq '.[]|select(.name|test("gate"))|.state' 2>/dev/null | head -1 || true)
    [[ "$c" == "SUCCESS" || "$c" == "FAILURE" ]] && { echo "$c"; return; }
    sleep 10; waited=$((waited+10))
  done
  echo "TIMEOUT"
}
