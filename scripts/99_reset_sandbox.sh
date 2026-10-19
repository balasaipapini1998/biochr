#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wipe test branches and PRs so you can re-run cleanly.
# Leaves master, corp-dev, corp-qa, release tags and the workspace alone.
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"

step "Closing open test PRs"
api GET "/repos/$REPO/pulls?state=open&per_page=100" \
  | "$PY" -c "
import sys,json,re
for p in json.load(sys.stdin):
    if re.match(r'^(feature|hotfix|release|revert)/t\d', p['head']['ref']):
        print(p['number'])
" | while read -r n; do pr_close "$n" && info "closed PR #$n"; done

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

step "Release tags kept (rollback needs them)"
git fetch --tags --quiet
git tag -l "cdp-release-*" | sed 's/^/    /' || true

summary
