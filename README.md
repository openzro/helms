<div align="center">
  <img width="120" src="https://raw.githubusercontent.com/openzro/openzro/main/brand/openzro-icon.svg" alt="openZro"/>
  <h1>openZro Helm Charts</h1>
  <p>
    <strong>Helm charts for self-hosting the openZro control plane and Kubernetes operator.</strong>
  </p>

  <p>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3-7c3aed" alt="BSD-3-Clause"/></a>
    <a href="https://github.com/openzro/openzro/blob/main/docs/adr/0008-kubernetes-helm-operator.md"><img src="https://img.shields.io/badge/ADR-0008-7c3aed" alt="ADR-0008"/></a>
  </p>
</div>

---

This repo holds three Helm charts for openZro deployments on Kubernetes:

| Chart | Purpose | Current version |
|---|---|---|
| [`charts/openzro`](charts/openzro/) | Control plane: management + signal + relay + dashboard + Dex IdP | `2.0.0-alpha.3` (appVersion `0.53.1-alpha.1`) |
| [`charts/openzro-operator`](charts/openzro-operator/) | Kubernetes operator (CRDs reconcile peers / groups / policies / setup keys / network resources) | `0.3.2-alpha.1` |
| [`charts/openzro-operator-config`](charts/openzro-operator-config/) | Operator runtime config (mTLS certs etc.) | `0.1.0` |

For the architecture rationale, see
[ADR-0008](https://github.com/openzro/openzro/blob/main/docs/adr/0008-kubernetes-helm-operator.md)
in the core repo. For the Dex IdP that the chart bundles by default see
[ADR-0006](https://github.com/openzro/openzro/blob/main/docs/adr/0006-embed-dex.md).

## Install

```bash
# Add the helm repo (gh-pages → Cloudflare-fronted)
helm repo add openzro https://openzro.github.io/helms
helm repo update

# Install the control plane
helm install openzro openzro/openzro \
  --create-namespace -n openzro \
  -f my-values.yaml

# Optional: install the K8s operator
helm install openzro-operator openzro/openzro-operator -n openzro
```

A modern OCI install path is also available
(`oci://ghcr.io/openzro/charts/openzro:2.0.0-alpha.3`) — see the OCI
section below.

For the full operator-facing walk-through (values overrides, Gateway
API instead of Ingress, image pull-secret caveat for private GHCR
packages, troubleshooting), see
[`docs/operator/k8s-deployment-guide.md`](https://github.com/openzro/openzro/blob/main/docs/operator/k8s-deployment-guide.md)
in the core repo.

## What the charts produce

`helm template openzro openzro/openzro` renders ~28 Kubernetes resources:

- 5 Deployments — `openzro-management`, `openzro-signal`, `openzro-relay`,
  `openzro-dashboard`, plus the Dex subchart's deployment
- 5 Services — one per Deployment, plus a separate gRPC Service for
  management
- 5 ServiceAccounts + RBAC
- 4 Ingress (or HTTPRoute/GRPCRoute when `gatewayApi.enabled: true`)
- 1 ConfigMap + 1 PVC (Dex sqlite)
- 1 Secret (or wired through cert-manager)

Each component has a `<component>.enabled: false` toggle so operators
can split the install (e.g. run management externally, helm install
only signal+relay+dashboard inside the cluster).

## Gateway API support

The chart emits HTTPRoute (dashboard, management REST, relay) and
GRPCRoute (management gRPC, signal) when:

```yaml
gatewayApi:
  enabled: true
  gatewayClassName: envoy   # or istio / cilium / traefik
  createGateway: true
  gateway:
    hostname: openzro.example.com
    tls:
      certificateRefs:
        - name: openzro-tls
```

Both bundled-Gateway and externally-managed-Gateway modes are
supported via `gatewayApi.createGateway`.

## Subchart: Dex

The chart bundles [dexidp/dex](https://github.com/dexidp/helm-charts)
@ `0.23.0` as a subchart with `condition: dex.enabled`. Default config
seeds:

- Issuer URL `https://openzro.example.com/dex` (override via
  `dex.config.issuer`)
- One bootstrap admin via `staticPasswords` (rotate before going to
  prod)
- The dashboard SPA static client (PKCE, public)
- mTLS gRPC config (cert-manager-friendly)
- `DEX_API_CONNECTORS_CRUD=true` env so the dashboard's Authentication
  Providers tab can manage upstream IdPs (Google / GitHub / Microsoft /
  Keycloak / Okta / generic OIDC) at runtime

To run with an external Dex instead, set `dex.enabled: false` and
configure the management deployment with `OPENZRO_DEX_GRPC_*` env
vars manually.

## OCI install path

In addition to the gh-pages helm repo, charts are also published as
OCI artifacts to `ghcr.io/openzro/charts/`:

```bash
helm install openzro \
  oci://ghcr.io/openzro/charts/openzro \
  --version 2.0.0-alpha.3
```

(OCI publish from CI on every tag is currently best-effort due to a
GitHub package-namespace collision — see ADR-0008's "Open questions"
section. Manual bootstrap pushes from a maintainer keep the OCI path
populated.)

## Publishing

CI publishes on every `charts/*/Chart.yaml` change:

- gh-pages branch → served at https://openzro.github.io/helms (the
  canonical `helm repo add` URL)
- OCI registry → `ghcr.io/openzro/charts/<chart>:<version>` (parallel
  install path)

The workflow definition is at
[`.github/workflows/helm.yml`](.github/workflows/helm.yml). Manual
re-runs via `gh workflow run helm.yml -R openzro/helms`.

## Fork point

This repo was forked from `netbirdio/helms` at the upstream `main`
HEAD on 2026-04-26 (BSD-3-Clause). The fork is documented in
[`FORK.md`](FORK.md). License preserved verbatim.

## Issues / contributions

- Helm chart bugs / values questions: file here
- Operator bugs / CRD reconciler issues: [`openzro/openzro-operator`](https://github.com/openzro/openzro-operator)
- Management server / dashboard / Dex integration: [`openzro/openzro`](https://github.com/openzro/openzro)

## License

[BSD 3-Clause](LICENSE) — preserved verbatim from the upstream
`netbirdio/helms` fork point.
