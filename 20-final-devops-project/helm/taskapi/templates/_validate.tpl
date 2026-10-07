{{/*
  Fail fast on a combination that cannot work, rather than shipping it and
  letting pods hang in ContainerCreating.

  persistence uses a ReadWriteOnce PVC. RWO is bound to ONE node, so a second
  replica scheduled anywhere else can never mount it -- it waits forever with
  "Multi-Attach error" or an unschedulable volume. Allowing an HPA to scale such
  a Deployment is a guaranteed outage under exactly the load the HPA exists for.

  So: persistent + autoscaled past 1 replica is rejected here. Pick one of the
  two shipped values files, or move state to a database / a StatefulSet with
  volumeClaimTemplates (where each replica gets its OWN volume).
*/}}
{{- define "taskapi.validate" -}}
{{- if and .Values.persistence.enabled .Values.autoscaling.enabled -}}
{{- if gt (int .Values.autoscaling.maxReplicas) 1 -}}
{{- fail (printf "invalid values: persistence.enabled=true needs a single replica, but autoscaling.maxReplicas=%d. A ReadWriteOnce volume cannot be mounted by pods on more than one node. Either set persistence.enabled=false (see values-scaled.yaml) or set autoscaling.maxReplicas=1." (int .Values.autoscaling.maxReplicas)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
