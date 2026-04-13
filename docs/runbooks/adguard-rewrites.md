# AdGuard Rewrites Runbook

Last updated: 2026-04-13 (America/Toronto)

## Purpose

This runbook captures the test-only naming layer currently configured in
AdGuard Home before router DNS cutover.

## Current stance

- AdGuard is not the sole DNS authority for the network
- router cutover is intentionally deferred
- the current goal is direct-query validation against `192.168.50.200`

## Configured rewrites

- `k8s.home.arpa -> 192.168.50.197`
- `adguard.home.arpa -> 192.168.50.200`
- `openwebui.home.arpa -> 192.168.50.201`
- `vllm.home.arpa -> 192.168.50.205`

## Upstream resolver choice

The initial Quad9 DNS-over-HTTPS upstream was noisy and unreliable on this
network. The current test configuration uses plain upstream resolvers:

- `9.9.9.9`
- `149.112.112.112`
- `1.1.1.1`
- `1.0.0.1`

## Validation

```bash
for name in k8s.home.arpa adguard.home.arpa openwebui.home.arpa vllm.home.arpa; do
  echo \"== $name ==\"
  dig +short @192.168.50.200 $name
  echo
done
```

Expected:

- `k8s.home.arpa -> 192.168.50.197`
- `adguard.home.arpa -> 192.168.50.200`
- `openwebui.home.arpa -> 192.168.50.201`
- `vllm.home.arpa -> 192.168.50.205`

Public resolution should also work:

```bash
dig +short @192.168.50.200 github.com
```

## Real-client validation

Direct queries are necessary but not sufficient. The stronger check is a real
client using AdGuard as its resolver.

Validated on 2026-03-26:

- client: MIMIR (`192.168.50.171`)
- method:
  - temporarily disable Tailscale `CorpDNS`
  - point `/etc/resolv.conf` at `192.168.50.200`
  - resolve and fetch by name
  - restore Tailscale DNS management immediately after the test

Observed results:

- `openwebui.home.arpa -> 192.168.50.201`
- `vllm.home.arpa -> 192.168.50.205`
- `adguard.home.arpa -> 192.168.50.200`
- `k8s.home.arpa -> 192.168.50.197`
- `curl -I http://openwebui.home.arpa/` returned `200 OK`
- `curl http://vllm.home.arpa:8000/v1/models` returned the live model list
- `curl -I http://adguard.home.arpa/` returned `302 Found`
- `curl -sk https://k8s.home.arpa:6443/readyz` returned `401 Unauthorized`, which is the expected unauthenticated response and proves the name resolved to the API endpoint

## What this does not mean yet

- clients are not using AdGuard by default
- router DNS has not been changed
- remote `home.arpa` resolution through Tailscale split DNS is not enabled yet
