{{/*
Expand the name of the chart.
*/}}
{{- define "openzro.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "openzro.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openzro.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openzro.common.labels" -}}
helm.sh/chart: {{ include "openzro.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{/*
Common management labels
*/}}
{{- define "openzro.management.labels" -}}
helm.sh/chart: {{ include "openzro.chart" . }}
{{ include "openzro.management.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common signal labels
*/}}
{{- define "openzro.signal.labels" -}}
helm.sh/chart: {{ include "openzro.chart" . }}
{{ include "openzro.signal.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common relay labels
*/}}
{{- define "openzro.relay.labels" -}}
helm.sh/chart: {{ include "openzro.chart" . }}
{{ include "openzro.relay.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common dashboard labels
*/}}
{{- define "openzro.dashboard.labels" -}}
helm.sh/chart: {{ include "openzro.chart" . }}
{{ include "openzro.dashboard.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Management selector labels
*/}}
{{- define "openzro.management.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openzro.name" . }}-management
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Signal selector labels
*/}}
{{- define "openzro.signal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openzro.name" . }}-signal
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Relay selector labels
*/}}
{{- define "openzro.relay.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openzro.name" . }}-relay
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Dashboard selector labels
*/}}
{{- define "openzro.dashboard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openzro.name" . }}-dashboard
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Create the name of the management service account to use
*/}}
{{- define "openzro.management.serviceAccountName" -}}
{{- if .Values.management.serviceAccount.create }}
{{- default (printf "%s-management" (include "openzro.fullname" .)) .Values.management.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.management.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the signal service account to use
*/}}
{{- define "openzro.signal.serviceAccountName" -}}
{{- if .Values.signal.serviceAccount.create }}
{{- default (printf "%s-signal" (include "openzro.fullname" .)) .Values.signal.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.signal.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the relay service account to use
*/}}
{{- define "openzro.relay.serviceAccountName" -}}
{{- if .Values.relay.serviceAccount.create }}
{{- default (printf "%s-relay" (include "openzro.fullname" .)) .Values.relay.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.relay.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the dashboard service account to use
*/}}
{{- define "openzro.dashboard.serviceAccountName" -}}
{{- if .Values.dashboard.serviceAccount.create }}
{{- default (printf "%s-dashboard" (include "openzro.fullname" .)) .Values.dashboard.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.dashboard.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Allow the release namespace to be overridden
*/}}
{{- define "openzro.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace -}}
{{- end -}}


{{/*
Database credential helpers — central source of truth so chart
templates render management's DSN string and Dex's config Secret
from the same `postgres:`/`mysql:` block in values.yaml.

Component-aware variants check `<engine>.overrides.<component>`
first, falling back to the top-level username/password.
*/}}

{{/*
Engine selection guard. Returns "postgres", "mysql", or "" (sqlite).
Fails template rendering if both postgres.enabled and mysql.enabled
are true — they're mutually exclusive.
*/}}
{{- define "openzro.store.engine" -}}
{{- $pg := and .Values.postgres .Values.postgres.enabled -}}
{{- $my := and .Values.mysql .Values.mysql.enabled -}}
{{- if and $pg $my -}}
{{- fail "postgres.enabled and mysql.enabled are mutually exclusive — pick one or the other" -}}
{{- else if $pg -}}postgres
{{- else if $my -}}mysql
{{- end -}}
{{- end -}}

{{- define "openzro.postgres.managementUser" -}}
{{- $o := dig "overrides" "management" dict .Values.postgres -}}
{{- $o.username | default .Values.postgres.username -}}
{{- end -}}

{{- define "openzro.postgres.managementPassword" -}}
{{- $o := dig "overrides" "management" dict .Values.postgres -}}
{{- $o.password | default .Values.postgres.password -}}
{{- end -}}

{{- define "openzro.postgres.dexUser" -}}
{{- $o := dig "overrides" "dex" dict .Values.postgres -}}
{{- $o.username | default .Values.postgres.username -}}
{{- end -}}

{{- define "openzro.postgres.dexPassword" -}}
{{- $o := dig "overrides" "dex" dict .Values.postgres -}}
{{- $o.password | default .Values.postgres.password -}}
{{- end -}}

{{/*
Renders the lib/pq DSN string the management daemon expects.
Format mirrors what `psql` accepts on the command line.
*/}}
{{- define "openzro.postgres.managementDSN" -}}
host={{ .Values.postgres.host }} port={{ .Values.postgres.port }} dbname={{ .Values.postgres.databases.management }} user={{ include "openzro.postgres.managementUser" . }} password={{ include "openzro.postgres.managementPassword" . }} sslmode={{ .Values.postgres.sslMode }}
{{- end -}}

{{- define "openzro.mysql.managementUser" -}}
{{- $o := dig "overrides" "management" dict .Values.mysql -}}
{{- $o.username | default .Values.mysql.username -}}
{{- end -}}

{{- define "openzro.mysql.managementPassword" -}}
{{- $o := dig "overrides" "management" dict .Values.mysql -}}
{{- $o.password | default .Values.mysql.password -}}
{{- end -}}

{{- define "openzro.mysql.dexUser" -}}
{{- $o := dig "overrides" "dex" dict .Values.mysql -}}
{{- $o.username | default .Values.mysql.username -}}
{{- end -}}

{{- define "openzro.mysql.dexPassword" -}}
{{- $o := dig "overrides" "dex" dict .Values.mysql -}}
{{- $o.password | default .Values.mysql.password -}}
{{- end -}}

{{/*
Renders the go-sql-driver/mysql DSN string the management daemon
expects: user:password@tcp(host:port)/dbname?tls=<mode>&parseTime=true
*/}}
{{- define "openzro.mysql.managementDSN" -}}
{{- $u := include "openzro.mysql.managementUser" . -}}
{{- $p := include "openzro.mysql.managementPassword" . -}}
{{- printf "%s:%s@tcp(%s:%d)/%s?tls=%s&parseTime=true" $u $p .Values.mysql.host (.Values.mysql.port | int) .Values.mysql.databases.management .Values.mysql.tls -}}
{{- end -}}

{{/*
Renders the lib/pq DSN string for the flow events HOT tier.
*/}}
{{- define "openzro.postgres.flowDSN" -}}
host={{ .Values.postgres.host }} port={{ .Values.postgres.port }} dbname={{ .Values.postgres.databases.flow }} user={{ include "openzro.postgres.managementUser" . }} password={{ include "openzro.postgres.managementPassword" . }} sslmode={{ .Values.postgres.sslMode }}
{{- end -}}

{{/*
Renders the lib/pq DSN string for the activity events log.
*/}}
{{- define "openzro.postgres.activityDSN" -}}
host={{ .Values.postgres.host }} port={{ .Values.postgres.port }} dbname={{ .Values.postgres.databases.activity }} user={{ include "openzro.postgres.managementUser" . }} password={{ include "openzro.postgres.managementPassword" . }} sslmode={{ .Values.postgres.sslMode }}
{{- end -}}

{{/*
Renders the go-sql-driver/mysql DSN for the flow events HOT tier.
*/}}
{{- define "openzro.mysql.flowDSN" -}}
{{- $u := include "openzro.mysql.managementUser" . -}}
{{- $p := include "openzro.mysql.managementPassword" . -}}
{{- printf "%s:%s@tcp(%s:%d)/%s?tls=%s&parseTime=true" $u $p .Values.mysql.host (.Values.mysql.port | int) .Values.mysql.databases.flow .Values.mysql.tls -}}
{{- end -}}

{{/*
Renders the go-sql-driver/mysql DSN for the activity events log.
*/}}
{{- define "openzro.mysql.activityDSN" -}}
{{- $u := include "openzro.mysql.managementUser" . -}}
{{- $p := include "openzro.mysql.managementPassword" . -}}
{{- printf "%s:%s@tcp(%s:%d)/%s?tls=%s&parseTime=true" $u $p .Values.mysql.host (.Values.mysql.port | int) .Values.mysql.databases.activity .Values.mysql.tls -}}
{{- end -}}

{{/*
Auto-wired environment variables for the management Deployment.
Renders the env block that selects the right backend for the data,
flow, and activity stores from postgres.enabled / mysql.enabled.

Operators can still override anything via management.envRaw — Kubernetes
applies env in order and the LAST entry with a given name wins, so
envRaw (rendered after this block in management-deployment.yaml) is
always authoritative.
*/}}
{{- define "openzro.management.autoWiredEnv" -}}
{{- $engine := include "openzro.store.engine" . -}}
{{- if eq $engine "postgres" }}
- name: OPENZRO_STORE_ENGINE
  value: postgres
- name: OPENZRO_STORE_ENGINE_POSTGRES_DSN
  value: {{ include "openzro.postgres.managementDSN" . | quote }}
- name: OPENZRO_FLOW_STORE_ENGINE
  value: postgres
- name: OPENZRO_FLOW_STORE_DSN
  value: {{ include "openzro.postgres.flowDSN" . | quote }}
- name: OZ_ACTIVITY_EVENT_STORE_ENGINE
  value: postgres
- name: OZ_ACTIVITY_EVENT_POSTGRES_DSN
  value: {{ include "openzro.postgres.activityDSN" . | quote }}
{{- else if eq $engine "mysql" }}
- name: OPENZRO_STORE_ENGINE
  value: mysql
- name: OPENZRO_STORE_ENGINE_MYSQL_DSN
  value: {{ include "openzro.mysql.managementDSN" . | quote }}
- name: OPENZRO_FLOW_STORE_ENGINE
  value: mysql
- name: OPENZRO_FLOW_STORE_DSN
  value: {{ include "openzro.mysql.flowDSN" . | quote }}
- name: OZ_ACTIVITY_EVENT_STORE_ENGINE
  value: mysql
- name: OZ_ACTIVITY_EVENT_MYSQL_DSN
  value: {{ include "openzro.mysql.activityDSN" . | quote }}
{{- end -}}
{{- end -}}

{{/*
Bootstrap username/password for the provisioning Job. Falls back to
the runtime credential when the dedicated provisioning credential is
not provided.
*/}}
{{- define "openzro.postgres.bootstrapUser" -}}
{{- $p := dig "provisioning" "username" "" .Values.postgres -}}
{{- $p | default .Values.postgres.username -}}
{{- end -}}

{{- define "openzro.postgres.bootstrapPassword" -}}
{{- $p := dig "provisioning" "password" "" .Values.postgres -}}
{{- $p | default .Values.postgres.password -}}
{{- end -}}

{{- define "openzro.mysql.bootstrapUser" -}}
{{- $p := dig "provisioning" "username" "" .Values.mysql -}}
{{- $p | default .Values.mysql.username -}}
{{- end -}}

{{- define "openzro.mysql.bootstrapPassword" -}}
{{- $p := dig "provisioning" "password" "" .Values.mysql -}}
{{- $p | default .Values.mysql.password -}}
{{- end -}}

{{/*
Name of the Secret the chart renders for Dex when postgres.enabled
or mysql.enabled. The Dex subchart consumes it via configSecret.create=false +
configSecret.name=<this>.
*/}}
{{- define "openzro.dex.configSecretName" -}}
{{- printf "%s-dex-config" (include "openzro.fullname" .) -}}
{{- end -}}

