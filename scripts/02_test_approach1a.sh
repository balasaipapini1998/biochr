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
# The script disables approach_1b for you if it is still active.
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"
T=$(date +%s | tail -c 4)

[[ "$(wf_state approach_1b.yml)" == "active" ]] && \
  warn "approach_1b is still enabled — disabling it now" && wf_disable approach_1b.yml
[[ "$(wf_state approach_1a.yml)" != "active" ]] && wf_enable approach_1a.yml

step "Merging feature A into corp-dev"
make_feature "feature/t${T}-ready" "resources/t${T}ready.txt" "ready for QA"
PR=$(open_pr "feature/t${T}-ready" corp-dev)
pr_merge "$PR" merge >/dev/null
pass "merged PR #$PR into corp-dev"

step "Waiting for approach_1a to deploy dev and raise the promotion PR"
C=$(wait_for_run approach_1a.yml 900)
[[ "$C" == "success" ]] && pass "approach_1a run succeeded" || fail "approach_1a run: $C"

sleep 5
PROMO=$(pr_find "feature/t${T}-ready" corp-qa)
[[ -n "$PROMO" ]] \
  && pass "promotion PR #$PROMO raised automatically: feature -> corp-qa" \
  || fail "no promotion PR was raised"

if [[ -n "$PROMO" ]]; then
  AM=$(pr_automerge "$PROMO")
  [[ -n "$AM" ]] \
    && pass "auto-merge is enabled — it will merge once approved" \
    || warn "auto-merge not enabled (is 'Allow auto-merge' ON in repo settings?)"
fi

step "SELECTIVITY: a second, NOT-ready feature must stay behind"
make_feature "feature/t${T}-notready" "resources/t${T}notready.txt" "NOT ready"
info "feature 'notready' was never merged to corp-dev, so 1A never fires for it"
NP=$(pr_find "feature/t${T}-notready" corp-qa)
[[ -z "$NP" ]] \
  && pass "no promotion PR for the unready feature — promotion is feature-level" \
  || fail "unexpected promotion PR #$NP for an unready feature"

step "Confirm the deployed dev bundle"
info "Check your workspace:  /Users/<you>/.bundle/cdp_sandbox_dev"
info "Jobs UI should show:   cdp_sbx_customer_ingest_dev, cdp_sbx_segment_calc_dev"

git checkout -q master
summary
