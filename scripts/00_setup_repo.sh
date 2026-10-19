#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-time sandbox setup.  No GitHub CLI needed — uses the REST API via curl.
#
#   export GITHUB_TOKEN=ghp_xxxx        (classic PAT, scopes: repo + workflow)
#   bash scripts/00_setup_repo.sh
# ---------------------------------------------------------------------------
source "$(dirname "$0")/lib.sh"

step "Sandbox setup for $REPO"

step "Repository options"
api PATCH "/repos/$REPO" '{
  "allow_auto_merge": true,
  "allow_merge_commit": true,
  "allow_squash_merge": false,
  "allow_rebase_merge": false,
  "delete_branch_on_merge": false
}' >/dev/null
pass "auto-merge ON · merge-commits only · delete-on-merge OFF"

step "Branches"
git fetch origin --quiet
for b in corp-dev corp-qa; do
  if git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    info "$b already exists"
  else
    git push -q origin "origin/master:refs/heads/$b"
    pass "created $b from master"
  fi
done

step "Labels"
c=$(label_create emergency-hotfix B60205 "Skips the promotion gate — audited")
[[ "$c" == "201" ]] && pass "created emergency-hotfix" || info "emergency-hotfix already exists"
label_create auto-promotion 0E8A16 "Raised by the promotion workflow" >/dev/null

step "Branch protection (optional)"
VIS=$(repo_visibility)
if [[ "$VIS" != "public" ]]; then
  warn "Repo is '$VIS'. Branch protection needs a public repo or a paid plan."
  warn "The gate will still RUN and FAIL correctly — it just cannot block a merge."
  warn "For real enforcement, make the repo public in Settings -> General -> Danger Zone."
else
  for b in corp-qa master; do
    code=$(api_code PUT "/repos/$REPO/branches/$b/protection" '{
      "required_status_checks": {"strict": false, "contexts": ["gate"]},
      "enforce_admins": false,
      "required_pull_request_reviews": {"required_approving_review_count": 0},
      "restrictions": null
    }')
    [[ "$code" == "200" ]] && pass "protected $b (required check: gate)" \
                           || warn "could not protect $b (HTTP $code)"
  done
fi

step "Secrets"
for s in DATABRICKS_HOST DATABRICKS_TOKEN; do
  if secret_exists "$s"; then
    pass "$s is set"
  else
    fail "$s is NOT set — add it in Settings -> Secrets and variables -> Actions"
  fi
done

step "Workflows found"
api GET "/repos/$REPO/actions/workflows" \
  | "$PY" -c "import sys,json;[print('    '+w['path'].split('/')[-1].ljust(22)+w['state']) for w in json.load(sys.stdin).get('workflows',[])]" \
  2>/dev/null || info "(none registered yet — push to master first)"

summary
