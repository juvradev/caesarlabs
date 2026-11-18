#!/usr/bin/env bash
set -euo pipefail

hr='select(.kind == "HelmRelease")'
status=0
checked=0

while IFS= read -r file; do
  name=$(yq "$hr | .metadata.name" "$file")
  namespace=$(yq "$hr | .metadata.namespace" "$file")
  chart=$(yq "$hr | .spec.chart.spec.chart" "$file")
  version=$(yq "$hr | .spec.chart.spec.version" "$file")
  src_kind=$(yq "$hr | .spec.chart.spec.sourceRef.kind" "$file")
  src_name=$(yq "$hr | .spec.chart.spec.sourceRef.name" "$file")
  src_namespace=$(NS="$namespace" yq "$hr | .spec.chart.spec.sourceRef.namespace // env(NS)" "$file")

  echo "==> $file ($chart $version)"

  # HelmRepository only sources are supported, not chartRef or OCIRepository
  if [ "$chart" = "null" ] || [ "$src_kind" != "HelmRepository" ]; then
    echo "unsupported chart source – skipped"
    continue
  fi

  # find matching HelmRepository in the repo
  url=$(grep -rl --include='*.yaml' --exclude-dir=.git '^kind: HelmRepository' . \
    | xargs env NAME="$src_name" NS="$src_namespace" yq ea \
        '[select(.kind == "HelmRepository" and .metadata.name == env(NAME) and .metadata.namespace == env(NS))] | .[0].spec.url')

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "HelmRepository '$src_namespace/$src_name' not found"
    status=1
    continue
  fi

  # HTTPS repo vs OCI registry
  if [[ "$url" == oci://* ]]; then
    chart_args=("${url%/}/$chart")
  else
    chart_args=("$chart" --repo "$url")
  fi

  if [ "$(yq "$hr | .spec.valuesFrom != null" "$file")" = "true" ]; then
    echo "valuesFrom is not checked – only inline values"
  fi

  checked=$((checked + 1))
  if yq "$hr | .spec.values // {}" "$file" \
    | helm template "$name" "${chart_args[@]}" --version "$version" --namespace "$namespace" -f - > /dev/null; then
    echo "values ok"
  else
    echo "values do not match the chart"
    status=1
  fi
done < <(grep -rl --include='*.yaml' --exclude-dir=.git --exclude-dir=charts '^kind: HelmRelease' . || true)

if [ "$checked" -eq 0 ]; then
  echo "No HelmReleases found – nothing to check."
fi

exit "$status"
