# Public cutover

sys-admin went from a private repository with 236 commits to a **public repository with one
squashed commit** (sys-admin#194, map homelab#478, owner decision homelab#465, 16 Nov 2026).
The earlier history stays private in `deanjstone/sys-admin-archive`, which also keeps every old
issue and pull request, the releases and the tags. The model is `deanjstone/skills` (skills#27).

## Why a fresh history, not a rewrite

The audit (homelab#464) found 113 Tailscale addresses and 18 MagicDNS names in the history.
GitHub, on removing sensitive data from a repository: "Rewriting history will change the
hashes of the commits that introduced the sensitive data", and if you only rewrite and force
push, "the commits with sensitive data may still be accessible elsewhere": "Directly via their
SHA-1 hashes in cached views on GitHub", "In any clones or forks of your repository" and
"Through any pull requests that reference them"
([Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
The first step there is to "revoke and/or rotate that secret". None of these values is a
credential: a Tailscale address is unroutable outside the tailnet, so the exposure is the
network's shape, not access. A new repository has no old commits to reach by SHA.

## What a public repository changes

([Setting repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility))
"The code will be visible to everyone who can visit GitHub.com." "Anyone can fork your
repository." "Actions history and logs will be visible to everyone." "Stars and watchers for
this repository will be erased." "All push rulesets will be disabled." "The repository will
automatically gain access to GitHub Advanced Security features." The page says nothing about
transferring issues; skills#27 found that GitHub refuses a transfer from a private to a public
repository, so the script makes the new repository public last.

Forks ([About forks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/about-forks)):
"A fork's visibility depends on the upstream repository." "Public repository forks are public."

Fork pull requests ([Managing GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)):
"By default, all first-time contributors require approval to run workflows." The strictest
policy is "Require approval for all external contributors", which the script sets
(`all_external_contributors`). "Workflows from forks do not have access to sensitive data such
as secrets." But "If you are using self-hosted runners, potentially malicious user-controlled
workflow code will execute automatically", and `pull_request_target` runs "regardless of
approval settings". Hence the rules below.

## The rules the guard test pins

`tests/bats/scripts/public-safe.bats`:

1. Every job runs on `ubuntu-latest`. The only other runner allowed is
   `[self-hosted, homelab, deploy]`, and only in a workflow whose only trigger is a push to
   `deploy`. sys-admin has no such job today: it installs from a checkout at `origin/deploy`
   on the host (`scripts/require-deploy-checkout.sh`), and `Release` runs hosted.
2. No `pull_request_target`; no `CI_RUNS_ON` or `runner.environment`; no action or workflow
   from a private repository of the owner (the old `host-pnpm` action came from `argus`);
   no `BWS_ACCESS_TOKEN`.
3. A workflow a pull request starts reads no secret but `GITHUB_TOKEN` and has top-level
   `permissions: contents: read`.
4. The tree has no private value (`scripts/scrub-scan.sh`: gitleaks' default rules plus rules
   for Tailscale addresses and names, LAN addresses, email addresses, AU mobile numbers,
   Cloudflare ids, Access team domains and full Syncthing device ids). A failing scan prints
   the rule and the place, never the value.

## Private values

Nine values moved to Bitwarden Secrets Manager under the key names in `.env.example`
(`SYS_ADMIN_TAILSCALE_IP_*`, `SYS_ADMIN_TAILSCALE_HOST_*`, `SYS_ADMIN_SYNCTHING_DEVICE_ID_*`).
`scripts/owner-steps/194.sh` creates them from the last old commit that held them
(`6710bb1c0809182ac8bf2e819b0d50f14b928af2`); `scripts/private-value.sh` reads them.

## The cutover (owner step)

```bash
bash scripts/owner-steps/194.sh --dry-run    # reads state, prints every action, changes nothing
bash scripts/owner-steps/194.sh              # the live run: its own approval
```

Run it on WSL2 from a clean checkout of `main` equal to `origin/main`. In order, each step
checking state first, so a stopped run can run again:

1. rename `sys-admin` to `sys-admin-archive` (stays private);
2. create the nine BWS keys (the project of `syncthing-device-homelab`);
3. create `sys-admin` as a private repository with one squashed commit of the scrubbed tree;
4. clone the labels; set any mapped Actions secret from BWS (none today); the `CI_RUNS_ON`
   variable is not recreated;
5. transfer the open issues, except the cutover's own (`194 195`);
6. scan the transferred issues' text; a finding stops the run before step 7 (exit 3);
7. make `sys-admin` public and set the fork approval policy to all external contributors;
8. print the wiring: the ops-hub promotion list (`OPS_HUB_PROMOTION_REPOS`, name unchanged),
   the hub App's repository access, the JIT dispatcher enrolment to remove, issue-number
   references to repoint, and the local checkouts to re-clone on WSL2 and homelab.

It never pushes `deploy`, never runs `promote.sh` and starts no workflow. After it, the owner's
Approve on the ops-hub card creates `deploy` in the new repository.
