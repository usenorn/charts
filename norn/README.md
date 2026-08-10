# Norn Helm chart

This chart installs Norn on Kubernetes. Its default profile includes persistent single-node PostgreSQL, Valkey, and Garage services suitable for a small self-hosted installation. Each service can be replaced with an external one.

## Requirements

- Kubernetes 1.34 or newer
- Helm 3 or 4
- An Ingress controller when `ingress.enabled=true`
- DNS records for the Norn and storage hosts

The bundled data services are not highly available. Back up their persistent volumes or configure external managed services before using Norn for data that cannot be recreated.

## Install

Add two DNS records pointing to the same Ingress load balancer. The storage host defaults to `storage.<Norn host>`.

```console
helm install norn oci://ghcr.io/usenorn/charts/norn \
  --namespace norn \
  --create-namespace \
  --set ingress.host=norn.example.com \
  --set ingress.className=nginx \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt'
```

This example expects DNS for `norn.example.com` and `storage.norn.example.com`. Set `garage.publicHost` when the derived storage name is unsuitable. Set `ingress.tls.secretName` when TLS is managed outside ingress-shim.

The chart generates database, Valkey, Garage, and Norn encryption credentials. They live only in a Kubernetes Secret and are retained if the release is uninstalled. Keep that Secret with the persistent volume claims when reinstalling.

```console
helm test norn --namespace norn
```

## Existing Secret

Set `norn.existingSecret` to prevent the chart from creating credentials. When bundled services are enabled, the Secret must contain:

- `NORN_SECURITY_ENCRYPTION_KEY`
- `POSTGRES_PASSWORD`
- `NORN_POSTGRES_DSN`
- `VALKEY_PASSWORD`
- `NORN_VALKEY_PASSWORD`
- `NORN_ASYNQ_PASSWORD`
- `GARAGE_DEFAULT_ACCESS_KEY`
- `GARAGE_DEFAULT_SECRET_KEY`
- `GARAGE_RPC_SECRET`
- `GARAGE_ADMIN_TOKEN`
- `GARAGE_METRICS_TOKEN`
- `NORN_STORAGE_ACCESS_KEY_ID`
- `NORN_STORAGE_SECRET_ACCESS_KEY`
- `valkey.conf`

`valkey.conf` must enable authentication with the same password as `VALKEY_PASSWORD`. Extra application secrets such as SMTP credentials, licence data, and source-control application keys can be added to the same Secret using their `NORN_*` environment names.

The alternative `norn.secretEnv` map creates those additional keys in the chart-managed Secret. Values supplied through Helm are stored in Helm release state; use an existing Secret when that is unsuitable.

## External services

Disable a bundled service and provide its connection settings:

```yaml
norn:
  existingSecret: norn-production

postgresql:
  enabled: false

valkey:
  enabled: false
  external:
    address: valkey.database.svc.cluster.local:6379
    username: norn

garage:
  enabled: false
  external:
    endpoint: https://s3.eu-west-1.amazonaws.com
    region: eu-west-1
    bucket: norn
    usePathStyle: false
```

The existing Secret must then provide `NORN_POSTGRES_DSN`, any Valkey passwords, `NORN_STORAGE_ACCESS_KEY_ID`, `NORN_STORAGE_SECRET_ACCESS_KEY`, and `NORN_SECURITY_ENCRYPTION_KEY`.

External object storage must allow browser `GET`, `HEAD`, and `PUT` requests from the Norn origin. The Garage CORS Job only runs for the bundled service.

## Configuration

`norn.configEnv` accepts non-secret `NORN_*` environment variables. `norn.secretEnv` accepts secret `NORN_*` values when the chart manages the Secret. `norn.extraEnv` and `norn.extraEnvFrom` expose the native Kubernetes container fields for integrations that need `valueFrom` references.

The chart owns these settings and overrides matching entries elsewhere:

- `NORN_APP_BASE_URL`
- `NORN_HTTP_ADDR`
- `NORN_WORKER_HEALTH_ADDR`
- PostgreSQL, Valkey, Asynq, and storage connection settings
- `NORN_SESSION_SECURE` when the application URL uses HTTPS

If the API trusts a forwarded client-address header, set `NORN_HTTP_CLIENT_IP_HEADER` and `NORN_HTTP_TRUSTED_PROXIES` to match the actual Ingress proxy addresses. Do not use an unrestricted trusted-proxy range on a cluster where untrusted workloads can reach the API Service.

SSE traffic under `/v1/workspaces/<workspace>/events` must not be buffered or compressed by the Ingress controller. The chart does not add controller-specific middleware; configure that exclusion in the selected controller if compression or buffering is enabled globally.

## Ingress-free installation

When another system owns public routing, disable the Ingress and provide both public origins:

```yaml
ingress:
  enabled: false
  tls:
    enabled: false

norn:
  baseUrl: https://norn.example.com

garage:
  publicEndpoint: https://storage.norn.example.com
  service:
    type: LoadBalancer
```

The storage endpoint must be a different origin from Norn.

## Upgrades and data

Each revision creates a migration Job that runs database migrations and then reconciles the authorization policy. Norn pods wait for that Job before starting. Use `helm upgrade --wait` and a timeout long enough for the migration Job:

```console
helm upgrade norn oci://ghcr.io/usenorn/charts/norn \
  --namespace norn \
  --reuse-values \
  --wait \
  --timeout 15m
```

Add `--atomic` with Helm 3 or `--rollback-on-failure` with Helm 4 when automatic rollback is wanted.

StatefulSet volume claims are retained by Kubernetes when the release is removed. PostgreSQL major-version upgrades require PostgreSQL's data upgrade procedure; changing only `postgresql.image.tag` across major versions is not supported.
