# CDP Sandbox — test all three approaches in your own workspace

A complete, self-contained repo for proving Approach 1A, 1B, 2 and rollback
against **one personal Databricks workspace** and **one personal GitHub repo**.

Nothing here touches client code or the client workspace.

```
sandbox/
├── databricks.yml                 3 targets, one workspace
├── resources/
│   ├── job_customer_ingest.yml    present in every release
│   └── job_segment_calc.yml       deleted in release 2 — proves the destroy case
├── src/                           trivial notebooks, never executed
├── .github/
│   ├── CODEOWNERS
│   └── workflows/
│       ├── deploy.yml             main deploy + release tagging
│       ├── pr_validate.yml        bundle validation before merge
│       ├── promotion_gate.yml     APPROACH 2
│       ├── approach_1a.yml        APPROACH 1A
│       ├── approach_1b.yml        APPROACH 1B
│       └── rollback.yml           restore a previous tag
└── scripts/
    ├── lib.sh                     shared helpers
    ├── 00_setup_repo.sh           one-time setup
    ├── 01_test_approach2_gate.sh  6 gate scenarios
    ├── 02_test_approach1a.sh      auto-promote + selectivity
    ├── 03_test_approach1b.sh      fully automatic + conflict handling
    ├── 04_test_rollback.sh        two releases, then roll back
    └── 99_reset_sandbox.sh        wipe test branches and start over
```

---

## How three environments fit in one workspace

Two separations, both defined in `databricks.yml`:

| Target | Root path | Job name suffix |
|---|---|---|
| `corp-dev` | `/Users/<you>/.bundle/cdp_sandbox_dev` | `_dev` |
| `corp-qa` | `/Users/<you>/.bundle/cdp_sandbox_qa` | `_qa` |
| `master` | `/Users/<you>/.bundle/cdp_sandbox_prod` | `_prod` |

After deploying all three, the Jobs UI shows six jobs:

```
cdp_sbx_customer_ingest_dev     cdp_sbx_segment_calc_dev
cdp_sbx_customer_ingest_qa      cdp_sbx_segment_calc_qa
cdp_sbx_customer_ingest_prod    cdp_sbx_segment_calc_prod
```

Each target has its own bundle state, so a deploy to one never disturbs
another — exactly as three separate workspaces behave.

**The jobs have no schedule and are never run.** Deploying costs nothing; only
running a job starts a cluster. Every test here is about deployment mechanics.

---

## Setup (about 20 minutes)

### 1. Create the repo

```bash
gh repo create cdp-sandbox --public --clone
cd cdp-sandbox
# copy the contents of this sandbox/ folder in, then:
git add -A && git commit -m "sandbox baseline" && git push -u origin master
```

> **Make it public.** Branch protection on private repos needs a paid plan.
> Without protection the gate still *runs* and still *fails* correctly — it
> just cannot *block* the merge. There is no client code here, so public is
> fine. `00_setup_repo.sh` warns you if the repo is private.

If your default branch is `main`, rename it:
`git branch -m main master && git push -u origin master`

### 2. Point the bundle at your workspace

Edit `databricks.yml` and set `node_type_id` for your cloud:

| Cloud | Value |
|---|---|
| Azure | `Standard_DS3_v2` |
| AWS | `i3.xlarge` |
| GCP | `n1-standard-4` |

### 3. Add the secrets

```bash
gh secret set DATABRICKS_HOST   # https://adb-xxxx.azuredatabricks.net
gh secret set DATABRICKS_TOKEN  # a PAT from User Settings -> Developer
```

The sandbox uses a PAT instead of Azure OIDC — setting up federated
credentials for a personal workspace is not worth the effort. Everything else
is identical to the client version.

### 4. Run setup

```bash
bash scripts/00_setup_repo.sh
```

Creates `corp-dev` and `corp-qa`, enables auto-merge, restricts merges to
merge-commits, turns **off** delete-on-merge, creates the `emergency-hotfix`
label, and applies branch protection if the repo is public.

### 5. Seed all three environments

```bash
git checkout corp-dev && git merge master && git push
git checkout corp-qa  && git merge master && git push
git checkout master
```

Three deploys run. Check the Jobs UI — six jobs should appear.

---

## The tests

Scripts are bash. On Windows use **Git Bash** (ships with Git for Windows),
not PowerShell. They need `git` and `gh`, both already authenticated.

Every script prints `PASS` / `FAIL` per assertion and a summary at the end.

### Approach 2 — the gate (no Databricks involvement, ~3 min)

```bash
bash scripts/01_test_approach2_gate.sh
```

| # | Scenario | Expected |
|---|---|---|
| 1 | feature → corp-dev → corp-qa, in order | both pass |
| 2 | feature → corp-qa, skipping dev | **blocked** |
| 3 | feature → release/*, skipping QA | **blocked** |
| 4 | same PR with `emergency-hotfix` label | passes, bypass logged |
| 5 | branch cut from corp-dev instead of master | **blocked** |
| 6 | release → master containing code QA never saw | **blocked**, names the commits |

### Approach 1A — auto-promote, merge on approval (~10 min)

```bash
gh workflow disable approach_1b.yml
gh workflow enable  approach_1a.yml
bash scripts/02_test_approach1a.sh
```

Merging a feature into `corp-dev` deploys the dev folder, then raises a
`feature → corp-qa` PR **automatically** with auto-merge enabled. Approve it
and watch GitHub merge it by itself.

It also checks the selectivity claim: a second, unready feature never gets a
promotion PR.

### Approach 1B — fully automatic (~12 min)

```bash
gh workflow disable approach_1a.yml
gh workflow enable  approach_1b.yml
bash scripts/03_test_approach1b.sh
```

Merge once, walk away, and the feature lands in the qa workspace with no human
at any point. Also proves the conflict case: a feature that conflicts with
`corp-qa` **stops the workflow** and leaves `corp-qa` byte-for-byte unchanged.

> Only one of 1A / 1B may be enabled at a time, or both fire on the same merge.

### Rollback (~15 min, the one that changes prod)

```bash
bash scripts/04_test_rollback.sh
```

Builds two real releases and rolls back:

| Stage | Prod folder |
|---|---|
| Release 1 | `customer_ingest_prod` + `segment_calc_prod` |
| Release 2 | `customer_ingest_v2_prod`, **`segment_calc_prod` destroyed** |
| Rollback to release 1 | name reverted, **`segment_calc_prod` re-created** |

Open the deploy logs and read the `create / update / destroy` lines — that is
the whole mechanism visible in one place.

Then check the re-created job's **id**. It is a new one. Run history, alerts
and permissions attached to the old id are gone. That is the rollback caveat,
demonstrated rather than asserted.

### Start over

```bash
bash scripts/99_reset_sandbox.sh
```

Closes test PRs, deletes test branches, resets `corp-dev` and `corp-qa` to
`master`. Release tags are kept, since rollback needs them.

---

## What each test actually proves

| Claim | Proved by |
|---|---|
| The gate blocks environment-skipping | 01, tests 2, 3, 6 |
| Branching from corp-dev is detectable | 01, test 5 |
| Emergency bypass works and is audited | 01, test 4 |
| Promotion is feature-level, not branch-level | 02 and 03, selectivity checks |
| 1A keeps the human approval | 02 — the PR waits for you |
| 1B needs no human at all | 03 — merge once, walk away |
| A conflict cannot half-merge corp-qa | 03, test B |
| Deploying an older tag restores the workspace | 04 |
| A re-created job gets a new id | 04, final check |
| Every release gets a tag | 04 — both releases tagged with no commit-message prefix |

---

## Known differences from the client setup

| | Sandbox | Client |
|---|---|---|
| Auth | Databricks PAT | Azure OIDC federation |
| Environments | 3 folders in 1 workspace | 3 separate workspaces |
| GitHub Environments | not used | used, with required reviewers |
| Approvers | you | Team Lead / release group |
| Branch protection | only if the repo is public | enforced |

The workflow logic, the gate, the promotion chain and the rollback mechanism
are identical. Only authentication and the physical workspace split differ.

---

## Troubleshooting

**`databricks bundle validate` fails on node type** — set `node_type_id` in
`databricks.yml` to a value valid for your cloud.

**Auto-merge not enabled on the promotion PR** — Settings → General → check
"Allow auto-merge".

**The promotion PR cannot be raised** — Settings → General → uncheck
"Automatically delete head branches". The feature branch must survive its
first merge.

**Gate fails on a PR that should pass** — you squash-merged somewhere. Squash
creates new commit ids, so the feature's commits are not found in `corp-dev`.
Merge commits only. (Worth reproducing once deliberately — it is the single
hard requirement of Approach 2.)

**Both 1A and 1B fired** — disable one: `gh workflow disable approach_1b.yml`.

**`gh pr merge --admin` fails** — you are not an admin or the repo is private
without protection. The scripts fall back to a plain merge automatically.
