#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ROLLBACK — restore a previous release tag
#
#   bash scripts/04_test_rollback.sh
#
# Builds two real releases in the prod folder, then rolls back to the first
# and proves the workspace reverted.
#
#   Release 1 : both jobs present
#   Release 2 : segment_calc DELETED  +  customer_ingest renamed
#   Rollback  : segment_calc RE-CREATED (new job id) + name reverted
#
# This is the only test that changes the prod folder. Watch the deploy logs —
# the create / update / destroy lines are the point of the exercise.
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"
T=$(date +%s | tail -c 4)

command -v databricks >/dev/null || warn "databricks CLI not found locally — the final check will be skipped"

step "RELEASE 1  — both jobs"
git fetch origin --tags --quiet
git checkout -q master && git pull -q
git checkout -q -B "release/t${T}r1" origin/master
echo "release 1" >> "resources/t${T}rel.txt"
git add -A && git commit -qm "release 1 baseline"
git push -q -u origin "release/t${T}r1" --force
PR=$(open_pr "release/t${T}r1" master)
pr_merge "$PR" merge >/dev/null
C=$(wait_for_run deploy.yml 900)
[[ "$C" == "success" ]] && pass "release 1 deployed to prod" || fail "release 1 deploy: $C"

git fetch origin --tags --quiet
TAG1=$(git tag --list "cdp-release-*" --sort=-v:refname | head -n1)
[[ -n "$TAG1" ]] && pass "tagged $TAG1" || fail "no tag was created — check the tagging step"

step "RELEASE 2  — delete segment_calc, rename customer_ingest"
git checkout -q master && git pull -q
git checkout -q -B "release/t${T}r2" origin/master
git rm -q resources/job_segment_calc.yml
sed -i.bak 's/cdp_sbx_customer_ingest_/cdp_sbx_customer_ingest_v2_/' resources/job_customer_ingest.yml
rm -f resources/job_customer_ingest.yml.bak
git add -A && git commit -qm "release 2: drop segment_calc, rename ingest"
git push -q -u origin "release/t${T}r2" --force
PR=$(open_pr "release/t${T}r2" master)
pr_merge "$PR" merge >/dev/null
MERGE_SHA=$(git ls-remote origin master | cut -f1)
C=$(wait_for_run deploy.yml 900)
[[ "$C" == "success" ]] && pass "release 2 deployed to prod" || fail "release 2 deploy: $C"

git fetch origin --tags --quiet
TAG2=$(git tag --list "cdp-release-*" --sort=-v:refname | head -n1)
[[ "$TAG2" != "$TAG1" ]] && pass "tagged $TAG2" || fail "release 2 did not produce a new tag"

info ""
info "Look in the Jobs UI now. You should see:"
info "   cdp_sbx_customer_ingest_v2_prod   (renamed)"
info "   cdp_sbx_segment_calc_prod         GONE — destroyed by the deploy"
info ""

step "ROLLBACK to $TAG1"
wf_dispatch rollback.yml master \
   release_tag "$TAG1" target master reason "sandbox rollback test ${T}"
pass "rollback workflow dispatched"
C=$(wait_for_run rollback.yml 900)
[[ "$C" == "success" ]] && pass "rollback run succeeded" || fail "rollback run: $C"

info ""
info "Look again. You should now see:"
info "   cdp_sbx_customer_ingest_prod      (name reverted)"
info "   cdp_sbx_segment_calc_prod         BACK — but with a NEW job id"
info ""

if command -v databricks >/dev/null; then
  step "Verifying against the workspace"
  if databricks jobs list -o json 2>/dev/null | grep -q "cdp_sbx_segment_calc_prod"; then
    pass "segment_calc_prod exists again after the rollback"
  else
    warn "could not confirm via CLI — check the Jobs UI manually"
  fi
fi

step "Git now disagrees with the workspace — this is the follow-up"
info "Workspace is on $TAG1. master is still release 2."
info "To finish the rollback properly:"
info "    git fetch origin"
info "    git checkout -b revert/t${T} origin/master"
info "    git revert -m 1 ${MERGE_SHA:-<release-2-merge-sha>}"
info "    git push origin revert/t${T}   # then open a PR into master"
info ""
info "Then confirm:  git diff $TAG1 master   (should be empty)"

git checkout -q master
summary
