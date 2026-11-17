# GitHub settings

All settings for the account and this repository, so the setup can be reproduced or
copied to another repository.

---

## Account settings

| Setting                 | Where                                          | Value / why                                                        |
|-------------------------|------------------------------------------------|--------------------------------------------------------------------|
| Two-factor auth         | *Password and authentication*                  | **Required** – this account controls the cluster.                  |
| SSH key                 | *SSH and GPG keys* → type *Authentication*     | Push without passwords / tokens.                                   |
| Signing key (optional)  | *SSH and GPG keys* → type *Signing key*        | "Verified" commits; allows *Require signed commits* in the ruleset. |
| Email privacy           | *Emails*                                       | ✅ *Keep my email addresses private*<br>✅ *Block command line pushes that expose my email* |
| Notifications           | *Notifications* → *Actions*                    | Only notify on **failed** workflows.                               |

### Git identity

Use the GitHub no-reply address (found under *Settings → Emails*), so commits are linked to
the account without exposing a real email address:

```bash
git config --global user.name "<name>"
git config --global user.email "<id>+<username>@users.noreply.github.com"
git config --global --get-regexp '^user\.'
```

Without this, Git invents an address like `user@hostname.local` – GitHub then treats it as a
different person and adds `Co-authored-by` lines on squash merges.

---

## Repository → Settings → General

**Default branch:** `main`

**Features**

| Option      | Value | Why                                       |
|-------------|-------|-------------------------------------------|
| Wikis       | ❌    | Docs live versioned in `docs/`            |
| Issues      | ✅    | Backlog + Renovate Dependency Dashboard   |
| Discussions | ❌    | Not needed                                |
| Projects    | optional | Only for a kanban board                |

**Pull Requests**

| Option                                          | Value | Why                                                       |
|-------------------------------------------------|-------|-----------------------------------------------------------|
| Allow merge commits                             | ❌    | Avoid messy merge commits                                 |
| Allow squash merging                            | ✅ – *Default to pull request title* | One PR = one commit, easy reverts |
| Allow rebase merging                            | ❌    | One merge method keeps history consistent                 |
| Always suggest updating pull request branches   | ✅    | Shows a button when `main` moved on                       |
| Allow auto-merge                                | ✅    | Required for Renovate automerge                           |
| Automatically delete head branches              | ✅    | Branches are removed after merge                          |

---

## Repository → Settings → Actions → General

| Setting                                  | Value                                                                  |
|------------------------------------------|------------------------------------------------------------------------|
| Actions permissions                      | *Allow \<owner\>, and select non-\<owner\>, actions and reusable workflows* → ✅ *Allow actions created by GitHub*; further actions are added explicitly when needed |
| Require actions to be pinned to a full-length commit SHA | ✅ – protects against hijacked tags                    |
| Fork pull request workflows              | *Require approval for all external contributors*                       |
| Workflow permissions                     | *Read repository contents and packages permissions* (read-only default). Workflows that need more request it explicitly via `permissions:`. |
| Allow GitHub Actions to create and approve pull requests | ❌                                                     |

### Finding the commit SHA of an action

```bash
git ls-remote --tags https://github.com/actions/checkout
```

Use the newest tag. If a line ending in `^{}` exists for it, take **that** SHA (the actual commit,
not the tag object). Reference it with the version as a comment – Renovate keeps both up to date:

```yaml
- uses: actions/checkout@<40-char-sha> # v7.0.1
```

---

## Repository → Settings → Code security

| Option                          | Value | Why                                                         |
|---------------------------------|-------|-------------------------------------------------------------|
| Dependency graph                | ✅    | Required for alerts                                         |
| Dependabot alerts               | ✅    | Notifies about known vulnerabilities                        |
| Dependabot security updates     | ❌    | Renovate handles update PRs – avoids duplicates             |
| Dependabot version updates      | ❌    | Renovate                                                    |
| Secret scanning + push protection | ✅  | Blocks pushes containing known token formats                |
| Code scanning (CodeQL)          | ❌    | Analyses program code – not useful for a YAML repository    |

---

## Repository → Settings → Rules → Ruleset `protect-main`

| Setting            | Value                       |
|--------------------|-----------------------------|
| Enforcement status | Active                      |
| Bypass list        | **Empty** (see bootstrap procedure below) |
| Target branches    | Include default branch      |

| Rule                                    | Value                                                               |
|-----------------------------------------|---------------------------------------------------------------------|
| Restrict deletions                      | ✅                                                                  |
| Block force pushes                      | ✅                                                                  |
| Require linear history                  | ✅                                                                  |
| Require a pull request before merging   | ✅                                                                  |
| ↳ Required approvals                    | **0** – you cannot approve your own PR; 1 would lock you out        |
| ↳ Require conversation resolution       | ✅                                                                  |
| ↳ Allowed merge methods                 | Squash                                                              |
| Require status checks to pass           | ✅ – `yamllint`, `kubeconform`, `gitleaks`, `sops-encrypted`        |
| ↳ Require branches to be up to date     | ✅                                                                  |
| Require signed commits                  | ❌ for now (optional later)                                         |

> Status checks can only be selected after they have **run at least once**. Add a new CI job
> first, merge it, then register it here as required.

> With a free account, rulesets are only **enforced on public repositories**.

---

## Renovate

**GitHub app:** Mend Renovate, installed with *Only select repositories* → this repository only.

**Mend portal settings**

| Setting               | Value | Why                                                                 |
|-----------------------|-------|---------------------------------------------------------------------|
| Dependency Updates    | ✅    |                                                                     |
| Silent mode           | ❌    | Otherwise Renovate only reports in the portal, no PRs / issues      |
| Automated PRs         | ✅    | Otherwise every update waits for approval in the portal             |
| Require config file   | ✅    | Renovate only runs on repositories with their own config            |
| Create onboarding PRs | ✅    | New repositories get a starter config PR                            |

- Configuration lives in `.github/renovate.json5`.
- The **Dependency Dashboard** issue stays open permanently (pinned). Closing it makes Renovate
  create a new one.

---

## Flux bootstrap procedure

`flux bootstrap github` pushes directly to `main` and creates a deploy key. This needs a
temporary token and a temporary ruleset bypass.

### 1. Create a fine-grained personal access token

*Account settings → Developer settings → Personal access tokens → Fine-grained tokens*

| Field               | Value                                   |
|---------------------|-----------------------------------------|
| Repository access   | Only select repositories → this repository |
| Administration      | Read and write (create the deploy key)  |
| Contents            | Read and write (commit `flux-system/`)  |
| Metadata            | Read (set automatically)                |
| Expiration          | 7 days                                  |

### 2. Run the bootstrap

1. Ruleset `protect-main` → bypass list → add **Repository admin**.
2. Run `flux bootstrap github …` (see [bootstrap.md](bootstrap.md)).
3. Ruleset → **remove** the bypass again.
4. **Delete** the token.

Afterwards *Settings → Deploy keys* shows Flux's key with **read-only** access. Flux only
uses this key from now on.

---

## Not needed (for now)

| Setting                                 | Why                                                                 |
|-----------------------------------------|---------------------------------------------------------------------|
| *Secrets and variables → Actions*       | Workflows use the automatic `GITHUB_TOKEN`                          |
| *Environments*                          | Environments are folders in `clusters/`                             |
| Packages / GHCR                         | Only relevant in app repositories. Private images need a pull secret (token with `read:packages`, SOPS-encrypted) in the cluster. |

---

## Lessons from the initial setup

| Situation                                    | What happened / fix                                                         |
|----------------------------------------------|-----------------------------------------------------------------------------|
| Empty repository, feature branch pushed first | GitHub made the **first pushed branch the default branch**. Create `main` first, then `gh repo edit --default-branch main`. |
| Ruleset targets "default branch"             | While the wrong branch was default, the ruleset protected that branch instead of `main`. |
| Empty initial commit on an orphan `main`     | pre-commit found no config and aborted – bypass once with `PRE_COMMIT_ALLOW_NO_CONFIG=1`. |
