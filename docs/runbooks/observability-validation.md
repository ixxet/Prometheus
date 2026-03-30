# Observability Validation Runbook

Last updated: 2026-03-27 (America/Toronto)

## Purpose

Validate the `v0.6.x` observability slice without relying on hand-created
Grafana state.

## Expected live endpoints

- Grafana: `http://192.168.2.202`
- Prometheus: internal-only in `observability`
- Alertmanager: internal-only in `observability`

## Core rollout checks

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get kustomizations -n flux-system
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get pods -n observability
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get pods -n agents -l app.kubernetes.io/name=postgres-exporter
```

Success signals:

- `infra-observability` is `True`
- Prometheus, Grafana, metrics-server, node-exporter, kube-state-metrics, and DCGM exporter are `Running`
- `postgres-exporter` is `1/1 Running`

## Metrics API checks

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig top nodes
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig top pods -A | head -n 40
```

Success signal:

- both commands return real CPU and memory data

## Grafana reachability

```bash
curl -I http://192.168.2.202
```

Success signal:

- `HTTP/1.1 302 Found` to `/login` or `200 OK`

## Git-provisioned dashboards

List the dashboard ConfigMaps:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get configmaps -n observability -l grafana_dashboard=1
```

Confirm Grafana sidecar ingestion:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig exec -n observability kube-prometheus-stack-grafana-0 -c grafana-sc-dashboard -- ls -1 /tmp/dashboards
```

Expected custom dashboards:

- `ai-runtime-health.json`
- `cluster-node-health.json`
- `flux-health.json`
- `gpu-vllm.json`
- `network-cilium.json`
- `postgres-health.json`

## Grafana API proof

Get the admin credentials from the cluster:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get secret -n observability grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get secret -n observability grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Query the dashboard index:

```bash
curl -s -u 'admin:<password>' http://192.168.2.202/api/search | jq -r '.[] | [.uid, .title] | @tsv'
```

Expected custom UIDs:

- `prom-cluster-node-health`
- `prom-flux-health`
- `prom-gpu-vllm`
- `prom-postgres-health`
- `prom-ai-runtime-health`
- `prom-network-cilium`

## Scrape-surface checks

Validate the ServiceMonitors exist:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get servicemonitors -n observability
```

Expected non-default targets include:

- `flux-helm-controller`
- `flux-kustomize-controller`
- `flux-source-controller`
- `flux-notification-controller`
- `cilium-operator`
- `cilium-envoy`
- `metrics-server`
- `dcgm-exporter`
- `postgres-exporter`
- `vllm`

## What this runbook does not prove

- continuous uptime while the tower still boots Windows sometimes
- long-term retention sizing on the Talos SSD
- custom LangGraph or Open WebUI instrumentation

Those remain later observability hardening tasks.

## Known restart pitfall

If Grafana comes back as `Init:CrashLoopBackOff` after a tower reboot, inspect:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n observability logs kube-prometheus-stack-grafana-0 -c init-chown-data --previous
```

The observed failure mode in this repo was the `init-chown-data` container
trying to `chown` restart-created `png`, `csv`, and `pdf` directories on the
Grafana PVC. The current fix in Git is to keep `grafana.initChownData` disabled.
