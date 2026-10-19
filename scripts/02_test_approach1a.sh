#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# APPROACH 1A — auto-promote the feature, merge on approval
#
#   bash scripts/02_test_approach1a.sh
#
# Proves: merging a feature to corp-dev deploys dev, then raises a
# feature -> corp-qa PR automatically with auto-merge enabled; and that
# promotion is FEATURE-level, so an unready feature stays behind.
#
# Disable approach_1b.yml first, or both will fire:
#   gh workflow disable approach_1b.yml
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"
T=$(date +%s | tail -c 4)

gh workflow list --json name,state --jq '.[]|select(.name=="approach_1b" and .state=="active")|.name' \
  | grep -q approach_1b && warn "approach_1b is still enabled — run: gh workflow disable approach_1b.yml"

step "Merging feature A into corp-dev"
make_feature "feature/t${T}-ready" "resources/t${T}ready.txt" "ready for QA"
PR=$(open_pr "feature/t${T}-ready" corp-dev)
gh pr merge "$PR" --merge --admin >/dev/null 2>&1 || gh pr merge "$PR" --merge >/dev/null
pass "merged PR #$PR into corp-dev"

step "Waiting for approach_1a to deploy dev and raise the promotion PR"
C=$(wait_for_run approach_1a.yml 900)
[[ "$C" == "success" ]] && pass "approach_1a run succeeded" || fail "approach_1a run: $C"

sleep 5
PROMO=$(gh pr list --base corp-qa --head "feature/t${T}-ready" --state open \
          --json number --jq '.[0].number // empty')
[[ -n "$PROMO" ]] \
  && pass "promotion PR #$PROMO raised automatically: feature -> corp-qa" \
  || fail "no promotion PR was raised"

if [[ -n "$PROMO" ]]; then
  AM=$(gh pr view "$PROMO" --json autoMergeRequest --jq '.autoMergeRequest != null')
  [[ "$AM" == "true" ]] \
    && pass "auto-merge is enabled — it will merge once approved" \
    || warn "auto-merge not enabled (is 'Allow auto-merge' ON in repo settings?)"
fi

step "SELECTIVITY: a second, NOT-ready feature must stay behind"
make_feature "feature/t${T}-notready" "resources/t${T}notready.txt" "NOT ready"
info "feature 'notready' was never merged to corp-dev, so 1A never fires for it"
NP=$(gh pr list --base corp-qa --head "feature/t${T}-notready" --state open \
       --json number --jq '.[0].number // empty')
[[ -z "$NP" ]] \
  && pass "no promotion PR for the unready feature — promotion is feature-level" \
  || fail "unexpected promotion PR #$NP for an unready feature"

step "Confirm the deployed dev bundle"
info "Check your workspace:  /Users/<you>/.bundle/cdp_sandbox_dev"
info "Jobs UI should show:   cdp_sbx_customer_ingest_dev, cdp_sbx_segment_calc_dev"

git checkout -q master
summary
