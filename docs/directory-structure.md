# Directory structure
### explanation of directory structure

- `.github/` – github actions workflows with checks and renovate configuration
- `apps/` – applications, one directory per app with own namespace
- `charts/` - custom helm charts, selfwritten only
- `clusters/` – fluxdb entrypoint per cluster; defines which layers are deployed in which order
- `docs/` – documentation
- `infrastructure/` – cluster foundation: `controllers` (e.g. traefik or cert-manager) and `configs` (e.g. ClusterIssuer)
- `monitoring/` –  obervability stack: `controllers`: Prometheus, Grafana, Alertmanager, Loki, Alloy and `configs`: dashboards and alerts
- `scripts` - helper scripts used locally and in the CI (manifest validation, SOPS check)
- `.gitignore` - files which never getting tracked
- `.pre-commit-config.yaml` - local checks that run before every commit (yamllint, gitleaks, SOPS check)
- `.sops.yaml` - SOPS rules: which files get encrypted and with which age public key
- `.yamllint.yaml` - YAML linting rules shared by pre-commit and CI
- `README.md` - Project Overview
