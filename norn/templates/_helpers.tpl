{{- define "norn.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "norn.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "norn.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "norn.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "norn.labels" -}}
helm.sh/chart: {{ include "norn.chart" . }}
app.kubernetes.io/name: {{ include "norn.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "norn.selectorLabels" -}}
app.kubernetes.io/name: {{ include "norn.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "norn.componentSelectorLabels" -}}
{{ include "norn.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "norn.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "norn.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "norn.image" -}}
{{- $image := .image -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $image.repository $image.digest -}}
{{- else -}}
{{- printf "%s:%s" $image.repository (default .root.Chart.AppVersion $image.tag) -}}
{{- end -}}
{{- end }}

{{- define "norn.waitImage" -}}
{{- $tag := .Values.migration.waitImage.tag -}}
{{- if not $tag -}}
{{- $minor := regexFind "[0-9]+" .Capabilities.KubeVersion.Minor -}}
{{- $tag = printf "v%s.%s.0" .Capabilities.KubeVersion.Major $minor -}}
{{- end -}}
{{- $image := dict "repository" .Values.migration.waitImage.repository "tag" $tag "digest" .Values.migration.waitImage.digest -}}
{{- include "norn.image" (dict "root" . "image" $image) -}}
{{- end }}

{{- define "norn.appURL" -}}
{{- if .Values.ingress.enabled -}}
{{- ternary "https" "http" .Values.ingress.tls.enabled }}://{{ .Values.ingress.host }}
{{- else -}}
{{- required "norn.baseUrl is required when ingress is disabled" .Values.norn.baseUrl -}}
{{- end -}}
{{- end }}

{{- define "norn.storageHost" -}}
{{- default (printf "storage.%s" .Values.ingress.host) .Values.garage.publicHost -}}
{{- end }}

{{- define "norn.storageEndpoint" -}}
{{- if .Values.garage.enabled -}}
{{- if .Values.ingress.enabled -}}
{{- ternary "https" "http" .Values.ingress.tls.enabled }}://{{ include "norn.storageHost" . }}
{{- else -}}
{{- required "garage.publicEndpoint is required for bundled Garage when ingress is disabled" .Values.garage.publicEndpoint -}}
{{- end -}}
{{- else -}}
{{- required "garage.external.endpoint is required when garage.enabled is false" .Values.garage.external.endpoint -}}
{{- end -}}
{{- end }}

{{- define "norn.secretName" -}}
{{- default (printf "%s-env" (include "norn.fullname" .)) .Values.norn.existingSecret -}}
{{- end }}

{{- define "norn.migrationJobName" -}}
{{- printf "%s-migrate-%d" (include "norn.fullname" .) .Release.Revision | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "norn.postgresqlHost" -}}
{{- printf "%s-postgresql" (include "norn.fullname" .) -}}
{{- end }}

{{- define "norn.valkeyHost" -}}
{{- printf "%s-valkey" (include "norn.fullname" .) -}}
{{- end }}

{{- define "norn.garageHost" -}}
{{- printf "%s-garage" (include "norn.fullname" .) -}}
{{- end }}

{{- define "norn.validate" -}}
{{- if and .Values.norn.existingSecret (gt (len .Values.norn.secretEnv) 0) -}}
{{- fail "norn.secretEnv must be empty when norn.existingSecret is set" -}}
{{- end -}}
{{- if and .Values.ingress.enabled (eq .Values.ingress.host (include "norn.storageHost" .)) .Values.garage.enabled -}}
{{- fail "Garage must use a different public host from Norn" -}}
{{- end -}}
{{- if and (not .Values.postgresql.enabled) (not .Values.norn.existingSecret) (not .Values.postgresql.external.dsn) -}}
{{- fail "postgresql.external.dsn or norn.existingSecret is required when postgresql.enabled is false" -}}
{{- end -}}
{{- if and (not .Values.valkey.enabled) (not .Values.valkey.external.address) -}}
{{- fail "valkey.external.address is required when valkey.enabled is false" -}}
{{- end -}}
{{- if and (not .Values.garage.enabled) (not .Values.garage.external.bucket) -}}
{{- fail "garage.external.bucket is required when garage.enabled is false" -}}
{{- end -}}
{{- if and (not .Values.garage.enabled) (not .Values.norn.existingSecret) (or (not .Values.garage.external.accessKeyId) (not .Values.garage.external.secretAccessKey)) -}}
{{- fail "Garage external credentials or norn.existingSecret are required when garage.enabled is false" -}}
{{- end -}}
{{- end }}

{{- define "norn.envFrom" -}}
- configMapRef:
    name: {{ include "norn.fullname" . }}-env
- secretRef:
    name: {{ include "norn.secretName" . }}
{{- with .Values.norn.extraEnvFrom }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "norn.migrationWaitInitContainers" -}}
- name: wait-for-migration-job
  image: {{ include "norn.waitImage" . }}
  imagePullPolicy: {{ .Values.migration.waitImage.pullPolicy }}
  command:
    - kubectl
  args:
    - get
    - job
    - {{ include "norn.migrationJobName" . }}
    - --namespace
    - {{ .Release.Namespace }}
  volumeMounts:
    - name: kubernetes-api-access
      mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      readOnly: true
  securityContext:
    {{- toYaml .Values.containerSecurityContext | nindent 4 }}
- name: wait-for-migrations
  image: {{ include "norn.waitImage" . }}
  imagePullPolicy: {{ .Values.migration.waitImage.pullPolicy }}
  command:
    - kubectl
  args:
    - wait
    - --for=condition=complete
    - --timeout={{ .Values.migration.activeDeadlineSeconds }}s
    - job/{{ include "norn.migrationJobName" . }}
    - --namespace
    - {{ .Release.Namespace }}
  volumeMounts:
    - name: kubernetes-api-access
      mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      readOnly: true
  securityContext:
    {{- toYaml .Values.containerSecurityContext | nindent 4 }}
{{- end }}

{{- define "norn.migrationWaitVolume" -}}
- name: kubernetes-api-access
  projected:
    defaultMode: 420
    sources:
      - serviceAccountToken:
          expirationSeconds: 3600
          path: token
      - configMap:
          name: kube-root-ca.crt
          items:
            - key: ca.crt
              path: ca.crt
      - downwardAPI:
          items:
            - path: namespace
              fieldRef:
                apiVersion: v1
                fieldPath: metadata.namespace
{{- end }}

{{- define "norn.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
