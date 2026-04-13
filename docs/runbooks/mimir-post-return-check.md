# MIMIR Post-Return Check Runbook

Last updated: 2026-04-13 (America/Toronto)

## Purpose

Describe the MIMIR-hosted automation path for checking the tower after it
returns from a Windows session.

## Current status

Repo side:

- complete
- host-neutral script committed
- systemd service committed
- systemd timer committed
- example environment file committed

Host side on MIMIR:

- installed
- manual service invocation passed
- timer enabled and active

That means the automation path is now both versioned in Git and active on
MIMIR.

Important maintenance rule:

- when `scripts/verify-after-talos-return.sh` changes in Git, recopy the script
  to `/opt/prometheus-ops/` on MIMIR and rerun the one-shot service once
- do not assume the helper host is using the latest repo-side checks until that
  sync step is done

## Repo assets

- `scripts/verify-after-talos-return.sh`
- `ops/mimir/systemd/prometheus-after-talos-return.service`
- `ops/mimir/systemd/prometheus-after-talos-return.timer`
- `ops/mimir/talos-return.env.example`

## Live MIMIR install paths

- script: `/opt/prometheus-ops/verify-after-talos-return.sh`
- env file: `/etc/prometheus-ops/talos-return.env`
- Talos config: `/home/boi/.config/prometheus/talosconfig`
- kubeconfig: `/home/boi/.config/prometheus/kubeconfig`
- log file: `/home/boi/.local/state/prometheus-ops/verify-after-talos-return.log`

## Timer behavior

- one-shot service: `prometheus-after-talos-return.service`
- timer: `prometheus-after-talos-return.timer`
- first run: `5m` after boot
- recurring run: every `30m`
- `Persistent=true` so missed runs catch up after downtime

## Environment file shape

Use the example file as the source:

```bash
cp ops/mimir/talos-return.env.example /etc/prometheus-ops/talos-return.env
```

Key values:

- `NODE_IP=192.168.50.197`
- `TALOS_ENDPOINT=192.168.50.197`
- `K8S_ENDPOINT=https://192.168.50.197:6443`
- `TALOS_API_PORT=50000`
- `TALOS_HEALTH_MODE=auto`
- `OPEN_WEBUI_URL=http://192.168.50.201/`
- `VLLM_MODELS_URL=http://192.168.50.205:8000/v1/models`
- `ADGUARD_URL=http://192.168.50.200/`
- `GRAFANA_URL=http://192.168.50.202/login`
- `SUMMARIZER_URL=http://192.168.50.203/api/health`
- `ATHENA_NAMESPACE=athena`
- `ATHENA_SERVICE=athena`
- `ATHENA_LOCAL_URL=http://127.0.0.1:18083/api/v1/health`
- `APOLLO_NAMESPACE=agents`
- `APOLLO_SERVICE=apollo`
- `APOLLO_LOCAL_URL=http://127.0.0.1:18084/api/v1/health`
- `NATS_NAMESPACE=agents`
- `NATS_SERVICE=nats`
- `NATS_LOCAL_URL=http://127.0.0.1:18222/varz`

`TALOS_HEALTH_MODE=auto` prefers `talosctl health` when the helper host can run
`talosctl` natively. The script now passes `-e "$TALOS_ENDPOINT"` explicitly so
a stale endpoint inside `talosconfig` does not block health checks, and it uses
`K8S_ENDPOINT` for the Kubernetes phase of `talosctl health`. If the helper
host cannot execute `talosctl`, the script falls back to a direct TCP
reachability probe of the Talos API on `NODE_IP:TALOS_API_PORT`.

The return check now covers the bounded ATHENA path explicitly:

- ATHENA health
- APOLLO health
- NATS monitor reachability
- summarizer health in addition to the earlier core platform checks

## Verified activation path

1. Copy the verification script, configs, and unit files to MIMIR.
2. Install the script into `/opt/prometheus-ops/`.
3. Install the env file into `/etc/prometheus-ops/`.
4. Install the unit files into `/etc/systemd/system/`.
5. Install `talosctl` into `/usr/local/bin/`.
6. Run `sudo systemctl daemon-reload`.
7. Run `sudo systemctl start prometheus-after-talos-return.service` once.
8. Check the log file under `/home/boi/.local/state/prometheus-ops/`.
9. Run `sudo systemctl enable --now prometheus-after-talos-return.timer`.
10. Confirm the timer with `systemctl list-timers | grep prometheus-after-talos-return`.

## Refresh path after script changes

If the repo-side verification script gains new checks, refresh MIMIR with:

```bash
scp scripts/verify-after-talos-return.sh boi@<mimir>:/tmp/verify-after-talos-return.sh
ssh boi@<mimir> 'sudo install -m 0755 /tmp/verify-after-talos-return.sh /opt/prometheus-ops/verify-after-talos-return.sh && sudo systemctl start prometheus-after-talos-return.service'
```

Success signal:

- the service exits `0/SUCCESS`
- the log file shows the new checks running

## Current live status

Current timer state:

- `enabled`
- `active`
- next trigger every `30m`

Current service result:

- last manual invocation exited `0/SUCCESS`
- log file confirmed `Post-return verification passed.`

## Why this is external automation

The cluster cannot verify its own return while it is still down. That is why the
post-return automation belongs on MIMIR, not as an in-cluster CronJob.
