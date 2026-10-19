#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wipe test branches, PRs and tags so you can re-run from a clean state.
# Does NOT touch master, corp-dev, corp-qa or the Databricks workspace.
#   bash scripts/99_reset_sandbox.sh
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"

step "Closing open test PRs"
gh pr list --state open --json number,headRefName \
  --jq '.[]|select(.headRefName|test("^(feature|hotfix|release|revert)/t[0-9]"))|.number' \
  | while read -r n; do gh pr close "$n" >/dev/null && info "closed PR #$n"; done

step "Deleting test branches"
git fetch origin --prune --quiet
git ls-remote --heads origin | awk '{print $2}' | sed 's|refs/heads/||' \
  | grep -E '^(feature|hotfix|release|revert)/t[0-9]' \
  | while read -r b; do git push -q origin --delete "$b" && info "deleted $b"; done

step "Resetting corp-dev and corp-qa to master"
git fetch origin --quiet
for b in corp-dev corp-qa; do
  git push -q origin "origin/master:refs/heads/$b" --force && pass "$b reset to master"
done

step "Test tags"
git fetch --tags --quiet
info "Release tags kept (needed for rollback tests). Remove manually if you want:"
git tag -l "cdp-release-*" | sed 's/^/    /' || true

summary
