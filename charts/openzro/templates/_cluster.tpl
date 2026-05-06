{{/*
Cluster broker plumbing.

`openzro.cluster.workloadKind` returns the Kubernetes Kind that the
management + signal templates should render. In `embedded` mode each
pod runs its own NATS server, so we need stable network identities
(StatefulSet) for peer discovery. In every other mode a Deployment
is fine — workloads are stateless from the cluster-broker point of
view, and rolling upgrades work without Multi-Attach surprises on
RWO PVCs.
*/}}
{{- define "openzro.cluster.workloadKind" -}}
{{- if eq (.Values.cluster.mode | default "disabled") "embedded" -}}
StatefulSet
{{- else -}}
Deployment
{{- end -}}
{{- end -}}

{{/*
Headless service name for a given component. Only meaningful when
cluster.mode=embedded — the StatefulSet's `serviceName` field points
here so each pod gets a `<pod>-<index>.<svc>.<ns>.svc.cluster.local`
DNS record that NATS clustering uses to resolve sibling routes.

Usage: {{ include "openzro.cluster.headlessSvc" (dict "ctx" . "component" "management") }}
*/}}
{{- define "openzro.cluster.headlessSvc" -}}
{{- $ctx := .ctx -}}
{{- $component := .component -}}
{{- printf "%s-%s-headless" (include "openzro.fullname" $ctx) $component -}}
{{- end -}}

{{/*
Comma-separated NATS route URLs for every pod of a component.
Each pod gets `nats-route://<pod>.<headless-svc>:<clusterPort>`.

NATS dedups self automatically, so we can list every replica without
worrying about excluding the local pod. Output is empty when
replicaCount<=1 (no peers to advertise).

Usage: {{ include "openzro.cluster.peers" (dict "ctx" . "component" "management" "replicas" 2) }}
*/}}
{{- define "openzro.cluster.peers" -}}
{{- $ctx := .ctx -}}
{{- $component := .component -}}
{{- $replicas := int .replicas -}}
{{- $svc := include "openzro.cluster.headlessSvc" (dict "ctx" $ctx "component" $component) -}}
{{- $port := $ctx.Values.cluster.embedded.clusterPort -}}
{{- $fullname := include "openzro.fullname" $ctx -}}
{{- $peers := list -}}
{{- range $i, $_ := until $replicas -}}
{{- $peer := printf "nats-route://%s-%s-%d.%s:%v" $fullname $component $i $svc $port -}}
{{- $peers = append $peers $peer -}}
{{- end -}}
{{- join "," $peers -}}
{{- end -}}

{{/*
Whether the relay should run with ADR-0014's inter-pod fabric on.
Three states:
  - `relay.cluster.enabled: true`  → forced on, even at replicaCount=1
  - `relay.cluster.enabled: false` → forced off, even at replicaCount>1
  - `relay.cluster.enabled: null`  → auto: on iff replicaCount > 1

The auto behaviour is the right default: a single-replica relay has
nobody to talk to, multi-replica needs the fabric to share peers.
Returns "true" / "" so callers can `if include "..." .`.
*/}}
{{- define "openzro.relay.cluster.enabled" -}}
{{- $explicit := .Values.relay.cluster.enabled -}}
{{- $replicas := int (.Values.relay.replicaCount | default 1) -}}
{{- if eq (kindOf $explicit) "bool" -}}
{{- if $explicit -}}true{{- end -}}
{{- else if gt $replicas 1 -}}
true
{{- end -}}
{{- end -}}

{{/*
Headless Service short name for the relay's inter-pod fabric.
Wired into OZ_CLUSTER_HEADLESS — the relay's discovery loop
resolves this with net.LookupHost every cluster.interval seconds.
*/}}
{{- define "openzro.relay.cluster.headless" -}}
{{- printf "%s-relay-internal" (include "openzro.fullname" .) -}}
{{- end -}}

{{/*
Name of the Secret holding the inter-pod HMAC key. Either rendered
by relay-cluster-auth-secret.yaml (chart-managed) or pre-created by
the operator and pointed to via relay.cluster.authSecret.existingSecret.
*/}}
{{- define "openzro.relay.cluster.authSecretName" -}}
{{- if .Values.relay.cluster.authSecret.existingSecret -}}
{{- .Values.relay.cluster.authSecret.existingSecret -}}
{{- else -}}
{{- printf "%s-relay-cluster-auth" (include "openzro.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Key inside the Secret that holds the HMAC value. Defaults to
"authSecret" and matches what relay-cluster-auth-secret.yaml writes;
operators using their own Secret can override via
relay.cluster.authSecret.existingSecretKey.
*/}}
{{- define "openzro.relay.cluster.authSecretKey" -}}
{{- .Values.relay.cluster.authSecret.existingSecretKey | default "authSecret" -}}
{{- end -}}

{{/*
Env block for the relay container in cluster mode. Empty in
single-pod mode, so the deployment template can splice it in
unconditionally.

POD_IP comes from the K8s downward API. The relay binary uses it
as its inter-pod announce address (HELLO frame payload) so siblings
can dial back without depending on ephemeral source ports.
*/}}
{{- define "openzro.relay.cluster.env" -}}
{{- if include "openzro.relay.cluster.enabled" . }}
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: OZ_CLUSTER_HEADLESS
  value: {{ include "openzro.relay.cluster.headless" . | quote }}
- name: OZ_CLUSTER_PORT
  value: {{ .Values.relay.cluster.port | quote }}
- name: OZ_POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: OZ_CLUSTER_AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "openzro.relay.cluster.authSecretName" . | quote }}
      key: {{ include "openzro.relay.cluster.authSecretKey" . | quote }}
{{- end -}}
{{- end -}}

{{/*
Relay TLS plumbing.

`openzro.relay.tls.secretName` — Secret the relay pod mounts. Three sources,
in priority order:
  1. relay.tls.certManager.enabled=true → cert-manager populates the Secret
     whose name we own here (default `<fullname>-relay-tls`, override via
     relay.tls.certManager.secretName).
  2. relay.tls.existingSecret set → operator-managed Secret.
  3. else → empty string. Callers must guard with `relay.tls.enabled` first;
     this helper does NOT short-circuit on enabled=false because it is also
     used by relay-certificate.yaml at render time.
*/}}
{{- define "openzro.relay.tls.secretName" -}}
{{- $tls := .Values.relay.tls -}}
{{- if and $tls.certManager.enabled $tls.certManager.secretName -}}
{{- $tls.certManager.secretName -}}
{{- else if $tls.certManager.enabled -}}
{{- printf "%s-relay-tls" (include "openzro.fullname" .) -}}
{{- else if $tls.existingSecret -}}
{{- $tls.existingSecret -}}
{{- end -}}
{{- end -}}

{{/*
DNS names for the Certificate CRD. Falls back to [relay.publicHostname]
when relay.tls.certManager.dnsNames is empty — the typical single-host case.
Empty publicHostname plus empty dnsNames is a config error (caught in NOTES).
*/}}
{{- define "openzro.relay.tls.dnsNames" -}}
{{- $dn := .Values.relay.tls.certManager.dnsNames -}}
{{- if and (not $dn) .Values.relay.publicHostname -}}
{{- $dn = list .Values.relay.publicHostname -}}
{{- end -}}
{{- toYaml $dn -}}
{{- end -}}

{{/*
URL scheme advertised in management.config.relay.addresses. `rels://` when
TLS is on (peers do TLS handshake), `rel://` when off. Plain string output
so callers can compose with printf.
*/}}
{{- define "openzro.relay.tls.scheme" -}}
{{- if .Values.relay.tls.enabled -}}rels{{- else -}}rel{{- end -}}
{{- end -}}

{{/*
TLS-related env vars for the relay container. Empty when tls.enabled=false
so the deployment template can splice it in unconditionally.
*/}}
{{- define "openzro.relay.tls.env" -}}
{{- if .Values.relay.tls.enabled }}
- name: OZ_TLS_CERT_FILE
  value: {{ printf "%s/%s" .Values.relay.tls.mountPath .Values.relay.tls.secretKeys.cert | quote }}
- name: OZ_TLS_KEY_FILE
  value: {{ printf "%s/%s" .Values.relay.tls.mountPath .Values.relay.tls.secretKeys.key | quote }}
{{- end -}}
{{- end -}}

{{/*
Volume + volumeMount fragments for the TLS Secret. Empty when tls.enabled=false.
The mount is read-only because the relay only consumes the cert and key.
*/}}
{{- define "openzro.relay.tls.volumeMount" -}}
{{- if .Values.relay.tls.enabled }}
- name: relay-tls
  mountPath: {{ .Values.relay.tls.mountPath | quote }}
  readOnly: true
{{- end -}}
{{- end -}}

{{- define "openzro.relay.tls.volume" -}}
{{- if .Values.relay.tls.enabled }}
- name: relay-tls
  secret:
    secretName: {{ include "openzro.relay.tls.secretName" . | quote }}
{{- end -}}
{{- end -}}

{{/*
NATS connection URL for `cluster.mode=external`. Order of resolution:
  1. `cluster.external.url` — explicit operator override
  2. `nats.enabled=true` — auto-derive from the bundled subchart at
     `nats://<release>-nats:4222`
  3. Fail loudly with a `cluster.mode=external` config error so the
     operator notices at `helm install` time, not pod-CrashLoop time.
*/}}
{{- define "openzro.cluster.natsURL" -}}
{{- if .Values.cluster.external.url -}}
{{- .Values.cluster.external.url -}}
{{- else if .Values.nats.enabled -}}
nats://{{ .Release.Name }}-nats:4222
{{- else -}}
{{- fail "cluster.mode=external requires either cluster.external.url or nats.enabled=true" -}}
{{- end -}}
{{- end -}}

{{/*
Render the cluster-related env vars for a component. Output is the
list itself (no leading "env:") so the caller can splice it into an
existing `env:` block.

Usage:
  env:
    {{- include "openzro.cluster.env" (dict "ctx" . "component" "management" "replicas" .Values.management.replicaCount) | nindent 12 }}
*/}}
{{- define "openzro.cluster.env" -}}
{{- $ctx := .ctx -}}
{{- $component := .component -}}
{{- $replicas := int .replicas -}}
{{- $mode := $ctx.Values.cluster.mode | default "disabled" -}}
{{- if eq $mode "embedded" }}
- name: OPENZRO_BROKER
  value: "embedded"
- name: OPENZRO_EMBEDDED_NATS_CLIENT_PORT
  value: {{ $ctx.Values.cluster.embedded.clientPort | quote }}
- name: OPENZRO_EMBEDDED_NATS_CLUSTER_PORT
  value: {{ $ctx.Values.cluster.embedded.clusterPort | quote }}
{{- if eq $ctx.Values.cluster.embedded.jetstream.storage "file" }}
- name: OPENZRO_EMBEDDED_NATS_JETSTREAM_DIR
  value: "/var/lib/openzro/jetstream"
{{- end }}
{{- if gt $replicas 1 }}
- name: OPENZRO_CLUSTER_PEERS
  value: {{ include "openzro.cluster.peers" (dict "ctx" $ctx "component" $component "replicas" $replicas) | quote }}
{{- end }}
{{- if eq $component "signal" }}
- name: OPENZRO_SIGNAL_DISPATCHER
  value: "nats"
{{- end }}
{{- else if eq $mode "external" }}
- name: OPENZRO_NATS_URL
  value: {{ include "openzro.cluster.natsURL" $ctx | quote }}
{{- if eq $component "signal" }}
- name: OPENZRO_SIGNAL_DISPATCHER
  value: "nats"
{{- end }}
{{- end -}}
{{- end -}}
