# MIMIR Post-Return Check Runbook

Last updated: 2026-03-27 (America/Toronto)

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

- not yet installed
- blocked only by a degraded remote link during this rollout session

That means the automation path is designed and versioned, but not yet active on
MIMIR.

## Repo assets

- `scripts/verify-after-talos-return.sh`
- `ops/mimir/systemd/prometheus-after-talos-return.service`
- `ops/mimir/systemd/prometheus-after-talos-return.timer`
- `ops/mimir/talos-return.env.example`

## Intended MIMIR install paths

- script: `/opt/prometheus-ops/verify-after-talos-return.sh`
- env file: `/etc/prometheus-ops/talos-return.env`
- Talos config: `/home/boi/.config/prometheus/talosconfig`
- kubeconfig: `/home/boi/.config/prometheus/kubeconfig`
- log file: `/home/boi/.local/state/prometheus-ops/verify-after-talos-return.log`

## Intended timer behavior

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

- `NODE_IP=192.168.2.49`
- `TALOS_API_PORT=50000`
- `TALOS_HEALTH_MODE=auto`
- `OPEN_WEBUI_URL=http://192.168.2.201/`
- `VLLM_MODELS_URL=http://192.168.2.205:8000/v1/models`
- `ADGUARD_URL=http://192.168.2.200/`
- `GRAFANA_URL=http://192.168.2.202/login`

`TALOS_HEALTH_MODE=auto` prefers `talosctl health` when the helper host can run
`talosctl` natively. If the helper host cannot execute `talosctl`, the script
falls back to a direct TCP reachability probe of the Talos API on
`NODE_IP:TALOS_API_PORT`.

## Manual activation plan once the link is stable

1. Copy `talosctl`, the verification script, the unit files, and both configs to MIMIR.
2. Install the script into `/opt/prometheus-ops/`.
3. Install the env file into `/etc/prometheus-ops/`.
4. Install the unit files into `/etc/systemd/system/`.
5. Run `sudo systemctl daemon-reload`.
6. Run `sudo systemctl start prometheus-after-talos-return.service` once.
7. Check the log file under `/home/boi/.local/state/prometheus-ops/`.
8. Run `sudo systemctl enable --now prometheus-after-talos-return.timer`.
9. Confirm the timer with `systemctl list-timers | grep prometheus-after-talos-return`.

## Why this is external automation

The cluster cannot verify its own return while it is still down. That is why the
post-return automation belongs on MIMIR, not as an in-cluster CronJob.
