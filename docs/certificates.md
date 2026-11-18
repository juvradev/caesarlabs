# Certificates

All HTTPS traffic in the cluster uses certificates from **Let's Encrypt**, issued and renewed
automatically by **cert-manager**. A single **wildcard certificate** for `*.lab.caesarlabs.org`
is used by Traefik as the default certificate for every service.

---

## Overview

```
ClusterIssuer (letsencrypt-staging / letsencrypt-prod)
        │ used by
        ▼
Certificate "wildcard-lab"  ──creates──►  Secret "wildcard-lab-tls"  (namespace traefik)
                                                    │ referenced by
                                                    ▼
                                          TLSStore "default"  ──►  Traefik serves it for every HTTPS request
```

| Component        | Purpose                                                                      |
|------------------|------------------------------------------------------------------------------|
| **cert-manager** | Requests, stores and renews certificates                                      |
| **ClusterIssuer**| Defines *where* certificates come from (Let's Encrypt) and *how* domain ownership is proven (DNS-01 via Cloudflare) |
| **Certificate**  | An "order": which names, which issuer, which secret to store the result in   |
| **TLSStore**     | Traefik resource that makes the wildcard certificate the default             |

---

## How a certificate is issued (DNS-01 challenge)

```
1. cert-manager asks Let's Encrypt for a certificate for *.lab.caesarlabs.org
2. Let's Encrypt: "Prove you own the domain – create this TXT record"
3. cert-manager creates _acme-challenge.lab.caesarlabs.org via the Cloudflare API
4. cert-manager checks the record itself (using public resolvers 1.1.1.1 / 9.9.9.9)
5. Let's Encrypt verifies the record → issues the certificate
6. cert-manager stores it in the secret wildcard-lab-tls and removes the TXT record
7. Renewal happens automatically well before expiry
```

**Why DNS-01:**

- Let's Encrypt does **not** need to reach the server – valid certificates for purely internal
  services, no open ports.
- Wildcard certificates are **only** available via DNS-01.

---

## Issuers: staging vs. prod

| | `letsencrypt-staging` | `letsencrypt-prod` |
|---|---|---|
| Rate limits | Very generous | Strict (failed attempts count) |
| Certificate | **Not trusted** – browser warning, issuer contains "(STAGING)" | Trusted |
| Use for | Testing the whole chain | After staging works |

**Rule:** Always test with staging first. Repeated failures against prod can lock the domain
out for a week.

---

## Why one wildcard certificate

- New services need **no certificate configuration** – just a hostname.
- Fewer requests to Let's Encrypt → no rate-limit issues.
- **Privacy:** every public certificate is published in *Certificate Transparency logs*.
  Individual certificates would expose every service name; the wildcard only shows
  `*.lab.caesarlabs.org`.

**Limits of the wildcard:**

- Covers exactly **one level**: `grafana.lab.caesarlabs.org` ✅,
  `a.b.lab.caesarlabs.org` ❌, `lab.caesarlabs.org` itself ❌.

---

## Using certificates in apps

### Standard Kubernetes Ingress

List the host under `tls` **without** `secretName` – Traefik then serves the default
(wildcard) certificate:

```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: grafana.lab.caesarlabs.org
      # …
  tls:
    - hosts:
        - grafana.lab.caesarlabs.org
```

### Traefik IngressRoute

```yaml
spec:
  entryPoints:
    - websecure
  # …
  tls: {}
```

### A dedicated certificate (exception)

Only needed for names outside `*.lab.caesarlabs.org`: create a separate `Certificate`
in the app's namespace and reference its secret via `secretName`.

---

## Files

| File | Content |
|------|---------|
| `infrastructure/controllers/cert-manager/` | cert-manager HelmRelease (incl. CRDs) |
| `infrastructure/configs/cluster-issuers/letsencrypt-staging.yaml` | Staging ClusterIssuer |
| `infrastructure/configs/cluster-issuers/letsencrypt-prod.yaml` | Prod ClusterIssuer |
| `infrastructure/configs/cluster-issuers/cloudflare-token.sops.yaml` | Cloudflare API token (SOPS) |
| `infrastructure/configs/wildcard-certificate/certificate.yaml` | Wildcard `Certificate` |
| `infrastructure/configs/wildcard-certificate/tlsstore.yaml` | Traefik default `TLSStore` |

The secret `wildcard-lab-tls` is **created by cert-manager** and is not stored in Git.

---

## cert-manager configuration notes

| Value | Why |
|-------|-----|
| `crds.enabled: true` | Installs the CRDs (`Certificate`, `ClusterIssuer`, …) |
| `crds.keep: true` | CRDs survive an uninstall – otherwise all certificates and issuers would be deleted |
| `dns01RecursiveNameservers: "1.1.1.1:53,9.9.9.9:53"` + `dns01RecursiveNameserversOnly: true` | The self-check uses public DNS instead of the router (caching / DNS rebind protection could hide the TXT record) |
| `prometheus.servicemonitor.enabled: false` | Enabled once the monitoring stack (and its CRDs) exist |

---

## Cloudflare API token

| Property | Value |
|----------|-------|
| Name | `cert-manager-caesarlabs` |
| Type | User API token |
| Permissions | **DNS: Edit**, **Zone: Read** |
| Scope | Only zone `caesarlabs.org` |
| Expiry | None – rotate manually if needed |
| Stored in | Password manager + `cloudflare-token.sops.yaml` |

The secret must live in the **`cert-manager`** namespace – ClusterIssuers look up their
secrets there.

**Rotation:** create a new token in Cloudflare → `sops edit` the secret → PR → merge →
delete the old token in Cloudflare.

---

## Go-live procedure (December)

1. Flux applies `infra-controllers` (cert-manager, Traefik) and waits until ready.
2. Flux applies `infra-configs` (issuers, wildcard certificate, TLSStore).
3. Check the staging certificate (see *Operations*). Browser shows a warning with
   "(STAGING)" in the issuer – expected.
4. PR: change `issuerRef.name` in `certificate.yaml` to `letsencrypt-prod`.
   cert-manager re-issues the certificate automatically.
5. Verify the trusted certificate in the browser.
6. **Only then** add HSTS to the `security-headers` middleware – start with
   `stsSeconds: 300`, raise to `31536000` after a week. Never set `stsPreload`.

> ⚠️ HSTS + an untrusted (staging) certificate = browsers block access with no way to proceed.

---

## Operations

### Status

```bash
kubectl get certificate -A
kubectl describe certificate wildcard-lab -n traefik
```

`READY: True` = certificate issued and valid.

### Follow an issuance

```bash
kubectl get certificaterequests,orders,challenges -A
kubectl describe challenge <name> -n traefik
```

### Inspect the served certificate

```bash
echo | openssl s_client -connect traefik.lab.caesarlabs.org:443 \
  -servername traefik.lab.caesarlabs.org 2>/dev/null | openssl x509 -noout -issuer -subject -dates
```

### Force a renewal

```bash
cmctl renew wildcard-lab -n traefik
```

(`cmctl` via `brew install cmctl`.) Alternative without cmctl: delete the secret
`wildcard-lab-tls` – cert-manager recreates it immediately. Safe, because the secret is not
managed in Git.

---

## Monitoring (planned)

- ServiceMonitor for cert-manager.
- Alert when a certificate expires soon, based on
  `certmanager_certificate_expiration_timestamp_seconds` – an unnoticed failed renewal is a
  classic outage.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `Certificate` stays `READY: False` | Check `kubectl describe certificate` and the related `challenge`. |
| Challenge: `Cloudflare API error` / `403` | Token wrong, expired or missing permissions / wrong zone. Verify with Cloudflare's token verify endpoint. |
| Challenge: `secret "cloudflare-api-token" not found` | Secret not in namespace `cert-manager`, or Flux could not decrypt it (missing `decryption` block / `sops-age` secret). |
| Challenge: `propagation check failed` | TXT record not visible yet – wait; check with `dig TXT _acme-challenge.lab.caesarlabs.org @1.1.1.1`. |
| `no matches for kind "ClusterIssuer"` | cert-manager CRDs not installed yet – `infra-configs` must depend on `infra-controllers` with `wait: true`. |
| `429 Too Many Requests` / rate limited | Too many prod attempts – switch back to staging and wait (limits reset after up to a week). |
| Browser shows "TRAEFIK DEFAULT CERT" | Secret `wildcard-lab-tls` missing or TLSStore not applied – check the certificate status. |
| Browser warning with "(STAGING)" issuer | Expected while using `letsencrypt-staging`. |
