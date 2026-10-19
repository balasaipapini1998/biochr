#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# APPROACH 2 — promotion gate
#
#   bash scripts/01_test_approach2_gate.sh
#
# Proves: correct order passes, skipping an environment is blocked, a branch
# cut from corp-dev is detected, a release containing unseen code is rejected,
# and the emergency label bypasses the gate.
#
# No Databricks involvement — this is pure Git logic.
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"
T=$(date +%s | tail -c 4)      # short run id so branches stay unique

step "TEST 1  Correct order: feature -> corp-dev -> corp-qa"
make_feature "feature/t${T}-a" "resources/t${T}a.txt" "feature A"
PR=$(open_pr "feature/t${T}-a" corp-dev)
[[ "$(gate_conclusion "$PR")" == "SUCCESS" ]] \
  && pass "gate allowed feature -> corp-dev" \
  || fail "gate should have allowed feature -> corp-dev (PR #$PR)"
gh pr merge "$PR" --merge --admin >/dev/null 2>&1 || gh pr merge "$PR" --merge >/dev/null
info "merged into corp-dev"
sleep 5
PR=$(open_pr "feature/t${T}-a" corp-qa)
[[ "$(gate_conclusion "$PR")" == "SUCCESS" ]] \
  && pass "gate allowed feature -> corp-qa (it is in corp-dev)" \
  || fail "gate should have allowed feature -> corp-qa (PR #$PR)"
gh pr merge "$PR" --merge --admin >/dev/null 2>&1 || gh pr merge "$PR" --merge >/dev/null
info "merged into corp-qa"

step "TEST 2  Skipping dev: feature -> corp-qa directly  (must BLOCK)"
make_feature "feature/t${T}-b" "resources/t${T}b.txt" "feature B"
PR=$(open_pr "feature/t${T}-b" corp-qa)
[[ "$(gate_conclusion "$PR")" == "FAILURE" ]] \
  && pass "gate blocked a feature that skipped corp-dev" \
  || fail "gate should have BLOCKED PR #$PR"
gh pr close "$PR" >/dev/null

step "TEST 3  Skipping QA: feature -> release/*  (must BLOCK)"
PR_B=$(open_pr "feature/t${T}-b" corp-dev)
gh pr merge "$PR_B" --merge --admin >/dev/null 2>&1 || gh pr merge "$PR_B" --merge >/dev/null
info "feature B is now in corp-dev but NOT in corp-qa"
git fetch origin --quiet
git push -q origin "origin/master:refs/heads/release/t${T}" 2>/dev/null || true
PR=$(open_pr "feature/t${T}-b" "release/t${T}")
[[ "$(gate_conclusion "$PR")" == "FAILURE" ]] \
  && pass "gate blocked a feature that skipped corp-qa" \
  || fail "gate should have BLOCKED PR #$PR"

step "TEST 4  Emergency bypass"
gh pr edit "$PR" --add-label emergency-hotfix >/dev/null
sleep 5
[[ "$(gate_conclusion "$PR")" == "SUCCESS" ]] \
  && pass "emergency-hotfix label bypassed the gate" \
  || fail "bypass label did not work on PR #$PR"
gh pr edit "$PR" --remove-label emergency-hotfix >/dev/null
gh pr close "$PR" >/dev/null

step "TEST 5  Branch cut from corp-dev instead of master  (must BLOCK)"
git fetch origin --quiet
git checkout -q -B "feature/t${T}-c" origin/corp-dev     # deliberately wrong
echo "feature C" >> "resources/t${T}c.txt"
git add -A && git commit -qm "feature C from the wrong place"
git push -q -u origin "feature/t${T}-c" --force
PR=$(open_pr "feature/t${T}-c" corp-dev)
[[ "$(gate_conclusion "$PR")" == "FAILURE" ]] \
  && pass "gate detected a branch cut from corp-dev" \
  || fail "gate should have BLOCKED PR #$PR"
gh pr close "$PR" >/dev/null

step "TEST 6  Release containing code QA never saw  (must BLOCK)"
git fetch origin --quiet
git checkout -q -B "release/t${T}b" origin/master
git merge -q --no-ff "origin/feature/t${T}-b" -m "add feature B to release"
git push -q -u origin "release/t${T}b" --force
PR=$(open_pr "release/t${T}b" master)
[[ "$(gate_conclusion "$PR")" == "FAILURE" ]] \
  && pass "gate rejected a release holding code QA never saw" \
  || fail "gate should have BLOCKED PR #$PR"
gh pr close "$PR" >/dev/null

git checkout -q master
summary
