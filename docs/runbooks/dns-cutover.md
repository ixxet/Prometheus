# DNS Cutover Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook exists for the eventual move from ad hoc LAN DNS to AdGuard Home as
the primary resolver.

## Current status

- authored
- first-wave rewrites are configured in the live AdGuard runtime
- direct queries against `192.168.2.200` already resolve the first-wave names
- a real client on MIMIR has already resolved and reached the first-wave names when pointed directly at AdGuard
- not yet rehearsed end to end for router cutover
- router cutover is still deferred

## Preconditions

- AdGuard Home is reachable on `http://192.168.2.200`
- rewrites exist for:
  - `k8s.home.arpa`
  - `adguard.home.arpa`
  - `openwebui.home.arpa`
  - `vllm.home.arpa`
- at least one LAN client resolves those names correctly when pointed directly
  at AdGuard
- Tailscale remote access through MIMIR is working in case rollback is needed

## Current first-wave rewrites

- `k8s.home.arpa -> 192.168.2.46`
- `adguard.home.arpa -> 192.168.2.200`
- `openwebui.home.arpa -> 192.168.2.201`
- `vllm.home.arpa -> 192.168.2.205`

## Cutover steps

1. Export or screenshot the current router DNS settings.
2. Confirm AdGuard upstream resolvers are healthy.
3. Confirm the four first-wave rewrites resolve correctly from a test client.
4. Change the router or DHCP DNS server to `192.168.2.200`.
5. Renew DHCP leases or reconnect a test client.
6. Verify:
   - `adguard.home.arpa`
   - `openwebui.home.arpa`
   - `vllm.home.arpa`
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
