{{- define "clinicflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clinicflow.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "clinicflow.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "clinicflow.labels" -}}
app.kubernetes.io/name: {{ include "clinicflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "clinicflow.backendSelector" -}}
app.kubernetes.io/name: {{ include "clinicflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend
{{- end -}}

{{- define "clinicflow.frontendSelector" -}}
app.kubernetes.io/name: {{ include "clinicflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end -}}

{{- define "clinicflow.postgresSelector" -}}
app.kubernetes.io/name: {{ include "clinicflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: postgres
{{- end -}}

{{- define "clinicflow.backendImage" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}/{{ .Values.backend.image.name }}:{{ .Values.backend.image.tag | default (printf "sha-%s" .Chart.AppVersion) }}
{{- end -}}

{{- define "clinicflow.frontendImage" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}/{{ .Values.frontend.image.name }}:{{ .Values.frontend.image.tag | default (printf "sha-%s" .Chart.AppVersion) }}
{{- end -}}

{{- define "clinicflow.secretName" -}}
{{- .Values.postgres.existingSecret | default (printf "%s-db" (include "clinicflow.fullname" .)) -}}
{{- end -}}

{{/*
  The securityContext every pod in this chart shares. Written once so it cannot
  drift between workloads, and it is what lets the namespace enforce Pod
  Security Admission at `restricted`.
*/}}
{{- define "clinicflow.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
