# Secrets

This repository uses **SOPS** with **age** to store Kubernetes secrets **encrypted in Git**.
Git stays the single source of truth – no external secret store, no extra server to run.
Flux decrypts the secrets inside the cluster when applying them.

---

## How it works

```
                    encrypt (public key)                         decrypt (private key)
  plain Secret  ───────────────────────────►  *.sops.yaml in Git  ─────────────────────►  Secret in k3s
  (only in editor,                             (values encrypted,       Flux kustomize-controller
   never on disk)                               metadata readable)      with the "sops-age" secret
```

| Key             | Where it lives                                                         | Purpose           |
|-----------------|------------------------------------------------------------------------|-------------------|
| **Public key**  | `.sops.yaml` (committed)                                               | Encrypt           |
| **Private key** | Local key file, password manager backup, `sops-age` secret in cluster  | Decrypt           |

> ⚠️ **Without the private key all secrets are lost.** It must be backed up outside this repository.

---

## Key management

### Location of the private key (macOS)

```
~/Library/Application Support/sops/age/keys.txt
```

SOPS finds the key there automatically. A different location can be set with
`SOPS_AGE_KEY_FILE`.

### Backup

- The full content of `keys.txt` is stored in the password manager.
- The key is **never** committed – `.gitignore` excludes `*.agekey`, `keys.txt` and `age.txt`.

### Generating a key (only for a fresh setup)

```bash
mkdir -p "$HOME/Library/Application Support/sops/age"
age-keygen -o "$HOME/Library/Application Support/sops/age/keys.txt"
```

The output shows the public key (`age1…`), which goes into `.sops.yaml`.

---

## Configuration (`.sops.yaml`)

```yaml
stores:
  yaml:
    indent: 2

creation_rules:
  - path_regex: (clusters|infrastructure|monitoring|apps)/.*\.sops\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1…
```

| Setting           | Why                                                                                      |
|-------------------|------------------------------------------------------------------------------------------|
| `indent: 2`       | SOPS writes 4-space indentation by default, which fails `yamllint`.                      |
| `path_regex`      | Only matches the Kubernetes folders – not `.sops.yaml` itself, which would otherwise be flagged as "unencrypted" by the SOPS check. |
| `encrypted_regex` | Only values are encrypted. `metadata.name` / `namespace` stay readable, so PR diffs remain understandable. |
| `age`             | Public key – safe to commit, it can only encrypt.                                        |

---

## Conventions

- Encrypted files **must** end with `.sops.yaml`.
- Secrets live **next to the component that uses them** (e.g. `apps/<app>/secret.sops.yaml`).
- Use `stringData` (plain strings) instead of `data` (base64) – easier to edit.
- A secret must be in the **namespace of its consumer** (e.g. the Cloudflare token for a
  `ClusterIssuer` lives in `cert-manager`).

---

## Daily workflow

> Always run SOPS commands from the **repository root**, so `.sops.yaml` is found.

### Create a new secret

```bash
EDITOR=nvim sops edit apps/<app>/secret.sops.yaml
```

Replace the template with:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <name>
  namespace: <namespace>
type: Opaque
stringData:
  <key>: <value>
```

Save and close – SOPS encrypts on exit. The plaintext never ends up permanently on disk.

### View a secret

```bash
sops decrypt apps/<app>/secret.sops.yaml
```

Prints to the terminal only. **Never** redirect the output into a file inside the repository.

### Edit a secret

```bash
sops edit apps/<app>/secret.sops.yaml
```

### Re-encrypt with a new data key / apply new formatting

```bash
sops rotate -i apps/<app>/secret.sops.yaml
```

### After changing recipients in `.sops.yaml`

```bash
sops updatekeys apps/<app>/secret.sops.yaml
```

---

## Safeguards

| Layer      | Check                                                    | Catches                                   |
|------------|----------------------------------------------------------|-------------------------------------------|
| Git        | `.gitignore`                                             | Key files and decrypted copies            |
| pre-commit | `detect-private-key`, `gitleaks`                         | Keys / tokens in a commit                 |
| pre-commit | `sops-encrypted` (`scripts/check-sops-encrypted.sh`)     | `*.sops.yaml` that was not encrypted      |
| CI         | `gitleaks` (full history, `fetch-depth: 0`)              | Secrets anywhere in the Git history       |
| CI         | `sops-encrypted`                                         | Same as above, even with `--no-verify`    |
| GitHub     | Secret scanning + push protection                        | Known token formats are blocked on push   |

An encrypted file is recognised by its `sops:` block and values in the format `ENC[AES256_GCM,…]`.

`kubeconform` skips `Secret` resources on purpose – the `sops:` block would fail strict validation.

---

## Cluster setup (bootstrap)

Flux needs the private key to decrypt. Before `flux bootstrap`, create it once in the cluster:

```bash
kubectl create namespace flux-system
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

Every Flux `Kustomization` that contains secrets needs the decryption block:

```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

---

## Secret inventory

| Secret                 | Namespace      | File                                                              | Source / notes                                                                                   | Expires |
|------------------------|----------------|-------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|---------|
| `cloudflare-api-token` | `cert-manager` | `infrastructure/configs/cluster-issuers/cloudflare-token.sops.yaml` | Cloudflare user API token `cert-manager-caesarlabs` – **DNS: Edit + Zone: Read**, only zone `caesarlabs.org`. Used for Let's Encrypt DNS-01. | never   |

**Planned**

| Secret                       | Namespace     | Purpose                                         |
|------------------------------|---------------|-------------------------------------------------|
| Grafana admin credentials    | `monitoring`  | Grafana login                                   |
| Alertmanager Telegram config | `monitoring`  | Bot token + chat ID for alerts                  |
| Flux notification provider   | `flux-system` | Bot token + chat ID for Flux events             |
| GHCR pull secret             | per app       | Only needed if container images are private     |

> Keep this table up to date: every new secret gets a row. Only note **where** a credential is
> stored (e.g. password manager entry), never the value itself.

---

## Incident handling

### A secret was leaked (committed in plaintext, pasted somewhere, …)

1. **Revoke / rotate it at the provider immediately** (e.g. Cloudflare, Telegram).
   Deleting it from Git does **not** help – it stays in the history and in closed PRs.
2. Update the encrypted file with the new value: `sops edit <file>`.
3. Open a PR, merge, let Flux apply it.

### The age private key was leaked

1. Generate a new key (`age-keygen`) and back it up.
2. Replace the public key in `.sops.yaml`.
3. Run `sops updatekeys` on every `*.sops.yaml`.
4. **Rotate every secret value** at its provider – the old key can decrypt the Git history.
5. Replace the `sops-age` secret in the cluster.

### The age private key was lost

All encrypted values are unrecoverable. Create a new key, then re-create every secret
from its source (password manager / provider).

---

## Troubleshooting

| Problem                                              | Cause / fix                                                                                  |
|------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `yamllint`: `wrong indentation: expected 2 but found 4` | Missing `stores.yaml.indent: 2` in `.sops.yaml`. Add it, then `sops rotate -i <file>`.     |
| `no matching creation rules found`                   | SOPS was not run from the repo root, or the file path does not match `path_regex`.           |
| `failed to get the data key`                         | Private key not found – check the key file location or `SOPS_AGE_KEY_FILE`.                  |
| Flux: `decryption failed`                            | `sops-age` secret missing in `flux-system`, or `decryption` block missing in the Kustomization. |
