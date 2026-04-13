# Network Relocation Runbook

Last updated: 2026-04-13 (America/Toronto)

## Purpose

This runbook covers the safe operator path when the Talos tower is physically
moved to a different LAN and the old `192.168.2.x` assumptions no longer hold.

This is different from the Windows dual-boot path:

- dual boot keeps the tower on the same network identity after it returns
- relocation changes the network around the node, so the old service IPs and
  old MIMIR subnet-route assumptions can break

Current home-base facts as of 2026-04-13:

- MIMIR tailnet IP: `100.109.171.72`
- MIMIR LAN IP: `192.168.50.171`
- Prometheus Talos node IP: `192.168.50.197`
- MIMIR now advertises `192.168.50.0/24` into Tailscale

## Best to worst operator scenarios

### 1. Best case: Windows elsewhere, Talos only at home base

- the tower may physically travel as a Windows machine
- Talos is only booted again on the home-base LAN
- the node comes back on the same router and usually the same DHCP identity
- this is operationally closest to "nothing changed"

### 2. Middle case: both MIMIR and Prometheus move together

- the safe Tailscale model still works
- MIMIR advertises the new LAN into the tailnet
- Prometheus remains reachable through MIMIR once the advertised subnet route is updated
- the relocation script is still the correct validation path

### 3. Worst case: Prometheus moves but MIMIR stays behind

- MIMIR cannot route to a LAN it is no longer attached to
- raw IPs, AdGuard assumptions, and NFS targets from the old site can all fail
- treat the moved LAN as a new recovery site until either MIMIR moves too or another route exists

## What survives

- Talos cluster state on disk
- Kubernetes objects and etcd state
- PVC-backed app data
- pulled container images already stored on disk
- `vLLM` model cache on disk
- staged Gemma GGUF artifacts on the dedicated cache PV

## What can break immediately

- Talos node IP if it was learned via DHCP
- Kubernetes API VIP reachability from the old LAN
- Cilium `LoadBalancer` service IPs:
  - `192.168.2.200` AdGuard
  - `192.168.2.201` Open WebUI
  - `192.168.2.202` Grafana
  - `192.168.2.203` summarizer
  - `192.168.2.205` `vLLM`
- AdGuard DNS expectations
- MIMIR subnet-route access to Prometheus
- the current Cloudflare quick-tunnel URL if the tunnel pod restarts
- any NFS mount targets that still point at the old site

Current example:

- `LangGraph` is currently blocked on the relocated LAN because its archive PV still
  mounts `192.168.2.40:/prometheus-vault`
- on `192.168.50.0/24`, that old NFS path has no route and the pod stays in
  `ContainerCreating`

## What MIMIR and Tailscale still can and cannot do

What still works:

- logging into MIMIR over Tailscale, as long as MIMIR still has outbound
  internet access

What stops working after Prometheus leaves the old LAN:

- MIMIR acting as the subnet-router path to Prometheus on `192.168.2.0/24`
- the current MIMIR-hosted post-return check as the primary way to validate the
  tower

Reason:

- MIMIR only has route knowledge for the original LAN
- once the tower is elsewhere, you should treat your Mac on the same new LAN as
  the primary operator path

If MIMIR moves with Prometheus and remains on the same LAN, that subnet-router
model still works. What breaks is the "MIMIR can route to Prometheus from
somewhere else forever" assumption.

## Before unplugging the tower

1. Capture the current state:

```bash
/Users/zizo/Personal-Projects/Computers/Prometheus/scripts/capture-pre-move-state.sh
```

This writes a local snapshot under:

- `ops/state-snapshots/<timestamp>/`

Important files in that snapshot:

- current pod/service/workload inventory
- Talos image cache list
- current quick Cloudflare tunnel URL
- key deployment YAMLs for `vllm`, summarizer, ATHENA, APOLLO, and LangGraph

2. Shut Talos down cleanly:

```bash
talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig \
  -n 192.168.2.49 shutdown
```

## After the tower lands on the new network

Use your Mac on the same LAN as the tower. Do not assume MIMIR can still reach
it.

### 1. Find the new node IP

Use the new router, DHCP lease table, or local scanning tools. The old
`192.168.2.49` value may no longer apply.

### 2. Verify Talos and Kubernetes directly through the new node IP

Run:

```bash
NODE_IP=<new-node-ip> /Users/zizo/Personal-Projects/Computers/Prometheus/scripts/verify-after-network-move.sh
```

This script:

- talks to Talos directly with `-e <new-node-ip> -n <new-node-ip>`
- generates a temporary kubeconfig from the relocated node
- verifies Flux and core pods
- checks app health via `kubectl port-forward`
- does not depend on the old `192.168.2.x` service IPs

### 2a. Kubeconfig caveat on a moved LAN

The current Talos-generated kubeconfig still stamps the old Kubernetes API
endpoint into new kubeconfig files:

- current generated endpoint: `https://192.168.2.46:6443`

Short-term operator fix:

- rewrite the active kubeconfig `server:` field to the reachable node IP on the
  current LAN, for example `https://192.168.50.197:6443`

This is enough for operator access today. It is not yet the durable long-term
control-plane endpoint strategy.

### 3. Operator access model after relocation

Until you intentionally redesign the service IP layer for the new LAN:

- use `kubectl port-forward` or the relocation verification script
- do not trust the old `LoadBalancer` IPs
- treat the old AdGuard and router DNS assumptions as paused

## Cloudflare quick tunnel warning

The current quick tunnel URL is not a durable contract.

If the summarizer tunnel pod restarts after the move:

- the old `trycloudflare.com` URL may change

If you need a stable public path across moves and restarts, use a named
Cloudflare tunnel rather than a quick tunnel.
