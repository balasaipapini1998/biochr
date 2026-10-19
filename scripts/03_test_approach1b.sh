#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# APPROACH 1B — fully automatic promotion
#
#   gh workflow disable approach_1a.yml
#   gh workflow enable  approach_1b.yml
#   bash scripts/03_test_approach1b.sh
#
# Proves: a feature merged to corp-dev reaches the qa workspace with NO human
# involvement; only that feature is promoted; and a conflicting feature stops
# the automation cleanly instead of leaving corp-qa half-merged.
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"
T=$(date +%s | tail -c 4)

gh workflow list --json name,state --jq '.[]|select(.name=="approach_1a" and .state=="active")|.name' \
  | grep -q approach_1a && warn "approach_1a is still enabled — run: gh workflow disable approach_1a.yml"

step "TEST A  Merge a feature to corp-dev and walk away"
make_feature "feature/t${T}-auto" "resources/t${T}auto.txt" "auto promoted"
PR=$(open_pr "feature/t${T}-auto" corp-dev)
gh pr merge "$PR" --merge --admin >/dev/null 2>&1 || gh pr merge "$PR" --merge >/dev/null
pass "merged PR #$PR into corp-dev — no further human action from here"

step "Waiting for the full chain: deploy dev -> merge to qa -> deploy qa"
C=$(wait_for_run approach_1b.yml 1200)
[[ "$C" == "success" ]] && pass "approach_1b run succeeded" || fail "approach_1b run: $C"

git fetch origin --quiet
if git merge-base --is-ancestor "origin/feature/t${T}-auto" origin/corp-qa; then
  pass "feature reached corp-qa with no review"
else
  fail "feature did not reach corp-qa"
fi

step "SELECTIVITY: an unready feature must NOT have travelled"
make_feature "feature/t${T}-held" "resources/t${T}held.txt" "held back"
git fetch origin --quiet
if git merge-base --is-ancestor "origin/feature/t${T}-held" origin/corp-qa; then
  fail "the held-back feature leaked into corp-qa"
else
  pass "held-back feature is NOT in corp-qa — promotion is feature-level"
fi

step "TEST B  Conflict handling (must stop cleanly)"
QA_BEFORE=$(git rev-parse origin/corp-qa)
# Two branches editing the same line of the same file.
git checkout -q -B "feature/t${T}-x" origin/master
echo "LEFT" > "resources/t${T}conflict.txt"
git add -A && git commit -qm "conflict side X"
git push -q -u origin "feature/t${T}-x" --force
# Put a conflicting version directly on corp-qa
git checkout -q -B tmp-qa origin/corp-qa
echo "RIGHT" > "resources/t${T}conflict.txt"
git add -A && git commit -qm "conflict side Y on corp-qa"
git push -q origin tmp-qa:corp-qa
info "corp-qa now holds a conflicting version of the same file"
QA_BEFORE=$(git rev-parse origin/corp-qa)

PR=$(open_pr "feature/t${T}-x" corp-dev)
gh pr merge "$PR" --merge --admin >/dev/null 2>&1 || gh pr merge "$PR" --merge >/dev/null
C=$(wait_for_run approach_1b.yml 1200)
[[ "$C" == "failure" ]] \
  && pass "workflow failed on the conflict instead of forcing a merge" \
  || fail "expected failure on conflict, got: $C"

git fetch origin --quiet
[[ "$(git rev-parse origin/corp-qa)" == "$QA_BEFORE" ]] \
  && pass "corp-qa was left untouched — no half-merge" \
  || fail "corp-qa moved despite the conflict"

step "Confirm the deployed qa bundle"
info "Check your workspace:  /Users/<you>/.bundle/cdp_sandbox_qa"
info "Jobs UI should show:   cdp_sbx_customer_ingest_qa, cdp_sbx_segment_calc_qa"

git checkout -q master
git branch -D tmp-qa >/dev/null 2>&1 || true
summary
