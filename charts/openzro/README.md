# openzro

![Version: 2.1.0-alpha.13](https://img.shields.io/badge/Version-2.1.0--alpha.13-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.53.1-alpha.37](https://img.shields.io/badge/AppVersion-0.53.1--alpha.37-informational?style=flat-square)

## openZro Helm Chart

This Helm chart installs the openZro self-hosted control plane on
Kubernetes — management + signal + relay + dashboard + an embedded
Dex IdP (per [ADR-0006](https://github.com/openzro/openzro/blob/main/docs/adr/0006-embed-dex.md)).
Operators get federated SSO via Dex's runtime connector API
(Google / GitHub / Microsoft Entra / Keycloak / Okta / generic
OIDC), HA-capable mesh networking via WireGuard®, and an
opinionated dashboard.

This chart is the openZro fork of upstream `netbirdio/helms`,
re-cut at the v0.52.2 BSD-3 fork point. See
[ADR-0008](https://github.com/openzro/openzro/blob/main/docs/adr/0008-kubernetes-helm-operator.md)
for the chart-side architectural decisions.

## What this chart installs

| Component | Purpose | Workload kind | HA path |
|---|---|---|---|
| `management` | Account + peer + policy API | Deployment | `cluster.mode=embedded` (NATS) or `external` |
| `signal` | gRPC peer-to-peer signaling | Deployment | Same `cluster.mode` switch |
| `relay` | WireGuard fallback relay | Deployment | Multi-pod fabric (ADR-0014) |
| `dashboard` | React UI for the platform | Deployment | Stateless replicas |
| `dex` (subchart) | Federated IdP | Deployment | per upstream Dex chart |
| `postgres` / `mysql` (optional subcharts) | Storage backend | per subchart | per subchart |

Routing peers (gateways, exit nodes) are deployed by the
**[openzro-operator](https://github.com/openzro/openzro-operator)**
via the `OZRoutingPeer` CRD — they intentionally don't ship in this
chart because they're data plane, not control plane. See
[`examples/`](./examples) for the combined install pattern.

## Prerequisites

- Helm 3.12+
- Kubernetes 1.27+ (Gateway API CRDs require 1.31+ if
  `gatewayApi.enabled: true`)
- A DNS record pointing at your cluster's ingress / Gateway
- (Optional) cert-manager for TLS
- (Optional) `imagePullSecrets` while openZro container packages on
  ghcr.io remain private — see the
  [k8s deployment guide](https://github.com/openzro/openzro/blob/main/docs/operator/k8s-deployment-guide.md#pull-secret-note-private-ghcr-packages)

## Installation

```bash
helm repo add openzro https://openzro.github.io/helms
helm repo update
helm install openzro openzro/openzro
```

Override defaults via your own `values.yaml`:

```bash
helm install openzro openzro/openzro -f values.yaml
```

### Uninstalling

```bash
helm uninstall openzro
```

PVCs and Secrets created by hooks are NOT removed automatically —
delete them manually if you want a clean slate.

## High availability

Three modes selectable via `cluster.mode`:

```yaml
cluster:
  mode: disabled   # default — single replica each, no broker
  # mode: embedded   # each management/signal pod runs an embedded NATS cluster
  # mode: external   # point at an existing NATS via cluster.external.url
```

In `embedded` mode the chart renders a Headless Service that anchors
NATS clustering between pods (`management`, `signal`). The
deployment kind switches to **StatefulSet** to give each pod a stable
DNS hostname for NATS routes.

In `external` mode you bring your own NATS — useful if you already
operate a broker. Set `cluster.external.url` (or `nats.enabled: true`
to bundle the upstream NATS subchart).

The relay has its own multi-pod fabric — see below.

## Multi-pod relay (ADR-0014)

When `relay.replicaCount > 1`, the chart auto-wires:

- A Headless Service (`<release>-relay-internal`) that resolves to
  every relay pod's IP
- A second container port (`relay.cluster.port`, default 7090) for
  inter-pod TCP traffic
- Downward API env vars (`POD_IP`, `POD_NAME`)
- An HMAC-SHA256 secret (auto-generated on first install, preserved
  across upgrades) that authenticates inter-pod HELLO frames

Override the auto-on behavior:

```yaml
relay:
  replicaCount: 3
  cluster:
    enabled: true        # null (default) = auto at replicaCount > 1
    port: 7090
    authSecret:
      value: ""              # set a literal — chart manages the Secret
      existingSecret: ""     # OR point at your own Secret
      existingSecretKey: ""  # OR override the default key name
```

Operators with strict pod-to-pod NetworkPolicy must allow TCP/7090
between pods labeled `app.kubernetes.io/name: openzro-relay`. The
HMAC gate authenticates HELLO frames either way — NetworkPolicy is
defense-in-depth.

## Geolocation database (MaxMind GeoLite2)

The dashboard's geo posture-check populates from a GeoLite2 database
the management binary fetches on cold boot. By default it pulls from
the openZro mirror (`pkg.openzro.io`) — zero operator config:

```yaml
management:
  geoLite:
    licenseKey:
      value: ""                # leave empty for the openZro mirror
      # value: "abc123..."     # OR set a MaxMind license key
      # existingSecret: "..."  # OR read from a pre-existing Secret
```

When `licenseKey.value` (or `existingSecret`) is set, management
pulls directly from `download.maxmind.com` using the operator's
[free GeoLite2 license key](https://www.maxmind.com/en/geolite2/signup) —
useful for operators who want first-party-only egress and don't want
third-party-mirror indirection.

Air-gapped installs: stage your own `GeoLite2-City_<date>.mmdb` in
the management `datadir` and pass `--disable-geolite-update=true`
via `management.extraArgs`.

## Storage

The chart auto-wires the management daemon, flow store, and activity
event store against PostgreSQL or MySQL when either subchart is
enabled:

```yaml
postgres:
  enabled: true
  username: openzro
  password: change-me
  # database/host/port have sane defaults for the bundled subchart

# OR

mysql:
  enabled: true
  rootPassword: change-me
```

A pre-install Helm hook provisions per-store databases + users with
restricted grants — see [`templates/db-provisioning-job.yaml`](./templates/db-provisioning-job.yaml).
Skip the auto-wiring entirely by leaving both `enabled: false` and
configuring DSNs manually via `management.envFromSecret`.

## Identity provider (Dex)

The chart bundles [Dex](https://dexidp.io/) as a subchart per
[ADR-0006](https://github.com/openzro/openzro/blob/main/docs/adr/0006-embed-dex.md).
Operators wire connectors at runtime via the dashboard ("Identity
Providers" page) — no chart re-render needed when adding/removing
Google / GitHub / Microsoft Entra / Keycloak / Okta / generic OIDC.

Bring your own Dex instance:

```yaml
dex:
  enabled: false  # skip the subchart
management:
  env:
    OPENZRO_AUTH_AUDIENCE: openzro
    OPENZRO_AUTH_ISSUER: "https://your-dex.example.com"
```

[`examples/nginx-ingress/`](./examples/nginx-ingress) has working
configurations for `auth0`, `authentik`, `google`, and `okta` IdPs.

## Routing peers

This chart **does not** install routing peers / exit nodes. They are
data plane, not control plane, and the right deploy path is via the
**[openzro-operator](https://github.com/openzro/openzro-operator)**:

```yaml
apiVersion: openzro.io/v1
kind: OZRoutingPeer
metadata:
  name: us-east-gateway
spec:
  replicas: 2
  routes:
    - "10.10.0.0/16"
```

The operator handles setup-key generation against management's API,
materializes the Secret, and deploys the peer pods with the binary
in `up` mode. Pair with `OZNetwork` / `OZResource` for the
management-side routing.

For bare-metal / VM peers, use the `openzro_routing_peer` Ansible
role from the [openzro-ansible](https://github.com/openzro/openzro-ansible)
repo.

## STUN/TURN

If you need an HA STUN/TURN tier, this chart doesn't ship one — the
right path is a dedicated [coturn deployment](https://medium.com/l7mp-technologies/deploying-a-scalable-stun-service-in-kubernetes-c7b9726fa41d).
Wire its address into `management.configmap` under `Stuns`/`TURNConfig`.

## Values reference

The full table below is auto-generated from `## @param` annotations
in [`values.yaml`](./values.yaml) by [helm-docs](https://github.com/norwoodj/helm-docs).
Run `helm-docs --chart-search-root charts` after editing
`values.yaml` and commit the regenerated `README.md`; CI fails the
PR if the two drift.

The most-tweaked groups during a real install:

- `management.*` — image, env, resources, ingress
- `signal.*`, `relay.*`, `dashboard.*` — same, per component
- `cluster.mode` + `cluster.embedded.*` / `cluster.external.*` — HA
- `relay.cluster.*` — multi-pod fabric (ADR-0014)
- `relay.replicaCount` — auto-enables the multi-pod fabric when > 1
- `management.geoLite.licenseKey.*` — MaxMind GeoLite2 source
- `postgres.*` / `mysql.*` — storage backend
- `dex.*` — bundled IdP (subchart values forwarded)
- `metrics.serviceMonitor.*` — Prometheus operator integration
- `gatewayApi.enabled` — Gateway API instead of Ingress

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cluster.embedded.clientPort | int | `4222` |  |
| cluster.embedded.clusterPort | int | `6222` |  |
| cluster.embedded.jetstream.sizeGiB | int | `1` |  |
| cluster.embedded.jetstream.storage | string | `"memory"` |  |
| cluster.embedded.jetstream.storageClass | string | `""` |  |
| cluster.external.url | string | `""` |  |
| cluster.mode | string | `"disabled"` |  |
| dashboard.affinity | object | `{}` |  |
| dashboard.containerPort | int | `80` |  |
| dashboard.enabled | bool | `true` |  |
| dashboard.env | object | `{}` |  |
| dashboard.envFromSecret | object | `{}` |  |
| dashboard.envRaw | list | `[]` |  |
| dashboard.image.pullPolicy | string | `"IfNotPresent"` |  |
| dashboard.image.repository | string | `"ghcr.io/openzro/dashboard"` |  |
| dashboard.image.tag | string | `""` |  |
| dashboard.imagePullSecrets | list | `[]` |  |
| dashboard.ingress.annotations | object | `{}` |  |
| dashboard.ingress.className | string | `""` |  |
| dashboard.ingress.enabled | bool | `false` |  |
| dashboard.ingress.hosts[0].host | string | `"chart-example.local"` |  |
| dashboard.ingress.hosts[0].paths[0].path | string | `"/"` |  |
| dashboard.ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| dashboard.ingress.tls | list | `[]` |  |
| dashboard.lifecycle | object | `{}` |  |
| dashboard.livenessProbe.httpGet.path | string | `"/"` |  |
| dashboard.livenessProbe.httpGet.port | string | `"http"` |  |
| dashboard.livenessProbe.periodSeconds | int | `5` |  |
| dashboard.nodeSelector | object | `{}` |  |
| dashboard.podAnnotations | object | `{}` |  |
| dashboard.podCommand.args | list | `[]` |  |
| dashboard.podSecurityContext | object | `{}` |  |
| dashboard.readinessProbe.httpGet.path | string | `"/"` |  |
| dashboard.readinessProbe.httpGet.port | string | `"http"` |  |
| dashboard.readinessProbe.initialDelaySeconds | int | `5` |  |
| dashboard.readinessProbe.periodSeconds | int | `5` |  |
| dashboard.replicaCount | int | `1` |  |
| dashboard.resources | object | `{}` |  |
| dashboard.securityContext | object | `{}` |  |
| dashboard.service.annotations | object | `{}` |  |
| dashboard.service.externalIPs | list | `[]` |  |
| dashboard.service.name | string | `"http"` |  |
| dashboard.service.port | int | `80` |  |
| dashboard.service.type | string | `"ClusterIP"` |  |
| dashboard.serviceAccount.annotations | object | `{}` |  |
| dashboard.serviceAccount.create | bool | `true` |  |
| dashboard.serviceAccount.name | string | `""` |  |
| dashboard.tolerations | list | `[]` |  |
| dashboard.volumeMounts | list | `[]` |  |
| dashboard.volumes | list | `[]` |  |
| dex.config.connectors | list | `[]` |  |
| dex.config.enablePasswordDB | bool | `true` |  |
| dex.config.frontend.dir | string | `"/srv/dex/web"` |  |
| dex.config.frontend.issuer | string | `"openZro"` |  |
| dex.config.frontend.theme | string | `"openzro"` |  |
| dex.config.grpc.addr | string | `"0.0.0.0:5557"` |  |
| dex.config.grpc.tlsCert | string | `"/etc/dex/grpc-certs/server.crt"` |  |
| dex.config.grpc.tlsClientCA | string | `"/etc/dex/grpc-certs/ca.crt"` |  |
| dex.config.grpc.tlsKey | string | `"/etc/dex/grpc-certs/server.key"` |  |
| dex.config.issuer | string | `"https://openzro.example.com/dex"` |  |
| dex.config.logger.format | string | `"text"` |  |
| dex.config.logger.level | string | `"info"` |  |
| dex.config.oauth2.responseTypes[0] | string | `"code"` |  |
| dex.config.oauth2.skipApprovalScreen | bool | `true` |  |
| dex.config.staticClients[0].id | string | `"openzro-dashboard"` |  |
| dex.config.staticClients[0].name | string | `"openZro"` |  |
| dex.config.staticClients[0].public | bool | `true` |  |
| dex.config.staticClients[0].redirectURIs[0] | string | `"https://openzro.example.com/auth"` |  |
| dex.config.staticClients[0].redirectURIs[1] | string | `"https://openzro.example.com/silent-auth"` |  |
| dex.config.staticClients[0].redirectURIs[2] | string | `"https://openzro.example.com/"` |  |
| dex.config.staticClients[0].redirectURIs[3] | string | `"http://localhost:53000/"` |  |
| dex.config.staticClients[0].redirectURIs[4] | string | `"http://localhost:54000/"` |  |
| dex.config.staticClients[0].redirectURIs[5] | string | `"http://localhost:55000/"` |  |
| dex.config.staticClients[0].redirectURIs[6] | string | `"/device/callback"` |  |
| dex.config.staticPasswords[0].email | string | `"admin@openzro.example.com"` |  |
| dex.config.staticPasswords[0].hash | string | `"$2a$10$FnWvg5MH2t6QLmRkxC/WAervu3W3rrK0PJce1eKIYgQMp/S8oVuMy"` |  |
| dex.config.staticPasswords[0].userID | string | `"openzro-bootstrap-admin"` |  |
| dex.config.staticPasswords[0].username | string | `"admin"` |  |
| dex.config.storage.config.file | string | `"/var/lib/dex/dex.db"` |  |
| dex.config.storage.type | string | `"sqlite3"` |  |
| dex.config.web.allowedOrigins[0] | string | `"https://openzro.example.com"` |  |
| dex.config.web.http | string | `"0.0.0.0:5556"` |  |
| dex.enabled | bool | `true` |  |
| dex.env.DEX_API_CONNECTORS_CRUD | string | `"true"` |  |
| dex.grpc.enabled | bool | `true` |  |
| dex.image.pullPolicy | string | `"IfNotPresent"` |  |
| dex.image.repository | string | `"ghcr.io/openzro/dex"` |  |
| dex.image.tag | string | `"0.53.1-alpha.21"` |  |
| dex.ingress.annotations | object | `{}` |  |
| dex.ingress.className | string | `""` |  |
| dex.ingress.enabled | bool | `false` |  |
| dex.ingress.hosts[0].host | string | `"openzro.example.com"` |  |
| dex.ingress.hosts[0].paths[0].path | string | `"/dex"` |  |
| dex.ingress.hosts[0].paths[0].pathType | string | `"Prefix"` |  |
| dex.ingress.tls | list | `[]` |  |
| dex.persistence.accessModes[0] | string | `"ReadWriteOnce"` |  |
| dex.persistence.enabled | bool | `false` |  |
| dex.persistence.size | string | `"1Gi"` |  |
| dex.podSecurityContext.fsGroup | int | `1001` |  |
| dex.podSecurityContext.runAsNonRoot | bool | `true` |  |
| dex.podSecurityContext.runAsUser | int | `1001` |  |
| dex.ports.grpc.containerPort | int | `5557` |  |
| dex.ports.http.containerPort | int | `5556` |  |
| dex.replicaCount | int | `1` |  |
| dex.service.ports.grpc.port | int | `5557` |  |
| dex.service.ports.http.port | int | `5556` |  |
| dex.service.ports.telemetry.port | int | `5558` |  |
| dex.volumeMounts[0].mountPath | string | `"/srv/dex/web/themes/openzro"` |  |
| dex.volumeMounts[0].name | string | `"openzro-theme"` |  |
| dex.volumeMounts[0].readOnly | bool | `true` |  |
| dex.volumeMounts[1].mountPath | string | `"/etc/dex/grpc-certs"` |  |
| dex.volumeMounts[1].name | string | `"dex-grpc-certs"` |  |
| dex.volumeMounts[1].readOnly | bool | `true` |  |
| dex.volumes[0].configMap.name | string | `"openzro-dex-theme"` |  |
| dex.volumes[0].configMap.optional | bool | `true` |  |
| dex.volumes[0].name | string | `"openzro-theme"` |  |
| dex.volumes[1].name | string | `"dex-grpc-certs"` |  |
| dex.volumes[1].secret.optional | bool | `true` |  |
| dex.volumes[1].secret.secretName | string | `"openzro-dex-grpc"` |  |
| extraManifests | object | `{}` |  |
| fullnameOverride | string | `""` |  |
| gatewayApi.createGateway | bool | `true` |  |
| gatewayApi.enabled | bool | `false` |  |
| gatewayApi.gateway.allowedRoutes.namespaces.from | string | `"Same"` |  |
| gatewayApi.gateway.hostname | string | `"openzro.example.com"` |  |
| gatewayApi.gateway.httpPort | int | `80` |  |
| gatewayApi.gateway.httpsPort | int | `443` |  |
| gatewayApi.gateway.tls.certificateRefs[0].name | string | `"openzro-tls"` |  |
| gatewayApi.gateway.tls.mode | string | `"Terminate"` |  |
| gatewayApi.gatewayClassName | string | `""` |  |
| gatewayApi.parentRefs | list | `[]` |  |
| gatewayApi.routes.dashboard.enabled | bool | `true` |  |
| gatewayApi.routes.dashboard.path | string | `"/"` |  |
| gatewayApi.routes.dashboard.pathType | string | `"PathPrefix"` |  |
| gatewayApi.routes.management.enabled | bool | `true` |  |
| gatewayApi.routes.management.path | string | `"/api"` |  |
| gatewayApi.routes.management.pathType | string | `"PathPrefix"` |  |
| gatewayApi.routes.managementGrpc.enabled | bool | `true` |  |
| gatewayApi.routes.managementGrpc.method | string | `""` |  |
| gatewayApi.routes.managementGrpc.service | string | `""` |  |
| gatewayApi.routes.relay.enabled | bool | `true` |  |
| gatewayApi.routes.relay.path | string | `"/"` |  |
| gatewayApi.routes.relay.pathType | string | `"PathPrefix"` |  |
| gatewayApi.routes.signal.enabled | bool | `true` |  |
| gatewayApi.routes.signal.method | string | `""` |  |
| gatewayApi.routes.signal.service | string | `""` |  |
| global.namespace | string | `""` |  |
| management.affinity | object | `{}` |  |
| management.config.dataStoreEncryptionKey | string | `""` |  |
| management.config.deviceAuthorizationFlow.provider | string | `"hosted"` |  |
| management.config.deviceAuthorizationFlow.providerConfig.audience | string | `"openzro-dashboard"` |  |
| management.config.deviceAuthorizationFlow.providerConfig.clientId | string | `"openzro-dashboard"` |  |
| management.config.deviceAuthorizationFlow.providerConfig.deviceAuthEndpoint | string | `""` |  |
| management.config.deviceAuthorizationFlow.providerConfig.domain | string | `""` |  |
| management.config.deviceAuthorizationFlow.providerConfig.scope | string | `"openid profile email offline_access"` |  |
| management.config.deviceAuthorizationFlow.providerConfig.tokenEndpoint | string | `""` |  |
| management.config.deviceAuthorizationFlow.providerConfig.useIDToken | bool | `false` |  |
| management.config.disableDefaultPolicy | bool | `false` |  |
| management.config.httpConfig.address | string | `"0.0.0.0:33071"` |  |
| management.config.httpConfig.authAudience | string | `"openzro-dashboard"` |  |
| management.config.httpConfig.authIssuer | string | `""` |  |
| management.config.httpConfig.authUserIDClaim | string | `"sub"` |  |
| management.config.httpConfig.idpSignKeyRefreshEnabled | bool | `true` |  |
| management.config.httpConfig.oidcConfigEndpoint | string | `""` |  |
| management.config.idpManagerConfig.managerType | string | `"none"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.audience | string | `"openzro-dashboard"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.authorizationEndpoint | string | `""` |  |
| management.config.pkceAuthorizationFlow.providerConfig.clientId | string | `"openzro-dashboard"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.clientSecret | string | `""` |  |
| management.config.pkceAuthorizationFlow.providerConfig.domain | string | `""` |  |
| management.config.pkceAuthorizationFlow.providerConfig.redirectURLs[0] | string | `"http://localhost:53000/"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.redirectURLs[1] | string | `"http://localhost:54000/"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.redirectURLs[2] | string | `"http://localhost:55000/"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.scope | string | `"openid profile email offline_access"` |  |
| management.config.pkceAuthorizationFlow.providerConfig.tokenEndpoint | string | `""` |  |
| management.config.pkceAuthorizationFlow.providerConfig.useIDToken | bool | `false` |  |
| management.config.relay.addresses | list | `[]` |  |
| management.config.relay.credentialsTTL | string | `"24h"` |  |
| management.config.relay.secret | string | `""` |  |
| management.config.reverseProxy.trustedHTTPProxies | list | `[]` |  |
| management.config.reverseProxy.trustedHTTPProxiesCount | int | `0` |  |
| management.config.reverseProxy.trustedPeers[0] | string | `"0.0.0.0/0"` |  |
| management.config.signal.proto | string | `"https"` |  |
| management.config.signal.uri | string | `""` |  |
| management.config.stuns | list | `[]` |  |
| management.config.turnConfig.credentialsTTL | string | `"12h"` |  |
| management.config.turnConfig.secret | string | `"not-used"` |  |
| management.config.turnConfig.timeBasedCredentials | bool | `false` |  |
| management.config.turnConfig.turns | list | `[]` |  |
| management.configmap | string | `""` |  |
| management.containerPort | int | `80` |  |
| management.deploymentAnnotations | object | `{}` |  |
| management.disableAnonymousMetrics | bool | `false` |  |
| management.dnsDomain | string | `"openzro.selfhosted"` |  |
| management.enabled | bool | `true` |  |
| management.env | object | `{}` |  |
| management.envFromSecret | object | `{}` |  |
| management.envRaw | list | `[]` |  |
| management.existingConfigSecret | string | `""` |  |
| management.extraArgs | list | `[]` |  |
| management.geoLite.licenseKey.existingSecret | string | `""` |  |
| management.geoLite.licenseKey.existingSecretKey | string | `""` |  |
| management.geoLite.licenseKey.value | string | `""` |  |
| management.grpcContainerPort | int | `33073` |  |
| management.image.pullPolicy | string | `"IfNotPresent"` |  |
| management.image.repository | string | `"ghcr.io/openzro/management"` |  |
| management.image.tag | string | `""` |  |
| management.imagePullSecrets | list | `[]` |  |
| management.ingress.annotations | object | `{}` |  |
| management.ingress.className | string | `""` |  |
| management.ingress.enabled | bool | `false` |  |
| management.ingress.hosts[0].host | string | `"example.com"` |  |
| management.ingress.hosts[0].paths[0].path | string | `"/"` |  |
| management.ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| management.ingress.tls | list | `[]` |  |
| management.ingressGrpc.annotations | object | `{}` |  |
| management.ingressGrpc.className | string | `""` |  |
| management.ingressGrpc.enabled | bool | `false` |  |
| management.ingressGrpc.hosts[0].host | string | `"example.com"` |  |
| management.ingressGrpc.hosts[0].paths[0].path | string | `"/"` |  |
| management.ingressGrpc.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| management.ingressGrpc.tls | list | `[]` |  |
| management.lifecycle | object | `{}` |  |
| management.livenessProbe.failureThreshold | int | `3` |  |
| management.livenessProbe.initialDelaySeconds | int | `15` |  |
| management.livenessProbe.periodSeconds | int | `10` |  |
| management.livenessProbe.tcpSocket.port | string | `"http"` |  |
| management.livenessProbe.timeoutSeconds | int | `3` |  |
| management.logFile | string | `"console"` |  |
| management.logLevel | string | `"info"` |  |
| management.metrics.enabled | bool | `false` |  |
| management.metrics.port | int | `9090` |  |
| management.nodeSelector | object | `{}` |  |
| management.persistentVolume.accessModes[0] | string | `"ReadWriteOnce"` |  |
| management.persistentVolume.enabled | bool | `true` |  |
| management.persistentVolume.existingPVName | string | `""` |  |
| management.persistentVolume.size | string | `"10Mi"` |  |
| management.persistentVolume.storageClass | string | `nil` |  |
| management.podAnnotations | object | `{}` |  |
| management.podCommand.args | list | `[]` |  |
| management.podSecurityContext | object | `{}` |  |
| management.port | int | `80` |  |
| management.readinessProbe.failureThreshold | int | `3` |  |
| management.readinessProbe.initialDelaySeconds | int | `15` |  |
| management.readinessProbe.periodSeconds | int | `10` |  |
| management.readinessProbe.tcpSocket.port | string | `"http"` |  |
| management.readinessProbe.timeoutSeconds | int | `3` |  |
| management.replicaCount | int | `1` |  |
| management.resources | object | `{}` |  |
| management.securityContext | object | `{}` |  |
| management.service.annotations | object | `{}` |  |
| management.service.externalIPs | list | `[]` |  |
| management.service.name | string | `"http"` |  |
| management.service.port | int | `80` |  |
| management.service.type | string | `"ClusterIP"` |  |
| management.serviceAccount.annotations | object | `{}` |  |
| management.serviceAccount.create | bool | `true` |  |
| management.serviceAccount.name | string | `""` |  |
| management.serviceGrpc.annotations | object | `{}` |  |
| management.serviceGrpc.externalIPs | list | `[]` |  |
| management.serviceGrpc.name | string | `"grpc"` |  |
| management.serviceGrpc.port | int | `33073` |  |
| management.serviceGrpc.type | string | `"ClusterIP"` |  |
| management.singleAccountModeDomain | string | `"openzro.selfhosted"` |  |
| management.strategy.type | string | `"Recreate"` |  |
| management.tolerations | list | `[]` |  |
| management.useBackwardsGrpcService | bool | `false` |  |
| management.volumeMounts | list | `[]` |  |
| management.volumes | list | `[]` |  |
| metrics.serviceMonitor.annotations | object | `{}` |  |
| metrics.serviceMonitor.enabled | bool | `false` |  |
| metrics.serviceMonitor.honorLabels | bool | `false` |  |
| metrics.serviceMonitor.interval | string | `""` |  |
| metrics.serviceMonitor.jobLabel | string | `""` |  |
| metrics.serviceMonitor.labels | object | `{}` |  |
| metrics.serviceMonitor.metricRelabelings | list | `[]` |  |
| metrics.serviceMonitor.namespace | string | `""` |  |
| metrics.serviceMonitor.relabelings | list | `[]` |  |
| metrics.serviceMonitor.scrapeTimeout | string | `""` |  |
| metrics.serviceMonitor.selector | object | `{}` |  |
| mysql.databases.activity | string | `"openzro_activity"` |  |
| mysql.databases.dex | string | `"dex"` |  |
| mysql.databases.flow | string | `"openzro_flow"` |  |
| mysql.databases.management | string | `"openzro"` |  |
| mysql.enabled | bool | `false` |  |
| mysql.existingSecret | string | `""` |  |
| mysql.existingSecretPasswordKey | string | `""` |  |
| mysql.host | string | `""` |  |
| mysql.password | string | `""` |  |
| mysql.port | int | `3306` |  |
| mysql.provisioning.enabled | bool | `false` |  |
| mysql.provisioning.image | string | `"mysql:8.0"` |  |
| mysql.provisioning.password | string | `""` |  |
| mysql.provisioning.username | string | `""` |  |
| mysql.tls | string | `"preferred"` |  |
| mysql.username | string | `"openzro"` |  |
| nameOverride | string | `""` |  |
| nats.config.cluster.enabled | bool | `true` |  |
| nats.config.cluster.replicas | int | `3` |  |
| nats.config.jetstream.enabled | bool | `true` |  |
| nats.config.jetstream.fileStore.enabled | bool | `false` |  |
| nats.config.jetstream.memoryStore.enabled | bool | `true` |  |
| nats.config.jetstream.memoryStore.maxSize | string | `"256Mi"` |  |
| nats.enabled | bool | `false` |  |
| postgres.databases.activity | string | `"openzro_activity"` |  |
| postgres.databases.dex | string | `"dex"` |  |
| postgres.databases.flow | string | `"openzro_flow"` |  |
| postgres.databases.management | string | `"openzro"` |  |
| postgres.enabled | bool | `false` |  |
| postgres.existingSecret | string | `""` |  |
| postgres.existingSecretPasswordKey | string | `""` |  |
| postgres.host | string | `""` |  |
| postgres.password | string | `""` |  |
| postgres.port | int | `5432` |  |
| postgres.provisioning.enabled | bool | `false` |  |
| postgres.provisioning.image | string | `"postgres:16-alpine"` |  |
| postgres.provisioning.password | string | `""` |  |
| postgres.provisioning.username | string | `""` |  |
| postgres.sslMode | string | `"require"` |  |
| postgres.username | string | `"openzro"` |  |
| relay.affinity | object | `{}` |  |
| relay.cluster.authSecret.existingSecret | string | `""` |  |
| relay.cluster.authSecret.existingSecretKey | string | `""` |  |
| relay.cluster.authSecret.value | string | `""` |  |
| relay.cluster.enabled | string | `nil` |  |
| relay.cluster.port | int | `7090` |  |
| relay.containerPort | int | `33080` |  |
| relay.deploymentAnnotations | object | `{}` |  |
| relay.enabled | bool | `true` |  |
| relay.env | object | `{}` |  |
| relay.envFromSecret | object | `{}` |  |
| relay.envRaw | list | `[]` |  |
| relay.image.pullPolicy | string | `"IfNotPresent"` |  |
| relay.image.repository | string | `"ghcr.io/openzro/relay"` |  |
| relay.image.tag | string | `""` |  |
| relay.imagePullSecrets | list | `[]` |  |
| relay.ingress.annotations | object | `{}` |  |
| relay.ingress.className | string | `""` |  |
| relay.ingress.enabled | bool | `false` |  |
| relay.ingress.hosts[0].host | string | `"example.com"` |  |
| relay.ingress.hosts[0].paths[0].path | string | `"/relay"` |  |
| relay.ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| relay.ingress.tls | list | `[]` |  |
| relay.livenessProbe.initialDelaySeconds | int | `5` |  |
| relay.livenessProbe.periodSeconds | int | `5` |  |
| relay.livenessProbe.tcpSocket.port | string | `"http"` |  |
| relay.logLevel | string | `"info"` |  |
| relay.metrics.enabled | bool | `false` |  |
| relay.metrics.port | int | `9090` |  |
| relay.nodeSelector | object | `{}` |  |
| relay.podAnnotations | object | `{}` |  |
| relay.podSecurityContext | object | `{}` |  |
| relay.readinessProbe.initialDelaySeconds | int | `5` |  |
| relay.readinessProbe.periodSeconds | int | `5` |  |
| relay.readinessProbe.tcpSocket.port | string | `"http"` |  |
| relay.replicaCount | int | `1` |  |
| relay.resources | object | `{}` |  |
| relay.securityContext | object | `{}` |  |
| relay.service.annotations | object | `{}` |  |
| relay.service.externalIPs | list | `[]` |  |
| relay.service.name | string | `"http"` |  |
| relay.service.port | int | `33080` |  |
| relay.service.type | string | `"ClusterIP"` |  |
| relay.serviceAccount.annotations | object | `{}` |  |
| relay.serviceAccount.create | bool | `true` |  |
| relay.serviceAccount.name | string | `""` |  |
| relay.tolerations | list | `[]` |  |
| relay.volumeMounts | list | `[]` |  |
| relay.volumes | list | `[]` |  |
| signal.affinity | object | `{}` |  |
| signal.containerPort | int | `80` |  |
| signal.deploymentAnnotations | object | `{}` |  |
| signal.enabled | bool | `true` |  |
| signal.image.pullPolicy | string | `"IfNotPresent"` |  |
| signal.image.repository | string | `"ghcr.io/openzro/signal"` |  |
| signal.image.tag | string | `""` |  |
| signal.imagePullSecrets | list | `[]` |  |
| signal.ingress.annotations | object | `{}` |  |
| signal.ingress.className | string | `""` |  |
| signal.ingress.enabled | bool | `false` |  |
| signal.ingress.hosts[0].host | string | `"example.com"` |  |
| signal.ingress.hosts[0].paths[0].path | string | `"/signalexchange.SignalExchange"` |  |
| signal.ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| signal.ingress.tls | list | `[]` |  |
| signal.livenessProbe.initialDelaySeconds | int | `5` |  |
| signal.livenessProbe.periodSeconds | int | `5` |  |
| signal.livenessProbe.tcpSocket.port | string | `"grpc"` |  |
| signal.logLevel | string | `"info"` |  |
| signal.metrics.enabled | bool | `false` |  |
| signal.metrics.port | int | `9090` |  |
| signal.nodeSelector | object | `{}` |  |
| signal.podAnnotations | object | `{}` |  |
| signal.podSecurityContext | object | `{}` |  |
| signal.readinessProbe.initialDelaySeconds | int | `5` |  |
| signal.readinessProbe.periodSeconds | int | `5` |  |
| signal.readinessProbe.tcpSocket.port | string | `"grpc"` |  |
| signal.replicaCount | int | `1` |  |
| signal.resources | object | `{}` |  |
| signal.securityContext | object | `{}` |  |
| signal.service.annotations | object | `{}` |  |
| signal.service.externalIPs | list | `[]` |  |
| signal.service.name | string | `"grpc"` |  |
| signal.service.port | int | `80` |  |
| signal.service.type | string | `"ClusterIP"` |  |
| signal.serviceAccount.annotations | object | `{}` |  |
| signal.serviceAccount.create | bool | `true` |  |
| signal.serviceAccount.name | string | `""` |  |
| signal.tolerations | list | `[]` |  |
| signal.volumeMounts | list | `[]` |  |
| signal.volumes | list | `[]` |  |

## Examples

[`examples/`](./examples) ships full-stack configurations for the
most-asked combinations:

- `nginx-ingress/` — auth0, authentik, google, okta
- `istio/` — Istio gateway
- `traefik-ingress/` — Traefik IngressRoute

Each `values.yaml` is annotated and ready to `helm install -f`.

## Contributing

PRs welcome to the [GitHub repo](https://github.com/openzro/helms).
Run `helm lint charts/openzro` and verify your change with
`helm template t charts/openzro --set <your-flag>=<value>` before
opening the PR.
