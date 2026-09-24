{{- define "project.namespace" -}}
project-{{ .Values.name }}
{{- end }}

{{- define "project.labels" -}}
app.kubernetes.io/part-of: kid
app.kubernetes.io/managed-by: argocd
k8tre.io/project: {{ .Values.name }}
{{- end }}

{{/* JSON list of the size definitions offered by this project. */}}
{{- define "project.sizes" -}}
{{- $out := list -}}
{{- range .Values.sizes -}}
{{- $s := index $.Values.sizeCatalogue . | required (printf "unknown size %q" .) -}}
{{- $out = append $out (merge (dict "slug" .) $s) -}}
{{- end -}}
{{- toJson $out -}}
{{- end }}
