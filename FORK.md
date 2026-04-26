# openzro/helms fork point

Forked from `netbirdio/helms` at the upstream `main` branch HEAD as of
2026-04-26. The upstream is BSD-3-Clause (Copyright 2025, netbirdio);
the LICENSE file is preserved verbatim under the BSD-3 attribution
clause.

## Charts

- `charts/openzro/` — control plane (management, signal, relay).
  Was `charts/netbird/` upstream.
- `charts/openzro-operator/` — Kubernetes operator chart.
  Was `charts/kubernetes-operator/` upstream.
- `charts/openzro-operator-config/` — operator runtime config.
  Was `charts/netbird-operator-config/` upstream.

## What changed at the fork point

- The full `netbird → openzro` rebrand (lowercase identifier) and
  `NetBird → openZro` (Title Case for prose).
- Image registry references updated to `ghcr.io/openzro/...` (these
  images need to be pushed by the openzro CI separately).
- CRD API group `netbird.io` → `openzro.io`. Existing clusters running
  the upstream chart cannot be in-place upgraded — this is a clean fork.

## Upstream

- https://github.com/netbirdio/helms
- License: BSD-3-Clause (preserved verbatim)
