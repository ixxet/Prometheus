# DNS Cutover Runbook

Last updated: 2026-04-13 (America/Toronto)

## Purpose

This runbook exists for the eventual move from ad hoc LAN DNS to AdGuard Home as
the primary resolver.

Important boundary:

- AdGuard Home stays a separate service on `192.168.50.200`
- the router is not expected to run AdGuard
- "router cutover" means the router or DHCP server hands out `192.168.50.200`
  as the LAN DNS resolver

## Current status

- authored
- first-wave rewrites are configured in the live AdGuard runtime
- direct queries against `192.168.50.200` already resolve the first-wave names
- a real client on MIMIR has already resolved and reached the first-wave names when pointed directly at AdGuard
- not yet rehearsed end to end for router cutover
- router cutover is still deferred

## First-wave topology

- current discovered main gateway/admin path: `192.168.50.1`
- Talos node: `192.168.50.197`
- Kubernetes API endpoint: `192.168.50.197`
- AdGuard Home: `192.168.50.200`
- Open WebUI: `192.168.50.201`
- vLLM: `192.168.50.205`
- MIMIR LAN IP: `192.168.50.171`
- MIMIR Tailscale IP: `100.109.171.72`

These are the operator-facing addresses that matter during rollout and rollback.

## Recommended cutover window

Do the router cutover only when all of the following are true:

- the tower is expected to stay on Talos for the full test window
- there is no plan to boot Windows on the tower during or immediately after the cutover
- MIMIR subnet-router access is healthy so rollback can still be done remotely if needed
- you can spend at least 30 uninterrupted minutes validating clients and undoing the change if necessary
- the current router DNS settings are captured before any change

Practical recommendation:

- do the cutover when you are home or otherwise able to touch the router directly
- use one controlled client first, then widen out after public DNS and `home.arpa` both behave
- do not combine the router cutover with unrelated network or storage changes

## Safer staged rollout options

Preferred order:

1. test a single client by manually pointing it at `192.168.50.200`
2. if you have a second router or isolated segment, hand out `192.168.50.200`
   there first
3. only then change the main router or main DHCP scope

This keeps the blast radius smaller than a house-wide switch on the first try.

## Preconditions

- AdGuard Home is reachable on `http://192.168.50.200`
- rewrites exist for:
  - `k8s.home.arpa`
  - `adguard.home.arpa`
  - `openwebui.home.arpa`
  - `vllm.home.arpa`
- at least one LAN client resolves those names correctly when pointed directly
  at AdGuard
- Tailscale remote access through MIMIR is working in case rollback is needed

## Current first-wave rewrites

- `k8s.home.arpa -> 192.168.50.197`
- `adguard.home.arpa -> 192.168.50.200`
- `openwebui.home.arpa -> 192.168.50.201`
- `vllm.home.arpa -> 192.168.50.205`

## Cutover steps

1. Export or screenshot the current router DNS settings from the current main
   gateway at `192.168.50.1`.
2. Confirm AdGuard upstream resolvers are healthy.
3. Confirm the four first-wave rewrites resolve correctly from a test client.
4. Change the router or DHCP DNS server to `192.168.50.200`.
5. Renew DHCP leases or reconnect a test client.
6. Verify:
   - `adguard.home.arpa`
   - `openwebui.home.arpa`
   - `vllm.home.arpa`
   - `k8s.home.arpa`
   - normal public DNS resolution
7. Monitor AdGuard query logs and cluster service health.

## Rollback

1. Restore the previous router DNS setting.
2. Renew the client lease again.
3. Verify public DNS resolution is back.
4. Leave AdGuard running, but defer another cutover attempt until the failure is understood.

## Success criteria

- LAN clients resolve the first-wave names correctly
- public DNS still works
- no household devices lose name resolution after the cutover
