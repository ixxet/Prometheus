# Windows Dual-Boot And Talos Return Runbook

Last updated: 2026-04-13 (America/Toronto)

## Purpose

This runbook documents the safe operator path when the tower temporarily boots
into Windows and later returns to Talos.

Important boundary:

- this is acceptable only because Windows does not own the Talos SSD
- service availability drops to zero while the machine is in Windows
- persistence should survive because the Talos SSD and PVC-backed state remain
  untouched

## Current assumptions

- Talos node IP: `192.168.50.197`
- Kubernetes API endpoint: `192.168.50.197`
- AdGuard: `192.168.50.200`
- Open WebUI: `192.168.50.201`
- vLLM: `192.168.50.205:8000`
- Talos config:
  - `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig`
- kubeconfig:
  - `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig`

## Before booting Windows

Use a clean Talos shutdown:

```bash
talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig \
  -e 192.168.50.197 \
  -n 192.168.50.197 shutdown
```

Then boot Windows from BIOS or the boot menu.

## What should survive

- Postgres data
- LangGraph thread and checkpoint state
- Mem0/Qdrant state
- Open WebUI data
- AdGuard data
- `vLLM` model cache on disk
- off-tower archive data on MIMIR

## What will not survive during the Windows session

- cluster availability
- Talos API
- Kubernetes API
- LAN service endpoints
- any DNS served by the tower

This is expected downtime, not corruption.

## Returning to Talos

1. Enter BIOS or the boot menu.
2. Select the Talos SSD if Windows has changed boot priority.
3. Wait for the node to finish booting.
4. Run the post-return verification script:

```bash
/Users/zizo/Personal-Projects/Computers/Prometheus/scripts/verify-after-talos-return.sh
```

## What the verification script checks

- Talos node health
- Kubernetes API reachability
- Flux kustomization health
- key pods:
  - `adguard-home`
  - `open-webui`
  - `vllm`
  - `langgraph`
  - `postgres`
  - `qdrant`
  - `tei-embeddings`
  - `summarizer`
  - `athena`
  - `apollo`
  - `nats`
- LAN endpoints:
  - `http://192.168.50.200`
  - `http://192.168.50.201`
  - `http://192.168.50.205:8000/v1/models`
  - `http://192.168.50.203/api/health`
- LangGraph `/healthz` through a temporary port-forward
- ATHENA `/api/v1/health` through a temporary port-forward
- APOLLO `/api/v1/health` through a temporary port-forward
- NATS `/varz` through a temporary port-forward

## What can take longer after return

- `vLLM` still needs to load the model into VRAM after boot
- the node may be healthy before every app endpoint is ready

That is why the script waits instead of checking once and failing immediately.

## Safety notes

- Do not let Windows initialize, repair, or format the Talos SSD.
- Do not use Windows Disk Management on the Talos disk.
- Treat BIOS boot-order changes as likely if Windows was used most recently.

## Relationship to live observability

Prometheus, Grafana, metrics-server, and the dashboard set are already live on
this machine. What dual boot changes is the operator model, not the value of
the observability stack.

What changes because of dual boot:

- metrics history has expected gaps while the tower is in Windows
- dashboards are still useful for health and regression spotting, but they do
  not represent continuous uptime until the tower stops acting as a dual-boot
  workstation
- the return-check script is now host-neutral enough to run from the Mac or
  from MIMIR, where the committed systemd timer assets are now installed and
  enabled

That is acceptable for this phase.
