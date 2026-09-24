{{/*
kid.application renders an Argo CD Application that syncs a folder of this
repository.  Arguments (dict):
  root       - the root context ($)
  name       - Application name
  path       - folder in this repository
  namespace  - destination namespace
  wave       - sync wave (string)
  createNamespace - bool
  skipDryRun - bool; set for folders that use CRDs installed by another app
*/}}
{{- define "kid.application" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: {{ .root.Values.repoURL }}
    targetRevision: {{ .root.Values.revision }}
    path: {{ .path }}
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  syncPolicy:
    {{- include "kid.syncPolicy" . | nindent 4 }}
{{- end }}

{{- define "kid.syncPolicy" -}}
automated:
  prune: true
  selfHeal: true
retry:
  limit: 10
  backoff:
    duration: 15s
    factor: 2
    maxDuration: 5m
syncOptions:
  - ServerSideApply=true
  {{- if .createNamespace }}
  - CreateNamespace=true
  {{- end }}
  {{- if .skipDryRun }}
  - SkipDryRunOnMissingResource=true
  {{- end }}
{{- end }}
