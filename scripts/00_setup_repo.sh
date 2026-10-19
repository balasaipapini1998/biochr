#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-time sandbox setup. Run from inside your cloned sandbox repo.
#
#   bash scripts/00_setup_repo.sh
#
# Creates the branches, sets the repo options the approaches depend on, and
# creates the emergency-hotfix label. Branch protection is applied only if the
# repo is public or you are on a paid plan — it is skipped with a warning
# otherwise (the workflows still RUN, they just cannot BLOCK a merge).
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
step "Sandbox setup for $REPO"

step "Repository options"
gh repo edit --enable-auto-merge --enable-merge-commit \
             --enable-squash-merge=false --enable-rebase-merge=false \
             --delete-branch-on-merge=false
pass "auto-merge ON, merge-commits only, delete-on-merge OFF"

step "Branches"
git fetch origin --quiet
for b in corp-dev corp-qa; do
  if git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    info "$b already exists"
  else
    git branch -f "$b" origin/master >/dev/null
    git push -q origin "$b"
    pass "created $b from master"
  fi
done

step "Label"
gh label create emergency-hotfix --color B60205 \
   --description "Skips the promotion gate — audited" 2>/dev/null \
   && pass "created emergency-hotfix" || info "emergency-hotfix already exists"
gh label create auto-promotion --color 0E8A16 \
   --description "Raised by the promotion workflow" 2>/dev/null >/dev/null || true

step "Branch protection (optional)"
VIS=$(gh repo view --json visibility --jq .visibility)
if [[ "$VIS" != "PUBLIC" ]]; then
  warn "Repo is $VIS. Branch protection needs a public repo or a paid plan."
  warn "The gate will still RUN and FAIL correctly — it just cannot block the merge."
  warn "To test real enforcement, make the repo public: gh repo edit --visibility public"
else
  for b in corp-qa master; do
    gh api -X PUT "repos/$REPO/branches/$b/protection" \
      -H "Accept: application/vnd.github+json" \
      -f "required_status_checks[strict]=false" \
      -f "required_status_checks[contexts][]=gate" \
      -f "enforce_admins=false" \
      -f "required_pull_request_reviews[required_approving_review_count]=0" \
      -f "restrictions=" >/dev/null 2>&1 \
      && pass "protected $b (status check: gate)" \
      || warn "could not protect $b"
  done
fi

step "Secrets checklist"
for s in DATABRICKS_HOST DATABRICKS_TOKEN; do
  gh secret list --json name --jq '.[].name' | grep -qx "$s" \
    && pass "$s is set" \
    || fail "$s is NOT set  ->  gh secret set $s"
done

summary
