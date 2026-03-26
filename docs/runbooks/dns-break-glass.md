# DNS Break-Glass And Fallback Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook documents the fallback path if DNS changes behave badly. The
design assumption is simple:

- DNS can fail
- remote access must still work
- rollback must not depend on `home.arpa`

## Core rule

The break-glass path is IP-based, not DNS-based.

If `home.arpa` resolution fails, the following should still be usable:

- current discovered main gateway/admin path: `http://192.168.2.1`
- Tailscale to MIMIR: `100.109.171.72`
- MIMIR LAN IP: `192.168.2.40`
- Talos API: `192.168.2.49:50000`
- Kubernetes API VIP: `192.168.2.46:6443`
- AdGuard Home: `http://192.168.2.200`
- Open WebUI: `http://192.168.2.201`
- vLLM: `http://192.168.2.205:8000/v1/models`

## What DNS cutover does not break

- Tailscale subnet routing through MIMIR
- raw IP access to the Talos node
- raw IP access to the Kubernetes API VIP
- raw IP access to the `LoadBalancer` services
- in-cluster Kubernetes DNS such as `*.svc.cluster.local`

## What can break

- client resolution of `*.home.arpa`
- client public DNS if the router starts handing out `192.168.2.200` and the
  tower is offline
- client name-based access after a network move if the rewrite targets are not
  updated

## Break-glass sequence

1. Confirm MIMIR is still reachable over Tailscale:

```bash
ping 100.109.171.72
ssh -i /Users/zizo/.ssh/mimir_ed25519 boi@100.109.171.72
```

2. Confirm the home subnet route still works:

```bash
curl -I http://192.168.2.200
curl -I http://192.168.2.201
curl http://192.168.2.205:8000/v1/models
```

3. Confirm control-plane access by raw IP:

```bash
talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n 192.168.2.49 health
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get nodes -o wide
```

4. If the DNS change is the problem, revert the router or DHCP DNS setting to
   the captured previous value.

5. Renew the affected client lease and confirm public DNS works again.

## Router-side information to capture before cutover

Record these before changing anything:

- main router model
- main router admin IP, currently observed as `192.168.2.1`
- current DHCP DNS settings
- secondary router model, if it will be used as the first test segment
- whether the secondary router is running as a router or as a plain AP/bridge

## Recommended fallback strategy

Short term:

- keep AdGuard as a separate DNS service on `192.168.2.200`
- keep MIMIR as the remote-access backdoor
- keep a raw-IP operator path documented

Safer staged rollout:

- test one client manually against `192.168.2.200`
- if available, test a secondary router or isolated segment before the main
  router
- only then consider changing the main DHCP DNS handoff

Longer term:

- if DNS becomes a must-have service, run a second resolver on always-on
  infrastructure such as MIMIR
- do not make the tower the only resolver for the whole house if the tower is
  expected to reboot into Windows or move roles later
