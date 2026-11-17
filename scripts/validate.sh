#!/usr/bin/env bash
set -euo pipefail

# download schemas for flux (HelmRelease, kustomization)
SCHEMA_DIR="$(mktemp -d)"
mkdir -p "$SCHEMA_DIR/master-standalone-strict"
curl -sSL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz \
  | tar -xzf - -C "$SCHEMA_DIR/master-standalone-strict"

KUBECONFORM_FLAGS=(
  -strict
  -summary
  -skip Secret
  -ignore-missing-schemas
  -schema-location default
  -schema-location "$SCHEMA_DIR"
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
)

found=0
while IFS= read -r dir; do
  found=1
  echo "==> $dir"
  kustomize build "$dir" | kubeconform "${KUBECONFORM_FLAGS[@]}"
done < <(find . -name kustomization.yaml -not -path './charts/*' -exec dirname {} \; | sort)

if [ "$found" -eq 0 ]; then
  echo "Keine kustomization.yaml gefunden – nichts zu validieren."
fi
