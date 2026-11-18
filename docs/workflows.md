# Workflow

How changes get from my laptop into the cluster.

---

## Principles

- **`main` is the truth.** It always reflects the desired state of the cluster. Flux only reads `main`.
- **No manual changes in the cluster.** No `kubectl apply`, `kubectl edit` or `helm install` by hand –
  Flux would revert them anyway. `kubectl` / `k9s --readonly` are for **reading and debugging** only.
- **Environments are folders, not branches.** Each cluster has its own folder in `clusters/`.
  There are no `develop` / `staging` branches.
- **Every change goes through a pull request** and must pass all CI checks before merging.

```
main ───●──────────●──────────●──────────●──────►   (only long-lived branch)
         \        /  \        /  \        /
         feat/traefik  feat/cert-manager  fix/grafana-ingress
         (short-lived, deleted after merge)
```

---

## Branch naming

`<type>/<short-description>`

| Prefix      | Use for                                        | Example                       |
|-------------|------------------------------------------------|-------------------------------|
| `feat/`     | New component or app                           | `feat/loki-alloy`             |
| `fix/`      | Repairing something broken                     | `fix/grafana-ingress-host`    |
| `chore/`    | Maintenance, versions, housekeeping            | `chore/renovate-group-gitleaks` |
| `ci/`       | Changes to GitHub Actions workflows            | `ci/add-flux-diff`            |
| `docs/`     | Documentation only                             | `docs/network`                |
| `refactor/` | Restructuring without changing cluster state   | `refactor/split-monitoring`   |
| `renovate/` | Created automatically by Renovate              | –                             |

---

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org), written in the **imperative**
("add", not "added") – a message completes the sentence *"This commit will …"*.

```
feat: add letsencrypt cluster issuers (staging + prod)
fix(monitoring): correct grafana ingress host
chore: bump kubeconform to 0.8.0
docs: add secrets documentation
```

The optional scope in parentheses names the area (`monitoring`, `infrastructure`, `ci`, …).

---

## Step by step

### 1. Start from an up-to-date `main`

```bash
git switch main && git pull && git switch -c feat/<name>
```

### 2. Make the change

- One topic per branch, keep PRs small.
- Add a component **and** register it in the parent `kustomization.yaml` in the same PR.
- Update documentation in the same PR as the change it describes.
- Validate locally before pushing:

```bash
./scripts/validate.sh
```

### 3. Commit

```bash
git add . && git commit -m "feat: add traefik"
```

pre-commit runs automatically (whitespace, yamllint, gitleaks, SOPS check, …).

- If a hook **modified files** ("files were modified by this hook"): `git add .` and commit again.
- If a hook **failed**: fix the reported line and commit again.
- The very first run takes longer – pre-commit downloads its hook environments once.

### 4. Push and open a pull request

```bash
git push -u origin feat/<name>
gh pr create --fill
```

`--fill` takes title and description from the commit(s).

### 5. CI checks

| Check            | Workflow       | What it does                                              |
|------------------|----------------|-----------------------------------------------------------|
| `yamllint`       | validate       | YAML syntax and formatting (`--strict`: warnings fail)    |
| `kubeconform`    | validate       | `kustomize build` + schema validation of all manifests    |
| `gitleaks`       | security       | Secret scan over the full Git history                     |
| `sops-encrypted` | security       | All `*.sops.yaml` files are really encrypted              |
| `helm-values`    | validate       | Renders every HelmRelease with its values against the chart's schema |
```bash
gh pr checks        # status in the terminal
gh pr view --web    # open the PR in the browser
```

Merging is blocked until all required checks are green.

### 6. Review and merge

- Read the diff on GitHub (self-review).
- Merge with **squash** – one PR becomes exactly one commit on `main`.

```bash
gh pr merge --squash --delete-branch
```

### 7. Clean up locally

```bash
git switch main && git pull && git fetch --prune
git branch -D feat/<name>
```

`-D` (capital) is required after a squash merge: Git does not recognise the squash commit
as a merge of the branch, so `-d` refuses.

Tip – prune automatically on every fetch/pull:

```bash
git config --global fetch.prune true
```

### 8. Flux applies the change

Flux polls `main` and reconciles the cluster. Status / immediate sync:

```bash
flux get kustomizations
flux reconcile kustomization flux-system --with-source
```

---

## Rollback

Never fix a broken cluster by hand. Revert the PR instead – the revert goes through
the same pipeline:

```bash
git switch main && git pull && git switch -c fix/revert-<name>
git revert <commit-sha-of-the-squash-merge>
git push -u origin fix/revert-<name>
gh pr create --fill
```

Small, single-topic PRs make reverts clean.

---

## Updating a branch when `main` has moved

```bash
git fetch && git rebase origin/main
git push --force-with-lease
```

- Force-pushing is **fine on your own feature branch** after a rebase.
- `--force-with-lease` only overwrites if nobody else pushed in the meantime.
- Force-pushing to `main` is blocked by the ruleset – and that is intended.

---

## Abandoning a branch

```bash
git switch main
gh pr close <branch> --delete-branch
```

If the PR was already closed, delete the branch manually:

```bash
git push origin --delete <branch>   # on GitHub
git branch -D <branch>              # locally
git fetch --prune
```

> ⚠️ Closed PRs and their commits stay visible on GitHub. If a **real** secret was ever pushed,
> revoke it at the provider immediately – see [secrets.md](secrets.md).

---

## Renovate pull requests

Renovate opens PRs for new versions of Helm charts, images, GitHub Actions, pre-commit hooks
and CI tools. They run through the same checks.

| Update type                                     | Handling                                   |
|-------------------------------------------------|--------------------------------------------|
| CI tooling (actions, pre-commit, CI tool versions) – minor / patch / digest | **Automerged** once all checks are green |
| Everything else (Helm charts, images, major updates) | Reviewed and merged manually         |

Overview of all dependencies and open updates: the pinned **Dependency Dashboard** issue.

---

## Cheat sheet

| Task                              | Command                                    |
|-----------------------------------|--------------------------------------------|
| New branch                        | `git switch main && git pull && git switch -c <type>/<name>` |
| Open PR                           | `gh pr create --fill`                      |
| List PRs                          | `gh pr list`                               |
| Check status                      | `gh pr checks`                             |
| Squash merge                      | `gh pr merge --squash --delete-branch`     |
| All branches (local + remote)     | `git branch -a`                            |
| Clean up after merge              | `git switch main && git pull && git fetch --prune && git branch -D <branch>` |

---

## Common pitfalls

| Symptom                                                  | Cause / fix                                                                 |
|----------------------------------------------------------|-----------------------------------------------------------------------------|
| Shell shows continuation lines (`•`) after `git commit`  | Missing closing `"` in the commit message – `Ctrl+C` and retype.           |
| `error: src refspec <branch> does not match any`         | The branch has no commit yet – usually a pre-commit hook aborted the commit. Check `git log --oneline`. |
| pre-commit passes, CI `yamllint` fails                   | pre-commit must run yamllint with `--strict` too (`args: [--strict]`).      |
| `missing starting space in comment`                      | Write `# comment`, not `#comment`.                                          |
| A branch with an odd name appears (e.g. `delete`)        | `git branch <name>` **creates** a branch. Delete with `git branch -D <name>`. |
